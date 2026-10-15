//! Microphone capture through WASAPI (shared mode), replacing `CoreAudioRecorder`.
//!
//! A dedicated thread owns the COM objects, polls the capture client every
//! 10 ms, converts the device mix format to mono and resamples to 16 kHz on
//! the fly. The UI reads the current level through an atomic for the meter.

use super::com::{ComGuard, device_enumerator, friendly_name};
use super::error::{Context, Error, Result};
use crate::audio::convert::{Resampler, SampleFormat, downmix_to_mono};
use crate::audio::{LevelMeter, TARGET_SAMPLE_RATE};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};
use windows::Win32::Foundation::E_ACCESSDENIED;
use windows::Win32::Media::Audio::{
    AUDCLNT_BUFFERFLAGS_SILENT, AUDCLNT_SHAREMODE_SHARED, DEVICE_STATE_ACTIVE, IAudioCaptureClient, IAudioClient,
    IMMDevice, IMMDeviceEnumerator, WAVEFORMATEX, WAVEFORMATEXTENSIBLE, eCapture, eConsole,
};
use windows::Win32::System::Com::{CLSCTX_ALL, CoTaskMemFree};
use windows::core::GUID;

const WAVE_FORMAT_PCM: u16 = 1;
const WAVE_FORMAT_IEEE_FLOAT: u16 = 3;
const WAVE_FORMAT_EXTENSIBLE: u16 = 0xFFFE;
const SUBTYPE_PCM: GUID = GUID::from_u128(0x0000_0001_0000_0010_8000_00aa_0038_9b71);
const SUBTYPE_IEEE_FLOAT: GUID = GUID::from_u128(0x0000_0003_0000_0010_8000_00aa_0038_9b71);

/// WASAPI buffer duration in 100-ns units (200 ms).
const BUFFER_DURATION_HNS: i64 = 2_000_000;
const POLL_INTERVAL: Duration = Duration::from_millis(10);
const START_TIMEOUT: Duration = Duration::from_secs(5);
/// Pre-allocate room for a minute of 16 kHz audio.
const INITIAL_CAPACITY: usize = TARGET_SAMPLE_RATE as usize * 60;

/// Returns `(friendly name, is default)` for every active microphone.
///
/// # Errors
/// Fails when the audio device API is unavailable.
pub fn list_input_devices() -> Result<Vec<(String, bool)>> {
    let _com = ComGuard::new()?;
    let enumerator = device_enumerator()?;
    // SAFETY: COM calls on a valid enumerator.
    unsafe {
        let default_name = enumerator.GetDefaultAudioEndpoint(eCapture, eConsole).ok().and_then(|d| friendly_name(&d));
        let collection = enumerator.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE).context("list microphones")?;
        let mut devices = Vec::new();
        for i in 0..collection.GetCount().context("count microphones")? {
            let device = collection.Item(i).context("read microphone")?;
            let name = friendly_name(&device).unwrap_or_default();
            let is_default = default_name.as_deref() == Some(name.as_str());
            devices.push((name, is_default));
        }
        Ok(devices)
    }
}

/// A capture device whose name contains `hint` (case-insensitive), else the default.
fn select_device(enumerator: &IMMDeviceEnumerator, hint: Option<&str>) -> Option<IMMDevice> {
    // SAFETY: COM calls on a valid enumerator.
    unsafe {
        if let Some(hint) = hint.map(str::to_lowercase).filter(|h| !h.trim().is_empty()) {
            let collection = enumerator.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE).ok()?;
            for i in 0..collection.GetCount().ok()? {
                let Ok(device) = collection.Item(i) else { continue };
                if friendly_name(&device).is_some_and(|n| n.to_lowercase().contains(&hint)) {
                    return Some(device);
                }
            }
            log::warn!("microphone matching '{hint}' not found, using the default device");
        }
        enumerator.GetDefaultAudioEndpoint(eCapture, eConsole).ok()
    }
}

/// Layout of the shared-mode mix format.
#[derive(Debug, Clone, Copy)]
struct StreamFormat {
    sample: SampleFormat,
    channels: usize,
    rate: u32,
}

impl StreamFormat {
    /// Interprets a `WAVEFORMATEX` (or `WAVEFORMATEXTENSIBLE`).
    ///
    /// # Safety
    /// `fmt` must point to a valid format block as returned by `GetMixFormat`.
    unsafe fn from_raw(fmt: *const WAVEFORMATEX) -> Result<Self> {
        // SAFETY: guaranteed by the caller; unaligned reads because the block is packed.
        let header = unsafe { std::ptr::read_unaligned(fmt) };
        let float = match header.wFormatTag {
            WAVE_FORMAT_IEEE_FLOAT => true,
            WAVE_FORMAT_PCM => false,
            WAVE_FORMAT_EXTENSIBLE => {
                // SAFETY: the tag says the block is a WAVEFORMATEXTENSIBLE.
                let sub = unsafe { std::ptr::read_unaligned(fmt.cast::<WAVEFORMATEXTENSIBLE>()) }.SubFormat;
                match sub {
                    s if s == SUBTYPE_IEEE_FLOAT => true,
                    s if s == SUBTYPE_PCM => false,
                    other => return Err(format!("unsupported microphone sub-format {other:?}").into()),
                }
            }
            tag => return Err(format!("unsupported microphone format tag {tag:#x}").into()),
        };
        let channels = usize::from(header.nChannels.max(1));
        let sample = match (float, header.wBitsPerSample) {
            (true, 32) => SampleFormat::F32,
            (false, 16) => SampleFormat::I16,
            // Container size can exceed valid bits (24-in-32); trust nBlockAlign.
            (false, 24) if usize::from(header.nBlockAlign) / channels == 4 => SampleFormat::I32,
            (false, 24) => SampleFormat::I24,
            (false, 32) => SampleFormat::I32,
            (_, bits) => return Err(format!("unsupported sample size {bits} bits").into()),
        };
        Ok(Self { sample, channels, rate: header.nSamplesPerSec })
    }

    fn frame_bytes(self) -> usize {
        self.sample.bytes() * self.channels
    }
}

/// A started WASAPI capture stream.
struct Stream {
    client: IAudioClient,
    capture: IAudioCaptureClient,
    format: StreamFormat,
    device_name: String,
}

impl Stream {
    fn open(device_hint: Option<&str>) -> Result<Self> {
        let enumerator = device_enumerator()?;
        let device = select_device(&enumerator, device_hint)
            .ok_or("no microphone found — connect one and check Windows privacy settings")?;
        let device_name = friendly_name(&device).unwrap_or_else(|| "microphone".into());
        // SAFETY: COM calls on valid interfaces; the mix format block is read
        // before being freed exactly once with CoTaskMemFree.
        unsafe {
            let client: IAudioClient = device.Activate(CLSCTX_ALL, None).context("activate microphone")?;
            let mix = client.GetMixFormat().context("read microphone format")?;
            let format = StreamFormat::from_raw(mix);
            let init = client.Initialize(AUDCLNT_SHAREMODE_SHARED, 0, BUFFER_DURATION_HNS, 0, mix, None);
            CoTaskMemFree(Some(mix.cast_const().cast()));
            let format = format?;
            init.map_err(|e| {
                if e.code() == E_ACCESSDENIED {
                    Error::Message(
                        "microphone access is blocked — enable it in Settings › Privacy & security › Microphone".into(),
                    )
                } else {
                    Error::Win32 { context: "initialize microphone", source: e }
                }
            })?;
            let capture: IAudioCaptureClient = client.GetService().context("open capture service")?;
            client.Start().context("start microphone")?;
            Ok(Self { client, capture, format, device_name })
        }
    }

    /// Reads every pending packet as mono samples at the device rate.
    fn read_available(&self, mut on_block: impl FnMut(&[f32])) -> Result<()> {
        loop {
            // SAFETY: COM calls on a started capture client; the buffer returned
            // by GetBuffer is valid for `frames * frame_bytes` bytes until ReleaseBuffer.
            unsafe {
                if self.capture.GetNextPacketSize().context("capture")? == 0 {
                    return Ok(());
                }
                let mut data: *mut u8 = std::ptr::null_mut();
                let (mut frames, mut flags) = (0u32, 0u32);
                self.capture
                    .GetBuffer(&raw mut data, &raw mut frames, &raw mut flags, None, None)
                    .context("capture")?;
                let silent = flags & AUDCLNT_BUFFERFLAGS_SILENT.0.cast_unsigned() != 0 || data.is_null();
                let mono = if silent {
                    vec![0.0; frames as usize]
                } else {
                    let bytes = std::slice::from_raw_parts(data, frames as usize * self.format.frame_bytes());
                    downmix_to_mono(bytes, self.format.sample, self.format.channels)
                };
                self.capture.ReleaseBuffer(frames).context("capture")?;
                on_block(&mono);
            }
        }
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        // SAFETY: stopping a started client; errors are irrelevant during teardown.
        let _ = unsafe { self.client.Stop() };
    }
}

/// Shared flags between the UI and the capture thread.
#[derive(Default)]
struct Controls {
    stop: AtomicBool,
    discard: AtomicBool,
    /// Current level as `f32` bits (0..=1) for the overlay meter.
    level: Arc<AtomicU32>,
}

/// A running recording.
pub struct Recorder {
    controls: Arc<Controls>,
    thread: Option<JoinHandle<Result<Vec<f32>>>>,
    started: Instant,
    pub device_name: String,
}

impl Recorder {
    /// Starts capturing; returns once the device is running (or failed to start).
    ///
    /// # Errors
    /// Fails when no microphone is available or access is blocked.
    pub fn start(device_hint: Option<String>) -> Result<Recorder> {
        let controls = Arc::new(Controls::default());
        let (ready_tx, ready_rx) = mpsc::channel();
        let thread = {
            let controls = Arc::clone(&controls);
            std::thread::Builder::new()
                .name("voiceink-capture".into())
                .spawn(move || capture_thread(device_hint.as_deref(), &controls, &ready_tx))
                .map_err(|e| Error::Message(e.to_string()))?
        };

        match ready_rx.recv_timeout(START_TIMEOUT) {
            Ok(Ok(device_name)) => {
                Ok(Recorder { controls, thread: Some(thread), started: Instant::now(), device_name })
            }
            Ok(Err(message)) => {
                let _ = thread.join();
                Err(Error::Message(message))
            }
            Err(_) => {
                controls.stop.store(true, Ordering::SeqCst);
                Err("the microphone did not start within 5 seconds".into())
            }
        }
    }

    /// Shared input level (`f32` bits, 0..=1) for the overlay meter.
    pub fn level_handle(&self) -> Arc<AtomicU32> {
        Arc::clone(&self.controls.level)
    }

    pub fn elapsed(&self) -> Duration {
        self.started.elapsed()
    }

    /// Stops and returns the recorded 16 kHz mono samples.
    ///
    /// # Errors
    /// Fails when capturing failed midway.
    pub fn finish(mut self) -> Result<Vec<f32>> {
        self.controls.stop.store(true, Ordering::SeqCst);
        match self.thread.take().map(JoinHandle::join) {
            Some(Ok(result)) => result,
            Some(Err(_)) => Err("the capture thread crashed".into()),
            None => Err("the recorder was already stopped".into()),
        }
    }

    /// Stops without waiting for or keeping the audio.
    pub fn cancel(mut self) {
        self.controls.discard.store(true, Ordering::SeqCst);
        self.controls.stop.store(true, Ordering::SeqCst);
        self.thread.take();
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        self.controls.stop.store(true, Ordering::SeqCst);
    }
}

fn capture_thread(
    device_hint: Option<&str>,
    controls: &Controls,
    ready: &mpsc::Sender<std::result::Result<String, String>>,
) -> Result<Vec<f32>> {
    let opened = ComGuard::new().and_then(|com| Stream::open(device_hint).map(|stream| (com, stream)));
    let (_com, stream) = match opened {
        Ok(v) => v,
        Err(e) => {
            let _ = ready.send(Err(e.to_string()));
            return Err(e);
        }
    };
    let StreamFormat { sample, channels, rate } = stream.format;
    log::info!("recording from '{}' ({rate} Hz, {channels} ch, {sample:?})", stream.device_name);
    let _ = ready.send(Ok(stream.device_name.clone()));

    let mut resampler = Resampler::new(rate, TARGET_SAMPLE_RATE);
    let mut meter = LevelMeter::default();
    let mut samples = Vec::with_capacity(INITIAL_CAPACITY);
    let result = (|| -> Result<()> {
        while !controls.stop.load(Ordering::SeqCst) {
            std::thread::sleep(POLL_INTERVAL);
            stream.read_available(|block| {
                controls.level.store(meter.update(block).to_bits(), Ordering::Relaxed);
                samples.extend(resampler.process(block));
            })?;
        }
        Ok(())
    })();
    controls.level.store(0, Ordering::Relaxed);
    result?;
    Ok(if controls.discard.load(Ordering::SeqCst) { Vec::new() } else { samples })
}

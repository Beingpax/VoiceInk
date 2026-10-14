//! Microphone capture through WASAPI (shared mode), replacing `CoreAudioRecorder`.
//!
//! A dedicated thread owns the COM objects, polls the capture client every
//! 10 ms, converts the device mix format to mono and resamples to 16 kHz on
//! the fly. The UI reads the current level through an atomic for the meter.

use crate::audio::convert::{downmix_to_mono, Resampler, SampleFormat};
use crate::audio::{meter_level, TARGET_SAMPLE_RATE};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};
use windows::core::GUID;
use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
use windows::Win32::Media::Audio::{
    eCapture, eConsole, IAudioCaptureClient, IAudioClient, IMMDevice, IMMDeviceEnumerator,
    MMDeviceEnumerator, AUDCLNT_BUFFERFLAGS_SILENT, AUDCLNT_SHAREMODE_SHARED, DEVICE_STATE_ACTIVE,
    WAVEFORMATEX, WAVEFORMATEXTENSIBLE,
};
use windows::Win32::System::Com::StructuredStorage::PropVariantToStringAlloc;
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoTaskMemFree, CoUninitialize, CLSCTX_ALL,
    COINIT_MULTITHREADED, STGM_READ,
};

const WAVE_FORMAT_PCM: u16 = 1;
const WAVE_FORMAT_IEEE_FLOAT: u16 = 3;
const WAVE_FORMAT_EXTENSIBLE: u16 = 0xFFFE;
const SUBTYPE_PCM: GUID = GUID::from_u128(0x00000001_0000_0010_8000_00aa00389b71);
const SUBTYPE_IEEE_FLOAT: GUID = GUID::from_u128(0x00000003_0000_0010_8000_00aa00389b71);

/// Balances `CoInitializeEx`. A thread that already uses another apartment
/// model (the STA UI thread) keeps it and needs no uninitialization.
struct ComGuard {
    owned: bool,
}

impl ComGuard {
    fn new() -> Result<Self, String> {
        const RPC_E_CHANGED_MODE: i32 = 0x8001_0106_u32 as i32;
        let hr = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        if hr.0 == RPC_E_CHANGED_MODE {
            return Ok(ComGuard { owned: false });
        }
        hr.ok()
            .map_err(|e| format!("COM initialization failed: {e}"))?;
        Ok(ComGuard { owned: true })
    }
}

impl Drop for ComGuard {
    fn drop(&mut self) {
        if self.owned {
            unsafe { CoUninitialize() };
        }
    }
}

fn enumerator() -> windows::core::Result<IMMDeviceEnumerator> {
    unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }
}

fn friendly_name(device: &IMMDevice) -> windows::core::Result<String> {
    unsafe {
        let store = device.OpenPropertyStore(STGM_READ)?;
        let value = store.GetValue(&PKEY_Device_FriendlyName)?;
        let pwstr = PropVariantToStringAlloc(&value)?;
        let name = pwstr.to_string().unwrap_or_default();
        CoTaskMemFree(Some(pwstr.0 as *const _));
        Ok(name)
    }
}

/// Returns `(friendly name, is default)` for every active microphone.
pub fn list_input_devices() -> Result<Vec<(String, bool)>, String> {
    let _com = ComGuard::new()?;
    let map = |e: windows::core::Error| e.to_string();
    unsafe {
        let enumerator = enumerator().map_err(map)?;
        let default_name = enumerator
            .GetDefaultAudioEndpoint(eCapture, eConsole)
            .ok()
            .and_then(|d| friendly_name(&d).ok());
        let collection = enumerator
            .EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE)
            .map_err(map)?;
        let mut out = Vec::new();
        for i in 0..collection.GetCount().map_err(map)? {
            let device = collection.Item(i).map_err(map)?;
            let name = friendly_name(&device).map_err(map)?;
            let is_default = default_name.as_deref() == Some(name.as_str());
            out.push((name, is_default));
        }
        Ok(out)
    }
}

/// Finds a capture device whose name contains `hint` (case-insensitive), else the default.
fn select_device(
    enumerator: &IMMDeviceEnumerator,
    hint: Option<&str>,
) -> windows::core::Result<IMMDevice> {
    unsafe {
        if let Some(hint) = hint.map(str::to_lowercase).filter(|h| !h.trim().is_empty()) {
            let collection = enumerator.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE)?;
            for i in 0..collection.GetCount()? {
                let device = collection.Item(i)?;
                if friendly_name(&device).is_ok_and(|n| n.to_lowercase().contains(&hint)) {
                    return Ok(device);
                }
            }
            log::warn!("microphone matching '{hint}' not found, using the default device");
        }
        enumerator.GetDefaultAudioEndpoint(eCapture, eConsole)
    }
}

/// Interprets the shared-mode mix format.
unsafe fn sample_format(fmt: *const WAVEFORMATEX) -> Result<(SampleFormat, usize, u32), String> {
    let f = std::ptr::read_unaligned(fmt);
    let channels = f.nChannels as usize;
    let rate = f.nSamplesPerSec;
    let bits = f.wBitsPerSample;
    let float = match f.wFormatTag {
        WAVE_FORMAT_IEEE_FLOAT => true,
        WAVE_FORMAT_PCM => false,
        WAVE_FORMAT_EXTENSIBLE => {
            let ext = std::ptr::read_unaligned(fmt as *const WAVEFORMATEXTENSIBLE);
            let sub = ext.SubFormat;
            if sub == SUBTYPE_IEEE_FLOAT {
                true
            } else if sub == SUBTYPE_PCM {
                false
            } else {
                return Err(format!("unsupported mix sub-format {sub:?}"));
            }
        }
        tag => return Err(format!("unsupported mix format tag {tag:#x}")),
    };
    let format = match (float, bits) {
        (true, 32) => SampleFormat::F32,
        (false, 16) => SampleFormat::I16,
        (false, 24) => SampleFormat::I24,
        (false, 32) => SampleFormat::I32,
        _ => return Err(format!("unsupported sample size {bits} bits")),
    };
    // Container size can exceed valid bits (e.g. 24-in-32); trust nBlockAlign.
    let container = f.nBlockAlign as usize / channels.max(1);
    let format = match (format, container) {
        (SampleFormat::I24, 4) => SampleFormat::I32,
        (f, _) => f,
    };
    Ok((format, channels, rate))
}

/// A running recording.
pub struct Recorder {
    stop: Arc<AtomicBool>,
    discard: Arc<AtomicBool>,
    level: Arc<AtomicU32>,
    thread: Option<JoinHandle<Result<Vec<f32>, String>>>,
    started: Instant,
    pub device_name: String,
}

impl Recorder {
    /// Starts capturing; returns once the device is running (or failed to start).
    pub fn start(device_hint: Option<String>) -> Result<Recorder, String> {
        let stop = Arc::new(AtomicBool::new(false));
        let discard = Arc::new(AtomicBool::new(false));
        let level = Arc::new(AtomicU32::new(0));
        let (ready_tx, ready_rx) = mpsc::channel::<Result<String, String>>();

        let thread = {
            let stop = stop.clone();
            let discard = discard.clone();
            let level = level.clone();
            std::thread::Builder::new()
                .name("voiceink-capture".into())
                .spawn(move || capture_thread(device_hint, stop, discard, level, ready_tx))
                .map_err(|e| e.to_string())?
        };

        match ready_rx.recv_timeout(Duration::from_secs(5)) {
            Ok(Ok(device_name)) => Ok(Recorder {
                stop,
                discard,
                level,
                thread: Some(thread),
                started: Instant::now(),
                device_name,
            }),
            Ok(Err(e)) => {
                let _ = thread.join();
                Err(e)
            }
            Err(_) => {
                stop.store(true, Ordering::SeqCst);
                Err("the microphone did not start within 5 seconds".into())
            }
        }
    }

    /// Shared input level (`f32` bits, 0..=1) for the overlay meter.
    pub fn level_handle(&self) -> Arc<AtomicU32> {
        self.level.clone()
    }

    pub fn elapsed(&self) -> Duration {
        self.started.elapsed()
    }

    /// Stops and returns the recorded 16 kHz mono samples.
    pub fn finish(mut self) -> Result<Vec<f32>, String> {
        self.stop.store(true, Ordering::SeqCst);
        match self.thread.take().map(|t| t.join()) {
            Some(Ok(result)) => result,
            Some(Err(_)) => Err("capture thread panicked".into()),
            None => Err("recorder already stopped".into()),
        }
    }

    /// Stops without waiting for or keeping the audio.
    pub fn cancel(mut self) {
        self.discard.store(true, Ordering::SeqCst);
        self.stop.store(true, Ordering::SeqCst);
        self.thread.take();
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
    }
}

fn capture_thread(
    device_hint: Option<String>,
    stop: Arc<AtomicBool>,
    discard: Arc<AtomicBool>,
    level: Arc<AtomicU32>,
    ready: mpsc::Sender<Result<String, String>>,
) -> Result<Vec<f32>, String> {
    let fail = |ready: &mpsc::Sender<Result<String, String>>, msg: String| {
        let _ = ready.send(Err(msg.clone()));
        Err(msg)
    };

    let _com = match ComGuard::new() {
        Ok(g) => g,
        Err(e) => return fail(&ready, e),
    };

    let setup = || -> Result<(IAudioClient, IAudioCaptureClient, SampleFormat, usize, u32, String), String> {
        fn map(what: &'static str) -> impl Fn(windows::core::Error) -> String {
            move |e| format!("{what}: {e}")
        }
        unsafe {
            let enumerator = enumerator().map_err(map("device enumerator"))?;
            let device = select_device(&enumerator, device_hint.as_deref())
                .map_err(|_| "no microphone found — connect one and check Windows privacy settings".to_string())?;
            let name = friendly_name(&device).unwrap_or_else(|_| "microphone".into());
            let client: IAudioClient = device.Activate(CLSCTX_ALL, None).map_err(map("activate"))?;
            let mix = client.GetMixFormat().map_err(map("mix format"))?;
            let parsed = sample_format(mix);
            let init = client.Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 2_000_000, 0, mix, None);
            CoTaskMemFree(Some(mix as *const _));
            let (format, channels, rate) = parsed?;
            init.map_err(|e| {
                if e.code().0 as u32 == 0x8007_0005 {
                    "microphone access is blocked — enable it in Settings › Privacy & security › Microphone".to_string()
                } else {
                    format!("audio client init: {e}")
                }
            })?;
            let capture: IAudioCaptureClient = client.GetService().map_err(map("capture service"))?;
            client.Start().map_err(map("start"))?;
            Ok((client, capture, format, channels, rate, name))
        }
    };

    let (client, capture, format, channels, rate, name) = match setup() {
        Ok(v) => v,
        Err(e) => return fail(&ready, e),
    };
    log::info!("recording from '{name}' ({rate} Hz, {channels} ch, {format:?})");
    let _ = ready.send(Ok(name));

    let mut resampler = Resampler::new(rate, TARGET_SAMPLE_RATE);
    let mut samples: Vec<f32> = Vec::with_capacity(TARGET_SAMPLE_RATE as usize * 60);
    let frame_bytes = format.bytes() * channels;
    let mut smoothed = 0.0f32;

    let result = (|| -> Result<(), String> {
        while !stop.load(Ordering::SeqCst) {
            std::thread::sleep(Duration::from_millis(10));
            unsafe {
                loop {
                    let packet = capture
                        .GetNextPacketSize()
                        .map_err(|e| format!("capture: {e}"))?;
                    if packet == 0 {
                        break;
                    }
                    let mut data: *mut u8 = std::ptr::null_mut();
                    let mut frames = 0u32;
                    let mut flags = 0u32;
                    capture
                        .GetBuffer(&mut data, &mut frames, &mut flags, None, None)
                        .map_err(|e| format!("capture: {e}"))?;
                    let mono = if flags & (AUDCLNT_BUFFERFLAGS_SILENT.0 as u32) != 0
                        || data.is_null()
                    {
                        vec![0.0f32; frames as usize]
                    } else {
                        let bytes = std::slice::from_raw_parts(data, frames as usize * frame_bytes);
                        downmix_to_mono(bytes, format, channels)
                    };
                    capture
                        .ReleaseBuffer(frames)
                        .map_err(|e| format!("capture: {e}"))?;

                    let lvl = meter_level(&mono);
                    smoothed = if lvl > smoothed {
                        lvl
                    } else {
                        smoothed * 0.85 + lvl * 0.15
                    };
                    level.store(smoothed.to_bits(), Ordering::Relaxed);
                    samples.extend(resampler.process(&mono));
                }
            }
        }
        Ok(())
    })();

    unsafe {
        let _ = client.Stop();
    }
    level.store(0, Ordering::Relaxed);
    result?;
    if discard.load(Ordering::SeqCst) {
        return Ok(Vec::new());
    }
    Ok(samples)
}

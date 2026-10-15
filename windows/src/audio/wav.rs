//! Minimal RIFF/WAVE reader and writer.

// Signal processing on bounded sample counts and rates: the float/int
// conversions in this module are intentional and range-checked by design.
#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]

use super::TARGET_SAMPLE_RATE;
use super::convert::{SampleFormat, downmix_to_mono, resample};

/// Encodes mono `f32` samples as a 16-bit PCM WAV file.
pub fn encode_wav_i16(samples: &[f32], sample_rate: u32) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data_len as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&(sample_rate * 2).to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for s in samples {
        let v = (s.clamp(-1.0, 1.0) * 32767.0).round() as i16;
        out.extend_from_slice(&v.to_le_bytes());
    }
    out
}

const WAVE_FORMAT_PCM: u16 = 1;
const WAVE_FORMAT_IEEE_FLOAT: u16 = 3;
const WAVE_FORMAT_EXTENSIBLE: u16 = 0xFFFE;
const RIFF_HEADER_LEN: usize = 12;
const CHUNK_HEADER_LEN: usize = 8;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum WavError {
    #[error("not a RIFF/WAVE file")]
    NotWave,
    #[error("the WAV data chunk comes before its format chunk")]
    MissingFormat,
    #[error("the WAV file has no data chunk")]
    MissingData,
    #[error("unsupported WAV encoding (format {format}, {bits} bits)")]
    Unsupported { format: u16, bits: u16 },
}

#[derive(Debug)]
pub struct DecodedWav {
    pub sample_rate: u32,
    pub samples: Vec<f32>,
}

/// The parts of a `fmt ` chunk we need.
#[derive(Debug, Clone, Copy)]
struct FormatChunk {
    format: u16,
    channels: u16,
    sample_rate: u32,
    bits: u16,
}

fn u16_at(b: &[u8], i: usize) -> u16 {
    u16::from_le_bytes([b[i], b[i + 1]])
}

fn u32_at(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]])
}

impl FormatChunk {
    fn parse(body: &[u8]) -> Option<Self> {
        if body.len() < 16 {
            return None;
        }
        let mut format = u16_at(body, 0);
        // WAVE_FORMAT_EXTENSIBLE stores the real format in the sub-format GUID.
        if format == WAVE_FORMAT_EXTENSIBLE && body.len() >= 26 {
            format = u16_at(body, 24);
        }
        Some(Self { format, channels: u16_at(body, 2), sample_rate: u32_at(body, 4), bits: u16_at(body, 14) })
    }

    fn decode(self, data: &[u8]) -> Result<Vec<f32>, WavError> {
        let channels = usize::from(self.channels.max(1));
        let format = match (self.format, self.bits) {
            (WAVE_FORMAT_PCM, 8) => return Ok(decode_u8(data, channels)),
            (WAVE_FORMAT_PCM, 16) => SampleFormat::I16,
            (WAVE_FORMAT_PCM, 24) => SampleFormat::I24,
            (WAVE_FORMAT_PCM, 32) => SampleFormat::I32,
            (WAVE_FORMAT_IEEE_FLOAT, 32) => SampleFormat::F32,
            (format, bits) => return Err(WavError::Unsupported { format, bits }),
        };
        Ok(downmix_to_mono(data, format, channels))
    }
}

/// 8-bit WAV is unsigned with a 128 midpoint.
fn decode_u8(data: &[u8], channels: usize) -> Vec<f32> {
    data.chunks_exact(channels)
        .map(|frame| frame.iter().map(|&b| (f32::from(b) - 128.0) / 128.0).sum::<f32>() / frame.len() as f32)
        .collect()
}

/// Decodes PCM (8/16/24/32-bit) or IEEE-float WAV data to mono `f32`.
///
/// # Errors
/// Returns [`WavError`] for non-WAV data and unsupported encodings.
pub fn decode_wav(bytes: &[u8]) -> Result<DecodedWav, WavError> {
    if bytes.len() < RIFF_HEADER_LEN || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err(WavError::NotWave);
    }
    let mut pos = RIFF_HEADER_LEN;
    let mut format = None;
    while pos + CHUNK_HEADER_LEN <= bytes.len() {
        let id = &bytes[pos..pos + 4];
        let len = u32_at(bytes, pos + 4) as usize;
        let body_start = pos + CHUNK_HEADER_LEN;
        let body = &bytes[body_start..(body_start + len).min(bytes.len())];
        match id {
            b"fmt " => format = FormatChunk::parse(body),
            b"data" => {
                let format = format.ok_or(WavError::MissingFormat)?;
                return Ok(DecodedWav { sample_rate: format.sample_rate, samples: format.decode(body)? });
            }
            _ => {}
        }
        // Chunks are padded to an even length.
        pos = body_start + len + (len & 1);
    }
    Err(WavError::MissingData)
}

/// Loads any supported WAV and converts it to 16 kHz mono.
///
/// # Errors
/// See [`decode_wav`].
pub fn load_wav_16k(bytes: &[u8]) -> Result<Vec<f32>, WavError> {
    let wav = decode_wav(bytes)?;
    Ok(resample(&wav.samples, wav.sample_rate, TARGET_SAMPLE_RATE))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_pcm16() {
        let samples = vec![0.0, 0.5, -0.5, 1.0, -1.0];
        let bytes = encode_wav_i16(&samples, 16_000);
        assert_eq!(bytes.len(), 44 + 10);
        let decoded = decode_wav(&bytes).unwrap();
        assert_eq!(decoded.sample_rate, 16_000);
        for (a, b) in samples.iter().zip(decoded.samples.iter()) {
            assert!((a - b).abs() < 1e-3);
        }
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(decode_wav(b"nope").unwrap_err(), WavError::NotWave);
        let mut no_data = encode_wav_i16(&[], 16_000);
        no_data.truncate(36);
        assert_eq!(decode_wav(&no_data).unwrap_err(), WavError::MissingData);
    }
}

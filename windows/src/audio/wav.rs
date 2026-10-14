//! Minimal RIFF/WAVE reader and writer.

use super::convert::{downmix_to_mono, resample, SampleFormat};
use super::TARGET_SAMPLE_RATE;

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

#[derive(Debug)]
pub struct DecodedWav {
    pub sample_rate: u32,
    pub samples: Vec<f32>,
}

/// Decodes PCM (8/16/24/32-bit) or IEEE-float WAV data to mono `f32`.
pub fn decode_wav(bytes: &[u8]) -> Result<DecodedWav, String> {
    if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err("not a RIFF/WAVE file".into());
    }
    let mut pos = 12;
    let mut fmt: Option<(u16, u16, u32, u16)> = None;
    while pos + 8 <= bytes.len() {
        let id = &bytes[pos..pos + 4];
        let len = u32::from_le_bytes(bytes[pos + 4..pos + 8].try_into().unwrap()) as usize;
        let body_start = pos + 8;
        let body_end = (body_start + len).min(bytes.len());
        let body = &bytes[body_start..body_end];
        match id {
            b"fmt " if body.len() >= 16 => {
                let mut tag = u16::from_le_bytes([body[0], body[1]]);
                let channels = u16::from_le_bytes([body[2], body[3]]);
                let rate = u32::from_le_bytes(body[4..8].try_into().unwrap());
                let bits = u16::from_le_bytes([body[14], body[15]]);
                if tag == 0xFFFE && body.len() >= 26 {
                    tag = u16::from_le_bytes([body[24], body[25]]);
                }
                fmt = Some((tag, channels, rate, bits));
            }
            b"data" => {
                let (tag, channels, rate, bits) = fmt.ok_or("data chunk before fmt chunk")?;
                let samples = match (tag, bits) {
                    (1, 8) => {
                        let ch = channels.max(1) as usize;
                        body.chunks_exact(ch)
                            .map(|f| {
                                f.iter().map(|&b| (b as f32 - 128.0) / 128.0).sum::<f32>()
                                    / ch as f32
                            })
                            .collect()
                    }
                    (1, 16) => downmix_to_mono(body, SampleFormat::I16, channels as usize),
                    (1, 24) => downmix_to_mono(body, SampleFormat::I24, channels as usize),
                    (1, 32) => downmix_to_mono(body, SampleFormat::I32, channels as usize),
                    (3, 32) => downmix_to_mono(body, SampleFormat::F32, channels as usize),
                    _ => {
                        return Err(format!(
                            "unsupported WAV encoding (format {tag}, {bits} bits)"
                        ))
                    }
                };
                return Ok(DecodedWav {
                    sample_rate: rate,
                    samples,
                });
            }
            _ => {}
        }
        pos = body_start + len + (len & 1);
    }
    Err("WAV file has no data chunk".into())
}

/// Loads any supported WAV and converts it to 16 kHz mono.
pub fn load_wav_16k(bytes: &[u8]) -> Result<Vec<f32>, String> {
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
        assert!(decode_wav(b"nope").is_err());
    }
}

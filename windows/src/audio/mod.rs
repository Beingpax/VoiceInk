//! Portable audio helpers. Capture itself lives in `platform::capture`.

pub mod convert;
pub mod wav;

/// Every provider receives 16 kHz mono 16-bit PCM, like the macOS recorder.
pub const TARGET_SAMPLE_RATE: u32 = 16_000;

/// Root-mean-square level of a block, mapped to 0..=1 for the recorder meter.
pub fn meter_level(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let rms = (samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32).sqrt();
    // -50 dBFS .. 0 dBFS -> 0 .. 1
    let db = 20.0 * rms.max(1e-6).log10();
    ((db + 50.0) / 50.0).clamp(0.0, 1.0)
}

pub fn duration_secs(samples: usize, sample_rate: u32) -> f64 {
    samples as f64 / sample_rate as f64
}

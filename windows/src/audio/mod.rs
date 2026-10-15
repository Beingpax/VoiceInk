//! Portable audio helpers. Capture itself lives in `platform::capture`.

pub mod convert;
pub mod wav;

/// Every provider receives 16 kHz mono 16-bit PCM, like the macOS recorder.
pub const TARGET_SAMPLE_RATE: u32 = 16_000;

/// Root-mean-square level of a block, mapped to 0..=1 for the recorder meter.
#[allow(clippy::cast_precision_loss, reason = "block sizes are far below f32's exact range")]
pub fn meter_level(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let rms = (samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32).sqrt();
    // -50 dBFS .. 0 dBFS -> 0 .. 1
    let db = 20.0 * rms.max(1e-6).log10();
    ((db + 50.0) / 50.0).clamp(0.0, 1.0)
}

/// Peak-hold meter: rises instantly, falls back smoothly (for the recorder UI).
#[derive(Debug, Default, Clone, Copy)]
pub struct LevelMeter {
    value: f32,
}

impl LevelMeter {
    /// Weight of the previous value while the level falls.
    const DECAY: f32 = 0.85;

    /// Feeds one block of samples and returns the displayed level (0..=1).
    pub fn update(&mut self, block: &[f32]) -> f32 {
        let level = meter_level(block);
        self.value = if level > self.value { level } else { self.value * Self::DECAY + level * (1.0 - Self::DECAY) };
        self.value
    }
}

#[allow(clippy::cast_precision_loss, reason = "sample counts are far below f64's exact range")]
pub fn duration_secs(samples: usize, sample_rate: u32) -> f64 {
    samples as f64 / f64::from(sample_rate)
}

#[cfg(test)]
#[allow(clippy::float_cmp, reason = "exact values are expected")]
mod tests {
    use super::*;

    #[test]
    fn meter_rises_fast_and_decays_slowly() {
        let mut meter = LevelMeter::default();
        let loud = meter.update(&[0.5; 160]);
        assert!(loud > 0.8);
        let after_silence = meter.update(&[0.0; 160]);
        assert!(after_silence < loud && after_silence > loud * 0.8);
        assert_eq!(meter_level(&[]), 0.0);
    }
}

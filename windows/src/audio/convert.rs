//! Sample-format conversion for the WASAPI mix format.

// Signal processing on bounded sample counts and rates: the float/int
// conversions in this module are intentional and range-checked by design.
#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]

/// Interleaved sample layouts the shared-mode mix format can use.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SampleFormat {
    F32,
    I16,
    I24,
    I32,
}

impl SampleFormat {
    pub fn bytes(self) -> usize {
        match self {
            SampleFormat::I16 => 2,
            SampleFormat::I24 => 3,
            SampleFormat::F32 | SampleFormat::I32 => 4,
        }
    }
}

/// Decodes interleaved frames and averages all channels down to mono `f32`.
pub fn downmix_to_mono(bytes: &[u8], format: SampleFormat, channels: usize) -> Vec<f32> {
    let channels = channels.max(1);
    let frame_bytes = format.bytes() * channels;
    let mut out = Vec::with_capacity(bytes.len() / frame_bytes.max(1));
    for frame in bytes.chunks_exact(frame_bytes) {
        let mut sum = 0.0f32;
        for ch in frame.chunks_exact(format.bytes()) {
            sum += match format {
                SampleFormat::F32 => f32::from_le_bytes([ch[0], ch[1], ch[2], ch[3]]),
                SampleFormat::I16 => f32::from(i16::from_le_bytes([ch[0], ch[1]])) / 32768.0,
                SampleFormat::I24 => {
                    let v = i32::from_le_bytes([0, ch[0], ch[1], ch[2]]) >> 8;
                    v as f32 / 8_388_608.0
                }
                SampleFormat::I32 => i32::from_le_bytes([ch[0], ch[1], ch[2], ch[3]]) as f32 / 2_147_483_648.0,
            };
        }
        out.push(sum / channels as f32);
    }
    out
}

/// Streaming linear-interpolation resampler. Speech is band-limited well below
/// 8 kHz, so a short moving-average pre-filter is enough to avoid audible aliasing.
#[derive(Debug, Clone)]
pub struct Resampler {
    ratio: f64,
    position: f64,
    previous: f32,
    filter: Vec<f32>,
    filter_pos: usize,
}

impl Resampler {
    pub fn new(input_rate: u32, output_rate: u32) -> Self {
        let ratio = f64::from(input_rate) / f64::from(output_rate);
        let taps = ratio.floor().max(1.0) as usize;
        Self { ratio, position: 0.0, previous: 0.0, filter: vec![0.0; taps], filter_pos: 0 }
    }

    pub fn process(&mut self, input: &[f32]) -> Vec<f32> {
        if (self.ratio - 1.0).abs() < f64::EPSILON {
            return input.to_vec();
        }
        let filtered: Vec<f32> = if self.filter.len() > 1 {
            input
                .iter()
                .map(|&s| {
                    self.filter[self.filter_pos] = s;
                    self.filter_pos = (self.filter_pos + 1) % self.filter.len();
                    self.filter.iter().sum::<f32>() / self.filter.len() as f32
                })
                .collect()
        } else {
            input.to_vec()
        };

        let mut out = Vec::with_capacity((filtered.len() as f64 / self.ratio) as usize + 1);
        // `position` is measured relative to `previous` (index -1 of this block).
        while self.position < filtered.len() as f64 {
            let idx = self.position.floor();
            let frac = (self.position - idx) as f32;
            let i = idx as isize;
            let a = if i == 0 { self.previous } else { filtered[(i - 1) as usize] };
            let b = filtered[i as usize];
            out.push(a + (b - a) * frac);
            self.position += self.ratio;
        }
        self.position -= filtered.len() as f64;
        if let Some(&last) = filtered.last() {
            self.previous = last;
        }
        out
    }
}

/// One-shot helper for complete buffers.
pub fn resample(input: &[f32], input_rate: u32, output_rate: u32) -> Vec<f32> {
    Resampler::new(input_rate, output_rate).process(input)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn downmixes_stereo_float() {
        let mut bytes = Vec::new();
        for (l, r) in [(1.0f32, 0.0f32), (0.5, 0.5)] {
            bytes.extend_from_slice(&l.to_le_bytes());
            bytes.extend_from_slice(&r.to_le_bytes());
        }
        assert_eq!(downmix_to_mono(&bytes, SampleFormat::F32, 2), vec![0.5, 0.5]);
    }

    #[test]
    fn decodes_i16_and_i24() {
        let bytes = (-16384i16).to_le_bytes();
        assert_eq!(downmix_to_mono(&bytes, SampleFormat::I16, 1), vec![-0.5]);
        let v24: i32 = 4_194_304; // 0.5
        let b = v24.to_le_bytes();
        assert_eq!(downmix_to_mono(&b[..3], SampleFormat::I24, 1), vec![0.5]);
    }

    #[test]
    fn resamples_48k_to_16k_length() {
        let input = vec![0.25f32; 48_000];
        let out = resample(&input, 48_000, 16_000);
        assert!((out.len() as i64 - 16_000).abs() <= 1, "len {}", out.len());
        assert!(out[100..].iter().all(|s| (s - 0.25).abs() < 1e-4));
    }

    #[test]
    fn streaming_matches_one_shot_length() {
        let input: Vec<f32> = (0..44_100).map(|i| (i as f32 * 0.01).sin()).collect();
        let mut r = Resampler::new(44_100, 16_000);
        let mut total = 0;
        for chunk in input.chunks(441) {
            total += r.process(chunk).len();
        }
        assert!((total as i64 - 16_000).abs() <= 2, "total {total}");
    }
}

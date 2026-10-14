//! Offline transcription with whisper.cpp (the macOS app's `LocalTranscriptionService`).
//!
//! Models are the standard `ggml-*.bin` files from
//! <https://huggingface.co/ggerganov/whisper.cpp>. The loaded context is cached
//! between dictations because loading a model takes far longer than decoding.

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

static CONTEXT: Mutex<Option<(PathBuf, WhisperContext)>> = Mutex::new(None);

pub fn transcribe(
    model_path: &Path,
    samples: &[f32],
    language: Option<&str>,
    vocabulary: &[String],
) -> Result<String, String> {
    if !model_path.exists() {
        return Err(format!(
            "model not found: {} (download a ggml model into this folder)",
            model_path.display()
        ));
    }

    let mut guard = CONTEXT
        .lock()
        .map_err(|_| "whisper context poisoned".to_string())?;
    if guard.as_ref().map(|(p, _)| p.as_path()) != Some(model_path) {
        let ctx = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
            .map_err(|e| format!("failed to load {}: {e}", model_path.display()))?;
        *guard = Some((model_path.to_path_buf(), ctx));
    }
    let (_, ctx) = guard.as_ref().expect("context loaded above");
    let mut state = ctx.create_state().map_err(|e| e.to_string())?;

    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .min(8);
    params.set_n_threads(threads as i32);
    params.set_language(Some(language.unwrap_or("auto")));
    params.set_translate(false);
    params.set_no_context(true);
    params.set_suppress_blank(true);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    let prompt = vocabulary
        .iter()
        .map(|w| w.trim())
        .filter(|w| !w.is_empty())
        .collect::<Vec<_>>()
        .join(", ");
    if !prompt.is_empty() {
        params.set_initial_prompt(&prompt);
    }

    state.full(params, samples).map_err(|e| e.to_string())?;

    let mut text = String::new();
    for segment in state.as_iter() {
        let s = segment.to_str_lossy().map_err(|e| e.to_string())?;
        text.push_str(&s);
    }
    Ok(text.trim().to_string())
}

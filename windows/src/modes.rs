//! Modes: per-application settings overrides and spoken trigger words
//! (port of `ModeConfig` matching and `ModeTriggerWordDetectionService`).

use crate::config::{Config, EnhancementProvider, ModeConfig, OutputMode, SendKey};

/// Information about the window that was focused when recording started.
#[derive(Debug, Clone, Default)]
pub struct ForegroundInfo {
    /// Executable file name, e.g. `slack.exe`.
    pub process_name: String,
    pub window_title: String,
}

/// Picks the first enabled mode whose process name or title filter matches.
pub fn match_mode<'a>(modes: &'a [ModeConfig], fg: &ForegroundInfo) -> Option<&'a ModeConfig> {
    let process = fg.process_name.to_lowercase();
    let title = fg.window_title.to_lowercase();
    modes.iter().filter(|m| m.enabled).find(|m| {
        let process_hit = m.process_names.iter().any(|p| {
            let p = p.trim().to_lowercase();
            !p.is_empty() && (process == p || process.trim_end_matches(".exe") == p.trim_end_matches(".exe"))
        });
        let title_hit = m
            .window_title_contains
            .iter()
            .map(|t| t.trim().to_lowercase())
            .any(|t| !t.is_empty() && title.contains(&t));
        process_hit || title_hit
    })
}

/// Effective settings for one dictation after applying a mode.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Resolved {
    pub mode_name: Option<String>,
    pub language: Option<String>,
    pub text_formatting: bool,
    pub enhancement_enabled: bool,
    pub provider: EnhancementProvider,
    pub model: String,
    pub prompt_id: String,
    pub use_clipboard_context: bool,
    pub use_selected_text_context: bool,
    pub use_window_context: bool,
    pub output: OutputMode,
    pub custom_command: Option<String>,
    pub send_key: SendKey,
}

pub fn resolve(config: &Config, mode: Option<&ModeConfig>) -> Resolved {
    let e = &config.enhancement;
    let mut r = Resolved {
        mode_name: None,
        language: config.transcription.language_code().map(str::to_string),
        text_formatting: config.transcription.text_formatting,
        enhancement_enabled: e.enabled,
        provider: e.provider,
        model: e.model_name(),
        prompt_id: e.prompt_id.clone(),
        use_clipboard_context: e.use_clipboard_context,
        use_selected_text_context: e.use_selected_text_context,
        use_window_context: e.use_window_context,
        output: OutputMode::Paste,
        custom_command: None,
        send_key: config.output.send_key,
    };
    let Some(m) = mode else { return r };

    r.mode_name = Some(m.name.clone());
    if let Some(lang) = &m.language {
        r.language = (!lang.trim().is_empty() && !lang.eq_ignore_ascii_case("auto")).then(|| lang.trim().to_string());
    }
    if let Some(v) = m.text_formatting {
        r.text_formatting = v;
    }
    if let Some(v) = m.enhancement_enabled {
        r.enhancement_enabled = v;
    }
    if let Some(p) = m.enhancement_provider {
        r.provider = p;
        r.model = p.default_model().to_string();
    }
    if let Some(model) = m.enhancement_model.as_ref().filter(|s| !s.trim().is_empty()) {
        r.model.clone_from(model);
    }
    if let Some(id) = m.prompt_id.as_ref().filter(|id| config.prompt(id).is_some()) {
        r.prompt_id.clone_from(id);
    }
    if let Some(v) = m.use_clipboard_context {
        r.use_clipboard_context = v;
    }
    if let Some(v) = m.use_selected_text_context {
        r.use_selected_text_context = v;
    }
    if let Some(k) = m.send_key {
        r.send_key = k;
    }
    r.output = m.output;
    r.custom_command = m.custom_command.clone().filter(|c| !c.trim().is_empty());
    r
}

/// Result of detecting a trigger word in a transcript.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TriggerDetection {
    pub mode_index: usize,
    pub processed_text: String,
}

/// Finds a mode trigger word at the start or end of `text` and strips it.
/// Longer trigger words win, then earlier modes, then earlier words.
pub fn detect_trigger(text: &str, modes: &[ModeConfig]) -> Option<TriggerDetection> {
    let mut candidates: Vec<(usize, usize, &str)> = Vec::new();
    for (mi, mode) in modes.iter().enumerate().filter(|(_, m)| m.enabled) {
        for (wi, word) in mode.trigger_words.iter().enumerate() {
            let w = word.trim();
            if !w.is_empty() {
                candidates.push((mi, wi, w));
            }
        }
    }
    candidates.sort_by(|a, b| b.2.chars().count().cmp(&a.2.chars().count()).then(a.0.cmp(&b.0)).then(a.1.cmp(&b.1)));

    candidates.into_iter().find_map(|(mi, _, word)| {
        let processed = if let Some(after) = strip_trailing(text, word) {
            strip_leading(&after, word).unwrap_or(after)
        } else {
            let after = strip_leading(text, word)?;
            strip_trailing(&after, word).unwrap_or(after)
        };
        Some(TriggerDetection { mode_index: mi, processed_text: processed })
    })
}

const TRIGGER_PUNCT: &[char] = &[',', '.', '!', '?', ';', ':'];

fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}

/// Byte length of the prefix of `text` that equals `word` case-insensitively.
fn ci_prefix_len(text: &str, word: &str) -> Option<usize> {
    let n = word.chars().count();
    let end = text.char_indices().nth(n).map_or(text.len(), |(i, _)| i);
    (text.chars().count() >= n && text[..end].to_lowercase() == word.to_lowercase()).then_some(end)
}

fn ci_suffix_start(text: &str, word: &str) -> Option<usize> {
    let n = word.chars().count();
    let total = text.chars().count();
    if total < n {
        return None;
    }
    let start = text.char_indices().nth(total - n).map_or(0, |(i, _)| i);
    (text[start..].to_lowercase() == word.to_lowercase()).then_some(start)
}

fn strip_leading(text: &str, word: &str) -> Option<String> {
    let trimmed = text.trim();
    let end = ci_prefix_len(trimmed, word)?;
    if trimmed[end..].chars().next().is_some_and(char::is_alphanumeric) {
        return None;
    }
    let rest = trimmed[end..].trim_start_matches(|c: char| TRIGGER_PUNCT.contains(&c) || c.is_whitespace());
    Some(capitalize_first(rest.trim()))
}

fn strip_trailing(text: &str, word: &str) -> Option<String> {
    let trimmed = text.trim().trim_end_matches(TRIGGER_PUNCT);
    let start = ci_suffix_start(trimmed, word)?;
    if trimmed[..start].chars().next_back().is_some_and(char::is_alphanumeric) {
        return None;
    }
    let rest = trimmed[..start].trim_end_matches(|c: char| TRIGGER_PUNCT.contains(&c) || c.is_whitespace());
    Some(capitalize_first(rest.trim()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mode(name: &str) -> ModeConfig {
        ModeConfig { name: name.into(), ..Default::default() }
    }

    #[test]
    fn matches_by_process_and_title() {
        let mut slack = mode("Chat");
        slack.process_names = vec!["Slack.exe".into()];
        let mut gmail = mode("Email");
        gmail.window_title_contains = vec!["gmail".into()];
        let modes = vec![slack, gmail];

        let fg = ForegroundInfo { process_name: "slack.exe".into(), window_title: "x".into() };
        assert_eq!(match_mode(&modes, &fg).unwrap().name, "Chat");
        let fg = ForegroundInfo { process_name: "chrome.exe".into(), window_title: "Inbox - Gmail".into() };
        assert_eq!(match_mode(&modes, &fg).unwrap().name, "Email");
        let fg = ForegroundInfo { process_name: "notepad.exe".into(), window_title: String::new() };
        assert!(match_mode(&modes, &fg).is_none());
    }

    #[test]
    fn disabled_modes_are_ignored() {
        let mut m = mode("Off");
        m.enabled = false;
        m.process_names = vec!["a.exe".into()];
        let fg = ForegroundInfo { process_name: "a.exe".into(), window_title: String::new() };
        assert!(match_mode(&[m], &fg).is_none());
    }

    #[test]
    fn resolve_applies_overrides() {
        let mut cfg = Config::default();
        cfg.enhancement.enabled = false;
        let mut m = mode("Email");
        m.enhancement_enabled = Some(true);
        m.prompt_id = Some("00000000-0000-0000-0000-000000000003".into());
        m.enhancement_provider = Some(EnhancementProvider::Groq);
        m.language = Some("de".into());
        let r = resolve(&cfg, Some(&m));
        assert!(r.enhancement_enabled);
        assert_eq!(r.prompt_id, "00000000-0000-0000-0000-000000000003");
        assert_eq!(r.model, EnhancementProvider::Groq.default_model());
        assert_eq!(r.language.as_deref(), Some("de"));
        assert_eq!(r.mode_name.as_deref(), Some("Email"));

        m.prompt_id = Some("missing".into());
        assert_eq!(resolve(&cfg, Some(&m)).prompt_id, cfg.enhancement.prompt_id);
    }

    #[test]
    fn detects_leading_and_trailing_triggers() {
        let mut email = mode("Email");
        email.trigger_words = vec!["email".into()];
        let mut chat = mode("Chat");
        chat.trigger_words = vec!["chat mode".into()];
        let modes = vec![email, chat];

        let d = detect_trigger("Email, hi John how are you", &modes).unwrap();
        assert_eq!(d.mode_index, 0);
        assert_eq!(d.processed_text, "Hi John how are you");

        let d = detect_trigger("see you soon chat mode.", &modes).unwrap();
        assert_eq!(d.mode_index, 1);
        assert_eq!(d.processed_text, "See you soon");

        assert!(detect_trigger("emails are great", &modes).is_none());
        assert!(detect_trigger("nothing here", &modes).is_none());
    }
}

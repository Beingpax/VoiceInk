//! Voice snippets: say a short trigger phrase, get a longer saved text
//! (Wispr Flow's "snippets"). Saying only the trigger inserts the snippet
//! verbatim and skips AI enhancement; a trigger inside a longer dictation is
//! expanded in place after enhancement, so the LLM never rewrites it.
//!
//! Snippet text may contain `{date}`, `{time}` and `{datetime}`.

use super::lines::{LineError, parse_pairs};
use super::replacements::replace_phrase;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Snippet {
    /// What you say, e.g. "my calendar link".
    pub trigger: String,
    /// What gets inserted.
    pub text: String,
}

/// Lower-cases, collapses whitespace and strips surrounding punctuation, so
/// "My calendar link." matches the trigger "my calendar link".
pub fn normalize(s: &str) -> String {
    let trimmed = s.trim_matches(|c: char| c.is_whitespace() || ".,!?;:\"'„“”‘’…-".contains(c));
    trimmed.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}

/// Fills in `{date}`, `{time}` and `{datetime}`.
pub fn render(text: &str, now: DateTime<Local>) -> String {
    text.replace("{datetime}", &now.format("%Y-%m-%d %H:%M").to_string())
        .replace("{date}", &now.format("%Y-%m-%d").to_string())
        .replace("{time}", &now.format("%H:%M").to_string())
}

/// The snippet whose trigger is the whole dictation, if any.
pub fn exact_match<'a>(text: &str, snippets: &'a [Snippet]) -> Option<&'a Snippet> {
    let spoken = normalize(text);
    if spoken.is_empty() {
        return None;
    }
    snippets.iter().find(|s| !normalize(&s.trigger).is_empty() && normalize(&s.trigger) == spoken)
}

/// Expands every trigger phrase found inside `text` (longest triggers first).
pub fn expand_inline(text: &str, snippets: &[Snippet], now: DateTime<Local>) -> String {
    let mut sorted: Vec<&Snippet> = snippets.iter().filter(|s| !s.trigger.trim().is_empty()).collect();
    sorted.sort_by_key(|s| std::cmp::Reverse(s.trigger.trim().chars().count()));
    sorted.into_iter().fold(text.to_string(), |acc, s| replace_phrase(&acc, s.trigger.trim(), &render(&s.text, now)))
}

/// Parses the settings editor format: one snippet per line, `trigger => text`,
/// where `\n` in the text stands for a line break. Lines starting with `#` are comments.
///
/// # Errors
/// Returns the first malformed line.
pub fn parse_lines(text: &str) -> Result<Vec<Snippet>, LineError> {
    Ok(parse_pairs(text, "trigger => text")?
        .into_iter()
        .map(|(trigger, body)| Snippet { trigger, text: body.replace("\\n", "\n") })
        .collect())
}

/// Inverse of [`parse_lines`].
pub fn format_lines(snippets: &[Snippet]) -> String {
    snippets.iter().map(|s| format!("{} => {}", s.trigger, s.text.replace('\n', "\\n"))).collect::<Vec<_>>().join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> DateTime<Local> {
        Local.with_ymd_and_hms(2026, 10, 14, 9, 5, 0).unwrap()
    }

    fn snippets() -> Vec<Snippet> {
        vec![
            Snippet { trigger: "my calendar link".into(), text: "https://cal.example.com/me".into() },
            Snippet { trigger: "my address".into(), text: "Main St 1\n12345 Berlin".into() },
            Snippet { trigger: "today".into(), text: "{date}".into() },
        ]
    }

    #[test]
    fn exact_match_ignores_case_and_punctuation() {
        let s = snippets();
        assert_eq!(exact_match("My calendar link.", &s).unwrap().text, "https://cal.example.com/me");
        assert_eq!(exact_match("  my   ADDRESS!  ", &s).unwrap().trigger, "my address");
        assert!(exact_match("send my calendar link", &s).is_none());
        assert!(exact_match("", &s).is_none());
    }

    #[test]
    fn expands_inline_with_boundaries_and_placeholders() {
        let out = expand_inline("Book a slot via My calendar link. Today works.", &snippets(), now());
        assert_eq!(out, "Book a slot via https://cal.example.com/me. 2026-10-14 works.");
        assert_eq!(expand_inline("todays plan", &snippets(), now()), "todays plan");
    }

    #[test]
    fn renders_placeholders() {
        assert_eq!(render("{date} {time} | {datetime}", now()), "2026-10-14 09:05 | 2026-10-14 09:05");
    }

    #[test]
    fn parses_and_formats_lines() {
        let parsed = parse_lines("# comment\nmy address => Main St 1\\n12345 Berlin\nsig -> Best,\\nAlex").unwrap();
        assert_eq!(parsed[0].text, "Main St 1\n12345 Berlin");
        assert_eq!(parsed[1].trigger, "sig");
        assert_eq!(parse_lines(&format_lines(&parsed)).unwrap(), parsed);
        assert!(parse_lines("no separator").is_err());
        assert!(parse_lines("=> text").is_err());
    }
}

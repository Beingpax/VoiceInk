//! Port of `WordReplacementService` / `WordReplacementVariants`.
//!
//! A rule's `original` may hold several comma-separated variants. Longer
//! variants are applied first. Spaced scripts match on Unicode word
//! boundaries (punctuation counts as a boundary); CJK/Thai match as plain
//! case-insensitive substrings.

use super::lines::{LineError, parse_pairs};
use super::words::is_unspaced_script;
use regex::{NoExpand, Regex, RegexBuilder};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordReplacement {
    /// One or more comma-separated source spellings.
    pub original: String,
    pub replacement: String,
}

pub fn parse_variants(text: &str) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    text.split(',')
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .filter(|v| seen.insert(v.to_lowercase()))
        .map(str::to_string)
        .collect()
}

fn uses_word_boundaries(text: &str) -> bool {
    !text.chars().any(is_unspaced_script)
}

pub fn apply_replacements(text: &str, rules: &[WordReplacement]) -> String {
    let mut variants: Vec<(String, &str)> = rules
        .iter()
        .flat_map(|r| parse_variants(&r.original).into_iter().map(move |v| (v, r.replacement.as_str())))
        .collect();
    // Longest first, then stable by case-folded key.
    variants.sort_by(|a, b| {
        b.0.chars().count().cmp(&a.0.chars().count()).then_with(|| a.0.to_lowercase().cmp(&b.0.to_lowercase()))
    });

    let mut out = text.to_string();
    for (original, replacement) in variants {
        let Ok(re) = RegexBuilder::new(&regex::escape(&original)).case_insensitive(true).build() else {
            continue;
        };
        out = if uses_word_boundaries(&original) {
            replace_bounded(&out, &re, replacement)
        } else {
            re.replace_all(&out, NoExpand(replacement)).into_owned()
        };
    }
    out
}

/// Word characters for boundary checks: letters, marks and numbers, except
/// scripts written without spaces (mirrors the Swift character class).
fn is_word_char(ch: char) -> bool {
    ch.is_alphanumeric() && !is_unspaced_script(ch) || is_combining_mark(ch)
}

fn is_combining_mark(ch: char) -> bool {
    matches!(ch as u32, 0x0300..=0x036F | 0x1AB0..=0x1AFF | 0x1DC0..=0x1DFF | 0x20D0..=0x20FF | 0xFE20..=0xFE2F)
}

/// Replaces whole-phrase occurrences of `phrase` (case-insensitive) with `replacement`
/// literally, using the same boundary rules as dictionary replacements.
pub fn replace_phrase(text: &str, phrase: &str, replacement: &str) -> String {
    let phrase = phrase.trim();
    if phrase.is_empty() {
        return text.to_string();
    }
    let Ok(re) = RegexBuilder::new(&regex::escape(phrase)).case_insensitive(true).build() else {
        return text.to_string();
    };
    if uses_word_boundaries(phrase) {
        replace_bounded(text, &re, replacement)
    } else {
        re.replace_all(text, NoExpand(replacement)).into_owned()
    }
}

/// Equivalent of `(?<!\w)pattern(?!\w)`, which Rust's `regex` cannot express.
fn replace_bounded(text: &str, re: &Regex, replacement: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last = 0;
    let mut search = 0;
    while let Some(m) = re.find_at(text, search) {
        let before_ok = !text[..m.start()].chars().next_back().is_some_and(is_word_char);
        let after_ok = !text[m.end()..].chars().next().is_some_and(is_word_char);
        if before_ok && after_ok && !m.is_empty() {
            out.push_str(&text[last..m.start()]);
            out.push_str(replacement);
            last = m.end();
            search = m.end();
        } else {
            // Retry one character later so overlapping candidates are considered.
            match text[m.start()..].chars().next() {
                Some(c) => search = m.start() + c.len_utf8(),
                None => break,
            }
        }
        if search > text.len() {
            break;
        }
    }
    out.push_str(&text[last..]);
    out
}

/// Parses `spoken -> written` lines (also accepts `=>` and `→`).
///
/// # Errors
/// Returns the first malformed line.
pub fn parse_replacement_lines(text: &str) -> Result<Vec<WordReplacement>, LineError> {
    Ok(parse_pairs(text, "spoken -> written")?
        .into_iter()
        .map(|(original, replacement)| WordReplacement { original, replacement })
        .collect())
}

/// Inverse of [`parse_replacement_lines`].
pub fn format_replacement_lines(rules: &[WordReplacement]) -> String {
    rules.iter().map(|r| format!("{} -> {}", r.original, r.replacement)).collect::<Vec<_>>().join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(o: &str, r: &str) -> WordReplacement {
        WordReplacement { original: o.into(), replacement: r.into() }
    }

    #[test]
    fn replaces_whole_words_case_insensitively() {
        let rules = [rule("voice ink, voiceink", "VoiceInk")];
        assert_eq!(
            apply_replacements("I love voice ink. Voiceink rocks, voiceinks no.", &rules),
            "I love VoiceInk. VoiceInk rocks, voiceinks no."
        );
    }

    #[test]
    fn adjacent_matches_are_all_replaced() {
        let rules = [rule("a", "b")];
        assert_eq!(apply_replacements("a a a", &rules), "b b b");
    }

    #[test]
    fn longer_variants_win() {
        let rules = [rule("new york", "NYC"), rule("new", "fresh")];
        assert_eq!(apply_replacements("new york is new", &rules), "NYC is fresh");
    }

    #[test]
    fn cjk_uses_substring_matching() {
        let rules = [rule("東京", "Tokyo")];
        assert_eq!(apply_replacements("私は東京に", &rules), "私はTokyoに");
    }

    #[test]
    fn parses_replacement_lines() {
        let r = parse_replacement_lines("voice ink, voice inc -> VoiceInk\n\n# comment\nk8s => Kubernetes\nai → AI")
            .unwrap();
        assert_eq!(r.len(), 3);
        assert_eq!(r[0].original, "voice ink, voice inc");
        assert_eq!(r[0].replacement, "VoiceInk");
        assert_eq!(r[2].replacement, "AI");
        assert!(parse_replacement_lines("no arrow here").is_err());
        assert!(parse_replacement_lines(" -> x").is_err());
    }

    #[test]
    fn replacement_is_literal() {
        let rules = [rule("price", "$1")];
        assert_eq!(apply_replacements("the price", &rules), "the $1");
    }

    #[test]
    fn format_round_trips_through_parse() {
        let rules = vec![rule("voice ink, voice inc", "VoiceInk"), rule("gh", "GitHub")];
        assert_eq!(parse_replacement_lines(&format_replacement_lines(&rules)).unwrap(), rules);
    }
}

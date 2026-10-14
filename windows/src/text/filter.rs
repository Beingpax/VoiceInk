//! Ports of `TranscriptionOutputFilter` and `AIEnhancementOutputFilter`.

use regex::{Regex, RegexBuilder};
use std::sync::OnceLock;

/// Same defaults as `FillerWordManager.defaultFillerWords`.
pub const DEFAULT_FILLER_WORDS: &[&str] = &[
    "uh", "um", "uhm", "umm", "uhh", "uhhh", "hmm", "hm", "mmm", "mm", "mh", "ehh",
];

fn regex(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("static regex"))
}

/// Removes `<tag ...>...</tag>` blocks. Rust's `regex` has no back-references,
/// so the closing tag is located manually for every opening tag.
fn remove_tag_blocks(text: &str) -> String {
    static OPEN: OnceLock<Regex> = OnceLock::new();
    let open = regex(&OPEN, r"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>");

    let mut out = String::with_capacity(text.len());
    let mut pos = 0;
    while pos < text.len() {
        let Some(caps) = open.captures_at(text, pos) else {
            break;
        };
        let whole = caps.get(0).unwrap();
        let closing = format!("</{}>", &caps[1]);
        if let Some(rel) = text[whole.end()..].find(&closing) {
            out.push_str(&text[pos..whole.start()]);
            pos = whole.end() + rel + closing.len();
        } else {
            // No closing tag: keep the opening tag and keep scanning after its first character.
            let next = whole.start() + 1;
            out.push_str(&text[pos..next]);
            pos = next;
        }
    }
    out.push_str(&text[pos.min(text.len())..]);
    out
}

/// Cleans raw ASR output: strips tag blocks, bracketed hallucinations
/// (`[MUSIC]`, `(laughs)`, `{noise}`), filler words and redundant whitespace.
pub fn filter_transcription(text: &str, filler_words: &[String]) -> String {
    static BRACKETS: OnceLock<Regex> = OnceLock::new();
    static SPACES: OnceLock<Regex> = OnceLock::new();

    let mut filtered = remove_tag_blocks(text);
    filtered = regex(&BRACKETS, r"\[.*?\]|\(.*?\)|\{.*?\}")
        .replace_all(&filtered, "")
        .into_owned();

    for word in filler_words
        .iter()
        .map(|w| w.trim())
        .filter(|w| !w.is_empty())
    {
        let pattern = format!(r"\b{}\b[,.]?", regex::escape(word));
        if let Ok(re) = RegexBuilder::new(&pattern).case_insensitive(true).build() {
            filtered = re.replace_all(&filtered, "").into_owned();
        }
    }

    filtered = regex(&SPACES, r"\s{2,}")
        .replace_all(&filtered, " ")
        .into_owned();
    filtered.trim().to_string()
}

/// Strips reasoning blocks that some LLMs emit before their answer.
pub fn filter_enhancement_output(text: &str) -> String {
    static THINKING: OnceLock<Regex> = OnceLock::new();
    let re = regex(
        &THINKING,
        r"(?s)<thinking>.*?</thinking>|<think>.*?</think>|<reasoning>.*?</reasoning>",
    );
    re.replace_all(text, "").trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fillers() -> Vec<String> {
        DEFAULT_FILLER_WORDS.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn removes_hallucinations_and_fillers() {
        let out = filter_transcription("Um, hello [MUSIC] there (laughs) uh world.", &fillers());
        assert_eq!(out, "hello there world.");
    }

    #[test]
    fn removes_matching_tag_blocks_only() {
        assert_eq!(filter_transcription("a <x>b</x> c", &[]), "a c");
        assert_eq!(filter_transcription("a <x>b c", &[]), "a <x>b c");
        assert_eq!(filter_transcription("<b>x</b><i>y</i>z", &[]), "z");
    }

    #[test]
    fn filler_words_respect_word_boundaries() {
        assert_eq!(
            filter_transcription("umbrella hum", &fillers()),
            "umbrella hum"
        );
    }

    #[test]
    fn strips_think_blocks() {
        assert_eq!(
            filter_enhancement_output("<think>\nplan\n</think>\n Final "),
            "Final"
        );
        assert_eq!(
            filter_enhancement_output("<reasoning>r</reasoning>A<thinking>t</thinking>"),
            "A"
        );
    }
}

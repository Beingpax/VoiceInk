//! Port of `ParagraphFormatter`: groups sentences into paragraphs of roughly
//! 50 words, capped at four "significant" (4+ word) sentences each.

use super::words::word_count;

const TARGET_WORD_COUNT: usize = 50;
const MAX_SENTENCES_PER_CHUNK: usize = 4;
const MIN_WORDS_FOR_SIGNIFICANT_SENTENCE: usize = 4;

/// Splits text into sentences on terminal punctuation followed by whitespace
/// (or on CJK full-width terminators, which need no whitespace).
pub fn split_sentences(text: &str) -> Vec<String> {
    let mut sentences = Vec::new();
    let mut current = String::new();
    let mut chars = text.chars().peekable();

    while let Some(ch) = chars.next() {
        current.push(ch);
        let boundary = match ch {
            '。' | '！' | '？' | '\n' => true,
            '.' | '!' | '?' | '…' => {
                // Absorb closing quotes/brackets and repeated punctuation.
                while let Some(&next) = chars.peek() {
                    if matches!(next, '.' | '!' | '?' | '"' | '\'' | '”' | '’' | ')' | ']') {
                        current.push(next);
                        chars.next();
                    } else {
                        break;
                    }
                }
                chars.peek().is_none_or(|c| c.is_whitespace())
            }
            _ => false,
        };
        if boundary {
            let trimmed = current.trim();
            if !trimmed.is_empty() {
                sentences.push(trimmed.to_string());
            }
            current.clear();
        }
    }
    let trimmed = current.trim();
    if !trimmed.is_empty() {
        sentences.push(trimmed.to_string());
    }
    sentences
}

pub fn format_paragraphs(text: &str) -> String {
    let sentences = split_sentences(text);
    if sentences.is_empty() {
        return String::new();
    }

    let mut paragraphs: Vec<String> = Vec::new();
    let mut index = 0;
    while index < sentences.len() {
        let mut tentative: Vec<&str> = Vec::new();
        let mut words = 0;
        let mut significant = 0;
        for sentence in &sentences[index..] {
            let n = word_count(sentence);
            tentative.push(sentence);
            words += n;
            if n >= MIN_WORDS_FOR_SIGNIFICANT_SENTENCE {
                significant += 1;
            }
            if words >= TARGET_WORD_COUNT {
                break;
            }
        }

        let chunk: Vec<&str> = if significant > MAX_SENTENCES_PER_CHUNK {
            let mut kept = Vec::new();
            let mut counted = 0;
            for sentence in tentative {
                kept.push(sentence);
                if word_count(sentence) >= MIN_WORDS_FOR_SIGNIFICANT_SENTENCE {
                    counted += 1;
                    if counted >= MAX_SENTENCES_PER_CHUNK {
                        break;
                    }
                }
            }
            kept
        } else {
            tentative
        };

        if chunk.is_empty() {
            break;
        }
        index += chunk.len();
        paragraphs.push(chunk.join(" "));
    }

    paragraphs.join("\n\n").trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_sentences() {
        assert_eq!(
            split_sentences("Hi there. How are you? Fine! Version 1.5 works."),
            vec!["Hi there.", "How are you?", "Fine!", "Version 1.5 works."]
        );
    }

    #[test]
    fn short_text_stays_one_paragraph() {
        assert_eq!(format_paragraphs("One two. Three four."), "One two. Three four.");
    }

    #[test]
    fn caps_significant_sentences_per_paragraph() {
        let s = "This is a sentence. ".repeat(6);
        let out = format_paragraphs(&s);
        let paragraphs: Vec<&str> = out.split("\n\n").collect();
        assert_eq!(paragraphs.len(), 2);
        assert_eq!(paragraphs[0].matches("sentence.").count(), 4);
    }

    #[test]
    fn breaks_on_word_target() {
        let long = format!("{}.", "word ".repeat(60).trim());
        let text = format!("{long} Next one here.");
        assert_eq!(format_paragraphs(&text).split("\n\n").count(), 2);
    }
}

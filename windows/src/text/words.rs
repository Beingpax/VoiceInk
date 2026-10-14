//! Word counting (stand-in for `NLTokenizer(unit: .word)`).

/// Counts words. Runs of letters/digits (plus inner apostrophes) are one word;
/// CJK ideographs, kana and Thai count one word per character since those
/// scripts do not separate words with spaces.
pub fn word_count(text: &str) -> usize {
    let mut count = 0;
    let mut in_word = false;
    for ch in text.chars() {
        if is_unspaced_script(ch) {
            count += 1;
            in_word = false;
        } else if ch.is_alphanumeric() || (in_word && (ch == '\'' || ch == '’')) {
            if !in_word {
                count += 1;
                in_word = true;
            }
        } else {
            in_word = false;
        }
    }
    count
}

pub(crate) fn is_unspaced_script(ch: char) -> bool {
    matches!(ch as u32,
        0x3040..=0x309F | 0x30A0..=0x30FF | 0x4E00..=0x9FFF | 0xAC00..=0xD7AF | 0x0E00..=0x0E7F)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_words() {
        assert_eq!(word_count(""), 0);
        assert_eq!(word_count("Hello, world!"), 2);
        assert_eq!(word_count("It's 5 o'clock."), 3);
        assert_eq!(word_count("日本語"), 3);
    }
}

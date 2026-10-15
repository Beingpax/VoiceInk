//! The `left -> right` line format used by the dictionary and snippet editors.

/// Accepted separators between the two sides of a line.
const SEPARATORS: [&str; 3] = ["->", "=>", "→"];

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum LineError {
    #[error("line {line} needs \"{expected}\": {content}")]
    MissingSeparator { line: usize, expected: &'static str, content: String },
    #[error("line {line} has nothing before the arrow")]
    EmptyLeftSide { line: usize },
}

/// Parses non-empty, non-comment (`#`) lines into trimmed `(left, right)`
/// pairs, splitting at the first separator. `expected` describes the format
/// in error messages, e.g. `"spoken -> written"`.
///
/// # Errors
/// Returns the first malformed line as a [`LineError`] (1-based line numbers).
pub fn parse_pairs(text: &str, expected: &'static str) -> Result<Vec<(String, String)>, LineError> {
    let mut pairs = Vec::new();
    for (index, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let split =
            SEPARATORS.iter().filter_map(|sep| line.find(sep).map(|at| (at, sep.len()))).min_by_key(|&(at, _)| at);
        let Some((at, len)) = split else {
            return Err(LineError::MissingSeparator { line: index + 1, expected, content: line.to_string() });
        };
        let (left, right) = (line[..at].trim(), line[at + len..].trim());
        if left.is_empty() {
            return Err(LineError::EmptyLeftSide { line: index + 1 });
        }
        pairs.push((left.to_string(), right.to_string()));
    }
    Ok(pairs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_at_the_first_separator_and_skips_comments() {
        let pairs = parse_pairs("# note\n a -> b => c \n\nx → y", "a -> b").unwrap();
        assert_eq!(pairs, [("a".into(), "b => c".into()), ("x".into(), "y".into())]);
    }

    #[test]
    fn reports_line_numbers() {
        assert_eq!(
            parse_pairs("ok -> fine\nbroken", "a -> b"),
            Err(LineError::MissingSeparator { line: 2, expected: "a -> b", content: "broken".into() })
        );
        assert_eq!(parse_pairs(" -> x", "a -> b"), Err(LineError::EmptyLeftSide { line: 1 }));
    }
}

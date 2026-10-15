//! The sections of the dashboard & settings window. Shared by the CLI
//! (`voiceink settings`) and the Windows UI, so neither uses magic indices.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsPage {
    Dashboard,
    General,
    Transcription,
    Enhancement,
    Prompts,
    Dictionary,
    Snippets,
    CommandMode,
    Output,
    History,
}

impl SettingsPage {
    /// Navigation order.
    pub const ALL: [Self; 10] = [
        Self::Dashboard,
        Self::General,
        Self::Transcription,
        Self::Enhancement,
        Self::Prompts,
        Self::Dictionary,
        Self::Snippets,
        Self::CommandMode,
        Self::Output,
        Self::History,
    ];

    pub fn title(self) -> &'static str {
        match self {
            Self::Dashboard => "Dashboard",
            Self::General => "General",
            Self::Transcription => "Transcription",
            Self::Enhancement => "AI Enhancement",
            Self::Prompts => "Prompts",
            Self::Dictionary => "Dictionary",
            Self::Snippets => "Snippets",
            Self::CommandMode => "Command Mode",
            Self::Output => "Output",
            Self::History => "History",
        }
    }

    /// Position in [`Self::ALL`].
    pub fn index(self) -> usize {
        self as usize
    }

    pub fn from_index(index: usize) -> Option<Self> {
        Self::ALL.get(index).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn index_round_trips_in_navigation_order() {
        for (i, page) in SettingsPage::ALL.into_iter().enumerate() {
            assert_eq!(page.index(), i);
            assert_eq!(SettingsPage::from_index(i), Some(page));
        }
        assert_eq!(SettingsPage::from_index(SettingsPage::ALL.len()), None);
    }
}

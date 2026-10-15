//! Settings window behaviour, driven through its messages and rendered
//! headlessly with `iced_test`.

use super::*;
use crate::config::{Config, HotkeyMode};
use crate::paths::AppPaths;
use std::cell::RefCell;
use std::path::{Path, PathBuf};

/// Records what the pages asked the operating system to do.
#[derive(Default)]
struct FakeDesktop {
    copied: RefCell<Vec<String>>,
    opened: RefCell<Vec<PathBuf>>,
}

impl Desktop for FakeDesktop {
    fn input_devices(&self) -> Vec<String> {
        vec!["USB Microphone".into()]
    }

    fn copy_text(&self, text: &str) -> Result<(), String> {
        self.copied.borrow_mut().push(text.into());
        Ok(())
    }

    fn open_path(&self, path: &Path) {
        self.opened.borrow_mut().push(path.into());
    }
}

struct Fixture {
    dir: PathBuf,
    desktop: Rc<FakeDesktop>,
    window: SettingsWindow,
}

impl Fixture {
    fn new(page: SettingsPage) -> Self {
        let dir = std::env::temp_dir().join(format!("voiceink-ui-{}", uuid::Uuid::new_v4()));
        let ctx = AppContext::new(AppPaths::new(&dir));
        let desktop = Rc::new(FakeDesktop::default());
        let window = SettingsWindow::new(ctx, Rc::clone(&desktop) as Rc<dyn Desktop>, page).unwrap();
        Self { dir, desktop, window }
    }

    fn send(&mut self, message: Message) -> Outcome {
        self.window.update(message)
    }

    fn saved_config(&self) -> Config {
        Config::load(&self.dir.join("config.json")).unwrap()
    }

    fn status(&self) -> Option<&Status> {
        self.window.status.as_ref()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.dir).ok();
    }
}

#[test]
fn save_writes_edited_fields() {
    let mut f = Fixture::new(SettingsPage::General);
    f.send(Message::General(general::Message::Record("F9".into())));
    f.send(Message::General(general::Message::Mode(style::Labeled::new(HotkeyMode::Toggle, "Toggle"))));
    f.send(Message::General(general::Message::Microphone("USB Microphone".into())));
    f.send(Message::Output(output::Message::RestoreDelay("750".into())));

    assert_eq!(f.send(Message::Save), Outcome::Saved);
    let saved = f.saved_config();
    assert_eq!(saved.hotkeys.record, "F9");
    assert_eq!(saved.hotkeys.mode, HotkeyMode::Toggle);
    assert_eq!(saved.audio.input_device.as_deref(), Some("USB Microphone"));
    assert_eq!(saved.output.clipboard_restore_delay_ms, 750);
    assert_eq!(f.status(), Some(&Status::info("Settings saved.")));
}

#[test]
fn invalid_input_is_reported_on_its_page_and_nothing_is_written() {
    let mut f = Fixture::new(SettingsPage::Dashboard);
    let before = f.saved_config();
    f.send(Message::Output(output::Message::RestoreDelay("soon".into())));

    assert_eq!(f.send(Message::Save), Outcome::None);
    assert_eq!(f.window.page, SettingsPage::Output);
    assert_eq!(f.status(), Some(&Status::error("Restore delay must be a number")));
    assert_eq!(f.saved_config(), before);
}

#[test]
fn command_shortcut_must_differ_from_record_shortcut() {
    let mut f = Fixture::new(SettingsPage::CommandMode);
    f.send(Message::Command(command::Message::Hotkey("RightCtrl".into())));

    assert_eq!(f.send(Message::Save), Outcome::None);
    assert_eq!(f.window.page, SettingsPage::CommandMode);
    assert!(f.status().is_some_and(|s| s.is_error && s.text.contains("must differ")));
}

#[test]
fn typed_api_key_is_stored_and_can_be_removed() {
    let mut f = Fixture::new(SettingsPage::Transcription);
    f.send(Message::Transcription(transcription::Message::Key(form::KeyMessage::Input(" sk-test ".into()))));
    assert_eq!(f.send(Message::Save), Outcome::Saved);
    assert_eq!(f.window.ctx.secrets.get("openai").as_deref(), Some("sk-test"));

    f.send(Message::Transcription(transcription::Message::Key(form::KeyMessage::Remove)));
    assert!(!f.window.ctx.secrets.has("openai"));
    assert_eq!(f.status(), Some(&Status::info("Removed the openai API key")));
}

#[test]
fn prompts_can_be_added_but_not_all_deleted() {
    let mut f = Fixture::new(SettingsPage::Prompts);
    let count = f.window.config.prompts.len();
    f.send(Message::Prompts(prompts::Message::New));
    assert_eq!(f.window.config.prompts.len(), count + 1);

    for _ in 0..=count {
        f.send(Message::Prompts(prompts::Message::Delete));
    }
    assert_eq!(f.window.config.prompts.len(), 1);
    assert_eq!(f.status(), Some(&Status::error("At least one prompt is required.")));
}

#[test]
fn history_clear_needs_confirmation_and_dashboard_copies_entries() {
    let mut f = Fixture::new(SettingsPage::Dashboard);
    let mut entry = crate::history::Entry::new(crate::history::Status::Completed);
    entry.text = "hello world".into();
    f.window.ctx.history.append(&entry).unwrap();
    f.window.history_changed();

    f.send(Message::Dashboard(dashboard::Message::Copy(0)));
    assert_eq!(*f.desktop.copied.borrow(), vec!["hello world".to_string()]);

    f.send(Message::Navigate(SettingsPage::History));
    f.send(Message::History(history::Message::Clear));
    assert_eq!(f.window.ctx.history.load().len(), 1, "first click only asks");
    f.send(Message::History(history::Message::ConfirmClear));
    assert_eq!(f.window.ctx.history.load(), vec![]);
}

#[test]
fn closing_and_navigation_are_reported() {
    let mut f = Fixture::new(SettingsPage::Dashboard);
    assert_eq!(f.send(Message::Navigate(SettingsPage::Snippets)), Outcome::None);
    assert_eq!(f.window.page, SettingsPage::Snippets);
    assert_eq!(f.send(Message::Close), Outcome::Close);
}

#[test]
fn every_page_renders_and_buttons_produce_messages() {
    for page in SettingsPage::ALL {
        let f = Fixture::new(page);
        let mut ui = iced_test::simulator(f.window.view());
        ui.click("Save").unwrap_or_else(|e| panic!("{page:?}: {e}"));
        let messages: Vec<Message> = ui.into_messages().collect();
        assert!(matches!(messages.as_slice(), [Message::Save]), "{page:?}: {messages:?}");
    }
}

/// Writes a PNG of every page to `$VOICEINK_SCREENSHOTS` (for docs and
/// visual review): `VOICEINK_SCREENSHOTS=/tmp/shots cargo test -- --ignored`.
#[test]
#[ignore = "writes screenshots; run on demand"]
fn render_screenshots() {
    let Some(dir) = std::env::var_os("VOICEINK_SCREENSHOTS").map(PathBuf::from) else { return };
    for page in SettingsPage::ALL {
        let f = Fixture::new(page);
        let mut ui = iced_test::Simulator::with_size(iced::Settings::default(), (1000.0, 700.0), f.window.view());
        let snapshot = ui.snapshot(&style::theme()).unwrap();
        let path = dir.join(format!("{page:?}").to_lowercase());
        std::fs::remove_file(path.with_extension("png")).ok();
        assert!(snapshot.matches_image(&path).unwrap());
    }
}

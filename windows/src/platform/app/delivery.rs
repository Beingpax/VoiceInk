//! Puts the final text where the user wants it: pasted into the target
//! window or handed to a mode's custom command. Runs on worker threads.

use super::super::tray::NoticeKind;
use super::super::{foreground, paste};
use super::events::{SendHwnd, UiSender};
use crate::config::{OutputMode, OutputSettings, SendKey};
use crate::pipeline::Delivery;
use std::io::Write;
use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const COMMAND_TIMEOUT: Duration = Duration::from_secs(10);
const COMMAND_POLL_INTERVAL: Duration = Duration::from_millis(50);
const SEND_KEY_DELAY: Duration = Duration::from_millis(150);
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Why a custom command failed.
#[derive(Debug, thiserror::Error)]
pub enum CommandError {
    #[error("cannot run the command: {0}")]
    Io(#[from] std::io::Error),
    #[error("exit code {code}: {stderr}")]
    Failed { code: i32, stderr: String },
    #[error("timed out after {} seconds", COMMAND_TIMEOUT.as_secs())]
    TimedOut,
}

/// Delivers `delivery` on a worker thread; problems become tray notices.
pub fn deliver(delivery: Delivery, target: SendHwnd, output: OutputSettings, events: UiSender) {
    std::thread::spawn(move || match delivery.output {
        OutputMode::Paste => {
            foreground::restore_focus(target.get());
            if let Err(e) = paste::paste_text(&delivery.text, &output, delivery.send_key) {
                events.notice("Paste failed", &e.to_string(), NoticeKind::Warning);
            }
        }
        OutputMode::CustomCommand => {
            let Some(command) = delivery.custom_command else {
                events.notice("Custom command", "No command configured for this mode", NoticeKind::Warning);
                return;
            };
            match run_custom_command(&command, &delivery.text) {
                Ok(()) if delivery.send_key != SendKey::None => {
                    std::thread::sleep(SEND_KEY_DELAY);
                    paste::press_send_key(delivery.send_key);
                }
                Ok(()) => {}
                Err(e) => events.notice("Custom command failed", &e.to_string(), NoticeKind::Warning),
            }
        }
    });
}

/// Runs a mode's custom command with the text on stdin and in `VOICEINK_TRANSCRIPT`.
///
/// # Errors
/// Fails when the command cannot start, exits with an error or takes too long.
pub fn run_custom_command(command: &str, text: &str) -> Result<(), CommandError> {
    let mut child = Command::new("cmd")
        .args(["/D", "/S", "/C", command])
        .env("VOICEINK_TRANSCRIPT", text)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        // A command that ignores stdin closes the pipe early; that is fine.
        let _ = stdin.write_all(text.as_bytes());
    }
    let deadline = Instant::now() + COMMAND_TIMEOUT;
    loop {
        if let Some(status) = child.try_wait()? {
            if status.success() {
                return Ok(());
            }
            let output = child.wait_with_output()?;
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            return Err(CommandError::Failed { code: status.code().unwrap_or(-1), stderr });
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            return Err(CommandError::TimedOut);
        }
        std::thread::sleep(COMMAND_POLL_INTERVAL);
    }
}

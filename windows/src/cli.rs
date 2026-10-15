//! Command-line interface: argument parsing (pure, tested) and execution.

use anyhow::{Context, Result, bail};
use std::io::Write;
use std::sync::atomic::AtomicBool;
use voiceink::audio::wav;
use voiceink::config::credential_keys;
use voiceink::context::AppContext;
use voiceink::pipeline::{Pipeline, PipelineInput};
use voiceink::settings_page::SettingsPage;

pub const HELP: &str = "\
VoiceInk for Windows — voice to text in any app

USAGE:
    voiceink                          Start the tray app (default)
    voiceink dashboard                Open the dashboard (starts the app if needed)
    voiceink settings                 Open the settings
    voiceink set-key <provider> <key> Store an API key (encrypted with DPAPI)
    voiceink remove-key <provider>    Delete a stored API key
    voiceink keys                     List providers that have a key
    voiceink transcribe <file.wav>    Run the full pipeline on a WAV file and print the result
    voiceink devices                  List microphones
    voiceink history [count]          Print recent transcriptions
    voiceink export-history <out.csv> Export the history as CSV
    voiceink config-path              Print the settings file location
    voiceink --version

PROVIDERS:
    transcription: openai, groq, deepgram, elevenlabs, mistral, custom-transcription
    enhancement:   openai, anthropic, gemini, groq, cerebras, mistral, openrouter, custom-enhancement
";

const DEFAULT_HISTORY_COUNT: usize = 10;

/// What the user asked for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    /// Start the tray app, optionally opening a settings page.
    App {
        page: Option<SettingsPage>,
    },
    Help,
    Version,
    ConfigPath,
    SetKey {
        name: String,
        key: String,
    },
    RemoveKey {
        name: String,
    },
    Keys,
    Transcribe {
        file: String,
    },
    Devices,
    History {
        count: usize,
    },
    ExportHistory {
        file: String,
    },
}

/// Parses the arguments after the program name.
///
/// # Errors
/// Fails on unknown commands, missing arguments and unknown provider names.
pub fn parse(args: &[String]) -> Result<Command> {
    let arg = |i: usize, usage: &str| args.get(i).cloned().with_context(|| format!("usage: voiceink {usage}"));
    let Some(first) = args.first() else {
        return Ok(Command::App { page: None });
    };
    Ok(match first.as_str() {
        "dashboard" => Command::App { page: Some(SettingsPage::Dashboard) },
        "settings" => Command::App { page: Some(SettingsPage::General) },
        "-h" | "--help" | "help" => Command::Help,
        "-V" | "--version" => Command::Version,
        "config-path" => Command::ConfigPath,
        "set-key" => Command::SetKey {
            name: provider_name(&arg(1, "set-key <provider> <key>")?)?,
            key: arg(2, "set-key <provider> <key>")?,
        },
        "remove-key" => Command::RemoveKey { name: provider_name(&arg(1, "remove-key <provider>")?)? },
        "keys" => Command::Keys,
        "transcribe" => Command::Transcribe { file: arg(1, "transcribe <file.wav>")? },
        "devices" => Command::Devices,
        "history" => Command::History {
            count: args
                .get(1)
                .map(|n| n.parse())
                .transpose()
                .context("count must be a number")?
                .unwrap_or(DEFAULT_HISTORY_COUNT),
        },
        "export-history" => Command::ExportHistory { file: arg(1, "export-history <out.csv>")? },
        other => bail!("unknown command '{other}'\n\n{HELP}"),
    })
}

fn provider_name(name: &str) -> Result<String> {
    let name = name.to_ascii_lowercase();
    if credential_keys().contains(&name.as_str()) {
        Ok(name)
    } else {
        bail!("unknown provider '{name}'. Known: {}", credential_keys().join(", "))
    }
}

/// Runs a non-GUI command, writing results to `out`.
///
/// # Errors
/// Returns any failure with context for the user.
pub fn execute(command: Command, ctx: &AppContext, out: &mut impl Write) -> Result<()> {
    match command {
        Command::App { .. } => bail!("the tray app is started by `main`"),
        Command::Help => write!(out, "{HELP}")?,
        Command::Version => writeln!(out, "VoiceInk for Windows {}", voiceink::APP_VERSION)?,
        Command::ConfigPath => writeln!(out, "{}", ctx.paths.config().display())?,
        Command::SetKey { name, key } => {
            ctx.secrets.set(&name, &key)?;
            writeln!(out, "Stored API key for {name}.")?;
        }
        Command::RemoveKey { name } => {
            ctx.secrets.remove(&name)?;
            writeln!(out, "Removed API key for {name}.")?;
        }
        Command::Keys => {
            for name in credential_keys() {
                let state = if ctx.secrets.has(name) { "configured" } else { "-" };
                writeln!(out, "{name:<22} {state}")?;
            }
        }
        Command::Transcribe { file } => transcribe_file(&file, ctx, out)?,
        Command::Devices => list_devices(out)?,
        Command::History { count } => {
            for e in ctx.history.load().iter().rev().take(count) {
                writeln!(
                    out,
                    "{} [{:?}] {:.1}s {}\n  {}\n",
                    e.timestamp.format("%Y-%m-%d %H:%M:%S"),
                    e.status,
                    e.duration,
                    e.mode_name.as_deref().unwrap_or(""),
                    e.final_text().replace('\n', "\n  ")
                )?;
            }
        }
        Command::ExportHistory { file } => {
            let count = ctx.history.export_csv_file(file.as_ref()).with_context(|| format!("cannot write {file}"))?;
            writeln!(out, "Exported {count} entries to {file}")?;
        }
    }
    Ok(())
}

fn transcribe_file(file: &str, ctx: &AppContext, out: &mut impl Write) -> Result<()> {
    let bytes = std::fs::read(file).with_context(|| format!("cannot read {file}"))?;
    let samples = wav::load_wav_16k(&bytes).with_context(|| format!("cannot decode {file}"))?;
    let config = ctx.load_config()?;
    let input = PipelineInput { samples, ..PipelineInput::default() };
    let output = Pipeline::new(&config, ctx.services.as_ref(), &AtomicBool::new(false), &|stage| {
        eprintln!("{stage:?}…");
    })
    .run(&input);
    if let Some(error) = output.error {
        bail!(error);
    }
    if let Some(warning) = &output.warning {
        eprintln!("warning: {warning}");
    }
    writeln!(out, "{}", output.entry.final_text())?;
    ctx.history.record(&config.history, output.entry, &input.samples)?;
    Ok(())
}

#[cfg(windows)]
fn list_devices(out: &mut impl Write) -> Result<()> {
    for (name, is_default) in voiceink::platform::capture::list_input_devices()? {
        writeln!(out, "{}{name}", if is_default { "* " } else { "  " })?;
    }
    Ok(())
}

#[cfg(not(windows))]
fn list_devices(_out: &mut impl Write) -> Result<()> {
    bail!("device listing is only available on Windows")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_str(args: &[&str]) -> Result<Command> {
        parse(&args.iter().map(|s| (*s).to_string()).collect::<Vec<_>>())
    }

    #[test]
    fn parses_commands() {
        assert_eq!(parse_str(&[]).unwrap(), Command::App { page: None });
        assert_eq!(parse_str(&["dashboard"]).unwrap(), Command::App { page: Some(SettingsPage::Dashboard) });
        assert_eq!(
            parse_str(&["set-key", "OpenAI", "sk"]).unwrap(),
            Command::SetKey { name: "openai".into(), key: "sk".into() }
        );
        assert_eq!(parse_str(&["history"]).unwrap(), Command::History { count: DEFAULT_HISTORY_COUNT });
        assert_eq!(parse_str(&["history", "3"]).unwrap(), Command::History { count: 3 });
    }

    #[test]
    fn rejects_bad_input() {
        assert!(parse_str(&["set-key", "nope", "x"]).is_err());
        assert!(parse_str(&["set-key", "openai"]).is_err());
        assert!(parse_str(&["history", "many"]).is_err());
        assert!(parse_str(&["frobnicate"]).is_err());
    }

    #[test]
    fn executes_key_commands_against_a_temp_dir() {
        let dir = std::env::temp_dir().join(format!("voiceink-cli-{}", uuid::Uuid::new_v4()));
        let ctx = AppContext::new(voiceink::paths::AppPaths::new(&dir));
        let mut out = Vec::new();
        execute(Command::SetKey { name: "groq".into(), key: "gsk".into() }, &ctx, &mut out).unwrap();
        execute(Command::Keys, &ctx, &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("Stored API key for groq."));
        assert!(text.lines().any(|l| l.starts_with("groq") && l.ends_with("configured")));
        std::fs::remove_dir_all(dir).ok();
    }
}

// Release builds are GUI-subsystem apps (no console window); CLI subcommands
// re-attach to the parent console, see `platform::attach_parent_console`.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

use std::sync::atomic::AtomicBool;
use voiceink::config::{self, Config, EnhancementProvider, TranscriptionProvider};
use voiceink::{audio, credentials, history, pipeline};

const HELP: &str = "\
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

fn known_key_names() -> Vec<&'static str> {
    let mut names: Vec<&str> = TranscriptionProvider::ALL
        .iter()
        .map(|p| p.key_name())
        .chain(EnhancementProvider::ALL.iter().map(|p| p.key_name()))
        .filter(|n| !n.is_empty())
        .collect();
    names.sort_unstable();
    names.dedup();
    names
}

fn init_logging() {
    use simplelog::{ConfigBuilder, LevelFilter, WriteLogger};
    let dir = config::data_dir();
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("voiceink.log");
    // Start fresh once the log grows large; otherwise append (a second instance must not wipe it).
    if std::fs::metadata(&path).is_ok_and(|m| m.len() > 2 * 1024 * 1024) {
        let _ = std::fs::remove_file(&path);
    }
    if let Ok(file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        let cfg = ConfigBuilder::new().set_time_format_rfc3339().build();
        let _ = WriteLogger::init(LevelFilter::Info, cfg, file);
    }
}

fn load_config() -> Result<Config, String> {
    Config::load(&config::config_path())
}

fn cli(args: &[String]) -> Result<(), String> {
    match args[0].as_str() {
        "-h" | "--help" | "help" => print!("{HELP}"),
        "-V" | "--version" => println!("VoiceInk for Windows {}", voiceink::APP_VERSION),
        "config-path" => println!("{}", config::config_path().display()),
        "set-key" => {
            let (Some(name), Some(key)) = (args.get(1), args.get(2)) else {
                return Err("usage: voiceink set-key <provider> <key>".into());
            };
            let name = name.to_ascii_lowercase();
            if !known_key_names().contains(&name.as_str()) {
                return Err(format!(
                    "unknown provider '{name}'. Known: {}",
                    known_key_names().join(", ")
                ));
            }
            credentials::set(&name, key)?;
            println!("Stored API key for {name}.");
        }
        "remove-key" => {
            let name = args.get(1).ok_or("usage: voiceink remove-key <provider>")?;
            credentials::remove(&name.to_ascii_lowercase())?;
            println!("Removed API key for {name}.");
        }
        "keys" => {
            for name in known_key_names() {
                let state = if credentials::has(name) {
                    "configured"
                } else {
                    "-"
                };
                println!("{name:<22} {state}");
            }
        }
        "transcribe" => {
            let path = args.get(1).ok_or("usage: voiceink transcribe <file.wav>")?;
            let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
            let samples = audio::wav::load_wav_16k(&bytes)?;
            let cfg = load_config()?;
            let input = pipeline::PipelineInput {
                samples,
                ..Default::default()
            };
            let out = pipeline::run(&cfg, &input, &AtomicBool::new(false), &|stage| {
                eprintln!("{stage:?}…");
            });
            if let Some(err) = out.error {
                return Err(err);
            }
            if let Some(w) = out.warning {
                eprintln!("warning: {w}");
            }
            println!("{}", out.entry.final_text());
            if cfg.history.enabled {
                let _ = history::append(&history::history_path(), &out.entry);
            }
        }
        "history" => {
            let n: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(10);
            let entries = history::load(&history::history_path());
            for e in entries.iter().rev().take(n) {
                println!(
                    "{} [{:?}] {:.1}s {}\n  {}\n",
                    e.timestamp.format("%Y-%m-%d %H:%M:%S"),
                    e.status,
                    e.duration,
                    e.mode_name.as_deref().unwrap_or(""),
                    e.final_text().replace('\n', "\n  ")
                );
            }
        }
        "export-history" => {
            let out = args
                .get(1)
                .ok_or("usage: voiceink export-history <out.csv>")?;
            let entries = history::load(&history::history_path());
            let mut file = std::fs::File::create(out).map_err(|e| e.to_string())?;
            history::export_csv(&entries, &mut file).map_err(|e| e.to_string())?;
            println!("Exported {} entries to {out}", entries.len());
        }
        "devices" => {
            #[cfg(windows)]
            {
                for (name, is_default) in voiceink::platform::capture::list_input_devices()? {
                    println!("{}{name}", if is_default { "* " } else { "  " });
                }
            }
            #[cfg(not(windows))]
            return Err("device listing is only available on Windows".into());
        }
        other => return Err(format!("unknown command '{other}'\n\n{HELP}")),
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    #[cfg(windows)]
    if let Some(page) = match args.first().map(String::as_str) {
        Some("dashboard") => Some(0),
        Some("settings") => Some(1),
        _ => None,
    } {
        if !voiceink::platform::app::open_settings_in_running_instance(page) {
            init_logging();
            if let Err(e) = voiceink::platform::app::run(Some(page)) {
                voiceink::platform::show_error(&e);
                std::process::exit(1);
            }
        }
        return;
    }

    if !args.is_empty() {
        #[cfg(windows)]
        voiceink::platform::attach_parent_console();
        if let Err(e) = cli(&args) {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
        return;
    }

    init_logging();
    log::info!("VoiceInk for Windows {} starting", voiceink::APP_VERSION);

    #[cfg(windows)]
    {
        if let Err(e) = voiceink::platform::app::run(None) {
            log::error!("fatal: {e}");
            voiceink::platform::show_error(&e);
            std::process::exit(1);
        }
    }

    #[cfg(not(windows))]
    {
        eprintln!("The VoiceInk desktop app only runs on Windows. CLI commands work everywhere:\n\n{HELP}");
        std::process::exit(2);
    }
}

# Contributing to VoiceInk for Windows (Rust)

## Before every commit

```sh
cargo fmt
cargo clippy --all-targets -- -D warnings                                 # portable core
cargo clippy --target x86_64-pc-windows-msvc --all-targets -- -D warnings # Win32 layer
cargo test
```

The lint policy lives in `Cargo.toml` (`[lints]`): `clippy::pedantic`,
`undocumented_unsafe_blocks`, `unwrap_used` (allowed in tests via
`clippy.toml`), `unsafe_op_in_unsafe_fn = deny`. Formatting is set in
`rustfmt.toml` (120 columns).

## Architecture rules

- **Portable core, thin platform layer.** Logic that can be expressed without
  Win32 lives outside `platform/` and is unit tested there: hotkey state
  machines (`input`), the recording policy, the pipeline, settings changes.
  `platform/` translates OS events into calls on that core.
- **Depend on traits, not on concrete providers.** The pipeline uses
  `pipeline::Services`, which hands out `Transcriber` and `ChatModel`
  objects; API keys come from `credentials::SecretStore`. Tests substitute
  fakes (`MemoryStore`, fake services, `http::test_server`).
- **One composition root.** `context::AppContext` builds the long-lived
  services once and is passed down. No global mutable state; the tray app's
  state lives in a `thread_local!` on the UI thread and is reached through
  `with_app`, which tolerates re-entrancy from nested message loops (menus).
- **One responsibility per type.** E.g. the tray app is split into window
  procedure (`app/mod.rs`), state machine (`controller`), menu (`menu`),
  delivery, events and the link to the UI (`ui_link`); each settings page is
  its own module with `new` / `update` / `view` / `apply`.
- **Workers talk to the tray app through `app::events::UiSender`** (a channel
  plus a `PostMessageW` wake-up), never through shared mutable globals.

## The iced UI (`src/ui`)

- **Portable.** The UI depends only on the core and two traits: `Desktop`
  (microphones, clipboard, opening files, font) and `Host` (settings saved,
  quit). `platform::desktop` implements them for Windows; tests use fakes.
- **The Elm architecture.** Each page keeps only what needs validating
  (text typed into number or shortcut fields, editor contents); toggles and
  choices write straight into the window's working `Config`. A page's
  `apply` validates its fields and writes them back when the user saves; an
  error names the field and switches to its page.
- **One event loop.** iced runs as a daemon on the main thread for the
  process lifetime. The tray app sends `UiRequest`s through a `UiHandle`
  (requests made before the UI connects are queued in `UiLink`). Quitting
  always goes through the UI: it calls `Host::quit` (which destroys the Win32
  window) and then ends the loop.
- **Tests.** Drive the window with its `Message`s against a temporary data
  folder, and render it headlessly with `iced_test` (click a button by its
  label, check the produced messages). Long editors need a fixed height, as
  pages scroll.

## Rust practices

- **Errors:** typed errors with `thiserror` in the library (`ConfigError`,
  `CredentialError`, `TranscriptionError`, `platform::Error`, ...); `anyhow`
  only in the binary (`cli.rs`, `main.rs`). Public fallible functions document
  `# Errors`. Errors shown to users are full sentences.
- **No panics for recoverable situations.** No `unwrap()` outside tests;
  `expect` only for true invariants, with the invariant as the message.
- **`unsafe`:** keep blocks small, one `// SAFETY:` comment per block saying
  why the call is sound. Wrap Win32 resources in RAII guards (`ComGuard`,
  `OpenClipboard`, `OwnedIcon`, `gdi::Owned`, `gdi::Selection`,
  `BufferedPaint`, `SingleInstance`, `ForegroundHook`) so early returns
  cannot leak handles.
- **Casts:** prefer `From` / `try_from`. Modules that do deliberate lossy
  numeric conversion (audio DSP, statistics, Win32 pixel math) allow the cast
  lints at module level with a comment explaining why.
- **Names over magic numbers:** constants for timings, sizes and ids; enums
  such as `SettingsPage`, `MenuAction`, `SettingChange`, `UiRequest` instead of integer
  ranges.
- **Tests** sit next to the code (`#[cfg(test)] mod tests`) and cover
  behaviour, not implementation details.

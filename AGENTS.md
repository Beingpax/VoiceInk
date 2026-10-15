# Repository Guidelines

## Project Structure & Module Organization

- `VoiceInk/`: macOS Swift app, organized into App, Core, Features, Infrastructure, and DesignSystem. Assets are in Assets.xcassets and Resources; UI tests are in `Tests/VoiceInkUITests/`. Open `VoiceInk.xcodeproj` for Xcode development.
- `windows/`: Rust Windows app, with code in src and assets in resources.
- `windows-dotnet/`: .NET 10/WinUI 3 port. `src/VoiceInk.Core` contains portable logic, `VoiceInk.Platform` implements Windows integrations, and `VoiceInk.App` composes the UI. Tests are in `tests/VoiceInk.Core.Tests`.
- `scripts/` and `release-notes/`: release tooling and version notes.

## Build, Test, and Development Commands

Run macOS commands from the repository root with macOS 15+ and Xcode:
- `make check`: verify required tools.
- `make local`: prepare Whisper, build Release, and copy the app to ~/Downloads.
- `make dev`: build and launch the development app.

From `windows-dotnet/`, with the .NET 10 SDK:
- `dotnet test tests/VoiceInk.Core.Tests`: run portable core tests.
- `dotnet publish src/VoiceInk.App -c Release -r win-x64 -p:Platform=x64 --self-contained -o artifacts/VoiceInk`: publish the Windows app. Launch `artifacts/VoiceInk/VoiceInk.exe` on Windows.

Consult platform READMEs and `BUILDING.md` for additional setup.

## Coding Style & Naming Conventions

Match surrounding code and use four-space indentation. Use PascalCase for Swift/C# types and C# methods, camelCase for Swift methods and local variables, and Rust snake_case conventions. Format Rust changes with `cargo fmt`. Keep functions focused and explain complex logic. C# enables nullable references and treats warnings as errors. Keep portable logic independent of platform APIs and UI.

## Testing Guidelines

The .NET core uses xUnit. Add regression tests for behavior changes with descriptive names in `CoreTests.cs` or focused `*Tests.cs` files. Run relevant existing tests and manually validate microphone capture, shortcuts, clipboard restoration, and UI changes. No numeric coverage threshold is specified.

## Commit & Pull Request Guidelines

Recent commits use short, action-oriented subjects, such as “Add native Windows version written in Rust”; platform prefixes such as “Windows:” also appear. Keep commits focused.

`CONTRIBUTING.md` currently states that upstream pull requests are not accepted. Use issues for reproducible bugs and feature suggestions. For fork reviews, include the change description, related issues, validation results, and screenshots for UI changes.

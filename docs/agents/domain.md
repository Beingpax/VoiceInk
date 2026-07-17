# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

This repo is single-context: one `CONTEXT.md`, one `docs/adr/`, no per-context split.

## File structure

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-build-from-source.md
│   ├── 0002-v2-target-with-smoke-test-gate.md
│   ├── 0003-telemetry-posthog-cloud.md
│   ├── 0004-finetune-trigger.md
│   ├── 0005-solo-scope-for-now.md
│   └── 0006-ship-rough-now.md
└── VoiceInk/            ← upstream's Swift source, unchanged layout
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (PostHog Cloud) — but worth reopening because…_

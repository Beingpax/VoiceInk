# 0006. Ship rough now rather than polish before daily use

## Status

Decided

## Context

Two rollout options: hold off daily use until Personal Dictionary tuning and telemetry are fully polished, or start using the build for real as soon as the smoke test (ADR-0002) passes and the flag mechanism (ADR-0003's context) exists.

## Decision

Ship rough now. Start daily use as soon as the build passes its smoke test and the one-keystroke flag mechanism is wired up — don't wait for dictionary tuning or dashboard polish.

## Consequences

- Real usage is what generates the flagged-session data ADR-0004's trigger depends on — waiting for polish delays the clock on Phase 2 for no benefit.
- Early daily use will surface rough edges (prompt biasing not yet tuned, occasional flagged sessions) — that's expected, not a regression to fix before shipping.
- Dictionary and prompt-biasing tuning happens iteratively, informed by real flagged sessions, rather than guessed upfront.

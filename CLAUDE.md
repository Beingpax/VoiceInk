## Agent skills

### Issue tracker

Issues live as GitHub Issues on this fork (`aadhar-build/VoiceInk`), not upstream. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), unchanged. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Development workflow

**Test-protected editing.** Before touching any file: confirm it has test coverage (or note the gap explicitly — this codebase is triaged into tested/needs-refactoring/untested tiers, see the test-coverage GitHub issue). Run the existing tests first to get a clean baseline. Make the change. Run tests again — both the tests that existed before and any new ones must pass. Never leave a change committed with a red or skipped test.

**Post-issue architecture review.** After closing out each issue's work, run a code architecture review before moving to the next one (`/code-review`, or mattpocock's `/codebase-design` / `/improve-codebase-architecture`) to catch structural gaps early, while the change is still fresh, rather than letting them compound across issues.

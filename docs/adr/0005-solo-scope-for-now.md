# 0005. Solo, single-device scope for now

## Status

Decided

## Context

This could be designed for one person on one Mac, or for eventual multi-device/multi-person use (tagging every telemetry event with a `device_id`/`user_id` from day one to avoid a later backfill).

## Decision

Solo, single device. No device/user tagging in telemetry yet.

## Consequences

- Simpler event schema now; every PostHog event implicitly belongs to the one user, one Mac.
- If this ever expands to another Mac or another person, telemetry from before that point has no device/user dimension to filter by — accept that gap rather than pre-paying for it now, since backfilling is cheap at this data volume (see ADR-0003 for the volume this implies).
- Revisit this ADR before onboarding a second device or person; add the dimension going forward from that point rather than retrofitting history.

# Run Ledger

## Purpose

`.metrics/runs.csv` is a durable, version-controlled ledger of agent session runs and automated review cycles. It records one row per significant event in the repository's control plane: when an agent completes a session merge, or when a reviewer posts a verdict on a pull request.

The ledger serves as a queryable source of truth for run history, making it possible to audit agent behaviour, track model tier decisions, correlate fix cycles with review findings, and build reporting and dashboards over the history of work in this repository.

## Storage

The ledger is stored at `.metrics/runs.csv`, tracked by git like all version-controlled data. It is append-only — once a row is written, it is never modified or deleted. Exactly one workflow, `.github/workflows/run-ledger.yml`, writes to this file, ensuring deterministic ordering and atomicity.

## Schema

| Column | Source | Format | Empty Means |
| --- | --- | --- | --- |
| `timestamp` | Session start or verdict post time | RFC3339 (e.g., `2026-09-14T19:15:37Z`) | Not allowed |
| `event` | Type of event recorded | `merge` (session completes and merges to main), `session` (agent session completes, may or may not merge) | Not allowed |
| `issue` | GitHub issue number | Decimal integer; `0` if no Issue (e.g., exploratory session) | The field itself is never empty — a session with no Issue writes the `0` sentinel, not a blank value |
| `pr` | GitHub pull request number | Decimal integer | Not allowed |
| `role` | Agent role or session type | One of: `planner`, `implementer`, `reviewer`, `fixer`, `plan-reviewer`, `exploratory`, `other` | Session type unknown |
| `vendor` | AI vendor | One of: `copilot`, `anthropic`, `claude` — the same vocabulary as the third segment of an `agent:{role}:{vendor}` label (`bootstrap-labels.sh`) | Not specified |
| `model_requested` | Model requested by Issue label or config | Model ID string (e.g., `claude-sonnet-5`) | Default applied |
| `model_resolved` | Model actually used by the session | Model ID string | Same as requested |
| `tier_label` | Issue model tier label at run time | One of: `model:haiku`, `model:sonnet`, `model:opus` or empty | No tier label |
| `fix_round` | Which fix cycle this row represents | Decimal integer (0 for first review, 1 for first fix, etc.) | Not applicable for non-review events |
| `verdict` | Review verdict posted | One of: `pass`, `fix`, `design-ambiguity`, `planning-failure` | Not a review event |
| `outcome` | Completion status | One of: `completed`, `harness_error`, `model_unavailable`, `budget_exhausted`, `rate_limited`, `session_error`, `no_assistant_output` | Session ongoing |
| `duration_seconds` | Wallclock time from start to end | Decimal number | Unknown duration |
| `run_url` | GitHub Actions run or PR URL | HTTPS URL | Not a GitHub event |

## Event Vocabulary

The `event` column uses these allowed values:

- **`merge`**: Agent session completed, its PR was merged to main, and the merge event was recorded to the ledger.
- **`session`**: Agent session completed and posted a result (PR, comment, or other output), but may or may not have been merged. This is the catch-all for non-merge completions.

## Outcome Vocabulary

The `outcome` column uses these allowed values:

- **`completed`**: Session or review completed successfully.
- **`harness_error`**: The Claude Code harness itself failed (e.g., permission error, network failure).
- **`model_unavailable`**: Requested model was not available or had been deprecated.
- **`budget_exhausted`**: User's API budget or token limit was exceeded.
- **`rate_limited`**: API rate limit was hit.
- **`session_error`**: Agent session produced an error (e.g., code syntax error, script failure).
- **`no_assistant_output`**: Agent did not produce output (e.g., refused request, incomplete response).

## Future Work

A fallback storage mechanism has been considered but is not yet adopted: storing one JSON file per run under `.metrics/runs/` as a structured per-run report, with a rollup summary aggregated on demand. This design is deferred pending a clearer use case and frequency of query access. When adopted, the JSON structure and query patterns will be documented here.

# Run Ledger

## Purpose

`.metrics/runs.csv` is a durable, version-controlled ledger of agent session runs and automated review cycles. It records one row per significant event in the repository's control plane: when an agent completes a session merge, or when a reviewer posts a verdict on a pull request.

The ledger serves as a queryable source of truth for run history, making it possible to audit agent behaviour, track model tier decisions, correlate fix cycles with review findings, and build reporting and dashboards over the history of work in this repository.

## Storage

The ledger is stored at `.metrics/runs.csv` **on the `ledger` branch**, tracked by git like all version-controlled data. It is append-only — once a row is written, it is never modified or deleted. Exactly one workflow, `.github/workflows/run-ledger.yml`, writes to this file, ensuring deterministic ordering and atomicity. It remains the ledger's only writer, and the ledger stays the single source of truth, even as readers are added.

`.github/scripts/pipeline_metrics.py` and `.github/scripts/render-pipeline-report.py` are readers, not writers: the weekly `pipeline-report.yml` workflow fetches the ledger from its branch, calls them to derive delivery and agent-accuracy figures from it, and publishes the result to the pinned `pipeline-report` Issue. Neither script appends to, rewrites, or otherwise changes the ledger.

### Why a separate branch

> **Revised 2026-09-16.** The ledger was previously written to `main`. This section records why it is not any more (#369).

The `Main Protection` ruleset requires a pull request on `~DEFAULT_BRANCH`, so `run-ledger.yml`'s direct push to `main` is rejected. A `GITHUB_TOKEN` push cannot be exempted from it: adding a bypass actor for the GitHub Actions integration is refused with

```text
422  Actor GitHub Actions integration must be part of the ruleset
     source or owner organization
```

and this repository is user-owned, so there is no owner organization for that integration to belong to. The alternatives were worse — a deploy key would work but raises workflow events, and `ci.yml` has no `paths-ignore` on push to `main`, so every ledger commit would trigger a full nine-job build.

The ruleset's conditions name `~DEFAULT_BRANCH` and nothing else, so **any other branch is unrestricted and needs no exemption at all.**

Three properties of the branch follow from that:

- **It is an orphan.** It shares no history with `main` and is never merged in either direction. Merging it back would put the ledger on the protected branch again, which is the thing being undone. It also means a ledger commit can never carry a code change, and a code change can never carry a ledger commit.
- **It is created on demand.** If the branch is missing, `run-ledger.yml` recreates it with a header row. This is a guard against a hard failure and a first-run bootstrap — **not a backup.** A recreated branch has no rows. Protecting the branch from deletion is a separate ruleset's job, and that ruleset must carry `deletion` and `non_fast_forward` only: a `pull_request` or `required_status_checks` rule on it would recreate the exact problem this move solved.
- **Losing a row is visible.** `run-ledger.yml` still never fails the merge, so a rejected push leaves the job green. The run summary now states the loss under its own heading, names the pull request, and prints the `workflow_dispatch` replay that recovers it.

### The copy of `.metrics/runs.csv` on `main`

`main` still carries a `.metrics/runs.csv`, frozen at the migration point. It is **not** the ledger and is never written to again. It survives for one reason: `test-workflow-logic.sh` Part 18 makes one pass against the real committed file as a read-only fixture, checking that genuine ledger data parses. See `.metrics/README.md`, which says the same thing next to the file.

Removing it, and the now-vestigial `.metrics/**` path gates in `ci.yml`, is deliberate follow-up work rather than part of the move.

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

# The `ledger` branch

This branch holds one file: `.metrics/runs.csv`, the run ledger. It is an
**orphan branch** — it shares no history with `main`, and it is never merged
into `main` or anything else.

## Why it is not on `main`

The `Main Protection` ruleset requires a pull request on the default branch,
so `run-ledger.yml`'s direct push is rejected there. A `GITHUB_TOKEN` push
cannot be exempted from it: adding the GitHub Actions integration as a bypass
actor is refused with

```text
422  Actor GitHub Actions integration must be part of the ruleset
     source or owner organization
```

and this repository is user-owned, so there is no such organization. The
ruleset targets `~DEFAULT_BRANCH` and nothing else, so this branch is
unrestricted and needs no exemption.

See `docs/RUN_LEDGER.md` on `main` for the schema, the vocabularies, and the
full reasoning (#369).

## Do not

- **Do not merge this branch into `main`.** That puts the ledger back on the
  protected branch, which is the thing this arrangement undoes.
- **Do not rewrite history here.** The ledger is append-only: rows are never
  modified, reordered or deleted once written.
- **Do not put a `pull_request` or `required_status_checks` rule on this
  branch.** A ruleset here should carry `deletion` and `non_fast_forward`
  only; anything more recreates the problem that moved the ledger here.

## If this branch is deleted

`run-ledger.yml` will recreate it with a header row and no rows. That is a
guard against a hard failure, **not a backup** — the history is gone. Deletion
protection is a ruleset's job.

## Reading it

```bash
git fetch origin ledger
git show FETCH_HEAD:.metrics/runs.csv
```

The weekly `pipeline-report.yml` does the same thing and renders the figures
to the pinned `pipeline-report` Issue.

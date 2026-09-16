# `.metrics/` on `main` — frozen

**The live run ledger is not here. It is `.metrics/runs.csv` on the `ledger`
branch.**

The `runs.csv` next to this file is a snapshot, frozen on 2026-09-16 at the
point the ledger moved off `main` (#369). Nothing writes to it any more.
Reading it will give you an answer that stops at the migration and says
nothing about it.

It survives for one reason: `.github/scripts/test-workflow-logic.sh` Part 18
makes one pass against the real committed file as a read-only fixture, so that
the metrics reader is exercised against genuine ledger data and not only
against CSVs the harness wrote itself.

To read the actual ledger:

```bash
git fetch origin ledger
git show FETCH_HEAD:.metrics/runs.csv
```

See `docs/RUN_LEDGER.md` for the schema, the vocabularies, and why the ledger
lives on a branch of its own.

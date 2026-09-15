#!/usr/bin/env python3
"""Pure computation of the ledger-derived pipeline metrics (#339).

Reads `.metrics/runs.csv`, validates it against the schema
`docs/RUN_LEDGER.md` describes, and emits one JSON model containing every
figure the pipeline report derives from the ledger alone: delivery
frequency, first-pass yield, model-tier accuracy, verdict distribution, and
fix-round counts. Nothing here touches GitHub -- lead time, change failure
rate, time to restore, and CI wall-clock duration all need state this ledger
does not carry, and are out of scope for this module (see the epic, #222).

Pure, exactly as `ledger_row.py` is pure: no `subprocess`, `urllib` or
`requests` import or call site, no network, no `gh`, no third-party
dependency. Every input arrives as a file path or a flag. This module is
also read-only with respect to the ledger -- it never writes, sorts,
rewrites or repairs `.metrics/runs.csv`.

`HEADER` is imported from the sibling `ledger_row` module, not restated, and
every column index this module uses is derived from it.

Validation is fatal in exactly three cases -- a diagnostic naming the path
and the problem goes to stderr, stdout stays empty, and the exit status is
non-zero:

    * the ledger path does not exist or cannot be read;
    * the file is empty, or its first line is not the imported `HEADER`;
    * the file has a valid header but no data rows.

Everything else degrades per row instead of aborting the run: a data row
with the wrong field count, or one whose `timestamp` does not parse, is
skipped, counted in `coverage.skipped_rows`, and noted on stderr -- every
other row still contributes to the model.

`coverage` describes the whole file that was read. `delivery_frequency`,
`first_pass_yield`, `tier_accuracy`, `verdict_distribution` and `fix_rounds`
are each scoped to the reporting window: the `--weeks` ISO weeks ending at
`--now` (defaulting to the current UTC instant), closed over those two
inputs alone -- nothing else here reads the wall clock.

Every percentage in the model comes out of one shared `share()` helper,
returning `{"numerator": int, "denominator": int, "percent": float | None}`
with `percent` left `None` whenever the denominator is too thin
(`MIN_DENOMINATOR_FOR_PERCENT`) to make a percentage meaningful.

Usage:

    pipeline_metrics.py --ledger .metrics/runs.csv --weeks 12 \\
        --now 2026-09-15T12:00:00Z --json
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import pathlib
import sys
from datetime import date, datetime, timedelta, timezone

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from ledger_row import HEADER  # noqa: E402  (path set above; siblings)

# A share below this denominator is reported as a count, not a percentage --
# one shared rule, applied by the one `share()` helper below.
MIN_DENOMINATOR_FOR_PERCENT = 10

# `docs/RUN_LEDGER.md`'s closed verdict vocabulary. Anything else observed on
# a merge row is `other`; an empty value is `none`.
KNOWN_VERDICTS = ("pass", "fix", "design-ambiguity", "planning-failure")

# One explicit model-ID-to-tier table. Prefix-matched, since a model ID
# carries a version suffix (`claude-haiku-4-5-20251001`) the tier label does
# not.
MODEL_ID_TIER_PREFIXES = (
    ("claude-haiku-", "haiku"),
    ("claude-sonnet-", "sonnet"),
    ("claude-opus-", "opus"),
)
TIER_ORDER = {"haiku": 0, "sonnet": 1, "opus": 2}
TIERS = ("haiku", "sonnet", "opus")

COL = {name: index for index, name in enumerate(HEADER)}


def fatal(message: str) -> "NoReturn":
    print(f"pipeline_metrics: {message}", file=sys.stderr)
    raise SystemExit(1)


def share(numerator: int, denominator: int) -> dict:
    """The one shared percentage: `None` below `MIN_DENOMINATOR_FOR_PERCENT`,
    a rounded float otherwise. No metric computes its own."""

    percent = None
    if denominator >= MIN_DENOMINATOR_FOR_PERCENT:
        percent = round((numerator / denominator) * 100.0, 2)
    return {"numerator": numerator, "denominator": denominator, "percent": percent}


def parse_timestamp(value: str):
    """An RFC3339 UTC `timestamp`, or `None` if it does not parse.

    `ledger_row.py` always normalises to `%Y-%m-%dT%H:%M:%SZ`, tried first;
    `datetime.fromisoformat` (after the `Z`-to-offset swap it also uses)
    covers anything with fractional seconds or an explicit offset, so a
    `--now` supplied by hand is not held to a stricter format than the
    ledger itself.
    """

    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
    except ValueError:
        pass
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def rfc3339(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_int(value):
    """`value` as an `int`, or `None` for empty/unparseable -- the "non-empty
    numeric" test `first_pass_yield` and `fix_rounds` both need."""

    if value is None or value == "":
        return None
    try:
        return int(value)
    except ValueError:
        try:
            as_float = float(value)
        except ValueError:
            return None
        return int(as_float) if as_float.is_integer() else None


def to_number(value):
    """`value` as an `int` when it parses as one, else the raw string --
    used for `issue`/`pr` in output, which are usually decimal but must not
    be lost when they are not (the ledger's own `0` sentinel included)."""

    parsed = parse_int(value)
    return parsed if parsed is not None else value


def model_tier(model_id: str):
    if not model_id:
        return None
    for prefix, tier in MODEL_ID_TIER_PREFIXES:
        if model_id.startswith(prefix):
            return tier
    return None


def resolve_now(value):
    if value is None:
        return datetime.now(timezone.utc)
    parsed = parse_timestamp(value)
    if parsed is None:
        fatal(f"--now value {value!r} is not a valid RFC3339 timestamp")
    return parsed


def load_ledger_rows(path: str) -> list:
    """Every data row (header excluded) of the ledger at `path`, or a fatal
    diagnostic for the three cases this module refuses to guess past."""

    ledger_path = pathlib.Path(path)
    try:
        text = ledger_path.read_text(encoding="utf-8")
    except OSError as exc:
        fatal(f"cannot read ledger {path}: {exc}")

    if not text.strip():
        fatal(f"ledger {path} is empty")

    rows = list(csv.reader(io.StringIO(text)))
    if not rows:
        fatal(f"ledger {path} is empty")

    header = tuple(rows[0])
    if header != HEADER:
        fatal(
            f"ledger {path} header does not match the expected schema: "
            f"got {header!r}, expected {HEADER!r}"
        )

    data_rows = rows[1:]
    if not data_rows:
        fatal(f"ledger {path} has a header row but no data rows")

    return data_rows


def parse_rows(data_rows: list) -> tuple:
    """`(good_rows, skipped_count)`. A `good` row is a dict of every `HEADER`
    column plus `_ts`, the row's parsed `timestamp`."""

    good_rows = []
    skipped = 0
    idx_timestamp = COL["timestamp"]

    for row in data_rows:
        if len(row) != len(HEADER):
            print(
                f"pipeline_metrics: skipping row with {len(row)} fields,"
                f" expected {len(HEADER)}: {row!r}",
                file=sys.stderr,
            )
            skipped += 1
            continue

        timestamp = parse_timestamp(row[idx_timestamp])
        if timestamp is None:
            print(
                f"pipeline_metrics: skipping row with unparseable timestamp"
                f" {row[idx_timestamp]!r}",
                file=sys.stderr,
            )
            skipped += 1
            continue

        record = dict(zip(HEADER, row))
        record["_ts"] = timestamp
        good_rows.append(record)

    return good_rows, skipped


def iso_week_label(moment: datetime) -> str:
    iso_year, iso_week, _ = moment.isocalendar()
    return f"{iso_year:04d}-W{iso_week:02d}"


def week_start(moment: datetime) -> datetime:
    """Monday 00:00:00 UTC of `moment`'s ISO week."""

    iso_year, iso_week, _ = moment.isocalendar()
    monday = date.fromisocalendar(iso_year, iso_week, 1)
    return datetime(monday.year, monday.month, monday.day, tzinfo=timezone.utc)


def delivery_frequency(merge_window: list, window_start: datetime, window_end: datetime) -> dict:
    """One entry per ISO week touching the window, in chronological order,
    with its `merge` count -- zero included -- plus the mean over weeks
    whose full seven days lie inside the window. Counts only: this metric
    never produces a percentage."""

    counts = {}
    for row in merge_window:
        label = iso_week_label(row["_ts"])
        counts[label] = counts.get(label, 0) + 1

    weeks = []
    complete_counts = []
    cursor = week_start(window_start)
    while cursor < window_end:
        cursor_end = cursor + timedelta(days=7)
        label = iso_week_label(cursor)
        merges = counts.get(label, 0)
        weeks.append({"week": label, "merges": merges})
        if cursor >= window_start and cursor_end <= window_end:
            complete_counts.append(merges)
        cursor = cursor_end

    mean = (sum(complete_counts) / len(complete_counts)) if complete_counts else None

    return {"weeks": weeks, "mean_merges_per_complete_week": mean}


def first_pass_yield(merge_window: list) -> dict:
    """A share whose denominator is `merge` rows with a non-empty numeric
    `fix_round`, and whose numerator is those at `fix_round == 0`."""

    values = [parse_int(row["fix_round"]) for row in merge_window]
    valid = [value for value in values if value is not None]
    numerator = sum(1 for value in valid if value == 0)
    return share(numerator, len(valid))


def tier_accuracy(merge_window: list, session_window: list) -> dict:
    """Per declared tier: how many merges carried it, how many escalated to
    a model resolved at a strictly higher tier, and how many could not be
    classified at all because no session for that pull request resolved a
    recognisable model ID. Escalation is defined in terms of the resolved
    model, never `fix_round` -- that is first-pass yield's business."""

    sessions_by_pr = {}
    for row in session_window:
        sessions_by_pr.setdefault(row["pr"], []).append(row)

    result = {}
    for tier in TIERS:
        tasks = 0
        escalated = 0
        unclassified = 0

        for row in merge_window:
            if row["tier_label"] != tier:
                continue
            tasks += 1

            sessions = sessions_by_pr.get(row["pr"], [])
            recognised = [
                model_tier(session["model_resolved"]) for session in sessions
            ]
            recognised = [t for t in recognised if t is not None]

            if not recognised:
                unclassified += 1
                continue

            if any(TIER_ORDER[t] > TIER_ORDER[tier] for t in recognised):
                escalated += 1

        result[tier] = {
            "tasks": tasks,
            "escalated": escalated,
            "unclassified": unclassified,
            "share": share(escalated, tasks - unclassified),
        }

    return result


def verdict_distribution(merge_window: list) -> dict:
    """Counts over `merge` rows for the closed verdict vocabulary, plus
    `none` for the empty value and `other` for anything off it."""

    counts = {verdict: 0 for verdict in KNOWN_VERDICTS}
    counts["none"] = 0
    counts["other"] = 0

    for row in merge_window:
        verdict = row["verdict"]
        if verdict == "":
            counts["none"] += 1
        elif verdict in KNOWN_VERDICTS:
            counts[verdict] += 1
        else:
            counts["other"] += 1

    return counts


def fix_rounds(merge_window: list) -> dict:
    """Counts at 0, 1, 2 and 3-or-more fix rounds, plus the list of tasks at
    2 or more -- the ones `docs/AGENT_WORKFLOW.md` asks a human to go find."""

    buckets = {"0": 0, "1": 0, "2": 0, "3+": 0}
    needs_human_review = []

    for row in merge_window:
        value = parse_int(row["fix_round"])
        if value is None:
            continue

        key = "3+" if value >= 3 else str(value)
        if key not in buckets:
            continue
        buckets[key] += 1

        if value >= 2:
            needs_human_review.append({
                "issue": to_number(row["issue"]),
                "pr": to_number(row["pr"]),
                "fix_round": value,
            })

    return {**buckets, "needs_human_review": needs_human_review}


def build_model(good_rows: list, skipped_rows: int, weeks: int, now: datetime) -> dict:
    merge_rows = [row for row in good_rows if row["event"] == "merge"]
    session_rows = [row for row in good_rows if row["event"] == "session"]
    timestamps = [row["_ts"] for row in good_rows]

    window_end = now
    window_start = window_end - timedelta(weeks=weeks)

    coverage = {
        "rows": len(merge_rows) + len(session_rows) + skipped_rows,
        "merge_rows": len(merge_rows),
        "session_rows": len(session_rows),
        "skipped_rows": skipped_rows,
        "first_timestamp": rfc3339(min(timestamps)) if timestamps else None,
        "last_timestamp": rfc3339(max(timestamps)) if timestamps else None,
        "window": {
            "weeks": weeks,
            "start": rfc3339(window_start),
            "end": rfc3339(window_end),
        },
    }

    merge_window = [
        row for row in merge_rows if window_start <= row["_ts"] < window_end
    ]
    session_window = [
        row for row in session_rows if window_start <= row["_ts"] < window_end
    ]

    return {
        "coverage": coverage,
        "delivery_frequency": delivery_frequency(merge_window, window_start, window_end),
        "first_pass_yield": first_pass_yield(merge_window),
        "tier_accuracy": tier_accuracy(merge_window, session_window),
        "verdict_distribution": verdict_distribution(merge_window),
        "fix_rounds": fix_rounds(merge_window),
    }


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Pure computation of the ledger-derived pipeline metrics: reads"
            " and validates the run ledger, then emits a JSON model of"
            " delivery frequency, first-pass yield, tier accuracy, verdict"
            " distribution and fix-round counts."
        )
    )
    parser.add_argument(
        "--ledger", default=".metrics/runs.csv",
        help="Path to the run ledger CSV (default: .metrics/runs.csv).",
    )
    parser.add_argument(
        "--weeks", type=int, default=12,
        help="Reporting window width in ISO weeks, ending at --now (default: 12).",
    )
    parser.add_argument(
        "--now", default=None,
        help=(
            "RFC3339 instant treated as 'now' for the reporting window."
            " Defaults to the current UTC time."
        ),
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit the metrics model as JSON. The only output mode this ships.",
    )
    return parser


def main(argv=None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    now = resolve_now(args.now)
    data_rows = load_ledger_rows(args.ledger)
    good_rows, skipped_rows = parse_rows(data_rows)

    model = build_model(good_rows, skipped_rows, args.weeks, now)

    if args.json:
        print(json.dumps(model, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

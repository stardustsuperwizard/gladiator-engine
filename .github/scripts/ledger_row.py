#!/usr/bin/env python3
"""Turn already-fetched GitHub JSON for one merged pull request into CSV rows
for `.metrics/runs.csv`, printed to stdout.

Prints one `event=merge` row, then one `event=session` row per well-formed
session-record comment on the pull request, in comment order. See
`docs/RUN_LEDGER.md` for the column schema this fills, one column of it
(`issue`'s zero sentinel) aside -- that substitution, if it survives, belongs
to whatever appends these rows to the file, not to this printer; every
"unknown" value here is the empty string.

The session-record marker contract this reads is fixed and lives with the
writer that will one day produce it, not here: a comment whose entire body is
the line `<!-- agent-session-record`, then one line holding one JSON object
with exactly the keys `role`, `vendor`, `model_requested`, `model_resolved`,
`outcome`, `duration_seconds`, `fix_round`, `run_url`, then the line `-->`.
Only `role`, `vendor`, `model_requested`, `model_resolved`, `outcome`,
`duration_seconds` and `run_url` are emitted -- `fix_round` on a session row
is a per-record detail the merge row's own `fix_round` (a count of
`<!-- agent-fix-applied -->` comments) does not need.

No network call and no external process: every input arrives as a file path
or a flag, and the only file this ever fails to finish over is an unreadable
or non-JSON `--pr-json`, which is fatal -- nothing is printed and the exit
status is non-zero. A malformed `--issue-json` or a malformed session-record
comment is not fatal; it is skipped, with a note on stderr, and every other
row still prints.

Usage:

    ledger_row.py --pr-json pr.json [--issue-json issue.json] --run-url URL
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HEADER = (
    "timestamp", "event", "issue", "pr", "role", "vendor",
    "model_requested", "model_resolved", "tier_label", "fix_round",
    "verdict", "outcome", "duration_seconds", "run_url",
)

SESSION_RECORD_HEADER = "<!-- agent-session-record"
SESSION_RECORD_FOOTER = "-->"
FIX_APPLIED_MARKER = "<!-- agent-fix-applied -->"
REVIEW_VERDICT_MARKER = "<!-- agent-review-verdict -->"

CLOSES_RE = re.compile(r"\bCloses\s+#(\d+)", re.IGNORECASE)
VERDICT_RE = re.compile(
    r"^\s*VERDICT:\s*(PASS|FIX|PLANNING FAILURE|DESIGN AMBIGUITY)", re.MULTILINE
)
NEWLINE_RUN_RE = re.compile(r"[\r\n]+")


def clean(value) -> str:
    """A CSV field: never `None`, never containing a line break.

    A run of `\\r`/`\\n` collapses to one space, so a source value with an
    embedded blank line does not become two blank-looking fields either.
    """

    if value is None:
        return ""
    return NEWLINE_RUN_RE.sub(" ", str(value))


def label_names(entity: dict) -> list[str]:
    return [
        label.get("name", "")
        for label in (entity.get("labels") or [])
        if isinstance(label, dict)
    ]


def label_suffix(entity: dict, prefix: str) -> str:
    for name in label_names(entity):
        if name.startswith(prefix):
            return name[len(prefix):]
    return ""


def normalize_timestamp(merged_at) -> str:
    if not merged_at:
        return ""
    try:
        moment = datetime.fromisoformat(str(merged_at).replace("Z", "+00:00"))
    except ValueError:
        return ""
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def extract_issue_number(pr_json: dict):
    refs = pr_json.get("closingIssuesReferences") or []
    if refs and isinstance(refs[0], dict) and refs[0].get("number") is not None:
        return refs[0]["number"]

    match = CLOSES_RE.search(pr_json.get("body") or "")
    if match:
        return int(match.group(1))

    return None


def count_fix_rounds(comments: list[dict]) -> int:
    return sum(1 for c in comments if FIX_APPLIED_MARKER in (c.get("body") or ""))


def extract_verdict(pr_json: dict, comments: list[dict]) -> str:
    label_verdict = label_suffix(pr_json, "review:")
    if label_verdict:
        return label_verdict

    review_comments = [
        c for c in comments if REVIEW_VERDICT_MARKER in (c.get("body") or "")
    ]
    if not review_comments:
        return ""

    match = VERDICT_RE.search(review_comments[-1].get("body") or "")
    if not match:
        return ""

    return match.group(1).lower().replace(" ", "-")


def parse_session_records(comments: list[dict]) -> list[dict]:
    """Every well-formed `<!-- agent-session-record -->` comment, in order.

    A comment not opening with the marker line is not a session record and is
    silently skipped -- it is somebody else's comment. One that opens with the
    marker but does not otherwise match the fixed three-line contract is a
    session record that failed to parse, and is skipped with a diagnostic
    instead.
    """

    records = []

    for position, comment in enumerate(comments, start=1):
        lines = (comment.get("body") or "").strip("\n").splitlines()
        while lines and not lines[0].strip():
            lines.pop(0)
        while lines and not lines[-1].strip():
            lines.pop()

        if not lines or lines[0].strip() != SESSION_RECORD_HEADER:
            continue

        if len(lines) != 3 or lines[2].strip() != SESSION_RECORD_FOOTER:
            print(
                f"ledger_row: skipping malformed session-record comment"
                f" (comment {position} of {len(comments)}): expected a header"
                f" line, one JSON line, and a closing marker line",
                file=sys.stderr,
            )
            continue

        try:
            record = json.loads(lines[1])
        except json.JSONDecodeError as exc:
            print(
                f"ledger_row: skipping malformed session-record comment"
                f" (comment {position} of {len(comments)}): invalid JSON: {exc}",
                file=sys.stderr,
            )
            continue

        if not isinstance(record, dict):
            print(
                f"ledger_row: skipping malformed session-record comment"
                f" (comment {position} of {len(comments)}): JSON is not an"
                f" object",
                file=sys.stderr,
            )
            continue

        records.append(record)

    return records


def build_rows(pr_json: dict, issue_json: dict, run_url: str) -> list[dict]:
    comments = [c for c in (pr_json.get("comments") or []) if isinstance(c, dict)]

    timestamp = normalize_timestamp(pr_json.get("mergedAt"))
    issue = extract_issue_number(pr_json)
    pr_number = pr_json.get("number")

    rows = [{
        "timestamp": timestamp,
        "event": "merge",
        "issue": issue,
        "pr": pr_number,
        "role": "",
        "vendor": "",
        "model_requested": "",
        "model_resolved": "",
        "tier_label": label_suffix(issue_json, "model:") if issue_json else "",
        "fix_round": count_fix_rounds(comments),
        "verdict": extract_verdict(pr_json, comments),
        "outcome": "",
        "duration_seconds": "",
        "run_url": run_url,
    }]

    for record in parse_session_records(comments):
        rows.append({
            "timestamp": timestamp,
            "event": "session",
            "issue": issue,
            "pr": pr_number,
            "role": record.get("role", ""),
            "vendor": record.get("vendor", ""),
            "model_requested": record.get("model_requested", ""),
            "model_resolved": record.get("model_resolved", ""),
            "tier_label": "",
            "fix_round": "",
            "verdict": "",
            "outcome": record.get("outcome", ""),
            "duration_seconds": record.get("duration_seconds", ""),
            "run_url": record.get("run_url", ""),
        })

    return rows


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Print CSV ledger rows for one merged pull request's already"
            " fetched GitHub JSON."
        )
    )
    parser.add_argument(
        "--pr-json", required=True,
        help="Path to `gh pr view --json ...` output for the merged pull request.",
    )
    parser.add_argument(
        "--issue-json", required=False, default=None,
        help="Path to `gh issue view --json ...` output for the closed issue.",
    )
    parser.add_argument(
        "--run-url", required=True,
        help="URL of the ledger run appending this row, used as the merge row's run_url.",
    )
    args = parser.parse_args(argv)

    try:
        pr_json = load_json(Path(args.pr_json))
    except (OSError, ValueError) as exc:
        print(f"ledger_row: cannot read --pr-json {args.pr_json}: {exc}", file=sys.stderr)
        return 1

    issue_json = {}
    if args.issue_json:
        try:
            issue_json = load_json(Path(args.issue_json))
        except (OSError, ValueError) as exc:
            print(
                f"ledger_row: cannot read --issue-json {args.issue_json}, tier_label"
                f" will be empty: {exc}",
                file=sys.stderr,
            )

    rows = build_rows(pr_json, issue_json, args.run_url)

    writer = csv.writer(sys.stdout, lineterminator="\n")
    for row in rows:
        writer.writerow([clean(row[column]) for column in HEADER])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Render the whole pipeline report as markdown to stdout (#340).

Two halves, joined here and nowhere else:

  * **The ledger half** is `pipeline_metrics` (#339), imported and called.
    Delivery frequency, first-pass yield, planner tier accuracy, verdict
    distribution and fix rounds are *its* figures -- this script formats
    them and recomputes none of them. Its `share()` helper and its
    `MIN_DENOMINATOR_FOR_PERCENT` are imported too, so a percentage has one
    definition across both scripts.
  * **The GitHub half** -- lead time for change, change failure rate, time
    to restore and CI wall-clock duration -- needs state the ledger does not
    carry. It is collected through `gh` into a document with three keys
    (`issues`, `pull_requests`, `ci_runs`), which `--github-json` supplies
    verbatim instead. Everything below the fetch is therefore exercised
    identically by the live path and by a fixture, with no network and no
    credentials.

The two halves fail differently, on purpose:

  * A missing, empty or malformed ledger is **fatal** -- `pipeline_metrics`'
    own diagnostic on stderr, nothing on stdout, non-zero exit. A report
    whose ledger did not load is not a partial report, it is no report.
  * GitHub state that cannot be collected or cannot be read is **not**
    fatal. Every GitHub-derived section renders one explicit
    `Not available: <reason>` line, the ledger-derived sections render in
    full, and the exit status is 0. A zero rendered where the truth is
    "could not tell" is the misleading report epic #222 exists to prevent.

Change-failure attribution is two mechanical rules and nothing else -- a
later merged revert naming the pull request, or a `deferred-finding` Issue
filed after the merge that references it. No scoring, no judgement, no
model. `gh` is read-only here; this script writes no Issue, no comment, no
label and no file. Publishing the report is a separate job.

Usage:

    .github/scripts/render-pipeline-report.py --now 2026-09-15T12:00:00Z
    .github/scripts/render-pipeline-report.py --github-json state.json
    .github/scripts/render-pipeline-report.py --json

Requires `gh` authenticated against the repository unless `--github-json` is
supplied. No third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import statistics
import subprocess
import sys
from datetime import datetime

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import pipeline_metrics  # noqa: E402  (path set above; siblings)
from pipeline_metrics import (  # noqa: E402
    KNOWN_VERDICTS,
    MIN_DENOMINATOR_FOR_PERCENT,
    build_model,
    load_ledger_rows,
    parse_int,
    parse_rows,
    parse_timestamp,
    resolve_now,
    share,
)

MARKER = "<!-- pipeline-report -->"

# The three keys of the GitHub-state document, in the shape `--github-json`
# reads and `collect_github` produces.
GITHUB_KEYS = ("issues", "pull_requests", "ci_runs")

ISSUE_FIELDS = ["number", "title", "body", "createdAt", "labels"]
PR_FIELDS = ["number", "title", "mergedAt", "url"]
RUN_FIELDS = [
    "databaseId", "workflowName", "headBranch", "event",
    "status", "conclusion", "startedAt", "updatedAt", "url",
]

# The run set every GitHub-derived CI figure is computed over. The workflow
# selection is the fetch's `--workflow` flag -- a `--github-json` document
# carries `ci.yml` runs and nothing else, exactly as the fetch produces --
# while branch and event are re-checked here so the fixture path and the
# live path agree about what counts.
CI_WORKFLOW = "ci.yml"
CI_BRANCH = "main"
CI_EVENT = "push"

# A completed run is green, red, or neither. `cancelled` and `skipped` are
# neither: they say nothing about whether `main` was broken, so they neither
# open nor close a red period.
GREEN_CONCLUSIONS = {"success"}
RED_CONCLUSIONS = {"failure", "timed_out", "startup_failure"}

DEFERRED_FINDING_LABEL = "deferred-finding"
REVERT_RE = re.compile(r"\brevert\b", re.IGNORECASE)

# The heading each GitHub-derived section renders under, so a degraded run
# still produces the same document outline as a healthy one.
LEAD_TIME_HEADING = "Lead time for change"
CHANGE_FAILURE_HEADING = "Change failure rate"
TIME_TO_RESTORE_HEADING = "Time to restore"
CI_DURATION_HEADING = "CI wall-clock duration"


class GitHubUnavailable(Exception):
    """GitHub state could not be collected, or could not be read.

    Carries the reason verbatim so the report can name it. Never fatal --
    see this module's docstring for why the ledger is and this is not.
    """


# ---------------------------------------------------------------------------
# Collecting GitHub state
# ---------------------------------------------------------------------------


def one_line(text: str) -> str:
    """`text` collapsed to a single line, for a reason rendered inside one
    markdown line."""

    return " ".join(str(text).split())


def run_gh(args: list, repo) -> str:
    """The one `gh` call site, mirroring `render-dashboard.py`'s `run_gh`.

    It differs in exactly one way, and deliberately: where the dashboard
    exits, this raises, because a GitHub outage degrades four sections of
    this report rather than ending it.
    """

    if repo:
        args = [*args, "--repo", repo]
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=True
        )
    except FileNotFoundError:
        raise GitHubUnavailable("gh not found on PATH")
    except subprocess.CalledProcessError as exc:
        detail = one_line(exc.stderr) or f"exit status {exc.returncode}"
        raise GitHubUnavailable(f"gh {' '.join(args)} failed: {detail}")
    return proc.stdout


def gh_json(args: list, repo):
    raw = run_gh(args, repo)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GitHubUnavailable(f"gh {' '.join(args)} returned unreadable JSON: {exc}")


def collect_github(repo) -> dict:
    """The GitHub-state document, in exactly the shape `--github-json` reads."""

    return {
        "issues": gh_json([
            "issue", "list", "--state", "all", "--limit", "500",
            "--json", ",".join(ISSUE_FIELDS),
        ], repo),
        "pull_requests": gh_json([
            "pr", "list", "--state", "merged", "--limit", "500",
            "--json", ",".join(PR_FIELDS),
        ], repo),
        "ci_runs": gh_json([
            "run", "list", "--workflow", CI_WORKFLOW, "--branch", CI_BRANCH,
            "--event", CI_EVENT, "--status", "completed", "--limit", "200",
            "--json", ",".join(RUN_FIELDS),
        ], repo),
    }


def read_github_json(path: str) -> dict:
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise GitHubUnavailable(f"cannot read GitHub state {path}: {exc}")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise GitHubUnavailable(f"GitHub state {path} is not valid JSON: {exc}")


def validate_github(document) -> dict:
    """`document` if it carries the three keys as lists of objects, else a
    `GitHubUnavailable` naming what is wrong with it."""

    if not isinstance(document, dict):
        raise GitHubUnavailable("GitHub state is not a JSON object")

    for key in GITHUB_KEYS:
        if key not in document:
            raise GitHubUnavailable(f"GitHub state is missing the '{key}' key")
        if not isinstance(document[key], list):
            raise GitHubUnavailable(f"GitHub state's '{key}' key is not a list")
        if not all(isinstance(entry, dict) for entry in document[key]):
            raise GitHubUnavailable(
                f"GitHub state's '{key}' key holds something other than objects"
            )

    return document


# ---------------------------------------------------------------------------
# The GitHub-derived figures
# ---------------------------------------------------------------------------


def label_names(item: dict) -> set:
    names = set()
    for label in item.get("labels") or []:
        if isinstance(label, dict) and "name" in label:
            names.add(label["name"])
        elif isinstance(label, str):
            names.add(label)
    return names


def references_pr(text, pr_number: int) -> bool:
    """Whether `text` names pull request `pr_number` as `#N`.

    Word-bounded so `#90` does not match inside `#903` -- the whole of the
    attribution rule's "names the pull request number".
    """

    if not text:
        return False
    return re.search(rf"#{pr_number}\b", str(text)) is not None


def percentile(values: list, fraction: float):
    """Nearest-rank percentile: the smallest value at or above `fraction` of
    the sorted sample. Chosen over interpolation because the report's own
    acceptance criterion is that a reader can reproduce the figure by hand
    from the run timestamps."""

    if not values:
        return None
    ordered = sorted(values)
    rank = math.ceil(fraction * len(ordered))
    index = min(len(ordered) - 1, max(0, rank - 1))
    return ordered[index]


def median(values: list):
    return statistics.median(values) if values else None


def lead_time_for_change(merge_window: list, issues: list) -> dict:
    """For every `merge` row in the window carrying an `issue`, the interval
    from that Issue's `createdAt` to the merge row's own `timestamp` -- which
    `ledger_row.py` sets to the pull request's `mergedAt`.

    A merge whose Issue is absent from the fetched state, or whose
    `createdAt` does not parse, is excluded and counted, never treated as a
    zero.
    """

    by_number = {}
    for issue in issues:
        number = parse_int(issue.get("number"))
        if number is not None:
            by_number[number] = issue

    durations = []
    excluded = 0

    for row in merge_window:
        issue_number = parse_int(row["issue"])
        if issue_number is None:
            excluded += 1
            continue
        issue = by_number.get(issue_number)
        if issue is None:
            excluded += 1
            continue
        created = parse_timestamp(issue.get("createdAt") or "")
        if created is None:
            excluded += 1
            continue
        durations.append((row["_ts"] - created).total_seconds())

    return {
        "covered": len(durations),
        "excluded": excluded,
        "median_seconds": median(durations),
        "min_seconds": min(durations) if durations else None,
        "max_seconds": max(durations) if durations else None,
    }


def change_failure_rate(merge_window: list, pull_requests: list, issues: list) -> dict:
    """A share over the window's `merge` rows, whose numerator is the merges
    a failure is attributable to by either mechanical rule:

      (a) a later merged pull request whose title matches `Revert` and names
          the merge's pull request number; or
      (b) an Issue labelled `deferred-finding`, created after the merge,
          whose title or body references that pull request number.

    Both attributions are reported per pull request so every count in the
    numerator can be traced back to the evidence that produced it.
    """

    reverts = []
    for pull_request in pull_requests:
        title = pull_request.get("title") or ""
        if not REVERT_RE.search(title):
            continue
        merged_at = parse_timestamp(pull_request.get("mergedAt") or "")
        if merged_at is None:
            continue
        reverts.append((merged_at, title, parse_int(pull_request.get("number"))))

    findings = []
    for issue in issues:
        if DEFERRED_FINDING_LABEL not in label_names(issue):
            continue
        created = parse_timestamp(issue.get("createdAt") or "")
        if created is None:
            continue
        text = f"{issue.get('title') or ''}\n{issue.get('body') or ''}"
        findings.append((created, text, parse_int(issue.get("number"))))

    attributed = []

    for row in merge_window:
        pr_number = parse_int(row["pr"])
        if pr_number is None:
            continue

        evidence = []
        for merged_at, title, revert_number in reverts:
            if merged_at > row["_ts"] and references_pr(title, pr_number):
                evidence.append({"rule": "revert", "pr": revert_number})
        for created, text, issue_number in findings:
            if created > row["_ts"] and references_pr(text, pr_number):
                evidence.append({"rule": "deferred-finding", "issue": issue_number})

        if evidence:
            attributed.append({"pr": pr_number, "evidence": evidence})

    return {
        "share": share(len(attributed), len(merge_window)),
        "attributed": attributed,
        "attributed_prs": [entry["pr"] for entry in attributed],
    }


def ci_run_window(ci_runs: list, window_start: datetime, window_end: datetime) -> list:
    """The window's completed `ci.yml` runs on `main` from `push`, ordered by
    start time. One run set, shared by time to restore and wall-clock
    duration, so the two figures cannot disagree about what they measured."""

    selected = []
    for run in ci_runs:
        if run.get("headBranch") != CI_BRANCH or run.get("event") != CI_EVENT:
            continue
        # An in-progress run arrives with both timestamps set and an empty
        # `conclusion`; its `updatedAt` is not a finish, so it would report a
        # wall-clock duration that has not happened yet.
        if not run.get("conclusion"):
            continue
        started = parse_timestamp(run.get("startedAt") or run.get("createdAt") or "")
        # `gh run list` exposes no completion timestamp; `updatedAt` is the
        # last write to the run, which for a completed run is its finish.
        completed = parse_timestamp(run.get("updatedAt") or "")
        if started is None or completed is None:
            continue
        if not (window_start <= started < window_end):
            continue
        selected.append({
            "id": run.get("databaseId"),
            "conclusion": run.get("conclusion"),
            "started": started,
            "completed": completed,
        })

    selected.sort(key=lambda run: (run["started"], str(run["id"])))
    return selected


def time_to_restore(runs: list) -> dict:
    """Red periods over `runs`: one opens at the first red run while `main`
    is not already red, and closes at the next green run. Its duration is
    measured from the opening run's start to the restoring run's completion
    -- the whole interval `main` was known broken.

    A red period still open at the end of the window has no restore time
    yet, so it is reported separately rather than folded into the median
    with a guessed end.
    """

    durations = []
    open_run = None

    for run in runs:
        conclusion = run["conclusion"]
        if conclusion in RED_CONCLUSIONS and open_run is None:
            open_run = run
        elif conclusion in GREEN_CONCLUSIONS and open_run is not None:
            durations.append((run["completed"] - open_run["started"]).total_seconds())
            open_run = None

    return {
        "red_periods": len(durations),
        "median_seconds": median(durations),
        "durations_seconds": durations,
        "unresolved": open_run is not None,
        "runs": len(runs),
    }


def ci_duration(runs: list) -> dict:
    """Start-to-completion over the same run set: median, 90th percentile
    and the run count."""

    durations = [(run["completed"] - run["started"]).total_seconds() for run in runs]
    return {
        "runs": len(durations),
        "median_seconds": median(durations),
        "p90_seconds": percentile(durations, 0.90),
    }


def build_github_model(document: dict, merge_window: list,
                       window_start: datetime, window_end: datetime) -> dict:
    runs = ci_run_window(document["ci_runs"], window_start, window_end)
    return {
        "available": True,
        "reason": None,
        "lead_time_for_change": lead_time_for_change(merge_window, document["issues"]),
        "change_failure_rate": change_failure_rate(
            merge_window, document["pull_requests"], document["issues"]
        ),
        "time_to_restore": time_to_restore(runs),
        "ci_duration": ci_duration(runs),
    }


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def render_share(value: dict) -> str:
    """The one place a share becomes text, and the one place a percent sign
    is ever written.

    A percentage only once the denominator reaches
    `MIN_DENOMINATOR_FOR_PERCENT`; below it the raw `k of n`, because a
    percentage over four events reads as precision the sample does not have.
    """

    numerator = value["numerator"]
    denominator = value["denominator"]
    percent = value["percent"]
    if percent is None:
        return f"{numerator} of {denominator}"
    return f"{percent}% ({numerator} of {denominator})"


def format_duration(seconds) -> str:
    if seconds is None:
        return "—"
    seconds = float(seconds)
    sign = "-" if seconds < 0 else ""
    seconds = abs(seconds)

    if seconds < 60:
        return f"{sign}{seconds:.0f}s"
    if seconds < 3600:
        return f"{sign}{seconds / 60:.0f}m"
    if seconds < 86400:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        return f"{sign}{hours}h {minutes}m"

    days = seconds / 86400.0
    whole = round(days)
    if abs(days - whole) < 1e-9:
        return f"{sign}{whole} day{'' if whole == 1 else 's'}"
    return f"{sign}{days:.1f} days"


def plural(count: int, noun: str) -> str:
    return f"{count} {noun}{'' if count == 1 else 's'}"


def unavailable(reason: str) -> list:
    return [f"Not available: {reason}", ""]


def coverage_paragraph(coverage: dict, ledger_path: str) -> str:
    window = coverage["window"]
    first = coverage["first_timestamp"] or "—"
    last = coverage["last_timestamp"] or "—"
    skipped = coverage["skipped_rows"]
    skipped_text = (
        "1 row was skipped as unreadable."
        if skipped == 1
        else f"{skipped} rows were skipped as unreadable."
    )
    return (
        f"Read {plural(coverage['rows'], 'ledger row')} from `{ledger_path}`, "
        f"the earliest timestamped {first} and the latest {last}. "
        f"The reporting window is the {plural(window['weeks'], 'week')} from "
        f"{window['start']} to {window['end']}. {skipped_text} "
        "Every figure below is scoped to that window; a window wider than the "
        "ledger reads as partial, not as zero."
    )


def render_lead_time(figure: dict) -> list:
    if figure["covered"] == 0:
        return [
            "No merge in the window could be matched to an Issue, so there is "
            f"no lead time to report. {plural(figure['excluded'], 'merge')} "
            "excluded for a missing or unreadable Issue.",
            "",
        ]
    return [
        f"Median {format_duration(figure['median_seconds'])} over "
        f"{plural(figure['covered'], 'merge')} "
        f"(minimum {format_duration(figure['min_seconds'])}, "
        f"maximum {format_duration(figure['max_seconds'])}).",
        "",
        f"The median covers {plural(figure['covered'], 'merge')}; "
        f"{plural(figure['excluded'], 'merge')} excluded for a missing or "
        "unreadable Issue.",
        "",
    ]


def render_change_failure(figure: dict) -> list:
    out = [
        f"{render_share(figure['share'])} merges in the window are "
        "attributable to a failure, by a later revert naming the pull request "
        "or a `deferred-finding` Issue referencing it.",
        "",
    ]
    if figure["attributed"]:
        out.append("Attributed pull requests:")
        out.append("")
        for entry in figure["attributed"]:
            rules = ", ".join(
                f"revert in #{item['pr']}" if item["rule"] == "revert"
                else f"deferred finding #{item['issue']}"
                for item in entry["evidence"]
            )
            out.append(f"- #{entry['pr']} — {rules}")
        out.append("")
    else:
        out += ["No merge in the window is attributable to a failure.", ""]
    return out


def render_time_to_restore(figure: dict) -> list:
    if figure["runs"] == 0:
        return [
            f"No completed `{CI_WORKFLOW}` run on `{CI_BRANCH}` from "
            f"`{CI_EVENT}` falls in the window, so there is nothing to "
            "measure.",
            "",
        ]
    if figure["red_periods"] == 0:
        out = [
            f"No red periods: over {plural(figure['runs'], 'run')} of "
            f"`{CI_WORKFLOW}` on `{CI_BRANCH}`, the branch never went from "
            "green to red and back. There is no duration to report.",
            "",
        ]
    else:
        out = [
            f"{plural(figure['red_periods'], 'red period')}, median "
            f"{format_duration(figure['median_seconds'])}, over "
            f"{plural(figure['runs'], 'run')} of `{CI_WORKFLOW}` on "
            f"`{CI_BRANCH}`. Each is measured from the first failing run's "
            "start to the restoring run's completion.",
            "",
        ]
    if figure["unresolved"]:
        out += [
            "One red period is still open at the end of the window — it has "
            "no restore time yet and is excluded from the median.",
            "",
        ]
    return out


def render_ci_duration(figure: dict) -> list:
    if figure["runs"] == 0:
        return [
            f"No completed `{CI_WORKFLOW}` run on `{CI_BRANCH}` from "
            f"`{CI_EVENT}` falls in the window.",
            "",
        ]
    return [
        f"Median {format_duration(figure['median_seconds'])}, 90th percentile "
        f"{format_duration(figure['p90_seconds'])}, over "
        f"{plural(figure['runs'], 'run')} of `{CI_WORKFLOW}` on "
        f"`{CI_BRANCH}` from `{CI_EVENT}`.",
        "",
    ]


def render_delivery_frequency(figure: dict) -> list:
    out = ["| ISO week | Merges |", "|---|---|"]
    for entry in figure["weeks"]:
        out.append(f"| {entry['week']} | {entry['merges']} |")
    out.append("")
    mean = figure["mean_merges_per_complete_week"]
    if mean is None:
        out.append(
            "No complete ISO week lies inside the window, so there is no mean "
            "to report."
        )
    else:
        out.append(f"Mean {mean:.2f} merges per complete ISO week in the window.")
    out.append("")
    return out


def render_tier_accuracy(figure: dict) -> list:
    out = [
        "How often a task the planner labelled for one tier was actually "
        "resolved on a higher one.",
        "",
        "| Declared tier | Tasks | Escalated | Unclassified | Escalation rate |",
        "|---|---|---|---|---|",
    ]
    for tier in pipeline_metrics.TIERS:
        entry = figure[tier]
        out.append(
            f"| {tier} | {entry['tasks']} | {entry['escalated']} "
            f"| {entry['unclassified']} | {render_share(entry['share'])} |"
        )
    out += [
        "",
        "Unclassified means no session for that pull request resolved a "
        "recognisable model ID; those merges are out of the rate's "
        "denominator rather than counted as agreeing.",
        "",
    ]
    return out


def render_verdict_distribution(figure: dict) -> list:
    out = ["| Verdict | Merges |", "|---|---|"]
    for verdict in (*KNOWN_VERDICTS, "none", "other"):
        out.append(f"| {verdict} | {figure[verdict]} |")
    out.append("")
    return out


def render_fix_rounds(figure: dict) -> list:
    out = ["| Fix rounds | Tasks |", "|---|---|"]
    for bucket in ("0", "1", "2", "3+"):
        out.append(f"| {bucket} | {figure[bucket]} |")
    out.append("")

    flagged = figure["needs_human_review"]
    if flagged:
        out.append("Worth a human look — two or more fix rounds:")
        out.append("")
        for entry in flagged:
            out.append(
                f"- #{entry['issue']} (pull request #{entry['pr']}, "
                f"{plural(entry['fix_round'], 'fix round')})"
            )
    else:
        out.append("No task in the window needed two or more fix rounds.")
    out.append("")
    return out


def render(ledger_model: dict, github_model: dict, ledger_path: str) -> str:
    coverage = ledger_model["coverage"]
    reason = github_model.get("reason")

    def github_section(heading, renderer, key):
        out = [f"## {heading}", ""]
        if github_model["available"]:
            out += renderer(github_model[key])
        else:
            out += unavailable(reason)
        return out

    out = [
        MARKER,
        "# Pipeline Report",
        "",
        coverage_paragraph(coverage, ledger_path),
        "",
    ]

    out += github_section(
        LEAD_TIME_HEADING, render_lead_time, "lead_time_for_change"
    )

    out += ["## Delivery frequency", ""]
    out += render_delivery_frequency(ledger_model["delivery_frequency"])

    out += github_section(
        CHANGE_FAILURE_HEADING, render_change_failure, "change_failure_rate"
    )
    out += github_section(
        TIME_TO_RESTORE_HEADING, render_time_to_restore, "time_to_restore"
    )

    out += ["## First-pass yield", ""]
    out += [
        f"{render_share(ledger_model['first_pass_yield'])} merges in the "
        "window landed without a fix round.",
        "",
    ]

    out += ["## Planner tier accuracy", ""]
    out += render_tier_accuracy(ledger_model["tier_accuracy"])

    out += ["## Verdict distribution", ""]
    out += render_verdict_distribution(ledger_model["verdict_distribution"])

    out += ["## Fix rounds per task", ""]
    out += render_fix_rounds(ledger_model["fix_rounds"])

    out += github_section(CI_DURATION_HEADING, render_ci_duration, "ci_duration")

    out += [
        "---",
        "",
        f"_Generated by `.github/scripts/render-pipeline-report.py` from "
        f"`{ledger_path}`. A rate is a percentage only once its denominator "
        f"reaches {MIN_DENOMINATOR_FOR_PERCENT}; below that it is reported as "
        "a count._",
    ]

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Render the pipeline report as markdown to stdout: the"
            " ledger-derived figures from pipeline_metrics, plus lead time"
            " for change, change failure rate, time to restore and CI"
            " wall-clock duration collected from GitHub."
        )
    )
    parser.add_argument("--repo", help="OWNER/REPO, defaults to the checkout")
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
        "--github-json", default=None,
        help=(
            "Read GitHub state from this file instead of calling gh. Same"
            " shape gh would have produced: an object with 'issues',"
            " 'pull_requests' and 'ci_runs' keys."
        ),
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit the combined model as JSON instead of markdown.",
    )
    return parser


def main(argv=None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    # The ledger first, and fatally: a report whose ledger did not load is
    # not a partial report. `pipeline_metrics` owns the diagnostic.
    now = resolve_now(args.now)
    good_rows, skipped_rows = parse_rows(load_ledger_rows(args.ledger))
    ledger_model = build_model(good_rows, skipped_rows, args.weeks, now)

    # The window is read back out of the model rather than recomputed, so
    # the GitHub half and the ledger half cannot scope to different spans.
    window = ledger_model["coverage"]["window"]
    window_start = parse_timestamp(window["start"])
    window_end = parse_timestamp(window["end"])
    merge_window = [
        row for row in good_rows
        if row["event"] == "merge" and window_start <= row["_ts"] < window_end
    ]

    try:
        document = validate_github(
            read_github_json(args.github_json) if args.github_json
            else collect_github(args.repo)
        )
        github_model = build_github_model(
            document, merge_window, window_start, window_end
        )
    except GitHubUnavailable as exc:
        github_model = {"available": False, "reason": one_line(str(exc))}

    if args.json:
        print(json.dumps(
            {"ledger": ledger_model, "github": github_model}, indent=2,
        ))
    else:
        print(render(ledger_model, github_model, args.ledger))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

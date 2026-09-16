#!/usr/bin/env python3
"""Decide open/update/close/none for the single `red-main` Issue, from
already-fetched GitHub JSON only.

No network call and no subprocess: every input arrives as a JSON file path.
This script only decides and renders -- it creates no Issue, no comment, and
no other GitHub state. Fetching the run, its jobs, its head commit, and the
currently open `red-main` Issue (if any) is the caller's job, exactly as
`release-preflight.py`'s docstring states for itself.

Decisions are evaluated in this fixed order, so the first thing that applies
is the thing acted on:

1. the run's head branch is not `main`, or its event is not `push` --
   `action=none reason=not-main-push`.
2. the run's conclusion is neither red nor green -- `action=none
   reason=inconclusive`. Red is `{failure, timed_out, startup_failure}`;
   green is `{success}`; everything else (`cancelled`, `skipped`, ...) is
   neither.
3. the run's id is already recorded in the open Issue's state marker --
   `action=none reason=already-recorded`. This is what makes a retry of the
   whole calling workflow a no-op.
4. red, no open Issue -- `action=open`.
5. red, open Issue -- `action=update`.
6. green, open Issue -- `action=close`, also printing `interval_seconds=`
   and `first_failure_run_id=`.
7. green, no open Issue -- `action=none reason=already-green`.

An open Issue whose state marker is missing or unparseable is treated as
though this run were the first failure: recovery never raises, and prints
`reason=state-recovered` alongside whatever action (`update` or `close`) the
run's colour otherwise decides.

Inputs, all JSON file paths:

- `--run-json` -- the concluded `ci.yml` run, shaped like GitHub's REST
  workflow-run object: `id`, `conclusion`, `event`, `head_branch`,
  `head_sha`, `html_url`, `run_started_at`, `updated_at` (the run's
  completion -- a workflow run carries no separate `completed_at`).
- `--jobs-json` -- that run's jobs: a bare list, or a `{"jobs": [...]}`
  wrapper matching GitHub's REST jobs-for-a-run response. Each job carries
  `name`, `conclusion`, `id`, `started_at`, and a `steps` list of
  `{name, number, conclusion}`.
- `--commit-json` -- the run's head commit, as a single object the caller
  assembles from GitHub's commit and commit-pulls endpoints: `message` (the
  full commit message; its first line is the subject), `changed_files` (a
  list of paths), and `pull_requests` (a list, possibly empty, of the
  commit's associated pull requests).
- `--issue-json` -- the currently open `red-main` Issue, as `{"number":
  ..., "body": ...}`, or any JSON document representing none: `null`, `{}`,
  or `{"number": null}` all count as no open Issue.
- `--body-out PATH` -- where the rendered Issue body is written, for
  `open` and `update`.
- `--comment-out PATH` -- where the rendered notification comment is
  written, for `open`, `update` and `close`.

`action=`, and `reason=` when the decision has one, print as `key=value`
lines on stdout; `close` additionally prints `interval_seconds=` and
`first_failure_run_id=`; `open` and `update` additionally print `title=`,
a fixed string that never differs between the two.

A `--*-json` file that cannot be read or does not parse as JSON is a fatal
error naming that file on stderr; nothing prints on stdout, and the exit
status is non-zero.

Usage:

    red-main.py --run-json run.json --jobs-json jobs.json \\
        --commit-json commit.json --issue-json issue.json \\
        --body-out body.md --comment-out comment.md
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# Must match render-pipeline-report.py's own constants -- see this module's
# Architecture Constraints. Not imported from there: this script has no
# import-time dependency on anything outside the standard library.
GREEN_CONCLUSIONS = {"success"}
RED_CONCLUSIONS = {"failure", "timed_out", "startup_failure"}

MAIN_BRANCH = "main"
MAIN_EVENT = "push"

BOOKKEEPING_SUBJECT_PREFIX = "chore(ledger):"
BOOKKEEPING_PATH_PREFIX = ".metrics/"

TITLE = "main is red (ci.yml)"

MARKER_RE = re.compile(r"<!--\s*red-main-state\s+(?P<json>\{.*?\})\s*-->", re.DOTALL)
MARKER_KEYS = ("first_failure_run_id", "first_failure_at", "last_run_id", "failures")

EPOCH = datetime.min.replace(tzinfo=timezone.utc)


class Fatal(Exception):
    """An input file could not be read or parsed as JSON."""


def read_json(path_str: str):
    path = Path(path_str)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise Fatal(f"cannot read {path_str}: {exc}") from exc
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise Fatal(f"{path_str} is not valid JSON: {exc}") from exc


def as_list(data, wrapper_key: str) -> list:
    """`data` as a list of jobs/steps, accepting either a bare list or the
    `{wrapper_key: [...]}` shape GitHub's REST API wraps a collection in."""

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        wrapped = data.get(wrapper_key)
        if isinstance(wrapped, list):
            return wrapped
    return []


def parse_timestamp(value) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def sort_timestamp(value) -> datetime:
    return parse_timestamp(value) or EPOCH


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------


def select_failing_job(jobs: list) -> Optional[dict]:
    """The first red job, ordered by job start then id."""

    red_jobs = [
        job for job in jobs
        if isinstance(job, dict) and job.get("conclusion") in RED_CONCLUSIONS
    ]
    if not red_jobs:
        return None
    return min(
        red_jobs,
        key=lambda job: (sort_timestamp(job.get("started_at")), job.get("id") or 0),
    )


def select_failing_step(job: Optional[dict]) -> Optional[dict]:
    """The lowest-numbered red step within `job`."""

    if not job:
        return None
    steps = job.get("steps") or []
    red_steps = [
        step for step in steps
        if isinstance(step, dict) and step.get("conclusion") in RED_CONCLUSIONS
    ]
    if not red_steps:
        return None
    return min(red_steps, key=lambda step: step.get("number") if step.get("number") is not None else 0)


def classify_provenance(commit: dict) -> str:
    """`pull-request`, else `bookkeeping`, else `direct-push` -- the fixed
    three-way rule. Do not widen the bookkeeping path set."""

    pull_requests = commit.get("pull_requests") or []
    if pull_requests:
        return "pull-request"

    message = commit.get("message") or ""
    subject = message.splitlines()[0] if message.splitlines() else ""
    if subject.startswith(BOOKKEEPING_SUBJECT_PREFIX):
        return "bookkeeping"

    changed_files = commit.get("changed_files") or []
    if changed_files and all(
        str(path).startswith(BOOKKEEPING_PATH_PREFIX) for path in changed_files
    ):
        return "bookkeeping"

    return "direct-push"


# ---------------------------------------------------------------------------
# State marker
# ---------------------------------------------------------------------------


def parse_marker(body: str):
    """`(marker, True)` if `body` carries a well-formed
    `<!-- red-main-state {...} -->` marker, else `(None, False)` -- never
    raises."""

    match = MARKER_RE.search(body or "")
    if not match:
        return None, False
    try:
        data = json.loads(match.group("json"))
    except json.JSONDecodeError:
        return None, False
    if not isinstance(data, dict) or not all(key in data for key in MARKER_KEYS):
        return None, False
    return data, True


def render_marker(marker: dict) -> str:
    payload = {key: marker[key] for key in MARKER_KEYS}
    return f"<!-- red-main-state {json.dumps(payload, sort_keys=True)} -->"


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def repo_base_url(run_html_url) -> str:
    """The run URL with its own `/actions/runs/<id>` suffix stripped, so a
    commit link or another run's link can be built from it without a
    separate owner/repo input."""

    text = str(run_html_url or "")
    match = re.match(r"^(.*)/actions/runs/\d+", text)
    if match:
        return match.group(1)
    return text.rstrip("/")


def run_link(run_id, base_url: str) -> str:
    if not base_url or run_id is None:
        return str(run_id)
    return f"{base_url}/actions/runs/{run_id}"


def commit_link(sha, base_url: str) -> str:
    if not base_url or not sha:
        return str(sha or "unknown")
    return f"{base_url}/commit/{sha}"


def short_sha(sha) -> str:
    return str(sha)[:7] if sha else "unknown"


def human_interval(seconds: float) -> str:
    total = max(int(seconds), 0)
    days, remainder = divmod(total, 86400)
    hours, remainder = divmod(remainder, 3600)
    minutes, secs = divmod(remainder, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if secs or not parts:
        parts.append(f"{secs}s")
    return " ".join(parts)


def render_body(run: dict, commit: dict, job: Optional[dict], step: Optional[dict],
                 provenance: str, marker: dict) -> str:
    base_url = repo_base_url(run.get("html_url"))
    sha = run.get("head_sha")
    message = commit.get("message") or ""
    subject = message.splitlines()[0] if message.splitlines() else "unknown"

    lines = [
        f"- **Commit:** [`{short_sha(sha)}`]({commit_link(sha, base_url)}) — {subject}",
        f"- **Failing job:** {job.get('name') if job else 'unknown'}",
        f"- **First failing step:** {step.get('name') if step else 'unknown'}",
        f"- **Run:** {run_link(run.get('id'), base_url)}",
        f"- **Provenance:** {provenance}",
        f"- **main first went red:** {marker.get('first_failure_at')}",
        f"- **Consecutive failures:** {marker.get('failures')}",
        "",
        render_marker(marker),
    ]
    return "\n".join(lines) + "\n"


def render_comment_open_update(run: dict, failures) -> str:
    base_url = repo_base_url(run.get("html_url"))
    return (
        f"main is still red (failure #{failures}). "
        f"See the run: {run_link(run.get('id'), base_url)}\n"
    )


def render_comment_close(run: dict, first_failure_run_id, interval_seconds: float) -> str:
    base_url = repo_base_url(run.get("html_url"))
    restoring_url = run_link(run.get("id"), base_url)
    first_url = run_link(first_failure_run_id, base_url)
    return (
        f"main is green again. It was red for {int(round(interval_seconds))} seconds"
        f" ({human_interval(interval_seconds)}).\n"
        f"First failing run: {first_url}\n"
        f"Restoring run: {restoring_url}\n"
    )


def write_out(path_str: Optional[str], content: str) -> None:
    if not path_str:
        return
    Path(path_str).write_text(content, encoding="utf-8")


# ---------------------------------------------------------------------------
# Decision
# ---------------------------------------------------------------------------


def decide(args: argparse.Namespace) -> int:
    try:
        run = read_json(args.run_json)
        jobs_raw = read_json(args.jobs_json)
        commit_raw = read_json(args.commit_json)
        issue_raw = read_json(args.issue_json)
    except Fatal as exc:
        print(f"red-main: {exc}", file=sys.stderr)
        return 2

    if not isinstance(run, dict):
        run = {}
    jobs = as_list(jobs_raw, "jobs")
    commit = commit_raw if isinstance(commit_raw, dict) else {}
    issue = issue_raw if isinstance(issue_raw, dict) else None
    open_issue = issue if issue and issue.get("number") is not None else None

    if run.get("head_branch") != MAIN_BRANCH or run.get("event") != MAIN_EVENT:
        print("action=none")
        print("reason=not-main-push")
        return 0

    conclusion = run.get("conclusion")
    if conclusion in RED_CONCLUSIONS:
        colour = "red"
    elif conclusion in GREEN_CONCLUSIONS:
        colour = "green"
    else:
        print("action=none")
        print("reason=inconclusive")
        return 0

    run_id = run.get("id")

    marker: Optional[dict] = None
    marker_ok = False
    if open_issue is not None:
        marker, marker_ok = parse_marker(open_issue.get("body") or "")
        if marker_ok:
            recorded_ids = {marker.get("first_failure_run_id"), marker.get("last_run_id")}
            if run_id in recorded_ids:
                print("action=none")
                print("reason=already-recorded")
                return 0

    recovered = open_issue is not None and not marker_ok

    if colour == "red":
        if open_issue is None or recovered:
            new_marker = {
                "first_failure_run_id": run_id,
                "first_failure_at": run.get("run_started_at"),
                "last_run_id": run_id,
                "failures": 1,
            }
        else:
            new_marker = {
                "first_failure_run_id": marker["first_failure_run_id"],
                "first_failure_at": marker["first_failure_at"],
                "last_run_id": run_id,
                "failures": (marker.get("failures") or 0) + 1,
            }
        action = "open" if open_issue is None else "update"

        job = select_failing_job(jobs)
        step = select_failing_step(job)
        provenance = classify_provenance(commit)

        write_out(args.body_out, render_body(run, commit, job, step, provenance, new_marker))
        write_out(args.comment_out, render_comment_open_update(run, new_marker["failures"]))

        print(f"action={action}")
        if recovered:
            print("reason=state-recovered")
        print(f"title={TITLE}")
        return 0

    # colour == "green"
    if open_issue is None:
        print("action=none")
        print("reason=already-green")
        return 0

    if recovered:
        first_failure_run_id = run_id
        first_failure_at = run.get("run_started_at")
    else:
        first_failure_run_id = marker["first_failure_run_id"]
        first_failure_at = marker["first_failure_at"]

    started = parse_timestamp(first_failure_at)
    completed = parse_timestamp(run.get("updated_at"))
    interval_seconds = (completed - started).total_seconds() if started and completed else 0.0

    write_out(args.comment_out, render_comment_close(run, first_failure_run_id, interval_seconds))

    print("action=close")
    if recovered:
        print("reason=state-recovered")
    print(f"interval_seconds={int(round(interval_seconds))}")
    print(f"first_failure_run_id={first_failure_run_id}")
    return 0


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Decide open/update/close/none for the single red-main Issue"
            " from already-fetched GitHub JSON, and render the Issue body"
            " and notification comment the decision calls for."
        )
    )
    parser.add_argument("--run-json", required=True, dest="run_json",
                         help="Path to the concluded ci.yml run.")
    parser.add_argument("--jobs-json", required=True, dest="jobs_json",
                         help="Path to that run's jobs.")
    parser.add_argument("--commit-json", required=True, dest="commit_json",
                         help="Path to the run's head commit.")
    parser.add_argument("--issue-json", required=True, dest="issue_json",
                         help="Path to the currently open red-main Issue, or none.")
    parser.add_argument("--body-out", dest="body_out", default=None,
                         help="Path the rendered Issue body is written to.")
    parser.add_argument("--comment-out", dest="comment_out", default=None,
                         help="Path the rendered notification comment is written to.")
    args = parser.parse_args(argv)

    return decide(args)


if __name__ == "__main__":
    raise SystemExit(main())

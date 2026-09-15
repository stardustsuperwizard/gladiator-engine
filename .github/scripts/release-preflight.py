#!/usr/bin/env python3
"""Decide releasable/not-releasable for one candidate commit, from
already-fetched GitHub JSON only.

No network call and no subprocess: every input arrives as a JSON file path or
a flag. This script only decides and prints -- it creates no tag, no release,
and no other GitHub state, and the fetching (including the `--on-main`
ancestry check, which the workflow computes with `git` and hands in as an
answer) is the caller's job, not this one's.

Decisions are evaluated in this fixed order, so the first thing wrong is the
thing reported:

1. `--version` must match ``^0\\.\\d+\\.\\d+$`` -- `bad-version`.
2. `--on-main` must be `true` -- `not-on-main`.
3. a completed `ci.yml` run must exist for the commit's head SHA in
   `--runs-json`; when several completed runs exist, the most recent by
   `run_started_at` is selected -- `no-run`.
4. within the selected run, the jobs in `--jobs-json` named exactly
   `Godot Export` and `Godot Smoke Run` must each have concluded `success`
   -- `stage-not-passed`. `skipped` is a refusal, not a pass: `ci.yml` skips
   both jobs on a docs-only push while its aggregate check still reports
   success.
5. an unexpired artifact named `godot-linux-<commit>` must be present in
   `--artifacts-json` -- `artifact-missing` or `artifact-expired`.
6. the tag `v<version>` must not already exist in `--tags-json` --
   `tag-exists`.

On refusal, exactly one `reason=<slug>` line and one `message=<one line>`
line print to stdout naming the specific offender, and the exit status is
non-zero. On success, `verdict=ok`, `tag=`, `run_id=`, `artifact_id=` and
`artifact_name=` print to stdout, one `key=value` per line, and the exit
status is 0. A `--*-json` file that cannot be read or does not parse as JSON
is a fatal error naming that file; nothing named above prints, and the exit
status is non-zero either way.

Usage:

    release-preflight.py --commit <40-char-sha> --version 0.2.0 \\
        --on-main true --runs-json runs.json --jobs-json jobs.json \\
        --artifacts-json artifacts.json --tags-json tags.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

VERSION_RE = re.compile(r"^0\.\d+\.\d+$")

REQUIRED_JOBS = ("Godot Export", "Godot Smoke Run")

EPOCH = datetime.min.replace(tzinfo=timezone.utc)


class Fatal(Exception):
    """An input file could not be read or parsed as JSON."""


def parse_bool_flag(value: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise argparse.ArgumentTypeError("must be 'true' or 'false'")


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


def load_list(path_str: str, wrapper_key: str | None) -> list:
    """The JSON at `path_str` as a list.

    GitHub's REST responses for runs/jobs/artifacts wrap their list in an
    object keyed by `wrapper_key` (`workflow_runs`, `jobs`, `artifacts`); a
    caller that already unwrapped it hands in a bare list instead. Either is
    accepted; anything else -- an empty object, a list under the wrong key --
    is treated as no entries rather than a fatal error, since a workflow run
    with nothing to report is exactly the shape `no-run` exists to catch.
    """

    data = read_json(path_str)
    if isinstance(data, list):
        return data
    if wrapper_key and isinstance(data, dict):
        wrapped = data.get(wrapper_key)
        if isinstance(wrapped, list):
            return wrapped
    return []


def parse_started_at(value) -> datetime:
    if not value:
        return EPOCH
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return EPOCH


def tag_names(tags: list) -> set[str]:
    names = set()
    for entry in tags:
        if isinstance(entry, str):
            raw = entry
        elif isinstance(entry, dict):
            raw = entry.get("ref") or entry.get("name") or ""
        else:
            continue
        raw = raw.rsplit("/", 1)[-1]
        if raw:
            names.add(raw)
    return names


def refuse(reason: str, message: str) -> int:
    print(f"reason={reason}")
    print(f"message={message}")
    return 1


def decide(args: argparse.Namespace) -> int:
    if not VERSION_RE.match(args.version):
        return refuse(
            "bad-version",
            f"--version {args.version!r} does not match ^0\\.\\d+\\.\\d+$",
        )

    if not args.on_main:
        return refuse(
            "not-on-main", f"commit {args.commit} is not on main"
        )

    try:
        runs = load_list(args.runs_json, "workflow_runs")
        jobs = load_list(args.jobs_json, "jobs")
        artifacts = load_list(args.artifacts_json, "artifacts")
        tags = load_list(args.tags_json, None)
    except Fatal as exc:
        print(f"release-preflight: {exc}", file=sys.stderr)
        return 2

    completed = [
        run for run in runs
        if isinstance(run, dict) and run.get("status") == "completed"
    ]
    if not completed:
        return refuse(
            "no-run",
            f"no completed ci.yml run found for commit {args.commit}",
        )

    selected = max(completed, key=lambda run: parse_started_at(run.get("run_started_at")))
    run_id = selected.get("id")

    jobs_by_name = {
        job.get("name"): job for job in jobs if isinstance(job, dict)
    }
    for job_name in REQUIRED_JOBS:
        job = jobs_by_name.get(job_name)
        conclusion = job.get("conclusion") if job else None
        if conclusion != "success":
            return refuse(
                "stage-not-passed",
                f"job {job_name!r} concluded {conclusion!r}, not 'success'",
            )

    artifact_name = f"godot-linux-{args.commit}"
    artifact = next(
        (
            a for a in artifacts
            if isinstance(a, dict) and a.get("name") == artifact_name
        ),
        None,
    )
    if artifact is None:
        return refuse(
            "artifact-missing",
            f"no artifact named {artifact_name!r} in run {run_id}",
        )
    if artifact.get("expired"):
        return refuse(
            "artifact-expired", f"artifact {artifact_name!r} has expired"
        )

    tag = f"v{args.version}"
    if tag in tag_names(tags):
        return refuse("tag-exists", f"tag {tag!r} already exists")

    print("verdict=ok")
    print(f"tag={tag}")
    print(f"run_id={run_id}")
    print(f"artifact_id={artifact.get('id')}")
    print(f"artifact_name={artifact_name}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Print the releasable/not-releasable verdict for one candidate"
            " commit from already-fetched GitHub JSON."
        )
    )
    parser.add_argument(
        "--commit", required=True,
        help="Full 40-character commit SHA of the release candidate.",
    )
    parser.add_argument(
        "--version", required=True,
        help="Release version, e.g. 0.2.0 -- no leading 'v', no pre-release suffix.",
    )
    parser.add_argument(
        "--on-main", dest="on_main", required=True, type=parse_bool_flag,
        help="'true' if --commit is an ancestor of main, as the workflow's own git check found.",
    )
    parser.add_argument(
        "--runs-json", required=True,
        help="Path to the ci.yml workflow runs for --commit's head SHA, as GitHub returns them.",
    )
    parser.add_argument(
        "--jobs-json", required=True,
        help="Path to the jobs of the selected run.",
    )
    parser.add_argument(
        "--artifacts-json", required=True,
        help="Path to the selected run's artifacts.",
    )
    parser.add_argument(
        "--tags-json", required=True,
        help="Path to the repository's existing tag refs.",
    )
    args = parser.parse_args(argv)

    return decide(args)


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Derive the `human-credentials` label from an Issue's declared scope.

`agent-01-planner.yml` applies `human-credentials` once, at creation, from
`task_scope.evaluate(body)["implementer_eligible"]` -- the same fact
`agent-02-implement.yml` refuses on. Nothing else keeps the label in step
with that fact afterwards:

- editing an Issue's *Files or Subsystems Expected to Change* section after
  creation never re-derives the label;
- a hand-written `[task]` Issue the planner never saw never gets it at all;
- nothing re-derives it over the existing open backlog.

This script is the repair: given one or more Issues (or every open one), it
reads each body with `.github/scripts/task_scope.py` -- the single source of
truth for which paths `GITHUB_TOKEN` cannot push -- and adds or removes
`human-credentials` to match. It never reasons about paths itself.

Decision table, reported per Issue as an `action` and a `reason` code:

    derived                                   | label | action | reason
    -------------------------------------------|-------|--------|--------------------
    restricted paths                           | no    | add    | restricted
    restricted paths                           | yes   | none   | restricted
    no restricted, section had paths           | yes   | remove | no-restricted-paths
    no restricted, section had paths           | no    | none   | no-restricted-paths
    section missing                            | yes   | remove | no-section
    section missing                            | no    | none   | no-section
    section present, empty or unparseable      | yes   | remove | no-paths
    section present, empty or unparseable      | no    | none   | no-paths

Unknown derives to "not restricted" -- a missing section, an empty one, or
one naming no recognisable path never adds the label, and removes it if
present. This is the same uncertain-means-eligible posture `task_scope.py`
documents for the implementer gate: absence of `human-credentials` is not a
certificate that a task is automatable, which is why `no-section` and
`no-paths` are reported as different reasons even though they act
identically. Nothing is ever labelled on suspicion.

Modelled closely on `sync-issue-dependencies.py`: the same `gh()` / `gh_json()`
subprocess helpers, the same `Repository` wrapper shape, the same
`ensure_label` posture. This script owns exactly one label -- it never adds,
removes, or reads-to-modify any other label, comments on an Issue, or edits a
body, title, state, or assignee.

Usage:

    sync-human-credentials-label.py --issue 168
    sync-human-credentials-label.py --issue 168 --issue 169 --dry-run
    sync-human-credentials-label.py --sweep            # every open Issue
    sync-human-credentials-label.py --sweep --json

Requires `gh` authenticated against the repository, with write access to
Issues. No third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import task_scope

HUMAN_CREDENTIALS_LABEL = "human-credentials"

# Colour and description bootstrap-labels.sh and agent-01-planner.yml's
# `ensure_label` call both carry for this label -- byte-identical, so a
# repository where this script happens to create the label first still ends
# up with the description either of the other two would have written.
HUMAN_CREDENTIALS_COLOR = "D4C5F9"
HUMAN_CREDENTIALS_DESCRIPTION = (
    "Touches paths GITHUB_TOKEN cannot push; needs a human-credentialed session"
)

REASON_RESTRICTED = "restricted"
REASON_NO_RESTRICTED_PATHS = "no-restricted-paths"
REASON_NO_SECTION = "no-section"
REASON_NO_PATHS = "no-paths"

ACTION_ADD = "add"
ACTION_REMOVE = "remove"
ACTION_NONE = "none"

# GitHub's default page size is 30, which the open backlog already exceeds.
# Asked for explicitly, the same way sync-issue-dependencies.py does, rather
# than paginated: a sweep is a repair tool and its cost should be visible as
# one number here, not hidden behind an implicit page walk.
#
# A single request is only safe because `load_open_issues` refuses a full
# page. Without that refusal the sweep's failure mode is the one thing it
# must never do: report success having silently skipped Issues, leaving a
# queue that looks complete and is not. Raise this number when the repository
# outgrows it, or paginate -- but never let a full page pass quietly.
PAGE_SIZE = 500


class GhError(RuntimeError):
    """A `gh` call failed. Carries stderr so the caller can report it."""


def gh(args: list[str], check: bool = True) -> str:
    try:
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=False
        )
    except FileNotFoundError:
        sys.exit("gh not found on PATH. Install the GitHub CLI.")

    if proc.returncode != 0:
        message = (proc.stderr or proc.stdout).strip()
        if check:
            raise GhError(message)
        return ""

    return proc.stdout


def gh_json(args: list[str]):
    return json.loads(gh(args) or "null")


def has_expected_files_section(body: str) -> bool:
    """Whether the body declares the expected-files heading at all.

    `task_scope.section()` returns the same empty string whether the heading
    is absent or present with no content, which would collapse this script's
    `no-section` and `no-paths` reasons into one. This asks only "does the
    heading exist", anchored the same way `task_scope.section()` anchors its
    own match, and reads the heading name from `task_scope` rather than
    restating it, so a rename there cannot let the two definitions drift.
    This does not re-implement path extraction -- `task_scope.expected_paths`
    still does that alone.
    """
    pattern = rf"^#{{1,6}}\s*{re.escape(task_scope.EXPECTED_FILES_HEADING)}\s*$"
    text = task_scope.strip_comments(body or "")
    return bool(re.search(pattern, text, re.M | re.I))


def decide(body: str, has_label: bool) -> dict:
    """The action and reason code for one Issue body.

    `scope["restricted_paths"]` non-empty is the same test as
    `not scope["implementer_eligible"]` -- `task_scope.evaluate()` sets one
    from the other. Read as `restricted_paths` here because this script also
    reports *which* paths triggered the label; `agent-01-planner.yml`'s own
    gate reads the boolean. Same fact, two names, so a caller cannot "improve"
    one side into disagreement with the other.
    """
    scope = task_scope.evaluate(body)
    restricted = scope["restricted_paths"]

    if restricted:
        reason = REASON_RESTRICTED
        action = ACTION_NONE if has_label else ACTION_ADD
    else:
        if not has_expected_files_section(body):
            reason = REASON_NO_SECTION
        elif not scope["expected_paths"]:
            reason = REASON_NO_PATHS
        else:
            reason = REASON_NO_RESTRICTED_PATHS
        action = ACTION_REMOVE if has_label else ACTION_NONE

    return {
        "action": action,
        "reason": reason,
        "restricted_paths": restricted,
    }


class Repository:
    """Every read and write this script makes, with per-run caching."""

    def __init__(self, repo: str, dry_run: bool = False):
        self.repo = repo
        self.dry_run = dry_run
        self._issues: dict[int, dict] = {}

    # -- reads ------------------------------------------------------------

    def issue(self, number: int) -> dict:
        """The REST issue object. Raises GhError naming the Issue on failure."""
        if number not in self._issues:
            try:
                self._issues[number] = gh_json(
                    ["api", f"repos/{self.repo}/issues/{number}"]
                )
            except GhError as error:
                raise GhError(
                    f"#{number}: could not read the Issue: {error}"
                ) from error
        return self._issues[number]

    def body(self, number: int) -> str:
        return self.issue(number).get("body") or ""

    def labels(self, number: int) -> set[str]:
        return {label["name"] for label in self.issue(number).get("labels") or []}

    def load_open_issues(self) -> list[int]:
        """Cache every open Issue's body and labels. Returns their numbers.

        `gh issue list` rather than the REST issues endpoint precisely
        because it excludes pull requests for us; the REST one does not. A
        hand-written `[task]` Issue the planner never saw is read here too --
        this sweep is not filtered to `implementation`, on purpose.
        """
        try:
            issues = gh_json([
                "issue", "list",
                "--repo", self.repo,
                "--state", "open",
                "--limit", str(PAGE_SIZE),
                "--json", "number,body,labels",
            ]) or []
        except GhError as error:
            raise GhError(f"could not list open Issues: {error}") from error

        # A full page means `gh` had no room to return the rest, so this sweep
        # is incomplete and cannot be reported as a repair. Fail rather than
        # truncate: an operator reading "no Issues to derive" has to be able to
        # believe it.
        if len(issues) >= PAGE_SIZE:
            raise GhError(
                f"open Issues filled the {PAGE_SIZE}-item page, so the sweep"
                " would be incomplete. Raise PAGE_SIZE or paginate"
                " before trusting a sweep again."
            )

        for issue in issues:
            self._issues[issue["number"]] = issue

        return [issue["number"] for issue in issues]

    # -- writes -------------------------------------------------------------

    def ensure_label_exists(self) -> None:
        """Best-effort: create the label if missing, never touch it otherwise.

        A failure here is not attributed to any one Issue, so it is reported
        separately rather than through the per-Issue failure path -- and it
        does not stop the run, because an add that then fails on a missing
        label produces the same per-Issue failure anyway, with the Issue
        number attached.
        """
        existing = gh([
            "label", "list",
            "--repo", self.repo,
            "--limit", "200",
            "--json", "name",
            "--jq", ".[].name",
        ]).splitlines()

        if HUMAN_CREDENTIALS_LABEL in existing:
            return

        if self.dry_run:
            print(f"would create the `{HUMAN_CREDENTIALS_LABEL}` label")
            return

        gh([
            "label", "create", HUMAN_CREDENTIALS_LABEL,
            "--repo", self.repo,
            "--color", HUMAN_CREDENTIALS_COLOR,
            "--description", HUMAN_CREDENTIALS_DESCRIPTION,
        ], check=False)

    def add_label(self, number: int) -> None:
        if self.dry_run:
            print(f"would add `{HUMAN_CREDENTIALS_LABEL}` to #{number}")
            return

        gh([
            "issue", "edit", str(number),
            "--repo", self.repo,
            "--add-label", HUMAN_CREDENTIALS_LABEL,
        ])

        cached = self._issues.get(number)
        if cached is not None:
            cached["labels"] = list(cached.get("labels") or []) + [
                {"name": HUMAN_CREDENTIALS_LABEL}
            ]

    def remove_label(self, number: int) -> None:
        if self.dry_run:
            print(f"would remove `{HUMAN_CREDENTIALS_LABEL}` from #{number}")
            return

        gh([
            "issue", "edit", str(number),
            "--repo", self.repo,
            "--remove-label", HUMAN_CREDENTIALS_LABEL,
        ])

        cached = self._issues.get(number)
        if cached is not None:
            cached["labels"] = [
                label for label in (cached.get("labels") or [])
                if label["name"] != HUMAN_CREDENTIALS_LABEL
            ]


def process(repo: Repository, numbers: list[int], report: dict) -> None:
    """Derive and, unless dry-run, realize the label action for each Issue."""
    for number in numbers:
        try:
            body = repo.body(number)
            has_label = HUMAN_CREDENTIALS_LABEL in repo.labels(number)
        except GhError as error:
            report["failed"].append(f"#{number}: read failed -- {error}")
            continue

        decision = decide(body, has_label)
        entry = {
            "number": number,
            "action": decision["action"],
            "reason": decision["reason"],
            "restricted_paths": decision["restricted_paths"],
        }
        report["decisions"].append(entry)

        if decision["action"] == ACTION_ADD:
            try:
                repo.add_label(number)
                report["added"].append(number)
            except GhError as error:
                report["failed"].append(
                    f"#{number}: add {HUMAN_CREDENTIALS_LABEL} failed -- {error}"
                )
        elif decision["action"] == ACTION_REMOVE:
            try:
                repo.remove_label(number)
                report["removed"].append(number)
            except GhError as error:
                report["failed"].append(
                    f"#{number}: remove {HUMAN_CREDENTIALS_LABEL} failed -- {error}"
                )
        else:
            report["unchanged"].append(number)


def render(report: dict) -> str:
    """Markdown for the Actions job summary and for stdout."""
    lines = ["### `human-credentials` label sync", ""]

    def describe(entry: dict) -> str:
        text = f"#{entry['number']} -- {entry['reason']}"
        if entry["restricted_paths"]:
            text += ": " + ", ".join(entry["restricted_paths"])
        return text

    sections = [
        ("Added", "added"),
        ("Removed", "removed"),
        ("Unchanged", "unchanged"),
        ("Failed", "failed"),
    ]

    by_number = {entry["number"]: entry for entry in report.get("decisions") or []}
    wrote_any = False

    for title, key in sections:
        entries = report.get(key) or []
        if not entries:
            continue
        wrote_any = True
        lines.append(f"**{title}**")
        lines.append("")
        for value in entries:
            if key == "failed":
                lines.append(f"- {value}")
            else:
                decision = by_number.get(value)
                lines.append(f"- {describe(decision)}" if decision else f"- #{value}")
        lines.append("")

    if not wrote_any:
        lines.append("No Issues to derive.")
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Derive the `human-credentials` label from an Issue's declared "
            "expected-files scope, using task_scope.py, and add or remove "
            "it to match."
        )
    )
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY"),
        help="owner/name. Defaults to $GITHUB_REPOSITORY.",
    )
    parser.add_argument(
        "--issue",
        type=int,
        action="append",
        default=[],
        dest="issues",
        help="An Issue to derive the label for. Repeatable.",
    )
    parser.add_argument(
        "--sweep",
        action="store_true",
        help=(
            "Derive for every open Issue rather than named ones. Not "
            "filtered to `implementation`: a hand-written [task] Issue the "
            "planner never saw is read too."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report each decision without writing anything.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="Emit the machine-readable report instead of markdown.",
    )
    args = parser.parse_args()

    if not args.repo:
        parser.error("--repo is required when $GITHUB_REPOSITORY is unset")

    if not args.issues and not args.sweep:
        parser.error("pass --issue at least once, or --sweep")

    repo = Repository(args.repo, dry_run=args.dry_run)

    report = {
        "decisions": [],
        "added": [],
        "removed": [],
        "unchanged": [],
        "failed": [],
    }

    if args.sweep:
        try:
            numbers = repo.load_open_issues()
        except GhError as error:
            report["failed"].append(str(error))
            numbers = []
        for number in args.issues:
            if number not in numbers:
                numbers.append(number)
    else:
        numbers = list(dict.fromkeys(args.issues))

    try:
        repo.ensure_label_exists()
    except GhError as error:
        report["failed"].append(
            f"could not ensure the `{HUMAN_CREDENTIALS_LABEL}` label exists"
            f" -- {error}"
        )

    process(repo, numbers, report)

    report["markdown"] = render(report)
    report["needs_attention"] = bool(report["failed"])

    if args.as_json:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(report["markdown"])

    # A failed read or write is the thing this script exists to surface, so it
    # exits non-zero and names the Issue and the operation in "failed" -- an
    # Issue this script could not read or write must never be reported as
    # succeeded, and never silently treated as unrestricted.
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

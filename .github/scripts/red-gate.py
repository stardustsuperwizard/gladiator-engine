#!/usr/bin/env python3
"""Decide which test suites a pull request puts in scope for the red check,
and judge whether each of them was red when run against the merge base.

`plan --base-root <dir> --head-root <dir> --changed-files <path>` prints one
JSON document saying, for every changed path, whether it is a test path or a
production path, whether it is in scope, and which registered suite owns it.
`verdict --plan <plan.json> --base-log <log>` reads that document together
with the captured output of the merge-base run and prints a markdown report,
exiting `0` when every in-scope suite was red there, `1` when any was green,
and `2` when the inputs are unusable.

Exit `1` and exit `2` are different answers and nothing here may blur them.
`1` is a verdict about the pull request, and a human may downgrade it with
the `characterization-test` label after recording the reason in the pull
request body. `2` is this tool failing to reach a verdict at all, and no
label may downgrade it.

The unit of measurement -- the granularity decision
---------------------------------------------------

**The unit is the registered test suite -- in practice, the changed test file
-- and never the individual test function.** This was decided in planning; it
is recorded here because this is where it is implemented. It rests on four
facts about the harness, each of which would have to change before a
per-function verdict could exist:

1. `tests/test_bootstrap.gd` runs every suite in one headless Godot process.
   There is no test-selection flag, no per-function registry, and no
   per-function result anywhere in the output.
2. Each suite's `run()` aggregates private `static func _test_*()` helpers
   into a violations array. A function's identity reaches the log only as free
   text inside a failure message, and only when it fails.
3. The one machine-readable per-unit signal the harness emits is
   `PASS <suite display name>` / `FAIL <suite display name>`, printed by
   `_check()` at `tests/test_bootstrap.gd:160-166`.
4. Per-function verdicts would require rewriting `run()` in every suite in the
   repository into a named-callable registry -- a larger change than this gate
   and out of scope for the whole epic.

Added or changed `_test_*` function names are therefore *listed* in the
report, for the human reading it. They are never a verdict.

Reading the log -- why `FAIL ` is not a safe prefix
---------------------------------------------------

Suites print their own violations with `printerr("FAIL " + violation)` --
`rules/tests/charge_lockout_test.gd:61` and its siblings -- so a prefix match
reads free-text violation messages as suite results. Every line is matched
whole against the set of registered suite display names carried in the plan,
and everything else is ignored.

Reuse, not reimplementation
---------------------------

`strip_comment()` and the suite-reachability rules are imported from
`count-tests.py` rather than copied: a second copy of the reachability rule is
a second definition of what a suite is, and the two would drift.
`tests/orphan_test_contract_test.gd` remains the definition of record for
both, as `count-tests.py`'s own docstring says.

Python standard library only -- no network, no `gh`, no third-party package.
No git, no engine, no subprocess: both trees and the log arrive as arguments,
which is what makes this testable from fixture directories. The roots are the
only roots: nothing in either tree is read relative to `os.getcwd()` or to
this file's own location, because CI points this at a detached worktree under
`$RUNNER_TEMP` that is never the working directory. The single path resolved
against this file's own location is the sibling `count-tests.py` it imports,
which is code, not input.

Usage:

    red-gate.py plan --base-root <dir> --head-root <dir> --changed-files <path>
    red-gate.py verdict --plan <plan.json> --base-log <log>
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path


def _load_count_tests():
    """Import the sibling `count-tests.py` as a module.

    The filename is not an identifier, so a plain `import` cannot reach it;
    `importlib.util.spec_from_file_location` is the intended route. This is
    the one path resolved against this file's own location -- it is the tool's
    own code, not an input tree.
    """
    source = Path(__file__).resolve().with_name("count-tests.py")
    spec = importlib.util.spec_from_file_location("count_tests", source)
    if spec is None or spec.loader is None:  # pragma: no cover -- unreachable
        raise ImportError(f"cannot load {source}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


count_tests = _load_count_tests()

# Imported, never re-typed. See the docstring's "Reuse" note.
strip_comment = count_tests.strip_comment
read_file = count_tests.read_file
test_sources = count_tests.test_sources
declared_class_name = count_tests.declared_class_name
suite_names_in = count_tests.suite_names_in
reachable_names = count_tests.reachable_names
SCANNED_DIRS = count_tests.SCANNED_DIRS
TEST_SUFFIX = count_tests.TEST_SUFFIX
BOOTSTRAP_RELATIVE = count_tests.BOOTSTRAP_RELATIVE
SUITES_DECLARATION = count_tests.SUITES_DECLARATION
SUITE_ENTRY_PATTERN = count_tests.SUITE_ENTRY_PATTERN

# The display name in a `_suites` entry: `{"name": "Foo Test", "run": FooTest.run}`.
# The display name is what `_check()` prints, so it -- not the class name -- is
# what a log line has to be matched against.
SUITE_DISPLAY_PATTERN = re.compile(r'"name"\s*:\s*"([^"]*)"')

# A private per-test helper. Informational only; see the granularity decision.
TEST_FUNCTION_PATTERN = re.compile(
    r"^([ \t]*)(?:static[ \t]+)?func[ \t]+(_test_[A-Za-z0-9_]*)[ \t]*\("
)

# The two suite-level result prefixes `_check()` emits.
RESULT_PREFIXES = ("PASS ", "FAIL ")

# Outcomes, per in-scope suite.
OUTCOME_RED = "red"
OUTCOME_GREEN = "green-at-base"
OUTCOME_DID_NOT_LOAD = "did-not-load"

# Skip reasons recorded in the plan. Every skipped path carries exactly one.
REASON_DELETED = "deleted"
REASON_UID = "uid-file"
REASON_BOOTSTRAP = "bootstrap-registry"
REASON_NOT_A_TEST_FILE = "not-a-test-file"
REASON_COMMENT_ONLY = "comment-only"
REASON_UNREACHABLE = "unreachable"


# ---------------------------------------------------------------------------
# Tree reading
# ---------------------------------------------------------------------------


def suite_display_names(bootstrap_source: str) -> dict[str, str]:
    """`{suite class name: display name}` for every registered entry.

    Walks the `_suites` literal exactly as `count_tests.suite_names_in()`
    does -- same declaration line, same closing `]`, same comment stripping --
    and additionally reads the entry's `"name"` value, which is the string
    `_check()` prints. An entry with no `"name"` key falls back to its class
    name, so a hand-edited bootstrap never drops a suite silently.
    """
    names: dict[str, str] = {}
    inside = False

    for raw_line in bootstrap_source.split("\n"):
        line = strip_comment(raw_line).strip()

        if not inside:
            inside = line.startswith(SUITES_DECLARATION)
            continue

        if line == "]":
            break

        entry = SUITE_ENTRY_PATTERN.search(line)
        if not entry:
            continue

        class_name = entry.group(1)
        if class_name in names:
            continue

        display = SUITE_DISPLAY_PATTERN.search(line)
        names[class_name] = display.group(1) if display else class_name

    return names


def normalised_source(source: str) -> str:
    """`source` reduced to the lines that can change behaviour.

    Comments are stripped, trailing whitespace is dropped, and lines left
    empty are removed -- deleting a whole-line comment leaves a blank line
    behind, and a blank line is not a code change in GDScript. Two versions
    that normalise to the same text differ only in comments and whitespace,
    which is a change that cannot honestly produce a red run.
    """
    lines = []
    for raw_line in source.split("\n"):
        line = strip_comment(raw_line).rstrip()
        if line:
            lines.append(line)
    return "\n".join(lines)


def test_function_bodies(source: str) -> dict[str, str]:
    """`{_test_* function name: normalised body}` for one test file.

    A function runs from its `func` line to the next line indented no deeper
    than that line. Read from the normalised source, so a comment edit inside
    a function body does not make the function look changed.
    """
    bodies: dict[str, list[str]] = {}
    order: list[str] = []
    current: str | None = None
    indent = 0

    for line in normalised_source(source).split("\n"):
        match = TEST_FUNCTION_PATTERN.match(line)
        if match:
            current = match.group(2)
            indent = len(match.group(1))
            if current not in bodies:
                order.append(current)
            bodies[current] = [line.strip()]
            continue

        if current is None:
            continue

        if len(line) - len(line.lstrip()) <= indent:
            current = None
            continue

        bodies[current].append(line.strip())

    return {name: "\n".join(bodies[name]) for name in order}


def changed_test_functions(base_source: str, head_source: str) -> list[str]:
    """The `_test_*` names added or changed between the two versions, in head
    declaration order. Informational only -- never a verdict."""
    base_bodies = test_function_bodies(base_source)
    head_bodies = test_function_bodies(head_source)
    return [
        name
        for name, body in head_bodies.items()
        if base_bodies.get(name) != body
    ]


def is_test_path(path: str) -> bool:
    """True when `path` lies under one of `count-tests.py`'s `SCANNED_DIRS`.

    This by-path separation of test from production is defined here and
    nowhere else.
    """
    return any(path == d or path.startswith(d + "/") for d in SCANNED_DIRS)


def read_changed_files(path: Path) -> list[str]:
    """The newline-delimited, repository-relative paths the caller produced.

    Blank lines are dropped and separators normalised to `/` so a list
    produced on any platform reads the same; order is preserved and
    duplicates are collapsed.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    seen: list[str] = []
    for raw_line in text.split("\n"):
        entry = raw_line.strip().replace("\\", "/")
        if entry and entry not in seen:
            seen.append(entry)
    return seen


def suite_closures(
    registered: list[str],
    sources: dict[str, str],
    declared: dict[str, str],
) -> dict[str, dict[str, bool]]:
    """`{registered class name: the class names it reaches}`.

    `count_tests.reachable_names()` is called once per registered suite, with
    a single-element seed, so the attribution is per registered suite rather
    than one tree-wide closure. The rule itself is the imported one; only the
    seeding differs.
    """
    return {
        name: reachable_names([name], sources, declared) for name in registered
    }


def build_plan(base_root: Path, head_root: Path, changed: list[str]) -> dict:
    """The full plan document for one pull request."""
    bootstrap_source = read_file(head_root / BOOTSTRAP_RELATIVE)
    registered = suite_names_in(bootstrap_source)
    display = suite_display_names(bootstrap_source)

    sources = test_sources(head_root)
    declared: dict[str, str] = {}
    for path, source in sources.items():
        name = declared_class_name(source)
        if name:
            declared[path] = name

    closures = suite_closures(registered, sources, declared)

    paths: list[dict] = []
    in_scope: dict[str, dict] = {}

    for path in changed:
        if not is_test_path(path):
            paths.append({
                "path": path,
                "kind": "production",
                "in_scope": False,
                "reason": None,
                "suites": [],
                "functions": [],
            })
            continue

        record = {
            "path": path,
            "kind": "test",
            "in_scope": False,
            "reason": None,
            "suites": [],
            "functions": [],
        }

        head_path = head_root / path
        base_path = base_root / path

        if path == BOOTSTRAP_RELATIVE:
            # The registry, not a suite: it names what runs and declares no
            # `_test_*` of its own.
            record["reason"] = REASON_BOOTSTRAP
        elif path.endswith(".uid"):
            record["reason"] = REASON_UID
        elif not path.endswith(TEST_SUFFIX):
            record["reason"] = REASON_NOT_A_TEST_FILE
        elif not head_path.is_file():
            record["reason"] = REASON_DELETED
        else:
            head_source = read_file(head_path)
            added = not base_path.is_file()
            base_source = "" if added else read_file(base_path)

            if not added and normalised_source(base_source) == normalised_source(
                head_source
            ):
                record["reason"] = REASON_COMMENT_ONLY
            else:
                record["functions"] = changed_test_functions(
                    base_source, head_source
                )
                class_name = declared.get(path, "")
                owners = [
                    name
                    for name in registered
                    if class_name and class_name in closures.get(name, {})
                ]

                if not owners:
                    # `tests/orphan_test_contract_test.gd` already fails the
                    # build for this; the gate does not duplicate it.
                    record["reason"] = REASON_UNREACHABLE
                else:
                    record["in_scope"] = True
                    record["suites"] = [display.get(n, n) for n in owners]

                    for owner in owners:
                        suite_name = display.get(owner, owner)
                        entry = in_scope.setdefault(
                            suite_name,
                            {
                                "suite": suite_name,
                                "class_name": owner,
                                "files": [],
                                "functions": [],
                            },
                        )
                        entry["files"].append(path)
                        for function in record["functions"]:
                            if function not in entry["functions"]:
                                entry["functions"].append(function)

        paths.append(record)

    suites = [in_scope[name] for name in sorted(in_scope)]

    return {
        "gate_applies": bool(suites),
        "registered_suites": [display.get(n, n) for n in registered],
        "in_scope": suites,
        "paths": paths,
    }


def run_plan(base_root: Path, head_root: Path, changed_files: Path) -> int:
    try:
        changed = read_changed_files(changed_files)
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    plan = build_plan(base_root, head_root, changed)
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 0


# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------


def load_plan(path: Path) -> dict:
    """Load and shape-check a plan this script produced.

    Raises `ValueError` (shape) or lets `OSError`/`json.JSONDecodeError`
    (missing file, bad JSON) propagate. The caller turns all three into exit
    `2` -- a broken gate, never a verdict.
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)

    if (
        not isinstance(data, dict)
        or not isinstance(data.get("gate_applies"), bool)
        or not isinstance(data.get("registered_suites"), list)
        or not isinstance(data.get("in_scope"), list)
    ):
        raise ValueError(f"{path} is not a plan this script produced")

    for entry in data["in_scope"]:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("suite"), str)
            or not isinstance(entry.get("files"), list)
            or not isinstance(entry.get("functions"), list)
        ):
            raise ValueError(f"{path} has a malformed in_scope entry: {entry!r}")

    return data


def read_log(path: Path) -> str:
    """The merge-base run's captured output.

    Raises `ValueError` when the log is empty or blank: a run that produced no
    output at all is an input this tool cannot judge, not a generous pass.
    """
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    if not text.strip():
        raise ValueError(f"{path} is empty -- no merge-base run output to judge")
    return text


def suite_results(log_text: str, registered: list[str]) -> dict[str, str]:
    """`{suite display name: "PASS" | "FAIL"}` for every suite-level line.

    Each line is matched whole against the registered display names, never by
    prefix: a suite's own `printerr("FAIL " + violation)` output shares the
    prefix and must not be read as a suite result. A suite that somehow prints
    both is recorded as `FAIL`, because `_check()` prints exactly one line per
    suite and a contradiction is not a reason to report the friendlier half.
    """
    known = set(registered)
    results: dict[str, str] = {}

    for raw_line in log_text.split("\n"):
        line = raw_line.strip()
        for prefix in RESULT_PREFIXES:
            if not line.startswith(prefix):
                continue
            name = line[len(prefix):]
            if name not in known:
                continue
            verdict = prefix.strip()
            if results.get(name) != "FAIL":
                results[name] = verdict

    return results


def outcome_for(suite: str, results: dict[str, str]) -> str:
    verdict = results.get(suite)
    if verdict == "FAIL":
        return OUTCOME_RED
    if verdict == "PASS":
        return OUTCOME_GREEN
    return OUTCOME_DID_NOT_LOAD


UNIT_NOTE = (
    "The verdict unit is the **registered test suite**, not the individual "
    "test function: the harness emits one `PASS`/`FAIL` line per registered "
    "suite and no per-function result. The `_test_*` names below are listed "
    "for the reader and are informational only."
)

ESCAPE_HATCH_NOTE = (
    "A test that is green at the merge base on purpose -- a characterization "
    "test recording behaviour that already exists -- is exempted by a human "
    "applying the `characterization-test` label to the pull request, with the "
    "reason recorded in the pull request body."
)

NOTHING_RAN_NOTE = (
    "**No suite-level result line appears in the merge-base log at all.** The "
    "test bootstrap autoload itself failed to load against the merge base, so "
    "every in-scope suite below is reported `did-not-load` rather than judged "
    "individually. This is generous on purpose, and it is stated here so that "
    "it stays visible."
)


def build_report(plan: dict, results: dict[str, str], anything_ran: bool) -> tuple[str, int]:
    """The markdown report and the exit code, printed on every run.

    Returns `1` when any in-scope suite was green at the merge base, else `0`.
    """
    lines = ["## Red gate — merge-base verdict", "", UNIT_NOTE, ""]

    if not plan["gate_applies"]:
        lines.append(
            "This pull request changes no test file whose code changed, so the "
            "gate does not apply: it neither passes nor fails."
        )
        lines.append("")
        lines.append(ESCAPE_HATCH_NOTE)
        return "\n".join(lines) + "\n", 0

    if not anything_ran:
        lines.append(NOTHING_RAN_NOTE)
        lines.append("")

    lines.append("| Suite | Outcome | Test file(s) | Added or changed `_test_*` |")
    lines.append("| --- | --- | --- | --- |")

    green: list[dict] = []
    for entry in plan["in_scope"]:
        suite = entry["suite"]
        outcome = outcome_for(suite, results)
        if outcome == OUTCOME_GREEN:
            green.append(entry)

        files = ", ".join(f"`{path}`" for path in entry["files"]) or "—"
        functions = (
            ", ".join(f"`{name}`" for name in entry["functions"]) or "—"
        )
        lines.append(f"| {suite} | `{outcome}` | {files} | {functions} |")

    lines.append("")
    lines.append(
        f"`{OUTCOME_RED}` — the suite failed at the merge base, which is what "
        "the gate asks for. "
        f"`{OUTCOME_DID_NOT_LOAD}` — the suite produced no result line: it "
        "could not even load against the merge base, which demonstrates a "
        "dependency on this pull request's production change just as "
        "unambiguously, and is reported separately so a reader can tell the "
        "two apart. "
        f"`{OUTCOME_GREEN}` — the suite passed at the merge base."
    )

    if green:
        lines.append("")
        lines.append("### Green at the merge base")
        lines.append("")
        for entry in green:
            lines.append(
                f"- **{entry['suite']}** passed against the merge base with "
                "this pull request's test changes overlaid: this test asserts "
                "nothing the pull request changed."
            )

    lines.append("")
    lines.append(ESCAPE_HATCH_NOTE)

    return "\n".join(lines) + "\n", (1 if green else 0)


def run_verdict(plan_path: Path, log_path: Path) -> int:
    try:
        plan = load_plan(plan_path)
        log_text = read_log(log_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    registered = [name for name in plan["registered_suites"] if isinstance(name, str)]
    results = suite_results(log_text, registered)
    markdown, code = build_report(plan, results, bool(results))
    sys.stdout.write(markdown)
    return code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Pick the test suites a pull request must prove red, and judge "
            "the merge-base run's log against that list."
        )
    )
    subparsers = parser.add_subparsers(dest="mode", required=True)

    plan_parser = subparsers.add_parser(
        "plan", help="Report which suites this pull request puts in scope."
    )
    plan_parser.add_argument(
        "--base-root", required=True, help="Merge-base checkout root."
    )
    plan_parser.add_argument(
        "--head-root", required=True, help="Pull request checkout root."
    )
    plan_parser.add_argument(
        "--changed-files",
        required=True,
        help="File of newline-delimited repository-relative changed paths.",
    )

    verdict_parser = subparsers.add_parser(
        "verdict", help="Judge a merge-base run log against a plan."
    )
    verdict_parser.add_argument("--plan", required=True, help="Plan JSON.")
    verdict_parser.add_argument(
        "--base-log", required=True, help="Captured merge-base run output."
    )

    args = parser.parse_args(argv)

    if args.mode == "plan":
        return run_plan(
            Path(args.base_root), Path(args.head_root), Path(args.changed_files)
        )

    return run_verdict(Path(args.plan), Path(args.base_log))


if __name__ == "__main__":
    raise SystemExit(main())

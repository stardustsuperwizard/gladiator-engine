#!/usr/bin/env python3
"""Report how many test suites run and how many `_expect(` assertions exist,
for any checkout given by `--root`, and diff two such reports.

`count --root <dir>` prints one JSON document describing the tree at `<dir>`.
`compare --base <a.json> --head <b.json>` diffs two such documents and fails
when either total has fallen. Neither mode is wired into CI here -- this
script is the unit a ratchet job (#284) later calls.

This is a **port**, not an independent re-implementation, of
`tests/orphan_test_contract_test.gd` (suite reachability) and
`ExtractionContractTest.strip_comment()` in
`rules/tests/extraction_contract_test.gd:102` (comment stripping).
`tests/orphan_test_contract_test.gd` remains the definition of record; every
ported rule below says so again, next to the port, so the two cannot drift
without the docstring lying about it.

Python standard library only -- no network, no `gh`, no third-party package.
`--root` is the only root: nothing is read relative to `os.getcwd()` or to
this file's own location, because CI points this at a detached worktree of
the merge base, in `$RUNNER_TEMP`, that is never the working directory.

Usage:

    count-tests.py count --root <dir>
    count-tests.py compare --base <base.json> --head <head.json>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
import re

# Both test directories, relative to `--root`. Port of
# `OrphanTestContractTest.SCANNED_DIRS`.
SCANNED_DIRS = ("rules/tests", "tests")

# What makes a file a test file. Port of `OrphanTestContractTest.TEST_SUFFIX`.
TEST_SUFFIX = "_test.gd"

# The one definition of what runs, relative to `--root`. Port of
# `OrphanTestContractTest.BOOTSTRAP_PATH`. It is an input, never a subject: it
# does not end in `_test.gd` and is never itself scanned or reported.
BOOTSTRAP_RELATIVE = "tests/test_bootstrap.gd"

# The line that opens the `_suites` array literal. Port of
# `OrphanTestContractTest.SUITES_DECLARATION`.
SUITES_DECLARATION = "var _suites"

# One registered suite per entry line: the identifier before `.run`. Port of
# `OrphanTestContractTest.SUITE_ENTRY_PATTERN`.
SUITE_ENTRY_PATTERN = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*run\b")

# A reference in call position. Port of
# `OrphanTestContractTest.REFERENCE_PATTERN`.
REFERENCE_PATTERN = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.")

# A file-scope class declaration. Port of
# `OrphanTestContractTest.CLASS_NAME_PREFIX`.
CLASS_NAME_PREFIX = "class_name "

# The assertion literal counted per file.
ASSERTION_LITERAL = "_expect("


def strip_comment(line: str) -> str:
    """Return `line` with any GDScript `#` comment removed.

    Port of `ExtractionContractTest.strip_comment()`
    (`rules/tests/extraction_contract_test.gd:102`). Quote-aware: a backslash
    inside either quote skips two characters, `"` toggles double-quote state
    unless inside single, `'` toggles single unless inside double, and an
    unquoted `#` truncates the line there. String literals are not stripped,
    matching every scanner in this repository.
    """
    in_single = False
    in_double = False
    i = 0
    length = len(line)

    while i < length:
        char = line[i]

        if char == "\\" and (in_single or in_double):
            i += 2
            continue

        if char == '"' and not in_single:
            in_double = not in_double
        elif char == "'" and not in_double:
            in_single = not in_single
        elif char == "#" and not in_single and not in_double:
            return line[:i]

        i += 1

    return line


def read_file(path: Path) -> str:
    """File contents as text, or "" when the file cannot be read.

    An unreadable file reads as empty rather than aborting the scan, the same
    posture as `ExtractionContractTest.read_file()`.
    """
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def files_recursive(directory: Path) -> list[Path]:
    """Every file under `directory`, recursive, skipping any entry -- file or
    directory -- whose name begins with `.`.

    Port of `ExtractionContractTest.files_recursive()`, sorted at each level
    so the walk order never depends on the filesystem.
    """
    if not directory.is_dir():
        return []

    results: list[Path] = []
    for entry in sorted(directory.iterdir(), key=lambda p: p.name):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            results.extend(files_recursive(entry))
        else:
            results.append(entry)
    return results


def relative_posix(path: Path, root: Path) -> str:
    """`path`, relative to `root`, with `/` separators -- never an absolute
    path, so two reports from different checkouts diff cleanly."""
    return path.relative_to(root).as_posix()


def test_sources(root: Path) -> dict[str, str]:
    """Every `*_test.gd` file under the scanned directories, as
    `{relative_path: source}`. Port of `OrphanTestContractTest.test_sources()`."""
    sources: dict[str, str] = {}
    for scanned in SCANNED_DIRS:
        for file_path in files_recursive(root / scanned):
            if file_path.name.endswith(TEST_SUFFIX):
                sources[relative_posix(file_path, root)] = read_file(file_path)
    return sources


def suite_names_in(source: str) -> list[str]:
    """The suite class names in a bootstrap source: the identifier before
    `.run` on each line of the `_suites` array literal.

    Port of `OrphanTestContractTest.suite_names_in()`. The array opens at the
    first comment-stripped, edge-stripped line beginning `var _suites` and
    closes at the first subsequent line equal to `]`; the opening line itself
    is never scanned for an entry.
    """
    names: list[str] = []
    inside = False

    for raw_line in source.split("\n"):
        line = strip_comment(raw_line).strip()

        if not inside:
            inside = line.startswith(SUITES_DECLARATION)
            continue

        if line == "]":
            break

        match = SUITE_ENTRY_PATTERN.search(line)
        if match and match.group(1) not in names:
            names.append(match.group(1))

    return names


def declared_class_name(source: str) -> str:
    """The file-scope `class_name` this source declares, or "" when it
    declares none.

    Port of `OrphanTestContractTest.declared_class_name()`. File scope only:
    the line is stripped on the right but not the left, so an inner class's
    indented `class_name` does not count.
    """
    for raw_line in source.split("\n"):
        line = strip_comment(raw_line).rstrip()
        if not line.startswith(CLASS_NAME_PREFIX):
            continue

        rest = line[len(CLASS_NAME_PREFIX):].strip()
        space = rest.find(" ")
        return rest if space < 0 else rest[:space]

    return ""


def references_in(source: str) -> list[str]:
    """Every identifier this source uses in call position, comments stripped.

    Port of `OrphanTestContractTest.references_in()`. A file's own
    `class_name` line is skipped outright, so a file cannot reach itself.
    """
    names: list[str] = []

    for raw_line in source.split("\n"):
        line = strip_comment(raw_line)
        if line.lstrip().startswith(CLASS_NAME_PREFIX):
            continue

        for match in REFERENCE_PATTERN.finditer(line):
            name = match.group(1)
            if name not in names:
                names.append(name)

    return names


def reachable_names(
    registered_names: list[str],
    sources: dict[str, str],
    declared: dict[str, str],
) -> dict[str, bool]:
    """The transitive closure of executed class names, seeded from the
    registered set alone.

    Port of `OrphanTestContractTest._reachable_names()`. Only a file already
    proven to run has its source read for further references, so two
    unregistered suites naming each other are never traversed and neither is
    ever reached.
    """
    reached: dict[str, bool] = {}
    pending: list[str] = []

    for path, name in declared.items():
        if name in registered_names and name not in reached:
            reached[name] = True
            pending.append(path)

    while pending:
        path = pending.pop()
        referenced = references_in(sources[path])

        for other_path, other_name in declared.items():
            if other_name in reached:
                continue
            if other_name in referenced:
                reached[other_name] = True
                pending.append(other_path)

    return reached


def build_report(root: Path) -> dict | None:
    """The full count report for the checkout at `root`, or `None` when the
    `_suites` array yields no registered names (the vacuity case)."""
    bootstrap_source = read_file(root / BOOTSTRAP_RELATIVE)
    registered = suite_names_in(bootstrap_source)

    if not registered:
        return None

    sources = test_sources(root)

    declared: dict[str, str] = {}
    no_class_name: list[str] = []
    for path, source in sources.items():
        name = declared_class_name(source)
        if name:
            declared[path] = name
        else:
            no_class_name.append(path)

    reached = reachable_names(registered, sources, declared)

    counted_paths = sorted(path for path, name in declared.items() if name in reached)
    names = sorted(declared[path] for path in counted_paths)
    unreachable = sorted(
        no_class_name + [path for path, name in declared.items() if name not in reached]
    )

    total = 0
    by_file: dict[str, int] = {}
    for path, source in sources.items():
        stripped = "\n".join(strip_comment(line) for line in source.split("\n"))
        count = stripped.count(ASSERTION_LITERAL)
        total += count
        if count:
            by_file[path] = count

    return {
        "assertions": {"by_file": by_file, "total": total},
        "suites": {
            "count": len(counted_paths),
            "names": names,
            "unreachable": unreachable,
        },
    }


def run_count(root: Path) -> int:
    report = build_report(root)

    if report is None:
        print(
            f"{BOOTSTRAP_RELATIVE}: no registered suites parsed from the "
            f"{SUITES_DECLARATION} array -- the closure has no seed",
            file=sys.stderr,
        )
        return 2

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


def load_report(path: Path) -> dict:
    """Load and shape-check a report this script produced.

    Raises `ValueError` (shape) or lets `OSError`/`json.JSONDecodeError`
    (missing file, bad JSON) propagate -- `compare()`'s caller treats all
    three the same way.
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)

    suites = data.get("suites") if isinstance(data, dict) else None
    assertions = data.get("assertions") if isinstance(data, dict) else None

    if (
        not isinstance(suites, dict)
        or not isinstance(assertions, dict)
        or "count" not in suites
        or "names" not in suites
        or "total" not in assertions
        or "by_file" not in assertions
    ):
        raise ValueError(f"{path} is not a report this script produced")

    return data


def _signed(delta: int) -> str:
    return f"+{delta}" if delta > 0 else str(delta)


def compare_reports(base: dict, head: dict) -> tuple[str, int]:
    """A GitHub-flavoured Markdown report diffing `base` and `head`, and the
    exit code the caller should use: `1` when either total fell, else `0`.

    Totals are compared, never per-file paths, so a rename or a move that
    preserves both totals produces no decrease section.
    """
    base_suite_count = base["suites"]["count"]
    head_suite_count = head["suites"]["count"]
    base_assertion_total = base["assertions"]["total"]
    head_assertion_total = head["assertions"]["total"]

    suite_delta = head_suite_count - base_suite_count
    assertion_delta = head_assertion_total - base_assertion_total
    decreased = suite_delta < 0 or assertion_delta < 0

    lines = [
        "| Metric | Base | Head | Delta |",
        "| --- | --- | --- | --- |",
        f"| Suites | {base_suite_count} | {head_suite_count} | {_signed(suite_delta)} |",
        (
            f"| Assertions | {base_assertion_total} | {head_assertion_total} |"
            f" {_signed(assertion_delta)} |"
        ),
    ]

    if decreased:
        lines.append("")
        lines.append("## Decrease detected")
        lines.append("")

        if suite_delta < 0:
            lines.append(
                f"- Suite count fell by {-suite_delta} (from {base_suite_count} to"
                f" {head_suite_count})."
            )
        if assertion_delta < 0:
            lines.append(
                f"- Assertion total fell by {-assertion_delta} (from"
                f" {base_assertion_total} to {head_assertion_total})."
            )

        base_names = set(base["suites"].get("names", []))
        head_names = set(head["suites"].get("names", []))
        lost_suites = sorted(base_names - head_names)
        if lost_suites:
            lines.append("")
            lines.append("### Suites present in base and absent from head")
            lines.append("")
            for name in lost_suites:
                lines.append(f"- `{name}`")

        base_by_file = base["assertions"].get("by_file", {})
        head_by_file = head["assertions"].get("by_file", {})
        lost_files = []
        for path, before in base_by_file.items():
            after = head_by_file.get(path, 0)
            if after < before:
                lost_files.append((path, before, after))

        if lost_files:
            lines.append("")
            lines.append("### Files that lost assertions")
            lines.append("")
            lines.append("| File | Before | After |")
            lines.append("| --- | --- | --- |")
            for path, before, after in sorted(lost_files):
                lines.append(f"| {path} | {before} | {after} |")

    return "\n".join(lines) + "\n", (1 if decreased else 0)


def run_compare(base_path: Path, head_path: Path) -> int:
    try:
        base = load_report(base_path)
        head = load_report(head_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    markdown, code = compare_reports(base, head)
    sys.stdout.write(markdown)
    return code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Report deterministic test-suite and assertion counts for any "
            "checkout, and diff two such reports."
        )
    )
    subparsers = parser.add_subparsers(dest="mode", required=True)

    count_parser = subparsers.add_parser(
        "count", help="Report suite and assertion counts for --root."
    )
    count_parser.add_argument(
        "--root",
        required=True,
        help="Checkout root. Every read is resolved under it.",
    )

    compare_parser = subparsers.add_parser(
        "compare", help="Diff two count reports and fail on any decrease."
    )
    compare_parser.add_argument("--base", required=True, help="Base report JSON.")
    compare_parser.add_argument("--head", required=True, help="Head report JSON.")

    args = parser.parse_args(argv)

    if args.mode == "count":
        return run_count(Path(args.root))

    return run_compare(Path(args.base), Path(args.head))


if __name__ == "__main__":
    raise SystemExit(main())

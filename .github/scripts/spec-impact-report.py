#!/usr/bin/env python3
"""Spec-change impact report: diff the spec, map through the index, classify.

Diffs `docs/hex-skirmish-game-spec.md` between two git refs (or a ref and the
working tree), maps every changed section through
`docs/spec-traceability.json` via `spec_traceability.resolve`, and prints the
citing modules and tests -- quoting the section's text on both sides -- each
classified `still-valid`, `needs-review` or `likely-superseded`.

Classification rule (the contract; do not substitute similarity scoring,
keyword matching, or any heuristic of your own, and do not add a fourth
bucket). A *normative line* is a non-blank line that does not begin with `>`
(the spec's dated revision notes are written as blockquotes). For a changed
section, compare its normative lines before and after -- each line with
internal whitespace collapsed, so a rewrap is not itself a change:

  - `likely-superseded` -- the section lost or altered at least one normative
    line: some base normative line is not present, in order, among the head
    normative lines.
  - `needs-review` -- every base normative line survives, in order, among the
    head normative lines, and the head has at least one more: the section's
    normative lines were only added to.
  - `still-valid` -- the normative lines are identical before and after; the
    only differences are revision-note (`>`) lines or whitespace.

This tool classifies and reports. It never asserts that an implementation is
wrong, never edits a file, and never opens an Issue -- and it never calls
`gh` or a model.

Standard library only: `subprocess` for `git`, nothing installed. No
network, no credentials.

The pure core -- `build_report(base_text, head_text, index)` -- never touches
git or the filesystem, so the classification is testable against inline
fixture texts without constructing a repository. `git show` (and the
working-tree read for a default `--head`) is used only to obtain the two
texts before handing them to that function.

This file is executed, never imported: the hyphenated name is deliberate.
Do not rename it to an underscore, and do not import it from another script.

Usage:
    spec-impact-report.py [--base <ref>] [--head <ref>] [--json]

    --base defaults to HEAD. --head defaults to the working-tree file.

Exit codes:
    0 -- a report was produced and no changed section was unmapped.
    1 -- a report was produced and at least one changed section was unmapped.
    2 -- a usage error, missing git, a ref that does not carry the spec
         file, or a traceability index that failed to validate. The reason
         is always on stderr.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spec_traceability as st  # noqa: E402

SPEC_PATH = "docs/hex-skirmish-game-spec.md"
INDEX_PATH = "docs/spec-traceability.json"


# ---------------------------------------------------------------------------
# Pure core: no git, no filesystem below this line down to render_prose().
# ---------------------------------------------------------------------------


def normative_lines(text: str) -> List[str]:
    """Non-blank lines that are not a `>` blockquote, whitespace-collapsed."""
    lines = []
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith(">"):
            continue
        lines.append(re.sub(r"\s+", " ", stripped))
    return lines


def _is_subsequence(small: List[str], big: List[str]) -> bool:
    """True if every item of `small` appears in `big`, in order."""
    it = iter(big)
    return all(any(item == candidate for candidate in it) for item in small)


def classify_section(base_text: Optional[str], head_text: Optional[str]) -> str:
    """Classify a changed section per the module-header rule above."""
    base_norm = normative_lines(base_text) if base_text is not None else []
    head_norm = normative_lines(head_text) if head_text is not None else []

    if base_norm == head_norm:
        return "still-valid"
    if _is_subsequence(base_norm, head_norm):
        return "needs-review"
    return "likely-superseded"


def _section_sort_key(section_id: str) -> Tuple[int, ...]:
    return tuple(int(part) for part in section_id.split("."))


def build_report(
    base_text: str, head_text: str, index: Dict[str, Any]
) -> Dict[str, Any]:
    """Diff `base_text` against `head_text`, map through `index`, classify.

    Pure: takes two spec texts and an already-parsed index, returns the
    report structure. Never touches git or the filesystem.
    """
    base_sections = {s["id"]: s for s in st.parse_sections(base_text)}
    head_sections = {s["id"]: s for s in st.parse_sections(head_text)}

    all_ids = sorted(
        set(base_sections) | set(head_sections), key=_section_sort_key
    )

    sections: List[Dict[str, Any]] = []
    unmapped: List[Dict[str, Any]] = []

    for section_id in all_ids:
        base_section = base_sections.get(section_id)
        head_section = head_sections.get(section_id)
        base_section_text = base_section["text"] if base_section else None
        head_section_text = head_section["text"] if head_section else None

        if base_section_text == head_section_text:
            continue  # unchanged

        title = (head_section or base_section)["title"]
        classification = classify_section(base_section_text, head_section_text)
        entry, resolution = st.resolve(section_id, index)

        record = {
            "id": section_id,
            "title": title,
            "base_text": base_section_text,
            "head_text": head_section_text,
            "classification": classification,
            "resolution": resolution,
            "resolved_section": entry.get("section") if entry else None,
            "entry_id": entry.get("id") if entry else None,
        }

        if entry is None:
            unmapped.append(record)
            continue

        hits = []
        for path in entry.get("modules", []) or []:
            hits.append(
                {"path": path, "kind": "module", "classification": classification}
            )
        for path in entry.get("tests", []) or []:
            hits.append(
                {"path": path, "kind": "test", "classification": classification}
            )
        record["hits"] = hits
        sections.append(record)

    return {
        "changed": bool(sections or unmapped),
        "sections": sections,
        "unmapped": unmapped,
    }


def _indent(text: str, prefix: str = "    ") -> str:
    return "\n".join(prefix + line for line in text.split("\n"))


def render_prose(report: Dict[str, Any]) -> str:
    if not report["changed"]:
        return "No spec sections changed.\n"

    lines: List[str] = []
    total = len(report["sections"]) + len(report["unmapped"])
    lines.append(f"{total} spec section(s) changed.")
    lines.append("")

    for section in report["sections"]:
        lines.append(f"## Section {section['id']}: {section['title']}")
        if section["resolution"] == "direct":
            lines.append(
                f"  resolved directly by entry {section['entry_id']} "
                f"(section {section['resolved_section']})"
            )
        else:
            lines.append(
                f"  resolved via parent section {section['resolved_section']}, "
                f"entry {section['entry_id']}"
            )
        lines.append(f"  classification: {section['classification']}")
        lines.append("  base text:")
        lines.append(_indent(section["base_text"] or "(section did not exist)"))
        lines.append("  head text:")
        lines.append(_indent(section["head_text"] or "(section removed)"))
        if section["hits"]:
            lines.append("  hits:")
            for hit in section["hits"]:
                lines.append(
                    f"    - [{hit['classification']}] {hit['kind']}: {hit['path']}"
                )
        else:
            lines.append("  hits: (entry has no modules or tests)")
        lines.append("")

    if report["unmapped"]:
        lines.append("## Unmapped sections (no traceability entry, direct or inherited)")
        for section in report["unmapped"]:
            lines.append(f"  - Section {section['id']}: {section['title']}")
            lines.append("    base text:")
            lines.append(_indent(section["base_text"] or "(section did not exist)"))
            lines.append("    head text:")
            lines.append(_indent(section["head_text"] or "(section removed)"))
        lines.append("")

    return "\n".join(lines).rstrip("\n") + "\n"


# ---------------------------------------------------------------------------
# git-facing wrapper: obtains the two texts and the index, then hands off to
# the pure core above.
# ---------------------------------------------------------------------------


def _repo_root() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "not a git repository")
    return result.stdout.strip()


def _git_show(ref: str, path: str, cwd: str) -> str:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"], cwd=cwd, capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git show {ref}:{path} failed")
    return result.stdout


def _validate_index(index_path: Path, root: Path) -> Tuple[Optional[Dict[str, Any]], List[str]]:
    """Load and sanity-check the index. Never raises; returns problems instead.

    Beyond `load_index`'s own schema validation, checks that every cited
    module and test path actually exists in the tree at `root` -- an index
    that cites a moved or deleted file is exactly the kind of rot this report
    must refuse to build an impact set from.
    """
    index, errors = st.load_index(str(index_path))
    problems = [f"{err['type']}: {err.get('message')}" for err in errors]

    if index is not None:
        for entry in index.get("entries", []):
            if not isinstance(entry, dict):
                continue
            entry_id = entry.get("id", "?")
            for field in ("modules", "tests"):
                for path in entry.get(field, []) or []:
                    if not (root / path).exists():
                        problems.append(
                            f"entry {entry_id}: {field} path does not exist: {path}"
                        )

    return index, problems


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Diff docs/hex-skirmish-game-spec.md between two refs, map "
            "changed sections through docs/spec-traceability.json, and "
            "classify the citing modules and tests still-valid / "
            "needs-review / likely-superseded."
        )
    )
    parser.add_argument(
        "--base",
        default="HEAD",
        help="git ref supplying the old spec text (default: HEAD)",
    )
    parser.add_argument(
        "--head",
        default=None,
        help="git ref supplying the new spec text (default: the working-tree file)",
    )
    parser.add_argument(
        "--json", action="store_true", help="emit JSON instead of prose"
    )
    args = parser.parse_args(argv)

    try:
        root = Path(_repo_root())
    except FileNotFoundError:
        print("error: git is not installed or not on PATH", file=sys.stderr)
        return 2
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    try:
        base_text = _git_show(args.base, SPEC_PATH, str(root))
    except FileNotFoundError:
        print("error: git is not installed or not on PATH", file=sys.stderr)
        return 2
    except RuntimeError as exc:
        print(
            f"error: --base {args.base} does not carry {SPEC_PATH}: {exc}",
            file=sys.stderr,
        )
        return 2

    if args.head:
        try:
            head_text = _git_show(args.head, SPEC_PATH, str(root))
        except FileNotFoundError:
            print("error: git is not installed or not on PATH", file=sys.stderr)
            return 2
        except RuntimeError as exc:
            print(
                f"error: --head {args.head} does not carry {SPEC_PATH}: {exc}",
                file=sys.stderr,
            )
            return 2
    else:
        spec_file = root / SPEC_PATH
        if not spec_file.exists():
            print(f"error: working tree does not carry {SPEC_PATH}", file=sys.stderr)
            return 2
        head_text = spec_file.read_text()

    index_path = root / INDEX_PATH
    index, problems = _validate_index(index_path, root)
    if problems:
        print(
            "error: refusing to build an impact report from a rotted "
            "traceability index:",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 2

    report = build_report(base_text, head_text, index)

    if args.json:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(render_prose(report))

    return 1 if report["unmapped"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Assemble one plan-review context file out of a captured epic-plus-plan bundle.

A plan review asks one question: does this plan, as written, actually implement
the epic it claims to? Answering it needs an epic, every task the planner filed
against it, and enough of the repository to tell a named artifact that exists
from one nobody has written. Gathering that is deterministic work, and this
script does all of it before a model is ever loaded:

    build-plan-review-request.py --bundle bundle.json --out request.md

The bundle is JSON the *caller* has already fetched -- this script performs no
network access, spawns no `gh`, shells out to no `git`, and imports nothing
outside the standard library and its two sibling modules:

    {
      "epic":  {"number": 226, "title": "...", "body": "...",
                "comments": [{"author": "...", "body": "...",
                              "created_at": "..."}]},
      "tasks": [{"number": 227, "title": "...", "body": "...", "url": "..."}],
      "inventory": ["path/to/file.py", ...],  # optional
      "_provenance": "..."  # optional
    }

Any top-level key other than `epic` and `tasks` is ignored, which is how the
checked-in fixtures under `.github/tests/plan-review/` carry an optional
`inventory` key (for fixtures) and a `_provenance` note saying where their
contents came from without those reaching a reviewer's context.

Eight sections come out, in this order:

    # EPIC (AUTHORITATIVE INTENT)
    # EPIC AMENDMENT COMMENTS
    # PLANNED IMPLEMENTATION TASKS
    # DECLARED DEPENDENCY EDGES
    # DECLARED EXPECTED FILES
    # UNRESOLVED ARTIFACT NAMES
    # REPOSITORY FILE INVENTORY
    # DELIBERATELY EXCLUDED

The greppable half of the review is already resolved by the time the file is
written: which dependency edges were declared and which of them point outside
the plan, which tasks declared no expected files, and which artifact names a
task invents that resolve nowhere. A reviewer reads conclusions rather than
re-deriving them, and a regression in the derivation is a test failure here
rather than a judgement call in a model's output.

Two modules do the parsing, and neither is re-typed:
`issue_dependencies.parse()`/`edges()` read the `## Dependencies` table, and
`task_scope.expected_paths()` reads the *Files or Subsystems Expected to
Change* section. `task_scope.py` is imported, never modified.

**Machine-authored comments are dropped.** A comment whose body opens with an
`<!-- agent-` or `<!-- claude-` marker is machine output -- a rollup notice,
a triage summary -- and never a statement of the owner's intent. Feeding a
plan reviewer the control plane's own announcements invites it to review the
machine instead of the plan.

**Check 8 is deliberately conservative.** A token is reported unresolved only
when it looks like a repository artifact -- a path, a known file extension, or
a label-shaped name on a line that says "label" -- *and* resolves in none of
the working tree, the epic body, or a sibling task's body. A noisy check 8 is
worse than no check 8, because every false positive costs a human read.

The failure path writes nothing at all. A bundle with no tasks, or a task whose
body is missing, exits non-zero naming the epic or the task, and leaves no file
at `--out` -- a half-assembled request that a reviewer might run against is the
one outcome worth refusing outright.

No reviewer instructions live here. This assembles context; the contract is the
agent file's, prepended by the composite action that calls this.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import issue_dependencies  # noqa: E402  (path set above; both are siblings)
import task_scope  # noqa: E402

REPO_ROOT = SCRIPTS_DIR.parents[1]

# Machine-comment prefixes — both control-plane surfaces' vocabularies.
# Matched at the start, not searched for, for the same reason #69's marker
# read is: a comment that merely quotes the marker is not a machine comment.
MACHINE_COMMENT_MARKERS = ("<!-- agent-", "<!-- claude-")

SECTION_HEADINGS = (
    "# EPIC (AUTHORITATIVE INTENT)",
    "# EPIC AMENDMENT COMMENTS",
    "# PLANNED IMPLEMENTATION TASKS",
    "# DECLARED DEPENDENCY EDGES",
    "# DECLARED EXPECTED FILES",
    "# UNRESOLVED ARTIFACT NAMES",
    "# REPOSITORY FILE INVENTORY",
    "# DELIBERATELY EXCLUDED",
)

# Directories the inventory never descends into. `.git` is the one the brief
# names; the rest are generated or vendored trees that are not repository
# artifacts and whose thousands of entries would bury the ones that are --
# `.godot/` alone is larger than everything a plan ever names.
SKIP_DIRS = frozenset(
    {".git", ".godot", "__pycache__", ".import", "node_modules", ".venv"}
)

# Check 8's extension whitelist. A whitelist rather than `task_scope`'s
# any-dotted-suffix rule on purpose: that rule reads `Board.reachable_from()`
# as a path with a `.reachable_from` extension, and a check that reports every
# GDScript method call is the noisy check 8 the brief forbids.
KNOWN_EXTENSIONS = (
    ".py", ".sh", ".yml", ".yaml", ".md", ".gd", ".tscn", ".tres",
    ".json", ".jsonl", ".toml", ".cfg", ".ini", ".txt", ".godot",
    ".gdshader", ".import", ".svg", ".png",
)

# A label: `human-credentials`, or a routing label's `agent:role:vendor`
# triple. Deliberately not "anything with a colon in it" -- that shape is also
# worn by GitHub search qualifiers, and `is:issue` is not a label.
LABEL_SHAPE = re.compile(
    r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)+$"
    r"|^agent:[a-z0-9-]+:[a-z0-9-]+$"
)

# Label shape alone is worn by reason codes (`no-section`), enum values, and a
# good deal of hyphenated prose, so a label candidate must also sit on a line
# that says "label". As a word: `labelled` is how a task describes an Issue's
# state, and gating on it readmits every reason code the check just excluded.
LABEL_WORD = re.compile(r"\blabels?\b", re.I)

# Where the repository's labels are declared, as `name|colour|description`.
# The only file this script reads the contents of: a label is an artifact with
# no path, so "does it exist" cannot be answered from the inventory.
LABEL_REGISTRY = ".github/scripts/bootstrap-labels.sh"
LABEL_REGISTRY_ROW = re.compile(
    r"^([a-z][a-z0-9:._-]*)\|[0-9A-Fa-f]{6}\|", re.M
)

BACKTICKED = re.compile(r"`([^`\n]+)`")


# ---------------------------------------------------------------------------
# The bundle
# ---------------------------------------------------------------------------


def load_bundle(path: str) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def validate(bundle: dict) -> list[str]:
    """Every reason this bundle cannot be assembled, named concretely.

    Collected rather than raised one at a time so a caller fixing a capture
    sees the whole list, and checked before a single byte is written so a
    refusal leaves no half-built request behind.
    """
    problems: list[str] = []

    epic = bundle.get("epic") or {}
    epic_number = epic.get("number")
    epic_label = (
        f"#{epic_number}" if epic_number is not None else "(unnumbered)"
    )

    if not isinstance(epic, dict) or epic.get("body") is None:
        problems.append(
            f"epic {epic_label}: the epic body is missing. The review's"
            " authoritative intent cannot be assembled without it."
        )

    tasks = bundle.get("tasks")
    if not tasks:
        problems.append(
            f"epic {epic_label}: the bundle declares no Implementation Tasks."
            " There is no plan to review."
        )
        return problems

    for index, task in enumerate(tasks):
        number = task.get("number")
        task_label = f"#{number}" if number is not None else f"task[{index}]"
        if task.get("body") is None:
            problems.append(
                f"task {task_label}: body is null or absent. A task cannot be"
                " reviewed from its title alone."
            )

    return problems


def human_comments(epic: dict) -> list[dict]:
    """The epic's comments with machine output removed, in the order written."""
    kept = []
    for comment in epic.get("comments") or []:
        body = comment.get("body") or ""
        if any(body.lstrip().startswith(marker) for marker in MACHINE_COMMENT_MARKERS):
            continue
        kept.append(comment)
    return kept


# ---------------------------------------------------------------------------
# The working tree
# ---------------------------------------------------------------------------


class Tree:
    """The repository as three lookup sets, read with `pathlib` alone.

    No `git ls-files`: this script shells out to nothing, so "tracked" is
    approximated by "present, outside SKIP_DIRS". The difference only ever
    makes check 8 quieter, which is the direction it is supposed to fail in.

    When `inventory` is provided (a list of repository-relative paths), the
    Tree is built from that list instead of walking the filesystem. When
    absent, the behavior is as today: walk `root`.
    """

    def __init__(self, root: pathlib.Path, inventory: list[str] | None = None):
        self.root = root
        self.files: set[str] = set()
        self.dirs: set[str] = set()
        self.basenames: set[str] = set()

        if inventory is not None:
            self._from_inventory(inventory)
        else:
            self._walk(root)

        self.top_level = {name for name in self.dirs if "/" not in name}
        self.labels = self._labels()

    def _labels(self) -> set[str]:
        registry = self.root / LABEL_REGISTRY
        if not registry.is_file():
            return set()
        return set(
            LABEL_REGISTRY_ROW.findall(registry.read_text(errors="replace"))
        )

    def _from_inventory(self, inventory: list[str]) -> None:
        """Build the tree from a provided list of repository-relative paths.

        Each path is taken as given; no filtering by SKIP_DIRS is applied.
        The caller is responsible for excluding what should be excluded.
        """
        for path in inventory:
            if "/" in path:
                # It's a file: add it and its parent directories
                self.files.add(path)
                self.basenames.add(path.rsplit("/", 1)[-1])
                # Add all parent directories
                parts = path.split("/")
                for i in range(1, len(parts)):
                    dir_path = "/".join(parts[:i])
                    self.dirs.add(dir_path)
            else:
                # It's a top-level file or directory name
                # Assume it's a file if we don't know; the tree lookup is
                # permissive (it checks both files and dirs)
                self.basenames.add(path)
                self.files.add(path)

    def _walk(self, directory: pathlib.Path) -> None:
        for entry in sorted(directory.iterdir()):
            if entry.name in SKIP_DIRS:
                continue
            relative = entry.relative_to(self.root).as_posix()
            if entry.is_dir():
                self.dirs.add(relative)
                self._walk(entry)
            elif entry.is_file():
                self.files.add(relative)
                self.basenames.add(entry.name)

    def by_directory(self) -> list[tuple[str, list[str]]]:
        grouped: dict[str, list[str]] = {}
        for path in self.files:
            parent = path.rsplit("/", 1)[0] if "/" in path else "."
            grouped.setdefault(parent, []).append(path.rsplit("/", 1)[-1])
        return [
            (directory, sorted(names))
            for directory, names in sorted(grouped.items())
        ]


# ---------------------------------------------------------------------------
# Check 8: artifact names that resolve nowhere
# ---------------------------------------------------------------------------


def clean_token(raw: str) -> str:
    """Reduce one written token to the artifact name it refers to."""
    token = raw.strip().strip("*_")
    token = token.strip(",;:()[]<>\"'").rstrip(".")
    token = re.sub(r":\d+$", "", token)          # `agent-01-planner.yml:1558`
    if token.startswith("res://"):               # a Godot resource path
        token = token[len("res://"):]
    return task_scope.normalize(token)


def artifact_kind(token: str, allow_label: bool) -> str | None:
    """`path`, `file`, `label`, or None for "this is not an artifact name"."""
    if not token or len(token) > 120:
        return None
    if token.startswith("-"):                    # a command-line flag
        return None
    if any(character in token for character in " \t\\$&{}<>|\"'()!?=,;"):
        return None
    # `*.tres` names a kind of file, not a file.
    if "*" in token and "/" not in token:
        return None
    if token.casefold().endswith(KNOWN_EXTENSIONS):
        return "path" if "/" in token else "file"
    if "/" in token:
        return "path"
    if allow_label and LABEL_SHAPE.match(token):
        return "label"
    return None


def candidate_tokens(body: str) -> dict[str, str]:
    """Artifact-shaped tokens a body names, mapped to their kind.

    Read from backticked spans, which is how this repository's Issue templates
    and every planner session write an artifact name, plus whatever
    `task_scope.expected_paths()` finds -- the planner renders expected files
    as bare bullets with no backticks at all, so a backtick-only reader misses
    exactly the section most worth checking.
    """
    found: dict[str, str] = {}

    for line in (body or "").splitlines():
        allow_label = bool(LABEL_WORD.search(line))
        for span in BACKTICKED.findall(line):
            for word in span.split():
                token = clean_token(word)
                kind = artifact_kind(token, allow_label)
                if kind:
                    found.setdefault(token, kind)

    for path in task_scope.expected_paths(body or ""):
        token = clean_token(path)
        if artifact_kind(token, allow_label=False):
            found.setdefault(token, "path")

    return found


def _glob_stem(token: str) -> str:
    """The directory a token stands for: everything before its first wildcard.

    `.github/workflows/**`, `.github/workflows/*.yml` and `.github/workflows/`
    all reduce to `.github/workflows`, which either exists or does not. A path
    with no wildcard reduces to itself.
    """
    kept: list[str] = []
    for segment in token.split("/"):
        if "*" in segment:
            break
        kept.append(segment)
    return "/".join(kept).rstrip("/")


def is_repository_shaped(token: str, kind: str, tree: Tree) -> bool:
    """The half of "is this an artifact name" that needs the working tree.

    A path-shaped token carrying no known extension counts only when its first
    segment is a top-level directory that exists. `run/main_scene` is a
    `project.godot` configuration key and `OWNER/NAME` is an argument
    placeholder; reporting either is precisely the noise that makes a reviewer
    stop reading this section, and both die here.
    """
    if kind != "path":
        return True
    if token.casefold().endswith(KNOWN_EXTENSIONS):
        return True
    return token.split("/", 1)[0] in tree.top_level


def resolves(token: str, kind: str, tree: Tree, texts: list[str]) -> bool:
    """Does this name refer to something that exists, or that is being named?

    Three places, in the brief's own order: the working tree, the epic body,
    and a sibling task's body. A name one task invents and another task creates
    is accounted for -- that is a plan, not a gap. Comments are deliberately
    not consulted: the plan comment restates the plan, so resolving against it
    would let a name the plan invented resolve against itself.
    """
    basename = token.rsplit("/", 1)[-1]

    if kind == "label" and token in tree.labels:
        return True

    if token in tree.files or token in tree.dirs:
        return True
    if basename and basename in tree.basenames:
        return True

    stem = _glob_stem(token)
    if stem and (stem in tree.dirs or stem in tree.files):
        return True

    needle = basename or token
    return any(needle in (text or "") for text in texts)


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------


def render_epic(epic: dict) -> str:
    lines = [
        SECTION_HEADINGS[0],
        "",
        "The epic is the authoritative statement of intent. Where a task and"
        " the epic disagree, the epic is right and the task is the defect.",
        "",
        f"## #{epic.get('number')} — {epic.get('title', '')}".rstrip(" —"),
        "",
        (epic.get("body") or "").rstrip(),
        "",
    ]
    return "\n".join(lines)


def render_comments(epic: dict) -> str:
    lines = [
        SECTION_HEADINGS[1],
        "",
        "Human comments on the epic, in the order they were written. **A later"
        " comment wins.** An amendment that contradicts the epic body is the"
        " owner's newer intent, not a disagreement to resolve in the body's"
        " favour.",
        "",
        "Machine-authored comments are excluded; see the final section.",
        "",
    ]

    comments = human_comments(epic)
    if not comments:
        lines += ["_No human comments on this epic._", ""]
        return "\n".join(lines)

    for index, comment in enumerate(comments, start=1):
        author = comment.get("author") or "unknown"
        created = comment.get("created_at") or "unknown date"
        lines += [
            f"## Comment {index} of {len(comments)} — {author}, {created}",
            "",
            (comment.get("body") or "").rstrip(),
            "",
        ]

    return "\n".join(lines)


def render_tasks(tasks: list[dict]) -> str:
    lines = [
        SECTION_HEADINGS[2],
        "",
        f"{len(tasks)} task(s), each in full. These are the plan.",
        "",
    ]

    for task in tasks:
        heading = f"## #{task.get('number')} — {task.get('title', '')}"
        lines.append(heading.rstrip(" —"))
        if task.get("url"):
            lines += ["", task["url"]]
        lines += ["", (task.get("body") or "").rstrip(), ""]

    return "\n".join(lines)


def render_dependencies(epic: dict, tasks: list[dict]) -> str:
    planned = {task.get("number") for task in tasks}
    epic_number = epic.get("number")

    lines = [
        SECTION_HEADINGS[3],
        "",
        "Read by `issue_dependencies.parse()` from each task's"
        " `## Dependencies` table. An edge is written `(blocked, blocker)`.",
        "",
    ]

    any_edge = False
    for task in tasks:
        number = task.get("number")
        body = task.get("body") or ""
        parsed = issue_dependencies.parse(body)
        pairs = (
            issue_dependencies.edges(number, body)
            if isinstance(number, int)
            else []
        )

        lines.append(f"## #{number}")
        lines.append("")

        if not parsed["declared"]:
            lines.append(
                "- FLAG: no `## Dependencies` section at all. Silence is not"
                " the same answer as \"none\"."
            )
        elif not pairs:
            lines.append("- No edges declared.")

        for blocked, blocker in pairs:
            any_edge = True
            note = ""
            if blocker not in planned:
                note = (
                    " — FLAG: #%d is outside this plan%s"
                    % (
                        blocker,
                        " (it is the parent epic)"
                        if blocker == epic_number
                        else "",
                    )
                )
            if blocked not in planned:
                note += (
                    " — FLAG: #%d is outside this plan%s"
                    % (
                        blocked,
                        " (it is the parent epic)"
                        if blocked == epic_number
                        else "",
                    )
                )
            lines.append(f"- #{blocked} is blocked by #{blocker}{note}")

        for row in parsed["malformed"]:
            lines.append(
                f"- FLAG: malformed row names a relationship but no Issue:"
                f" `{row}`"
            )

        lines.append("")

    if not any_edge:
        lines += [
            "No task declares an edge. For a plan whose tasks are genuinely"
            " independent that is correct; for one with an ordering it is the"
            " ordering going unwritten.",
            "",
        ]

    return "\n".join(lines)


def render_expected_files(
    tasks: list[dict], per_task: dict, tree: Tree
) -> str:
    lines = [
        SECTION_HEADINGS[4],
        "",
        "Read by `task_scope.expected_paths()` from each task's *Files or"
        " Subsystems Expected to Change* section.",
        "",
    ]

    for task in tasks:
        number = task.get("number")
        paths = per_task[number]
        siblings = {
            path
            for other, other_paths in per_task.items()
            if other != number
            for path in other_paths
        }

        lines += [f"## #{number}", ""]

        if not paths:
            lines += [
                "- FLAG: declares no expected files. The section is missing,"
                " empty, or names nothing path-shaped — so nothing here says"
                " what this task touches.",
                "",
            ]
            continue

        for path in sorted(paths):
            if path in tree.files or path in tree.dirs:
                lines.append(f"- `{path}` — exists in the tree")
            elif path in siblings:
                lines.append(
                    f"- `{path}` — not in the tree; also named by a sibling"
                    " task"
                )
            else:
                stem = _glob_stem(path)
                if stem and stem in tree.dirs:
                    lines.append(
                        f"- `{path}` — glob over `{stem}/`, which exists"
                    )
                else:
                    lines.append(
                        f"- `{path}` — FLAG: new. In neither the tree nor"
                        " any sibling task's expected files, so this task"
                        " is the only thing that creates it."
                    )

        lines.append("")

    return "\n".join(lines)


def render_unresolved(epic: dict, tasks: list[dict], tree: Tree) -> str:
    lines = [
        SECTION_HEADINGS[5],
        "",
        "Artifact names a task writes down that resolve in none of the working"
        " tree, the epic body, or a sibling task's body. A name here is either"
        " a file the plan forgot to have somebody create, or a stale name left"
        " over from an earlier draft.",
        "",
        "Conservative by construction: only path-, file-, workflow- or"
        " label-shaped tokens are considered at all.",
        "",
    ]

    epic_body = epic.get("body") or ""
    unresolved: dict[str, list[int]] = {}
    kinds: dict[str, str] = {}

    for task in tasks:
        number = task.get("number")
        siblings = [
            other.get("body") or ""
            for other in tasks
            if other.get("number") != number
        ]
        candidates = candidate_tokens(task.get("body") or "")
        for token, kind in sorted(candidates.items()):
            if not is_repository_shaped(token, kind, tree):
                continue
            if resolves(token, kind, tree, [epic_body] + siblings):
                continue
            unresolved.setdefault(token, []).append(number)
            kinds.setdefault(token, kind)

    if not unresolved:
        lines += [
            "_Every artifact name the plan uses resolves._",
            "",
        ]
        return "\n".join(lines)

    for token in sorted(unresolved):
        named_by = ", ".join(f"#{number}" for number in unresolved[token])
        lines.append(f"- `{token}` ({kinds[token]}) — named by {named_by}")

    lines.append("")
    return "\n".join(lines)


def render_inventory(tree: Tree) -> str:
    lines = [
        SECTION_HEADINGS[6],
        "",
        "Every file in the working tree, by directory, so a name in the plan"
        " can be checked against what is actually there. `.git` and generated"
        " trees (`.godot`, `__pycache__`, `.import`, `node_modules`, `.venv`)"
        " are excluded.",
        "",
    ]

    for directory, names in tree.by_directory():
        label = "(repository root)" if directory == "." else f"{directory}/"
        lines.append(f"## {label} — {len(names)} file(s)")
        lines.append("")
        for name in names:
            prefix = "" if directory == "." else f"{directory}/"
            lines.append(f"- {prefix}{name}")
        lines.append("")

    return "\n".join(lines)


def render_exclusions() -> str:
    lines = [
        SECTION_HEADINGS[7],
        "",
        "What is not in this file, and why — so an absence is not read as a"
        " finding:",
        "",
        "- **Machine-authored comments.** Any comment whose body opens with an"
        " `<!-- agent-` or `<!-- claude-` marker: rollup notices, triage"
        " summaries, planner bookkeeping. They are the control plane talking"
        " to itself, never a statement of intent, and reviewing them is"
        " reviewing the machine instead of the plan.",
        "- **File contents.** The inventory carries names only, and a plan is"
        " judged against what exists rather than against how it is"
        f" implemented. The one exception is `{LABEL_REGISTRY}`, read for the"
        " label names it declares, because a label is an artifact with no"
        " path and the inventory cannot answer for one.",
        "- **Git history, pull requests, and review threads.** The plan is"
        " reviewed before any of it is dispatched; nothing has been"
        " implemented yet, so there is nothing there to read.",
        "- **Anything requiring the network.** The bundle arrives pre-fetched;"
        " this assembly performs no GitHub call and runs no model.",
        "- **Other epics and their tasks.** Sibling work does not expand or"
        " excuse this plan.",
        "- **The reviewer's own contract.** The role definition, the verdict"
        " vocabulary and the eight checks live in the agent file and are"
        " prepended by the action that calls this script. This file is"
        " context, not instructions.",
        "",
    ]
    return "\n".join(lines)


def build(bundle: dict, tree: Tree) -> str:
    epic = bundle["epic"]
    tasks = bundle["tasks"]
    per_task = {
        task.get("number"): task_scope.expected_paths(task.get("body") or "")
        for task in tasks
    }

    return "\n".join(
        [
            render_epic(epic),
            render_comments(epic),
            render_tasks(tasks),
            render_dependencies(epic, tasks),
            render_expected_files(tasks, per_task, tree),
            render_unresolved(epic, tasks, tree),
            render_inventory(tree),
            render_exclusions(),
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Assemble a plan-review context file from a captured"
            " epic-plus-plan bundle. No network, no `gh`, no model."
        )
    )
    parser.add_argument(
        "--bundle",
        required=True,
        help="JSON file holding the epic, its comments, and its tasks.",
    )
    parser.add_argument(
        "--out",
        required=True,
        help=(
            "Where to write the assembled request. Nothing is written"
            " anywhere else, and nothing is written at all on a refusal."
        ),
    )
    args = parser.parse_args()

    bundle = load_bundle(args.bundle)

    problems = validate(bundle)
    if problems:
        print(
            "build-plan-review-request: refusing to assemble a review"
            " request:",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    # Build the tree from an optional inventory in the bundle, or walk REPO_ROOT
    inventory = bundle.get("inventory")
    tree = Tree(REPO_ROOT, inventory)
    text = build(bundle, tree)

    out = pathlib.Path(args.out)
    if out.parent and not out.parent.exists():
        out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")

    print(
        f"Wrote {out} ({len(text.splitlines())} lines,"
        f" {len(bundle['tasks'])} task(s))."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

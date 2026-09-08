#!/usr/bin/env bash
# Regression checks for the logic embedded inside workflow YAML.
#
# The control plane's real behaviour lives in `shell: python` steps and `--jq`
# programs inside `.github/workflows/*.yml` and `.github/actions/*/action.yml`.
# No existing test could reach any of it: `validate-godot.sh` boots the Godot
# project, and `test-issue-dependencies.sh` covers the two `.github/scripts/`
# modules. Everything in between was verified by reading it.
#
# That gap has a cost history rather than a hypothetical one. Every check below
# exists because the thing it checks broke once:
#
#   Part 1  A syntax error in an embedded step is invisible until the step
#           runs, which for a failure reporter means it runs on the day
#           something else has already gone wrong.
#   Part 2  #115 -- triage re-filed a pull request's own "filed as #N"
#           announcements as new findings, four times.
#   Part 3  #65 -- a 115-character label description 422'd and failed a whole
#           run, because GitHub caps descriptions at 100.
#   Part 4  #69 -- a marker searched anywhere in a comment body matched a
#           comment that merely quoted it, and every retry skipped itself as
#           already done.
#   Part 5  #97/#98 -- scratch written to the repository root got swept into
#           an implementation commit, and then broke that branch's retry.
#
# Like `test-issue-dependencies.sh`, this needs nothing but python3: no
# network, no credentials, no GitHub CLI, and it never touches a real
# repository. `jq` is used if present and skipped with a notice if not, so the
# script stays runnable on a machine that does not have it.
#
# Usage: .github/scripts/test-workflow-logic.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

failures=0

run_part () {
  local name="$1"
  shift
  echo
  echo "$name"
  if "$@"; then
    :
  else
    failures=$((failures + 1))
  fi
}

# ---------------------------------------------------------------------------
# The extractor every part shares.
#
# Written to a temp module rather than repeated per heredoc: a hand-copied
# block-scalar walk is one that stops matching the others the first time any
# of them is fixed, which is the same reasoning agent-06-triage.yml gives for
# importing issue_dependencies instead of re-typing it.
# ---------------------------------------------------------------------------

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/wf.py" <<'EXTRACTOR'
"""Read `run:` block scalars out of workflow and action YAML, without a
YAML parser -- pyyaml is not guaranteed on a bare runner, and the block
scalar's own indentation is all that is needed to find its end."""

import glob
import pathlib
import re
import textwrap


def files():
    return sorted(
        glob.glob(".github/workflows/*.yml")
        + glob.glob(".github/actions/*/action.yml")
    )


def _blocks(path, want_shell):
    """Yield (line_number, dedented_source) per `run: |` block whose step
    declares `shell: <want_shell>`, or every block when want_shell is None."""

    lines = pathlib.Path(path).read_text(errors="replace").splitlines()
    i = 0

    while i < len(lines):
        stripped = lines[i].strip()

        # A step's `shell:` may appear before or after other keys, so anchor
        # on `run: |` and look backwards a bounded distance for the shell.
        if re.match(r"^run:\s*\|", stripped):
            indent = len(lines[i]) - len(lines[i].lstrip())

            shell = None
            for back in range(i - 1, max(-1, i - 25), -1):
                s = lines[back].strip()
                if s.startswith("- name:") or s.startswith("- uses:"):
                    break
                m = re.match(r"^shell:\s*(\S+)", s)
                if m:
                    shell = m.group(1)
                    break

            body, k = [], i + 1
            while k < len(lines):
                ln = lines[k]
                if ln.strip() and (len(ln) - len(ln.lstrip())) <= indent:
                    break
                body.append(ln)
                k += 1

            if want_shell is None or shell == want_shell:
                yield i + 1, textwrap.dedent("\n".join(body))

            i = k
            continue

        i += 1


def python_steps(path):
    return _blocks(path, "python")


def all_steps(path):
    return _blocks(path, None)


def step_source(path, marker, shell="python"):
    """The one step under `- name: <marker>`. Used by tests that exercise a
    specific parser rather than sweeping every step."""

    text = pathlib.Path(path).read_text()
    start = text.index(f"- name: {marker}")
    line_of_start = text[:start].count("\n")

    for line, src in _blocks(path, shell):
        if line > line_of_start:
            return src

    raise LookupError(f"no {shell} step under {marker!r} in {path}")
EXTRACTOR

# ---------------------------------------------------------------------------
# Part 1: every embedded program is at least syntactically real.
# ---------------------------------------------------------------------------

part1 () {
  python3 - "$work_dir" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import wf

failed = 0
count = 0

for path in wf.files():
    for line, src in wf.python_steps(path):
        count += 1
        try:
            compile(src, f"{path}:{line}", "exec")
        except SyntaxError as exc:
            failed += 1
            print(f"  FAIL — {path}:{line} does not compile: {exc}",
                  file=sys.stderr)

if not failed:
    print(f"  ok   — {count} embedded python step(s) compile")

sys.exit(1 if failed else 0)
PY
}

part1_jq () {
  if ! command -v jq > /dev/null 2>&1; then
    echo "  skip — jq is not installed; embedded jq programs not checked"
    return 0
  fi

  python3 - "$work_dir" <<'PY' > "$work_dir/jq-programs.txt"
import re
import sys

sys.path.insert(0, sys.argv[1])
import wf

# `--jq '<program>'` and `jq -r '<program>'`, single-quoted and possibly
# spanning lines. Double-quoted jq is not collected: it is interpolated by
# the shell before jq ever sees it, so checking the pre-interpolation text
# would report failures that are not real.
PATTERN = re.compile(r"(?:--jq|jq(?:\s+-[a-zA-Z]+)*)\s+'([^']+)'", re.S)

seen = set()
for path in wf.files():
    for line, src in wf.all_steps(path):
        for m in PATTERN.finditer(src):
            program = m.group(1)
            if "${{" in program or "$(" in program:
                continue

            # A shell quote-splice (`'"'"'`, how you put an apostrophe inside
            # a single-quoted shell word) closes the quote this pattern is
            # matching, so the capture stops mid-program. Checking the
            # fragment would report a truncation as a syntax error. Detected
            # by the `"` that immediately follows the closing quote.
            if src[m.end():m.end() + 1] == '"':
                continue
            key = (path, program)
            if key in seen:
                continue
            seen.add(key)
            print(f"{path}\t{line}\t{program!r}")
PY

  local bad=0
  local total=0

  while IFS=$'\t' read -r path line program; do
    total=$((total + 1))
    prog="$(python3 -c 'import ast,sys; print(ast.literal_eval(sys.argv[1]))' "$program")"

    # Exit 3 is jq's COMPILE error; exit 5 is a runtime error. Almost every
    # program here is valid and errors at runtime because `-n` feeds it null
    # -- `.labels[].name` against null is exit 5, and is not a defect. Only
    # exit 3 means the program would not have run whatever the input was.
    jq -n "$prog" > /dev/null 2>&1 || status=$?
    status=${status:-0}

    if [ "$status" -eq 3 ]; then
      echo "  FAIL — $path:$line is not a valid jq program: $prog" >&2
      bad=$((bad + 1))
    fi

    unset status
  done < "$work_dir/jq-programs.txt"

  if [ "$bad" -eq 0 ]; then
    echo "  ok   — $total embedded jq program(s) parse"
  fi

  return $((bad > 0))
}

# ---------------------------------------------------------------------------
# Part 2: agent-06-triage.yml's finding parser (#115).
#
# The parser is pure python with no GitHub call in the matching path, which is
# what made #115 the natural case to build this harness around. Each case
# below is one of that Issue's six acceptance criteria.
# ---------------------------------------------------------------------------

part2 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import os
import sys

sys.path.insert(0, sys.argv[1])
sys.path.insert(0, os.path.join(sys.argv[2], ".github", "scripts"))
import wf

TRIAGE = ".github/workflows/agent-06-triage.yml"

src = wf.step_source(TRIAGE, "Gather Findings")

# Everything up to `def findings(` is the matching path: the guards, is_empty()
# and bullets(). Past it the step reads pr.json and GITHUB_OUTPUT.
src = src[: src.index("def findings(")]
src = src.replace('pr = json.loads(pathlib.Path("pr.json").read_text())', "pr = {}")

module = {}
exec(compile(src, f"{TRIAGE}:Gather Findings", "exec"), module)

bullets = module["bullets"]
issue_dependencies = module["issue_dependencies"]
model_response = module["model_response"]

# (criterion, bullet, is it a finding that should be filed?)
CASES = [
    (1, "- #101 — [epic] Spec steward: a docs-scoped role.", False),
    (1, "- #101 - [epic] Spec steward.", False),
    (1, "- #101: [epic] Spec steward.", False),
    (1, "- **#111 — `_expect()` silent-fails on Godot 4.4.** Not filed here.", False),
    (1, "1. **#113 — a numbered announcement.**", False),
    (2, "- Something broken, filed as #123", False),
    (2, "- Something broken, see #123", False),
    (2, "- Something broken, duplicate of #9", False),
    (3, "- The client ignores status codes like #404, already documented.", True),
    (4, "- #100 base HP is wrong for archers.", True),
    (4, "- #004488 is the accent colour and fails contrast.", True),
    (6, "- Requires a keyword before it (`filed as #123`, `see #123`).", True),
    (6, "- A reference inside a span `#101 — thing` does not suppress.", True),
]

failed = 0

for criterion, text, should_file in CASES:
    filed = bool(bullets(text))
    if filed == should_file:
        print(f"  ok   — c{criterion}: {'filed' if filed else 'suppressed'}"
              f" — {text[:58]}")
    else:
        failed += 1
        print(f"  FAIL — c{criterion}: {'filed' if filed else 'suppressed'},"
              f" wanted {'filed' if should_file else 'suppressed'} — {text}",
              file=sys.stderr)

# Criterion 6's other half: a fence contributes no bullet at all, which
# `findings()` gets from strip_fenced_blocks rather than from the guards.
fenced = "## H\n\n- A real finding.\n\n```\n- filed as #123\n```\n"
got = bullets(
    issue_dependencies.section(
        model_response.strip_fenced_blocks(
            issue_dependencies.strip_comments(fenced)
        ),
        "H",
    )
)

if got == ["A real finding."]:
    print("  ok   — c6: a fenced block neither contributes nor suppresses")
else:
    failed += 1
    print(f"  FAIL — c6 fenced block: {got!r}", file=sys.stderr)

sys.exit(1 if failed else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 3: label descriptions fit GitHub's cap (#65).
#
# GitHub answers 422 above 100 characters, and `gh label create` surfaces that
# as a failed step -- in agent-06-triage.yml's case, before a single finding
# had been filed. bootstrap-labels.sh's descriptions were measured when that
# was fixed; the ones created inline by workflows were not, which is #65.
# ---------------------------------------------------------------------------

part3 () {
  python3 - "$work_dir" <<'PY'
import ast
import glob
import pathlib
import re
import sys

sys.path.insert(0, sys.argv[1])
import wf

CAP = 100
found = []


def from_python(src, origin):
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return

    for node in ast.walk(tree):
        # ["gh", "label", "create", ..., "--description", "<literal>"]
        if isinstance(node, ast.List):
            for idx, elt in enumerate(node.elts[:-1]):
                if isinstance(elt, ast.Constant) and elt.value == "--description":
                    nxt = node.elts[idx + 1]
                    if isinstance(nxt, ast.Constant) and isinstance(nxt.value, str):
                        found.append((len(nxt.value), origin, nxt.value))

        # {"label": ("RRGGBB", "<description>")}
        if isinstance(node, ast.Dict):
            for value in node.values:
                if not (isinstance(value, ast.Tuple) and len(value.elts) == 2):
                    continue
                colour, desc = value.elts
                if (
                    isinstance(colour, ast.Constant)
                    and isinstance(desc, ast.Constant)
                    and isinstance(desc.value, str)
                    and isinstance(colour.value, str)
                    and re.fullmatch(r"[0-9A-Fa-f]{6}", colour.value)
                ):
                    found.append((len(desc.value), origin, desc.value))


for path in wf.files():
    for line, src in wf.python_steps(path):
        from_python(src, f"{path}:{line}")

for path in sorted(glob.glob(".github/scripts/*.py")):
    from_python(pathlib.Path(path).read_text(), path)

# Shell: a literal `--description "..."`, and the `ensure_label NAME COLOUR
# DESCRIPTION` helper that agent-01-planner.yml and agent-04-review.yml define.
for path in sorted(wf.files() + glob.glob(".github/scripts/*.sh")):
    text = pathlib.Path(path).read_text(errors="replace")

    for m in re.finditer(r'--description\s+"([^"$][^"]*)"', text):
        line = text[: m.start()].count("\n") + 1
        found.append((len(m.group(1)), f"{path}:{line}", m.group(1)))

    for m in re.finditer(
        r'ensure_label\s+"([^"]+)"\s+"([0-9A-Fa-f]{6})"\s*\\?\s*\n?\s*"([^"]+)"',
        text,
    ):
        line = text[: m.start()].count("\n") + 1
        found.append((len(m.group(3)), f"{path}:{line}", m.group(3)))

if not found:
    print("  FAIL — no label descriptions found; the scan has stopped working",
          file=sys.stderr)
    sys.exit(1)

over = [row for row in found if row[0] > CAP]

for length, origin, desc in over:
    print(f"  FAIL — {origin}: {length} chars, cap is {CAP}\n         {desc}",
          file=sys.stderr)

if not over:
    longest = max(found)
    print(f"  ok   — {len(found)} label description(s) within {CAP};"
          f" longest is {longest[0]} ({longest[1]})")

sys.exit(1 if over else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 4: marker reads are classified (#69).
#
# A marker searched anywhere in a comment body matches a comment that merely
# QUOTES it. agent-06-triage.yml's already-triaged gate did exactly that: its
# own failure comment quoted the marker, so every retry skipped itself as
# already done. issue-linking.yml documents the same trap for the
# no-originating-issue marker.
#
# Whether a substring read is a defect depends on what a false positive costs,
# and that is a judgment, not something a regex can decide. So this part does
# not try to. It pins the INVENTORY: every marker read in the control plane is
# listed below with its verdict, and a read that is not listed fails the check
# until somebody classifies it. That is what makes the #69 audit durable
# instead of a thing someone did once.
# ---------------------------------------------------------------------------

part4 () {
  python3 - "$work_dir" <<'PY'
import pathlib
import re
import sys

sys.path.insert(0, sys.argv[1])
import wf

# path -> {marker: verdict}. A verdict is either "anchored" (matched against a
# comment's first non-blank line, so a quoting comment cannot trip it) or
# "substring: <why that is safe here>".
CLASSIFIED = {
    ".github/workflows/agent-06-triage.yml": {
        "agent-triage-complete": "anchored",
        "agent-review-verdict": "anchored",
    },
    ".github/workflows/issue-linking.yml": {
        "no-originating-issue": "anchored",
        "agent-execute-no-closing-ref": (
            "substring: dedup only. A false positive suppresses a second"
            " identical request comment, which is the desired outcome anyway."
        ),
        "agent-execute-blocked": (
            "substring: dedup only, and matched with its blocker list appended"
            " so the signature is per-blocker-set rather than per-marker."
        ),
    },
    ".github/workflows/agent-01-planner.yml": {
        "automated-planner-complete": "anchored",
        "agent-execute-blocked": (
            "substring: filters agent comments out of the human-comment digest"
            " sent to the planner. A false positive drops one comment from"
            " prompt context; it changes no control flow."
        ),
        "agent-review-verdict": "substring: same digest filter.",
        "agent-planner-failed": "substring: same digest filter.",
    },
    ".github/workflows/agent-05-fix.yml": {
        "agent-fix-applied": "anchored",
        "agent-review-verdict": (
            "substring: names the marker inside a human-facing message, not a"
            " search."
        ),
    },
    ".github/actions/build-fix-request/action.yml": {
        "agent-review-verdict": "anchored",
    },
    ".github/workflows/issue-dependencies.yml": {
        # `startswith("$MARKER")` against the whole body -- the strongest form
        # of anchoring available, and stricter than the first-non-blank-line
        # match the others use.
        "issue-dependency-sync": "anchored",
    },
}

# A read, as opposed to a write. `echo "<!-- x -->"` posts one; `contains(...)`,
# `grep`, and `in body` look for one.
READ = re.compile(
    r"""(?x)
    (?: contains\s*\(\s*" <!--\s*(?P<a>[a-z-]+)\s*--> " \s*\)
      | grep\s+(?:-[a-zA-Z]+\s+)*['"]<!--\s*(?P<b>[a-z-]+)\s*-->
      | ["']<!--\s*(?P<c>[a-z-]+)\s*-->["']\s*\)?\s*in\s
      | ==\s*"<!--\s*(?P<d>[a-z-]+)\s*-->"
      | \$MARKER|\$SIGNATURE
    )
    """
)

MARKER_ASSIGN = re.compile(r'MARKER["\']?[:=]\s*["\']<!--\s*([a-z-]+)\s*-->')

failed = 0
checked = 0

for path in wf.files():
    text = pathlib.Path(path).read_text(errors="replace")

    seen = set()
    for m in READ.finditer(text):
        name = m.group("a") or m.group("b") or m.group("c") or m.group("d")
        if name:
            seen.add(name)

    # `$MARKER`/`$SIGNATURE` reads resolve through the assignment above them.
    if "$MARKER" in text or "$SIGNATURE" in text:
        seen.update(MARKER_ASSIGN.findall(text))

    if not seen:
        continue

    known = CLASSIFIED.get(path, {})

    for name in sorted(seen):
        checked += 1
        if name not in known:
            failed += 1
            print(
                f"  FAIL — {path} reads <!-- {name} --> and it is not"
                f" classified in this check. Decide whether a comment that"
                f" merely quotes the marker can trip it, anchor the read to"
                f" the comment's first non-blank line if so, then record the"
                f" verdict here.",
                file=sys.stderr,
            )

if not failed:
    print(f"  ok   — {checked} marker read(s) classified, none unreviewed")

sys.exit(1 if failed else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 5: no workflow writes scratch to the repository root (#97/#98).
#
# A file written into the checkout can be swept into a commit by a workflow
# that grows a commit step, and can collide with `git checkout` on a resumed
# branch. #84 hit both at once. $RUNNER_TEMP removes the whole class.
#
# UNCONVERTED is the work #98 has left. It is an allowlist that must only ever
# shrink: a name not on it and not in $RUNNER_TEMP fails this check, so a new
# workflow cannot reintroduce the pattern while the old ones are still being
# migrated.
# ---------------------------------------------------------------------------

part5 () {
  python3 - "$work_dir" <<'PY'
import pathlib
import re
import sys

sys.path.insert(0, sys.argv[1])
import wf

# Still written into the working tree, tracked by #98. Shrinks to nothing.
UNCONVERTED = {
    "all-changes-after-fix.txt", "blocker-comment.md", "candidates.txt",
    "changed-after-fix.txt", "changed-gd-files.txt", "closing-issues.json",
    "comment.md", "comments.json", "dashboard.md", "filed-issues.json",
    "fix-comment.md", "fix-diff.txt", "fix-validate-output.txt",
    "fix-verdict.md", "fixer-failure.json", "fixer-pr-meta.json",
    "fixer-prompt.txt", "format-validate-output.txt", "gdformat-output.txt",
    "gdlint-output.txt", "gdscript-lint-report.md", "implement-diff.txt",
    "implementer-failure.json", "implementer-prompt.txt", "issue-body.md",
    "issue.json", "lint-fix-prompt.txt", "lint-fix-validate-output.txt",
    "no-commit-comment.md", "parent.json", "plan.json", "planner-failure.json",
    "planner-prompt.txt", "pr-body-verified.md", "pr-body.md", "pr-files.txt",
    "pr-meta.json", "pr-scope.json", "pr.json", "report.json", "review.md",
    "review-comment.md", "review-diff.txt", "review-verdict-failure.json",
    "reviewer-prompt.txt", "skip-comment.md", "suggest.txt",
    "sync-comment.md", "task-blockers.json", "task.json", "tasks.txt",
    "triage-drafts.json", "triage-failure.json", "triage-items.json",
    "triage-prompt.txt", "untracked-after-fix.txt", "update-pr.json",
    "valid-tasks.txt", "validate-output.txt", "validation-failed-comment.md",
    "verified-validate-output.txt",
}

# `> name.ext`, `--out name.ext`, `--body-file name.ext`, Path("name.ext").
WRITES = [
    re.compile(r">\s*([A-Za-z0-9][A-Za-z0-9._-]*\.(?:md|txt|json|jsonl))\b"),
    re.compile(
        r"(?:--out|--body-file|--input|--jsonl|--json|--stderr)\s+"
        r"([A-Za-z0-9][A-Za-z0-9._-]*\.(?:md|txt|json|jsonl))\b"
    ),
    re.compile(r'Path\(\s*"([A-Za-z0-9][A-Za-z0-9._-]*\.(?:md|txt|json|jsonl))"\s*\)'),
]

offenders = []
still = set()

for path in wf.files():
    text = pathlib.Path(path).read_text(errors="replace")

    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue

        for pattern in WRITES:
            for m in pattern.finditer(line):
                name = m.group(1)
                if name in UNCONVERTED:
                    still.add(name)
                else:
                    offenders.append((path, line_no, name, stripped[:88]))

for path, line_no, name, snippet in offenders:
    print(
        f"  FAIL — {path}:{line_no} writes {name} into the working tree."
        f"\n         Write it under $RUNNER_TEMP instead.\n         {snippet}",
        file=sys.stderr,
    )

if not offenders:
    left = len(still)
    print(f"  ok   — no new working-tree scratch; {left} name(s) still"
          f" awaiting the #98 conversion")

sys.exit(1 if offenders else 0)
PY
}

echo "Checking logic embedded in workflow YAML"

run_part "Part 1: embedded programs parse" part1
run_part "Part 1b: embedded jq parses" part1_jq
run_part "Part 2: triage finding parser (#115)" part2
run_part "Part 3: label description cap (#65)" part3
run_part "Part 4: marker reads are classified (#69)" part4
run_part "Part 5: scratch stays out of the tree (#97/#98)" part5

echo
if [ "$failures" -eq 0 ]; then
  echo "All workflow logic checks passed."
else
  echo "$failures check(s) failed." >&2
fi

exit $((failures > 0))

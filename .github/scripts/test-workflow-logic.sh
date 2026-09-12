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
#   Part 6  A role is written down on three surfaces with nothing linking
#           them; one that goes missing on a surface fails silently, the way
#           an unbootstrapped label does.
#   Part 7  The Godot version is pinned in several places that must move
#           together, and VERSION.md wrongly claimed one default covered
#           them all. A half-done bump would pass CI on the stale half.
#   Part 8  #227 -- `human-credentials` was bootstrapped with two different
#           descriptions in two files, and the label itself was only ever
#           applied once, at Issue creation; editing the expected-files
#           section afterwards, or hand-writing a [task] Issue, left it
#           wrong or missing with nothing to notice.
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

# The steps under test read $RUNNER_TEMP, which Actions always sets and a
# developer's shell does not. Supplied here so running this by hand exercises
# the same code path CI does, rather than a KeyError.
export RUNNER_TEMP="${RUNNER_TEMP:-$work_dir}"

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
import re
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
            continue

        # Compiling proves nothing about names resolved at runtime, and
        # SCRATCH is the one every step introduced by #98 depends on. A step
        # that uses it without defining it raises NameError on the runner --
        # for a failure reporter, on the day something else already went
        # wrong. Each step is its own program, so the definition has to be
        # in the same step, not merely somewhere in the file.
        if "SCRATCH" in src and not re.search(r"^\s*SCRATCH\s*=", src, re.M):
            failed += 1
            print(f"  FAIL — {path}:{line} uses SCRATCH without defining it."
                  f' Add SCRATCH = pathlib.Path(os.environ["RUNNER_TEMP"])'
                  f" to this step.", file=sys.stderr)

if not failed:
    print(f"  ok   — {count} embedded python step(s) compile and resolve"
          f" SCRATCH")

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
import re
import sys

sys.path.insert(0, sys.argv[1])
sys.path.insert(0, os.path.join(sys.argv[2], ".github", "scripts"))
import wf

TRIAGE = ".github/workflows/agent-06-triage.yml"

src = wf.step_source(TRIAGE, "Gather Findings")

# Everything up to `def findings(` is the matching path: the guards, is_empty()
# and bullets(). Past it the step reads pr.json and GITHUB_OUTPUT.
src = src[: src.index("def findings(")]
# Stub the one filesystem read, however it is currently spelled -- this
# line moved from pathlib.Path("pr.json") to (SCRATCH / "pr.json") during
# the #98 conversion, and pinning the old spelling turned that into a
# confusing traceback rather than a clear failure.
src = re.sub(r"^pr = json\.loads\(.*\)$", "pr = {}", src, count=1, flags=re.M)

if "pr = {}" not in src:
    print("  FAIL — could not stub the pr.json read; has the step changed?",
          file=sys.stderr)
    sys.exit(1)

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
# #98 is done: every scratch write in the control plane goes to $RUNNER_TEMP.
# UNCONVERTED is therefore EMPTY, and this check is absolute -- any scratch
# written into the checkout fails. It is kept as an empty set rather than
# deleted so that a future migration has the same shrinking-allowlist shape to
# use, and so the emptiness is visibly deliberate rather than an oversight.
# ---------------------------------------------------------------------------

part5 () {
  python3 - "$work_dir" <<'PY'
import pathlib
import re
import sys

sys.path.insert(0, sys.argv[1])
import wf

# Still written into the working tree, tracked by #98. Shrinks to nothing.
UNCONVERTED = set()

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

# Half-converted is worse than unconverted: the write moves, the read does
# not, and the step fails at runtime on a file that is simply not there.
# Within one file a name is either always under $RUNNER_TEMP or never.
mixed = []

for path in wf.files():
    text = pathlib.Path(path).read_text(errors="replace")
    body = "\n".join(
        line for line in text.splitlines() if not line.strip().startswith("#")
    )

    for name in sorted(set(re.findall(
        r"([A-Za-z0-9][A-Za-z0-9._-]*\.(?:md|txt|json|jsonl))", body
    ))):
        if name.endswith((".yml", ".yaml")) or name in {"action.yml"}:
            continue

        # A leading boundary on BOTH counts. Without it `pr-meta.json`
        # matches inside `fixer-pr-meta.json` and `validate-output.txt`
        # inside `format-validate-output.txt`, so a fully converted file
        # reports as half converted -- the longer name's occurrences count
        # towards the shorter name's total but never towards its prefixed
        # tally, because the prefix does not sit immediately before it.
        boundary = r"(?<![A-Za-z0-9._-])"

        prefixed = len(re.findall(
            r"(?:\$RUNNER_TEMP\b[\"']?/"
            r"|runner\.temp \}\}/"
            r"|SCRATCH / \""
            r"|SCRATCH\.joinpath\(\""
            r"|RUNNER_TEMP\"\], \")"
            + re.escape(name),
            body,
        ))
        total = len(re.findall(boundary + re.escape(name), body))

        if prefixed and prefixed != total:
            mixed.append((path, name, prefixed, total))

for path, name, prefixed, total in mixed:
    print(
        f"  FAIL — {path} uses {name} both under $RUNNER_TEMP and bare"
        f" ({prefixed} of {total} occurrences prefixed). A moved write with"
        f" an unmoved read fails at runtime on a missing file.",
        file=sys.stderr,
    )

if not offenders and not mixed:
    left = len(still)
    print(f"  ok   — no working-tree scratch, no half-converted name"
          f" ({left} unconverted names allowed)")

sys.exit(1 if (offenders or mixed) else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 6: the agent roles stay in parity across their three surfaces.
#
# A role is written down three times -- a cloud profile in `.github/agents/`,
# a local counterpart in `.claude/agents/`, and a slash command in
# `.claude/commands/` that invokes it. Nothing links them but discipline, and
# a role that exists on one surface and not another fails the way a missing
# label does: the trigger simply never fires, and nothing says why.
#
# `AGENTS.md` promises the two agent directories are counterparts, and
# `AGENT_ROLE_DESIGN.md` sets the test a new role must pass. Neither is
# checkable prose. This part makes the pairing itself checkable.
#
# The reviewer's tool list is checked separately and by name: "read-only
# against code -- never edits files" is an architectural claim the file makes
# about itself, and the only thing enforcing it is the absence of two strings.
# ---------------------------------------------------------------------------

part6 () {
  python3 - <<'PY'
import pathlib
import re
import sys

failures = []


def frontmatter(path):
    """Return the YAML frontmatter block of a markdown file as raw lines.

    Deliberately not a YAML parse: pyyaml is not guaranteed on a bare runner,
    and every field checked here is a flat `key: value` on one line.
    """
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    return text[4:end].splitlines()


def field(lines, key):
    for line in lines or []:
        m = re.match(rf"{re.escape(key)}:\s*(.*)$", line)
        if m:
            return m.group(1).strip()
    return None


def check_frontmatter(path, required):
    lines = frontmatter(path)
    if lines is None:
        failures.append(f"{path}: no YAML frontmatter block")
        return None
    for key in required:
        if field(lines, key) in (None, ""):
            failures.append(f"{path}: frontmatter missing `{key}:`")
    return lines


# --- The cloud profiles ----------------------------------------------------
cloud = {}
for path in sorted(pathlib.Path(".github/agents").glob("*.agent.md")):
    lines = check_frontmatter(path, ["name", "description", "model", "tools"])
    name = field(lines, "name")
    if not name:
        continue
    # `NN-<role>.agent.md`. The number tracks the workflow, not the role, so
    # gaps in it are fine; the suffix after it must be the declared name.
    stem = path.name[: -len(".agent.md")]
    slug = stem.split("-", 1)[1] if "-" in stem else stem
    if slug != name:
        failures.append(f"{path}: filename says `{slug}`, frontmatter says `{name}`")
    if name in cloud:
        failures.append(f"{path}: duplicate role name `{name}` (also {cloud[name]})")
    cloud[name] = path

# --- The local counterparts ------------------------------------------------
local = {}
for path in sorted(pathlib.Path(".claude/agents").glob("*.md")):
    lines = check_frontmatter(path, ["name", "description", "tools", "model"])
    name = field(lines, "name")
    if not name:
        continue
    if path.stem != name:
        failures.append(f"{path}: filename says `{path.stem}`, frontmatter says `{name}`")
    local[name] = path

# --- Parity ----------------------------------------------------------------
for name in sorted(set(cloud) - set(local)):
    failures.append(
        f"role `{name}` has a cloud profile ({cloud[name]}) but no"
        f" local counterpart at .claude/agents/{name}.md"
    )
for name in sorted(set(local) - set(cloud)):
    failures.append(
        f"role `{name}` has a local agent ({local[name]}) but no"
        f" cloud profile in .github/agents/"
    )

# --- Every role is reachable from a slash command --------------------------
for name in sorted(local):
    command = pathlib.Path(f".claude/commands/{name}.md")
    if not command.exists():
        failures.append(f"role `{name}` has no slash command at {command}")

for path in sorted(pathlib.Path(".claude/commands").glob("*.md")):
    check_frontmatter(path, ["description", "argument-hint"])

# --- The reviewer holds no writing tool ------------------------------------
# Stated in .claude/agents/reviewer.md, in AGENTS.md's role split, and in
# AGENT_ROLE_DESIGN.md's tool-boundary test. Enforced by nothing else.
reviewer = local.get("reviewer")
if reviewer is None:
    failures.append("no reviewer role found -- the read-only check cannot run")
else:
    tools = field(frontmatter(reviewer), "tools") or ""
    granted = {t.strip() for t in tools.split(",")}
    for forbidden in ("Edit", "Write", "NotebookEdit"):
        if forbidden in granted:
            failures.append(
                f"{reviewer}: reviewer has the `{forbidden}` tool."
                f" The role is read-only against code by design."
            )

if failures:
    for line in failures:
        print(f"  FAIL — {line}", file=sys.stderr)
    sys.exit(1)

print(
    f"  ok   — {len(cloud)} role(s) paired across .github/agents,"
    f" .claude/agents and .claude/commands; reviewer holds no write tool"
)
sys.exit(0)
PY
}

# ---------------------------------------------------------------------------
# Part 7: every Godot version pin agrees.
#
# The engine version is named in more places than one, and they have to move
# together. `setup-godot`'s input default is the canonical one; a workflow may
# also pass `godot-version:` explicitly, and `godot-validation.yml` declares
# its own input default that it forwards. `project.godot`'s
# `config/features` carries the same version as major.minor, and the test
# bootstrap enforces it as a floor at runtime.
#
# Nothing linked them. `docs/engine-reference/godot/VERSION.md` claimed that
# "every call site passes the default, so changing the default changes CI
# everywhere at once", and that was simply false -- three workflows pinned
# 4.7.1-stable explicitly, so bumping the default alone would have left them
# behind, silently and greenly. This part is the check that claim needed.
#
# Local and textual on purpose: it asks whether the pins agree with each
# other, never whether they are current. "Is there a newer Godot" needs the
# network and a judgement about whether upgrading is wise, which is the
# `/godot-upgrade` command's job, not a test's.
# ---------------------------------------------------------------------------

part7 () {
  python3 - <<'PY'
import pathlib
import re
import sys

failures = []

CANONICAL = pathlib.Path(".github/actions/setup-godot/action.yml")

# --- The canonical pin -----------------------------------------------------
# `default:` in setup-godot's `godot-version` input. Matched inside that
# input's block rather than anywhere in the file, so an unrelated input
# gaining a default does not silently become the version of record.
text = CANONICAL.read_text(encoding="utf-8")
block = re.search(
    r"^  godot-version:\n((?:    [^\n]*\n|[ \t]*\n)*)", text, re.MULTILINE
)
canonical = None
if block:
    m = re.search(r"^    default:\s*(\S+)\s*$", block.group(1), re.MULTILINE)
    if m:
        canonical = m.group(1).strip('"\'')

if canonical is None:
    print(f"  FAIL — no godot-version default found in {CANONICAL}", file=sys.stderr)
    sys.exit(1)

# --- Every other place a full release tag is written -----------------------
# `godot-version: <literal>` call sites, plus any `default:` under a
# `godot-version:` input in a workflow. An expression (${{ ... }}) forwards
# something else and is not a pin.
sites = []
for path in sorted(
    list(pathlib.Path(".github/workflows").glob("*.yml"))
    + list(pathlib.Path(".github/actions").glob("*/action.yml"))
):
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r"\s*godot-version:\s*(\S.*?)\s*$", line)
        if m and "${{" not in m.group(1):
            value = m.group(1).strip('"\'')
            if value and not value.endswith(":"):
                sites.append((path, n, value))

    # A `godot-version:` input block with its own default, e.g. the
    # reusable godot-validation.yml workflow.
    body = path.read_text(encoding="utf-8")
    # `[ \t]*`, never `\s*`: in MULTILINE, `\s` matches the newline before the
    # line too, so `^(\s*)` captures "\n      " and the `\1  ` backreference
    # then cannot match a plain indented line. The block matched empty and
    # godot-validation.yml's own input default -- the one site class this part
    # exists for -- was skipped in silence.
    for blk in re.finditer(
        r"^([ \t]*)godot-version:[ \t]*\n((?:\1[ \t]+[^\n]*\n|[ \t]*\n)*)",
        body,
        re.MULTILINE,
    ):
        m = re.search(r"^\s*default:\s*(\S+)\s*$", blk.group(2), re.MULTILINE)
        if m:
            value = m.group(1).strip('"\'')
            line_no = body[: blk.start()].count("\n") + 1
            if path != CANONICAL:
                sites.append((path, line_no, value))

for path, line_no, value in sites:
    if value != canonical:
        failures.append(
            f"{path}:{line_no} pins Godot {value}, but"
            f" {CANONICAL} defaults to {canonical}"
        )

# --- project.godot carries the same major.minor ----------------------------
# `config/features` is the version floor the test bootstrap enforces at
# runtime, so a mismatch here is a real disagreement about which engine this
# project targets -- not merely untidy.
project = pathlib.Path("project.godot")
m = re.search(
    r'config/features\s*=\s*PackedStringArray\((.*?)\)',
    project.read_text(encoding="utf-8"),
)
if not m:
    failures.append("project.godot: no config/features=PackedStringArray(...) found")
else:
    declared = re.findall(r'"([^"]+)"', m.group(1))
    versions = [v for v in declared if re.fullmatch(r"\d+\.\d+", v)]
    expected = ".".join(canonical.split("-")[0].split(".")[:2])
    if not versions:
        failures.append(
            f"project.godot: config/features declares no major.minor version"
            f" (found {declared!r}); expected {expected}"
        )
    elif expected not in versions:
        failures.append(
            f"project.godot: config/features declares {versions!r},"
            f" but the CI pin is {canonical} (expected {expected})"
        )

# --- VERSION.md records the pin it documents -------------------------------
# The engine reference exists to be trusted, so a stale pin in it is worse
# than none. Checked loosely: the tag must appear somewhere in the file.
version_md = pathlib.Path("docs/engine-reference/godot/VERSION.md")
if not version_md.exists():
    failures.append(f"{version_md} is missing -- the engine reference documents the pin")
elif canonical not in version_md.read_text(encoding="utf-8"):
    failures.append(f"{version_md} does not mention the current pin {canonical}")

if failures:
    for line in failures:
        print(f"  FAIL — {line}", file=sys.stderr)
    sys.exit(1)

print(
    f"  ok   — Godot {canonical} agreed across {len(sites) + 1} CI pin(s),"
    f" project.godot and VERSION.md"
)
sys.exit(0)
PY
}

# ---------------------------------------------------------------------------
# Part 8: `human-credentials` label derivation (#227).
#
# `sync-human-credentials-label.py` is the repair for the label's coverage gaps:
# it derives from `task_scope.py` -- never re-implementing the section or
# path parsing -- and adds or removes the label to match. Run against a stub
# `gh`, python3 only, no network, no credentials, no real repository, the
# same posture `test-issue-dependencies.sh`'s Part 2 uses for its own
# stub-`gh` driver.
# ---------------------------------------------------------------------------

part8 () {
  local part_dir bad
  part_dir="$(mktemp -d "$work_dir/part8.XXXXXX")"
  mkdir -p "$part_dir/bin"
  bad=0

  cat > "$part_dir/bin/gh" <<'STUB'
#!/usr/bin/env python3
"""Stub `gh`, covering only the calls sync-human-credentials-label.py makes.

State is a JSON file so the driver's own idempotence can be tested across
runs. Every invocation is also appended to $GH_STUB_LOG, one line per call,
so a test can assert *which* calls were made -- not just their effect --
without inventing a second state machine to track it.
"""
import json
import os
import pathlib
import sys

state_path = pathlib.Path(os.environ["GH_STUB_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]

log_path = os.environ.get("GH_STUB_LOG")
if log_path:
    with open(log_path, "a") as handle:
        handle.write(" ".join(args) + "\n")


def emit(obj):
    print(json.dumps(obj))


def save():
    state_path.write_text(json.dumps(state))


if args[:2] == ["label", "list"]:
    if "--jq" in args:
        print("\n".join(state["labels"]))
    else:
        emit([{"name": name} for name in state["labels"]])

elif args[:2] == ["label", "create"]:
    name = args[2]
    if name not in state["labels"]:
        state["labels"].append(name)
    save()

elif args[:2] == ["issue", "list"]:
    fields = args[args.index("--json") + 1].split(",")
    rows = []
    for number, issue in sorted(state["issues"].items(), key=lambda kv: int(kv[0])):
        row = {}
        for field in fields:
            if field == "number":
                row["number"] = int(number)
            elif field == "labels":
                row["labels"] = [{"name": n} for n in issue.get("labels", [])]
            else:
                row[field] = issue.get(field, "")
        rows.append(row)
    emit(rows)

elif args[:2] == ["issue", "edit"]:
    number = args[2]
    op = label = None
    if "--add-label" in args:
        op, label = "add", args[args.index("--add-label") + 1]
    elif "--remove-label" in args:
        op, label = "remove", args[args.index("--remove-label") + 1]

    if f"{op}:{number}" in state.get("fail_ops", []):
        print(f"gh: could not edit issue #{number} (stubbed failure)",
              file=sys.stderr)
        sys.exit(1)

    labels = state["issues"][number].setdefault("labels", [])
    if op == "add" and label not in labels:
        labels.append(label)
    elif op == "remove" and label in labels:
        labels.remove(label)
    save()

elif args[0] == "api":
    path = args[1]
    number = path.split("/issues/")[1].split("/")[0].split("?")[0]
    if number not in state["issues"]:
        print("gh: Not Found (HTTP 404)", file=sys.stderr)
        sys.exit(1)
    issue = dict(state["issues"][number])
    issue["number"] = int(number)
    issue["labels"] = [{"name": n} for n in issue.get("labels", [])]
    emit(issue)

else:
    print("stub gh: unhandled call: " + " ".join(args), file=sys.stderr)
    sys.exit(2)
STUB
  chmod +x "$part_dir/bin/gh"

  pass() { echo "  ok   — $1"; }
  fail() { echo "  FAIL — $1" >&2; bad=$((bad + 1)); }

  write_state () {
    cat > "$1" <<'JSON'
{
  "labels": ["implementation", "machine"],
  "fail_ops": ["add:30"],
  "issues": {
    "12": {"body": "## Files or Subsystems Expected to Change\n\n- `.github/workflows/foo.yml`\n", "labels": []},
    "13": {"body": "## Files or Subsystems Expected to Change\n\n- .github/actions/bar/action.yml\n", "labels": []},
    "14": {"body": "## Files or Subsystems Expected to Change\n\n- `.github/workflows/foo.yml`\n", "labels": ["human-credentials"]},
    "15": {"body": "## Files or Subsystems Expected to Change\n\n- rules/foo.gd\n", "labels": ["human-credentials"]},
    "16": {"body": "## Scope\n\nA body written by hand against no template.\n", "labels": []},
    "17": {"body": "## Scope\n\nA body written by hand against no template.\n", "labels": ["human-credentials"]},
    "18": {"body": "## Files or Subsystems Expected to Change\n\n<!-- `.github/workflows/example.yml` -->\n", "labels": []},
    "19": {"body": "## Files or Subsystems Expected to Change\n\n<!-- `.github/workflows/example.yml` -->\n", "labels": ["human-credentials"]},
    "20": {"body": "## Files or Subsystems Expected to Change\n\n- rules/foo.gd\n", "labels": []},
    "30": {"body": "## Files or Subsystems Expected to Change\n\n- `.github/workflows/foo.yml`\n", "labels": []}
  }
}
JSON
  }

  run_label_sync () {
    local state="$1"
    shift
    : > "$part_dir/calls.log"
    GH_STUB_STATE="$state" GH_STUB_LOG="$part_dir/calls.log" \
      PATH="$part_dir/bin:$PATH" \
      "$repo_root/.github/scripts/sync-human-credentials-label.py" --repo o/r "$@"
  }

  label_of () {
    python3 -c "
import json, sys
state = json.load(open(sys.argv[1]))
print('human-credentials' in state['issues'][sys.argv[2]].get('labels', []))
" "$1" "$2"
  }

  # -- row 1: restricted, unlabelled -> add. Backticked path. ----------------
  write_state "$part_dir/s.json"
  out="$(run_label_sync "$part_dir/s.json" --issue 12)"
  if grep -q '#12 -- restricted: .github/workflows/foo.yml' <<<"$out" \
     && grep -q '^\*\*Added\*\*$' <<<"$out"; then
    pass "backticked restricted path adds the label (#12)"
  else
    fail "expected #12 added for a backticked restricted path; got:\n$out"
  fi
  if [ "$(label_of "$part_dir/s.json" 12)" = "True" ]; then
    pass "#12 carries the label after the add"
  else
    fail "#12 should carry human-credentials after the add"
  fi
  if grep -q 'issue edit 12 .*--add-label human-credentials' "$part_dir/calls.log"; then
    pass "exactly one add call was made for #12"
  else
    fail "expected an --add-label call for #12; log:\n$(cat "$part_dir/calls.log")"
  fi

  second="$(run_label_sync "$part_dir/s.json" --issue 12)"
  if grep -q '^\*\*Unchanged\*\*$' <<<"$second" \
     && ! grep -q 'issue edit' "$part_dir/calls.log"; then
    pass "re-running #12 makes no write call"
  else
    fail "second run over #12 should be a no-op; got:\n$second"
  fi

  # -- row 1: restricted, unlabelled -> add. Bare bullet path. ----------------
  write_state "$part_dir/s.json"
  out="$(run_label_sync "$part_dir/s.json" --issue 13)"
  if [ "$(label_of "$part_dir/s.json" 13)" = "True" ]; then
    pass "a bare bullet restricted path also adds the label (#13)"
  else
    fail "expected #13 (bare bullet path) to be labelled; got:\n$out"
  fi

  # -- row 2: restricted, already labelled -> none. ---------------------------
  write_state "$part_dir/s.json"
  out="$(run_label_sync "$part_dir/s.json" --issue 14)"
  if grep -q '^\*\*Unchanged\*\*$' <<<"$out" \
     && ! grep -q 'issue edit' "$part_dir/calls.log"; then
    pass "#14 (restricted, already labelled) makes no write call"
  else
    fail "expected #14 unchanged; got:\n$out"
  fi

  # -- row 3: no restricted paths, section had paths, labelled -> remove. ----
  write_state "$part_dir/s.json"
  out="$(run_label_sync "$part_dir/s.json" --issue 15)"
  if grep -q '#15 -- no-restricted-paths' <<<"$out" \
     && grep -q '^\*\*Removed\*\*$' <<<"$out" \
     && grep -q 'issue edit 15 .*--remove-label human-credentials' "$part_dir/calls.log"; then
    pass "#15 loses the label once its section no longer names a restricted path"
  else
    fail "expected #15 removed with reason no-restricted-paths; got:\n$out"
  fi
  if [ "$(label_of "$part_dir/s.json" 15)" = "False" ]; then
    pass "#15 no longer carries the label"
  else
    fail "#15 should have lost human-credentials"
  fi

  # -- row 4: no restricted paths, section had paths, unlabelled -> none. -----
  write_state "$part_dir/s.json"
  out="$(run_label_sync "$part_dir/s.json" --issue 20)"
  if grep -q '#20 -- no-restricted-paths' <<<"$out" \
     && grep -q '^\*\*Unchanged\*\*$' <<<"$out"; then
    pass "#20 (unrestricted paths, unlabelled) stays unchanged"
  else
    fail "expected #20 unchanged with reason no-restricted-paths; got:\n$out"
  fi

  # -- row 5/6: no `## Files or Subsystems Expected to Change` section. ------
  write_state "$part_dir/s.json"
  out16="$(run_label_sync "$part_dir/s.json" --issue 16)"
  out17="$(run_label_sync "$part_dir/s.json" --issue 17)"
  if grep -q '#16 -- no-section' <<<"$out16" && grep -q '^\*\*Unchanged\*\*$' <<<"$out16"; then
    pass "#16 with no expected-files section stays unchanged (no-section)"
  else
    fail "expected #16 unchanged with reason no-section; got:\n$out16"
  fi
  if grep -q '#17 -- no-section' <<<"$out17" && grep -q '^\*\*Removed\*\*$' <<<"$out17"; then
    pass "#17 with no expected-files section loses the label (no-section)"
  else
    fail "expected #17 removed with reason no-section; got:\n$out17"
  fi

  # -- row 7/8: section present but empty or unparseable. --------------------
  write_state "$part_dir/s.json"
  out18="$(run_label_sync "$part_dir/s.json" --issue 18)"
  out19="$(run_label_sync "$part_dir/s.json" --issue 19)"
  if grep -q '#18 -- no-paths' <<<"$out18" && grep -q '^\*\*Unchanged\*\*$' <<<"$out18"; then
    pass "#18 with an empty expected-files section stays unchanged (no-paths)"
  else
    fail "expected #18 unchanged with reason no-paths; got:\n$out18"
  fi
  if grep -q '#19 -- no-paths' <<<"$out19" && grep -q '^\*\*Removed\*\*$' <<<"$out19"; then
    pass "#19 with an empty expected-files section loses the label (no-paths)"
  else
    fail "expected #19 removed with reason no-paths; got:\n$out19"
  fi

  # -- a failing write exits non-zero and names the Issue and the operation. -
  write_state "$part_dir/s.json"
  if run_label_sync "$part_dir/s.json" --issue 30 > "$part_dir/failing.out" 2>&1; then
    fail "a refused label write must exit non-zero"
  else
    if grep -q '#30' "$part_dir/failing.out" && grep -qi 'add' "$part_dir/failing.out"; then
      pass "a refused add exits non-zero and names #30 and the add operation"
    else
      fail "expected a failure naming #30's add; got:\n$(cat "$part_dir/failing.out")"
    fi
  fi
  if [ "$(label_of "$part_dir/s.json" 30)" = "False" ]; then
    pass "#30 was not reported as succeeded; no label was written"
  else
    fail "#30 should not carry the label after a failed write"
  fi

  # -- --dry-run decides and reports, and writes nothing. ---------------------
  write_state "$part_dir/s.json"
  before="$(cat "$part_dir/s.json")"
  out="$(run_label_sync "$part_dir/s.json" --issue 12 --dry-run)"
  if grep -q '#12 -- restricted' <<<"$out" \
     && [ "$before" = "$(cat "$part_dir/s.json")" ] \
     && ! grep -q 'issue edit' "$part_dir/calls.log"; then
    pass "--dry-run prints the decision and writes nothing"
  else
    fail "--dry-run should report #12 and change nothing; got:\n$out"
  fi

  # -- --json carries number, action, reason, restricted_paths, and markdown. -
  write_state "$part_dir/s.json"
  json_out="$(run_label_sync "$part_dir/s.json" --issue 12 --json)"
  if python3 -c "
import json, sys
report = json.loads(sys.argv[1])
entry = report['decisions'][0]
assert entry['number'] == 12
assert entry['action'] == 'add'
assert entry['reason'] == 'restricted'
assert entry['restricted_paths'] == ['.github/workflows/foo.yml']
assert 'markdown' in report and isinstance(report['markdown'], str)
" "$json_out"; then
    pass "--json reports number, action, reason, restricted_paths and markdown"
  else
    fail "--json report missing an expected field; got:\n$json_out"
  fi

  # -- --sweep asks for open Issues with an explicit, adequate page size. -----
  write_state "$part_dir/s.json"
  run_label_sync "$part_dir/s.json" --sweep > /dev/null
  if python3 -c "
import re, sys
for line in open(sys.argv[1]):
    if line.startswith('issue list'):
        m = re.search(r'--limit (\d+)', line)
        assert m, f'no --limit in: {line}'
        assert int(m.group(1)) >= 30, f'page size too small: {line}'
        sys.exit(0)
sys.exit('no issue list call was made')
" "$part_dir/calls.log"; then
    pass "--sweep requests open Issues with an explicit page size >= 30"
  else
    fail "sweep did not request an adequate, explicit page size"
  fi

  # -- a full page is refused rather than silently truncating the sweep. -----
  write_state "$part_dir/s.json"
  if GH_STUB_STATE="$part_dir/s.json" GH_STUB_LOG="$part_dir/calls.log" \
     PATH="$part_dir/bin:$PATH" python3 -c "
import importlib.util
import sys

spec = importlib.util.spec_from_file_location(
    'sync_human_credentials_label',
    '$repo_root/.github/scripts/sync-human-credentials-label.py',
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# The stub holds ten Issues; a page of two makes the first page full, which
# is the condition a real sweep hits once the backlog outgrows PAGE_SIZE.
module.PAGE_SIZE = 2
repo = module.Repository('o/r')

try:
    repo.load_open_issues()
except module.GhError as error:
    assert 'incomplete' in str(error), error
    sys.exit(0)

sys.exit('a full page was accepted; the sweep would have silently truncated')
"; then
    pass "a full page fails the sweep instead of silently truncating it"
  else
    fail "sweep accepted a full page and would report an incomplete run as success"
  fi

  # -- the script's derivation cannot drift from task_scope.evaluate(). -------
  if python3 -c "
import importlib.util
import sys

sys.path.insert(0, '$repo_root/.github/scripts')
import task_scope

spec = importlib.util.spec_from_file_location(
    'sync_human_credentials_label',
    '$repo_root/.github/scripts/sync-human-credentials-label.py',
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

BODIES = [
    '## Files or Subsystems Expected to Change\n\n- \`.github/workflows/x.yml\`\n',
    '## Files or Subsystems Expected to Change\n\n- .github/actions/y/action.yml\n',
    '## Files or Subsystems Expected to Change\n\n- rules/foo.gd\n',
    '## Scope\n\nNo expected-files section at all.\n',
    '## Files or Subsystems Expected to Change\n\n<!-- \`.github/workflows/z.yml\` -->\n',
]

for body in BODIES:
    decision = module.decide(body, has_label=False)
    scope = task_scope.evaluate(body)
    derived_restricted = bool(decision['restricted_paths'])
    planner_restricted = not scope['implementer_eligible']
    assert derived_restricted == planner_restricted, (body, decision, scope)
"; then
    pass "derivation matches task_scope.evaluate()'s implementer_eligible on every case"
  else
    fail "the script's derivation drifted from task_scope.evaluate()"
  fi

  return $((bad > 0))
}

echo "Checking logic embedded in workflow YAML"

run_part "Part 1: embedded programs parse" part1
run_part "Part 1b: embedded jq parses" part1_jq
run_part "Part 2: triage finding parser (#115)" part2
run_part "Part 3: label description cap (#65)" part3
run_part "Part 4: marker reads are classified (#69)" part4
run_part "Part 5: scratch stays out of the tree (#97/#98)" part5
run_part "Part 6: agent roles stay in parity" part6
run_part "Part 7: Godot version pins agree" part7
run_part "Part 8: human-credentials label derivation (#227)" part8

echo
if [ "$failures" -eq 0 ]; then
  echo "All workflow logic checks passed."
else
  echo "$failures check(s) failed." >&2
fi

exit $((failures > 0))

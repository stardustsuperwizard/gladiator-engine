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
#           an unbootstrapped label does. #72 -- the planner's contract
#           required it to post a plan comment, but its `tools:` line never
#           granted `mcp__github__add_issue_comment`, so the cloud surface
#           had no route to a step its own Procedure required.
#   Part 7  The Godot version is pinned in several places that must move
#           together, and VERSION.md wrongly claimed one default covered
#           them all. A half-done bump would pass CI on the stale half.
#   Part 8  #227 -- `human-credentials` was bootstrapped with two different
#           descriptions in two files, and the label itself was only ever
#           applied once, at Issue creation; editing the expected-files
#           section afterwards, or hand-writing a [task] Issue, left it
#           wrong or missing with nothing to notice.
#   Part 9  A `workflow_dispatch` input declared `type: number` reaches a
#           step's shell as a *float* -- #217 arrives as `217.0`. Every
#           single-Issue dispatch of issue-local-session.yml failed on it,
#           and the acceptance criterion covering that path had been ticked
#           from reading the YAML, where it looks right.
#   Part 10 #226/#227 -- a plan invented a second label for a fact the tree
#           already carried, and a retargeted task went on naming a script
#           that had been renamed. Both are review findings a machine can
#           assemble the evidence for, and both are now fixtures, so the
#           assembler that gathers that evidence cannot quietly stop.
#   Part 11 One gate now parses two verdict vocabularies. A `plan` mode that
#           quietly accepted a pull request verdict -- or a `pr` mode that
#           accepted a plan one -- would publish a label answering a
#           question nobody asked, and a truncation gate relaxed for the
#           newer mode would publish a verdict whose reasoning was cut off.
#   Part 16 A smoke stage is worth exactly its verdict. One that passed a
#           build which exited 0 having played nothing -- or that waited on a
#           hung child instead of killing it -- would be a green check and a
#           held runner, and both look fine in the YAML.
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


# Shared harness functions for Part 13 and Part 24 to avoid duplication
class TestHarness:
    """Shared test harness for extracting and running workflow steps."""

    def __init__(self, part_dir):
        import os
        import subprocess
        self.part_dir = pathlib.Path(part_dir)
        self.bin_dir = self.part_dir / "bin"
        self.bin_dir.mkdir(exist_ok=True)
        self.gh_stub = self.bin_dir / "gh"
        # Create a simple gh stub that outputs file contents
        self.gh_stub.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\ncat \"$GH_STUB_FILES\"\n",
            encoding="utf-8",
        )
        self.gh_stub.chmod(0o755)

    def run_step(self, step_script, env_overrides, cwd):
        """Run an extracted workflow step in its own scratch environment."""
        import os
        import subprocess
        import tempfile

        case = pathlib.Path(tempfile.mkdtemp(dir=self.part_dir))
        output_file = case / "github_output"
        output_file.write_text("", encoding="utf-8")

        env = dict(os.environ)
        env.update({"RUNNER_TEMP": str(case), "GITHUB_OUTPUT": str(output_file)})
        env.update(env_overrides)

        result = subprocess.run(
            ["bash", str(step_script)],
            capture_output=True,
            text=True,
            cwd=str(cwd),
            env=env,
        )
        outputs = dict(
            line.split("=", 1)
            for line in output_file.read_text().splitlines()
            if "=" in line
        )
        return result, outputs

    def run_pull_request(self, step_script, files, cwd):
        """Run a step as if it were triggered by a pull_request event."""
        import os
        import tempfile
        case = pathlib.Path(tempfile.mkdtemp(dir=self.part_dir))
        files_path = case / "files.txt"
        files_path.write_text("\n".join(files) + "\n", encoding="utf-8")
        return self.run_step(
            step_script,
            {
                "EVENT_NAME": "pull_request",
                "PR_NUMBER": "1",
                "REPOSITORY": "o/r",
                "GH_TOKEN": "stub-token",
                "GH_STUB_FILES": str(files_path),
                "PATH": f"{self.bin_dir}:{os.environ['PATH']}",
            },
            cwd=case,
        )
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
# The read-only roles' tool lists are checked separately and by name:
# "read-only -- never edits files" is an architectural claim each file makes
# about itself, and the only thing enforcing it is the absence of three
# strings in its `tools:` line.
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

# --- Read-only roles hold no writing tool -----------------------------------
# Stated in .claude/agents/reviewer.md and .claude/agents/plan-reviewer.md, in
# AGENTS.md's role split, and in AGENT_ROLE_DESIGN.md's tool-boundary test.
# Enforced by nothing else.
for read_only_role in ("reviewer", "plan-reviewer"):
    agent_path = local.get(read_only_role)
    if agent_path is None:
        failures.append(
            f"no {read_only_role} role found -- the read-only check cannot run"
        )
        continue
    tools = field(frontmatter(agent_path), "tools") or ""
    granted = {t.strip() for t in tools.split(",")}
    for forbidden in ("Edit", "Write", "NotebookEdit"):
        if forbidden in granted:
            failures.append(
                f"{agent_path}: {read_only_role} has the `{forbidden}` tool."
                f" The role is read-only against code by design."
            )

# --- Commenting roles hold the tool their contract requires -----------------
# #72 -- the planner's Procedure requires it to publish a plan comment (step
# 10), but its `tools:` line never granted `mcp__github__add_issue_comment`,
# so the cloud surface had no route to a step its own contract required.
# `reviewer` and `plan-reviewer` publish a verdict comment the same way.
# `implementer` and `fixer` open pull requests, never post Issue comments, and
# must not gain this grant merely to make the check below uniform.
for commenting_role in ("planner", "reviewer", "plan-reviewer"):
    agent_path = local.get(commenting_role)
    if agent_path is None:
        failures.append(
            f"no {commenting_role} role found -- the comment-tool check cannot run"
        )
        continue
    tools = field(frontmatter(agent_path), "tools") or ""
    granted = {t.strip() for t in tools.split(",")}
    if "mcp__github__add_issue_comment" not in granted:
        failures.append(
            f"{agent_path}: {commenting_role} has no"
            f" `mcp__github__add_issue_comment` tool, but its contract"
            f" requires it to publish a comment -- the cloud surface would"
            f" have no route to that step."
        )

if failures:
    for line in failures:
        print(f"  FAIL — {line}", file=sys.stderr)
    sys.exit(1)

print(
    f"  ok   — {len(cloud)} role(s) paired across .github/agents,"
    f" .claude/agents and .claude/commands; reviewer and plan-reviewer hold"
    f" no write tool; planner, reviewer and plan-reviewer hold"
    f" mcp__github__add_issue_comment"
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

# ---------------------------------------------------------------------------
# Part 9: no `workflow_dispatch` input is declared `type: number`.
#
# GitHub renders a `number` input into a step's shell as a float: a dispatch
# naming Issue 217 substitutes `217.0`. Anything that then treats it as an
# integer -- an argparse `type=int`, a `gh` call, an arithmetic test -- fails
# on input that looks correct everywhere a human reads it, the dispatch form
# included. Dispatch inputs cross the wire as strings regardless, so `number`
# buys nothing and costs this.
#
# Scanned repository-wide rather than scoped to the workflow that had the
# bug: the trap is in the declaration, not in any particular consumer, so a
# new workflow reaching for `type: number` should fail here rather than at
# its first dispatch.
# ---------------------------------------------------------------------------

part9 () {
  python3 - <<'PY'
import pathlib
import re
import sys

failures = []
workflows = sorted(pathlib.Path('.github/workflows').glob('*.yml'))

for path in workflows:
    in_dispatch = False
    dispatch_indent = 0

    for number, line in enumerate(path.read_text().splitlines(), start=1):
        stripped = line.strip()

        # A key at column 0 closes any block -- `jobs:` ends `on:`.
        if line and not line[0].isspace() and not stripped.startswith('#'):
            in_dispatch = False

        if re.match(r'^\s+workflow_dispatch:\s*$', line):
            in_dispatch = True
            dispatch_indent = len(line) - len(line.lstrip())
            continue

        if not in_dispatch or not stripped or stripped.startswith('#'):
            continue

        # A sibling trigger at the same indentation closes the block.
        if (len(line) - len(line.lstrip())) <= dispatch_indent:
            in_dispatch = False
            continue

        if re.match(r'^\s*type:\s*number\s*$', line):
            failures.append(
                f'{path}:{number}: `type: number` in a workflow_dispatch'
                ' input. Use `type: string` -- a number input reaches the'
                ' shell as a float (217 becomes 217.0).'
            )

if failures:
    for failure in failures:
        print(f'  FAIL - {failure}', file=sys.stderr)
    sys.exit(1)

print(f'  ok   - no float-valued dispatch inputs across {len(workflows)} workflow(s)')
sys.exit(0)
PY
}

# ---------------------------------------------------------------------------
# Part 10: the plan-review request assembler (#230).
#
# `build-plan-review-request.py` turns a captured epic-plus-plan bundle into
# the one file a plan reviewer reads. Everything it decides is decided before
# a model is loaded -- which sections exist and in what order, which comments
# are the owner's and which are the control plane talking to itself, and which
# artifact names the plan uses resolve nowhere -- so all of it is testable
# here, and a regression in any of it is a silently worse review rather than a
# failure anybody notices.
#
# Two of the three fixtures are historical defects rather than invented cases:
# #226's plan, which invented a second label for a fact `human-credentials`
# already carried, and #227 after its retarget, whose body still specified
# `sync-local-session-label.py` after the file had been renamed. The third is
# a plan that was implemented and merged without a planning failure, and is
# the control: the checks must stay quiet on it.
#
# python3 only, no network, no credentials, and every byte written under the
# harness's own work_dir -- Part 5's rule applies to a test as much as to a
# workflow.
# ---------------------------------------------------------------------------

part10 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
root = pathlib.Path(repo_root)
script = root / ".github" / "scripts" / "build-plan-review-request.py"
fixtures = root / ".github" / "tests" / "plan-review"
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part10.", dir=work_dir))

HEADINGS = [
    "# EPIC (AUTHORITATIVE INTENT)",
    "# EPIC AMENDMENT COMMENTS",
    "# PLANNED IMPLEMENTATION TASKS",
    "# DECLARED DEPENDENCY EDGES",
    "# DECLARED EXPECTED FILES",
    "# UNRESOLVED ARTIFACT NAMES",
    "# REPOSITORY FILE INVENTORY",
    "# DELIBERATELY EXCLUDED",
]

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def run(bundle, out):
    return subprocess.run(
        [sys.executable, str(script), "--bundle", str(bundle), "--out", str(out)],
        capture_output=True,
        text=True,
    )


def section(text, heading):
    """The heading's own block, up to whichever section heading follows it."""
    lines = text.splitlines()
    if heading not in lines:
        return ""
    start = lines.index(heading)
    end = len(lines)
    for other in HEADINGS:
        if other != heading and other in lines[start + 1:]:
            end = min(end, lines.index(other, start + 1))
    return "\n".join(lines[start:end])


def write_bundle(name, payload):
    path = part_dir / name
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return path


# -- 1: the sound plan assembles, with all eight sections in order. ----------
sound_out = part_dir / "sound-plan.md"
result = run(fixtures / "sound-plan.json", sound_out)
check(
    result.returncode == 0 and sound_out.is_file(),
    "sound-plan.json assembles and exits 0",
    f"sound-plan.json failed (exit {result.returncode}): {result.stderr.strip()}",
)

sound = sound_out.read_text(encoding="utf-8") if sound_out.is_file() else ""
lines = sound.splitlines()
positions = [lines.index(h) if h in lines else -1 for h in HEADINGS]
check(
    all(position >= 0 for position in positions)
    and positions == sorted(positions),
    "all eight sections are present, in the specified order",
    "sections missing or out of order: "
    + ", ".join(
        f"{heading}={position}"
        for heading, position in zip(HEADINGS, positions)
    ),
)

# -- 2: #226's plan, whole -- every task body, and a real file inventory. ----
before = json.loads(
    (fixtures / "226-before-correction.json").read_text(encoding="utf-8")
)
before_out = part_dir / "226-before-correction.md"
result = run(fixtures / "226-before-correction.json", before_out)
before_text = (
    before_out.read_text(encoding="utf-8") if before_out.is_file() else ""
)

missing = [
    task["number"]
    for task in before["tasks"]
    if task["body"].strip() not in before_text
]
check(
    result.returncode == 0 and not missing,
    "#227, #228 and #229 each appear in full, body and all",
    f"task bodies truncated or absent for: {missing or 'n/a'}"
    f" (exit {result.returncode})",
)

inventory = section(before_text, "# REPOSITORY FILE INVENTORY")
for path in (
    ".github/scripts/task_scope.py",
    ".github/workflows/agent-01-planner.yml",
):
    check(
        path in inventory,
        f"the file inventory lists {path}",
        f"the file inventory does not list {path}",
    )

# -- 3: check 8 reports the stale name and not the real one (#227/#232). ----
retarget_out = part_dir / "227-after-retarget.md"
result = run(fixtures / "227-after-retarget.json", retarget_out)
unresolved = section(
    retarget_out.read_text(encoding="utf-8") if retarget_out.is_file() else "",
    "# UNRESOLVED ARTIFACT NAMES",
)
check(
    result.returncode == 0 and "sync-local-session-label.py" in unresolved,
    "the stale `sync-local-session-label.py` is reported unresolved",
    "check 8 missed sync-local-session-label.py, the name this fixture exists"
    " to pin",
)
check(
    "sync-human-credentials-label.py" not in unresolved,
    "the real `sync-human-credentials-label.py` is not reported",
    "check 8 reported sync-human-credentials-label.py, which is in the tree."
    " A noisy check 8 is worse than none.",
)

# -- 4: agent-authored comments are dropped; human ones are not. -------------
AGENT_SENTINEL = "SENTINEL-AGENT-4f91c2"
HUMAN_SENTINEL = "SENTINEL-HUMAN-7b30da"
marker_bundle = write_bundle(
    "agent-marker.json",
    {
        "epic": {
            "number": 9001,
            "title": "[epic] A bundle carrying one comment of each kind",
            "body": "## Goal\n\nSomething the owner wants.\n",
            "comments": [
                {
                    "author": "github-actions[bot]",
                    "created_at": "2026-09-13T00:00:00Z",
                    "body": (
                        "<!-- agent-rollup-complete -->\n\n"
                        f"{AGENT_SENTINEL}\n"
                    ),
                },
                {
                    "author": "stardustsuperwizard",
                    "created_at": "2026-09-13T01:00:00Z",
                    "body": f"## Correction\n\n{HUMAN_SENTINEL}\n",
                },
            ],
        },
        "tasks": [
            {
                "number": 9002,
                "title": "[task] [9001] Do the one thing",
                "url": "https://example.invalid/9002",
                "body": (
                    "## Scope\n\nDo it.\n\n"
                    "## Files or Subsystems Expected to Change\n\n"
                    "- `rules/actions/pass_action.gd`\n\n"
                    "## Dependencies\n\n"
                    "| Relationship | Issue | Why |\n"
                    "| --- | --- | --- |\n"
                    "| None | — | — |\n"
                ),
            }
        ],
    },
)
marker_out = part_dir / "agent-marker.md"
result = run(marker_bundle, marker_out)
marker_text = (
    marker_out.read_text(encoding="utf-8") if marker_out.is_file() else ""
)
check(
    result.returncode == 0 and AGENT_SENTINEL not in marker_text,
    "a comment opening with an `<!-- agent-` marker is dropped entirely",
    "an agent-authored comment reached the assembled request",
)
check(
    HUMAN_SENTINEL in marker_text,
    "a human-authored comment in the same bundle survives",
    "the human-authored comment was dropped along with the agent one",
)

# -- 4b: claude-planner comments are dropped too (widened filter). -----------
CLAUDE_SENTINEL = "SENTINEL-CLAUDE-9f2e1a"
claude_bundle = write_bundle(
    "claude-marker.json",
    {
        "epic": {
            "number": 9003,
            "title": "[epic] A bundle carrying a claude-planner marker",
            "body": "## Goal\n\nSomething the owner wants.\n",
            "comments": [
                {
                    "author": "Claude",
                    "created_at": "2026-09-13T00:00:00Z",
                    "body": (
                        "<!-- claude-planner-complete -->\n\n"
                        f"{CLAUDE_SENTINEL}\n"
                    ),
                },
            ],
        },
        "tasks": [
            {
                "number": 9004,
                "title": "[task] [9003] Do the one thing",
                "url": "https://example.invalid/9004",
                "body": (
                    "## Scope\n\nDo it.\n\n"
                    "## Files or Subsystems Expected to Change\n\n"
                    "- `rules/actions/pass_action.gd`\n\n"
                    "## Dependencies\n\n"
                    "| Relationship | Issue | Why |\n"
                    "| --- | --- | --- |\n"
                    "| None | — | — |\n"
                ),
            }
        ],
    },
)
claude_out = part_dir / "claude-marker.md"
result = run(claude_bundle, claude_out)
claude_text = (
    claude_out.read_text(encoding="utf-8") if claude_out.is_file() else ""
)
check(
    result.returncode == 0 and CLAUDE_SENTINEL not in claude_text,
    "a comment opening with `<!-- claude-` marker is dropped entirely",
    "a claude-planner comment reached the assembled request",
)

# -- 5: a plan with no tasks is refused, by epic number, writing nothing. ----
empty_bundle = write_bundle(
    "no-tasks.json",
    {
        "epic": {
            "number": 9101,
            "title": "[epic] An epic whose plan filed no tasks",
            "body": "## Goal\n\nUnplanned.\n",
            "comments": [],
        },
        "tasks": [],
    },
)
empty_out = part_dir / "no-tasks.md"
result = run(empty_bundle, empty_out)
check(
    result.returncode != 0
    and "9101" in result.stderr
    and not empty_out.exists(),
    "a bundle with no tasks exits non-zero naming the epic, and writes nothing",
    f"expected a refusal naming #9101 and no output file; exit"
    f" {result.returncode}, file exists={empty_out.exists()},"
    f" stderr={result.stderr.strip()!r}",
)

# -- 6: a task with a null body is refused, by task number, writing nothing. -
null_bundle = write_bundle(
    "null-body.json",
    {
        "epic": {
            "number": 9201,
            "title": "[epic] An epic whose capture lost a task body",
            "body": "## Goal\n\nCaptured badly.\n",
            "comments": [],
        },
        "tasks": [
            {
                "number": 9202,
                "title": "[task] [9201] The one that captured",
                "url": "https://example.invalid/9202",
                "body": "## Scope\n\nFine.\n",
            },
            {
                "number": 9203,
                "title": "[task] [9201] The one that did not",
                "url": "https://example.invalid/9203",
                "body": None,
            },
        ],
    },
)
null_out = part_dir / "null-body.md"
result = run(null_bundle, null_out)
check(
    result.returncode != 0
    and "9203" in result.stderr
    and not null_out.exists(),
    "a task with a null body exits non-zero naming that task, and writes"
    " nothing",
    f"expected a refusal naming #9203 and no output file; exit"
    f" {result.returncode}, file exists={null_out.exists()},"
    f" stderr={result.stderr.strip()!r}",
)

# -- 7: optional inventory key in bundle produces matching inventory. --------
pinned_inventory = [
    "rules/actions/attack_action.gd",
    "rules/actions/charge_action.gd",
    "rules/actions/move_action.gd",
    "tests/round_driver_test.gd",
]
pinned_bundle = write_bundle(
    "pinned-inventory.json",
    {
        "epic": {
            "number": 9301,
            "title": "[epic] A bundle with a pinned inventory",
            "body": "## Goal\n\nTest pinned inventory.\n",
            "comments": [],
        },
        "tasks": [
            {
                "number": 9302,
                "title": "[task] [9301] Do the one thing",
                "url": "https://example.invalid/9302",
                "body": (
                    "## Scope\n\nDo it.\n\n"
                    "## Files or Subsystems Expected to Change\n\n"
                    "- `rules/actions/pass_action.gd`\n\n"
                    "## Dependencies\n\n"
                    "| Relationship | Issue | Why |\n"
                    "| --- | --- | --- |\n"
                    "| None | — | — |\n"
                ),
            }
        ],
        "inventory": pinned_inventory,
    },
)
pinned_out = part_dir / "pinned-inventory.md"
result = run(pinned_bundle, pinned_out)
pinned_text = (
    pinned_out.read_text(encoding="utf-8") if pinned_out.is_file() else ""
)

# Check that the inventory section contains exactly the pinned files
inventory_section = section(pinned_text, "# REPOSITORY FILE INVENTORY")
pinned_present = all(
    path in inventory_section for path in pinned_inventory
)
pinned_complete = inventory_section.count("- ") == len(pinned_inventory)

check(
    result.returncode == 0 and pinned_present and pinned_complete,
    "a bundle with inventory key produces a request whose inventory matches"
    " it exactly",
    f"inventory section mismatch: present={pinned_present},"
    f" complete={pinned_complete}",
)

# Verify a bundle with no `inventory` key behaves exactly as today: its
# inventory equals what a live walk of REPO_ROOT gives, not merely "more
# entries than a four-item pinned list". Import the script itself rather
# than re-deriving SKIP_DIRS or the walk order by hand -- the same rule
# check 8 states for a reviewer applies here to the test.
import importlib.util

spec = importlib.util.spec_from_file_location(
    "build_plan_review_request", script
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
expected_live_files = module.Tree(module.REPO_ROOT).files

live_walk_bundle = write_bundle(
    "live-walk.json",
    {
        "epic": {
            "number": 9301,
            "title": "[epic] A bundle without inventory (walks live tree)",
            "body": "## Goal\n\nTest live tree walk.\n",
            "comments": [],
        },
        "tasks": [
            {
                "number": 9302,
                "title": "[task] [9301] Do the one thing",
                "url": "https://example.invalid/9302",
                "body": (
                    "## Scope\n\nDo it.\n\n"
                    "## Files or Subsystems Expected to Change\n\n"
                    "- `rules/actions/pass_action.gd`\n\n"
                    "## Dependencies\n\n"
                    "| Relationship | Issue | Why |\n"
                    "| --- | --- | --- |\n"
                    "| None | — | — |\n"
                ),
            }
        ],
    },
)
live_out = part_dir / "live-walk.md"
result = run(live_walk_bundle, live_out)
live_text = (
    live_out.read_text(encoding="utf-8") if live_out.is_file() else ""
)

# A bundle without `inventory` must produce the same inventory a live walk
# of REPO_ROOT gives -- exact equality, not a cardinality check that would
# pass on almost any regression in the walk path.
live_inventory_section = section(live_text, "# REPOSITORY FILE INVENTORY")
rendered_live_files = {
    line[len("- "):]
    for line in live_inventory_section.splitlines()
    if line.startswith("- ")
}

check(
    result.returncode == 0 and rendered_live_files == expected_live_files,
    "a bundle without inventory walks the live tree and matches"
    " Tree(REPO_ROOT) exactly",
    "live tree walk did not match Tree(REPO_ROOT): "
    f"missing={sorted(expected_live_files - rendered_live_files)[:5]},"
    f" extra={sorted(rendered_live_files - expected_live_files)[:5]}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 11: extract-review-verdict's two modes (#230).
#
# `extract-review-verdict` is the one gate that decides whether a verdict is
# published, and it now reads two vocabularies: the pull request review's
# PASS/FIX/PLANNING FAILURE/DESIGN AMBIGUITY, and the plan review's PLAN
# PASS/PLAN FIX/PLAN REJECT. Three things about that are worth pinning.
#
# The vocabularies must not leak into each other. `VERDICT: PLAN PASS` read
# in `pr` mode would apply `review:pass` to a pull request nobody reviewed,
# and `VERDICT: PASS` read in `plan` mode would publish a slug no caller has
# a meaning for. Both are failures a regex written slightly differently
# would let through -- `PASS` is a substring of `PLAN PASS`.
#
# The truncation gate must apply to both. It is the whole reason this action
# exists: the verdict line comes first, so it survives exactly the truncation
# that removes the reasoning behind it, and a plan verdict is no more
# trustworthy in that state than a pull request one.
#
# And `pr` mode must not have moved. It has two live callers that pass no
# `mode` at all, so the default is what they get.
#
# The step is run as its own program with a stubbed environment -- no
# network, no credentials, no Actions runner -- so what is checked is the
# code that actually ships, not a re-typed copy of it.
# ---------------------------------------------------------------------------

part11 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
import wf

work_dir, repo_root = sys.argv[1], sys.argv[2]
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part11.", dir=work_dir))

ACTION = ".github/actions/extract-review-verdict/action.yml"

step = part_dir / "extract_verdict.py"
step.write_text(wf.step_source(ACTION, "Extract Verdict"), encoding="utf-8")

PR_REPORT = "\n".join(
    [
        "## Acceptance Criteria",
        "## Architecture Constraints",
        "## Scope Adherence",
        "## Findings",
        "## Deferred Findings",
        "## Required Before Merge",
    ]
)

PLAN_REPORT = "\n".join(
    ["## Checks", "## Findings", "## Required Before Dispatch"]
)

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def run(name, text, outcome, mode=None):
    """Run the step exactly as the action does, in its own scratch dir."""
    case = part_dir / name
    case.mkdir()

    (case / "assistant.txt").write_text(text, encoding="utf-8")
    (case / "outcome.json").write_text(json.dumps(outcome), encoding="utf-8")
    (case / "github_output").write_text("", encoding="utf-8")

    env = dict(os.environ)
    env.update(
        {
            "RUNNER_TEMP": str(case),
            "GITHUB_WORKSPACE": repo_root,
            "GITHUB_OUTPUT": str(case / "github_output"),
            "ASSISTANT_TEXT_FILE": str(case / "assistant.txt"),
            "OUTCOME_FILE": str(case / "outcome.json"),
        }
    )

    # Absent, not empty: an omitted `mode` reaches the step as the action's
    # own default, and that default is what the two live callers get.
    if mode is None:
        env.pop("MODE", None)
    else:
        env["MODE"] = mode

    result = subprocess.run(
        [sys.executable, str(step)],
        capture_output=True,
        text=True,
        cwd=repo_root,
        env=env,
    )

    outputs = dict(
        line.split("=", 1)
        for line in (case / "github_output").read_text().splitlines()
        if "=" in line
    )

    return result, outputs, case


FINISHED = {"reason": "completed", "assistant_text_chars": 4096}
CUT_OFF = {
    "reason": "completed",
    "unfinished_turn": True,
    "assistant_text_chars": 4096,
    "credit_limit": 25,
}

# -- 1: a complete plan review publishes PLAN REJECT / plan-reject. ----------
result, outputs, case = run(
    "plan-reject",
    f"VERDICT: PLAN REJECT\n\n{PLAN_REPORT}\n",
    FINISHED,
    mode="plan",
)
check(
    result.returncode == 0
    and outputs.get("verdict") == "PLAN REJECT"
    and outputs.get("slug") == "plan-reject",
    "plan mode: VERDICT: PLAN REJECT yields verdict=PLAN REJECT,"
    " slug=plan-reject",
    f"expected PLAN REJECT/plan-reject; exit {result.returncode},"
    f" outputs={outputs}, stderr={result.stderr.strip()!r}",
)
check(
    (case / "review.md").is_file()
    and "## Required Before Dispatch"
    in (case / "review.md").read_text(),
    "plan mode: the full report is written to review.md",
    "plan mode wrote no review.md, or wrote one missing the report",
)

# -- 2: the two vocabularies do not leak into each other. --------------------
result, outputs, case = run(
    "plan-mode-pr-verdict",
    f"VERDICT: PASS\n\n{PLAN_REPORT}\n",
    FINISHED,
    mode="plan",
)
check(
    result.returncode != 0 and not outputs,
    "plan mode: VERDICT: PASS is refused and publishes nothing",
    f"plan mode accepted a pull request verdict; exit {result.returncode},"
    f" outputs={outputs}",
)

result, outputs, case = run(
    "pr-mode-plan-verdict",
    f"VERDICT: PLAN PASS\n\n{PR_REPORT}\n",
    FINISHED,
    mode="pr",
)
check(
    result.returncode != 0 and not outputs,
    "pr mode: VERDICT: PLAN PASS is refused and publishes nothing",
    f"pr mode accepted a plan verdict; exit {result.returncode},"
    f" outputs={outputs}",
)

# -- 3: the truncation gate is not relaxed for plan mode. --------------------
result, outputs, case = run(
    "plan-truncated",
    f"VERDICT: PLAN PASS\n\n{PLAN_REPORT}\n",
    CUT_OFF,
    mode="plan",
)
failure_file = case / "review-verdict-failure.json"
recorded = (
    json.loads(failure_file.read_text()) if failure_file.is_file() else {}
)
check(
    result.returncode != 0
    and not outputs
    and recorded.get("reason") == "truncated_review",
    "plan mode: a cut-off session publishes no verdict, exits non-zero, and"
    " records truncated_review",
    f"expected a truncated_review refusal; exit {result.returncode},"
    f" outputs={outputs}, failure={recorded or 'no file'}",
)

# -- 4: pr mode, with no `mode` passed at all, is where it was. --------------
result, outputs, case = run(
    "pr-default",
    f"VERDICT: PASS\n\n{PR_REPORT}\n",
    FINISHED,
)
check(
    result.returncode == 0
    and outputs.get("verdict") == "PASS"
    and outputs.get("slug") == "pass",
    "no mode passed: the pr vocabulary still parses, unchanged",
    f"the default mode stopped parsing a pull request verdict; exit"
    f" {result.returncode}, outputs={outputs},"
    f" stderr={result.stderr.strip()!r}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 12: count-tests.py's suite reachability, assertion counting, and
# compare modes (#283).
#
# count-tests.py is a port of tests/orphan_test_contract_test.gd's
# reachability algorithm and ExtractionContractTest.strip_comment(), and this
# part is what pins the port against synthetic fixture trees rather than the
# repository's own tree, whose suite count and assertion total change over
# time. Every fixture is written under this harness's own work_dir via
# tempfile.mkdtemp(), never into the checkout -- Part 5's rule applies to a
# test as much as to a workflow.
#
# python3 only, no network, no credentials: count-tests.py is invoked as a
# subprocess exactly as CI would run it, so what is checked is the script
# that actually ships.
# ---------------------------------------------------------------------------

part12 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
script = pathlib.Path(repo_root) / ".github" / "scripts" / "count-tests.py"

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def write_tree(base, files):
    for rel, content in files.items():
        path = base / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def count(root):
    return subprocess.run(
        [sys.executable, str(script), "count", "--root", str(root)],
        capture_output=True,
        text=True,
    )


def compare(base_json, head_json):
    return subprocess.run(
        [
            sys.executable, str(script), "compare",
            "--base", str(base_json), "--head", str(head_json),
        ],
        capture_output=True,
        text=True,
    )


def bootstrap(entries):
    body = "".join(
        f'\t{{"name": "{name}", "run": {name}.run}},\n' for name in entries
    )
    return f"extends Node\n\nvar _suites: Array[Dictionary] = [\n{body}]\n"


def fixture_dir(prefix):
    return pathlib.Path(tempfile.mkdtemp(prefix=prefix, dir=work_dir))


def report_of(result):
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


# -- 1: a registered suite plus one reached only transitively is counted. ---
case1 = fixture_dir("ct-case1.")
write_tree(case1, {
    "tests/test_bootstrap.gd": bootstrap(["RegisteredTest"]),
    "tests/registered_test.gd": (
        "class_name RegisteredTest\n\n"
        "static func run() -> bool:\n"
        "\treturn TransitiveTest.run()\n"
    ),
    "tests/transitive_test.gd": (
        "class_name TransitiveTest\n\n"
        "static func run() -> bool:\n"
        "\treturn true\n"
    ),
})
result = count(case1)
report = report_of(result)
check(
    result.returncode == 0
    and report.get("suites", {}).get("count") == 2
    and sorted(report.get("suites", {}).get("names", [])) == ["RegisteredTest", "TransitiveTest"]
    and report.get("suites", {}).get("unreachable") == [],
    "a suite reached only transitively through a registered one is counted",
    f"expected both suites counted; exit {result.returncode}, report={report or result.stdout}",
)

# -- 2: two unregistered suites naming each other are both unreachable. -----
case2 = fixture_dir("ct-case2.")
write_tree(case2, {
    "tests/test_bootstrap.gd": bootstrap(["RegisteredTest"]),
    "tests/registered_test.gd": (
        "class_name RegisteredTest\n\n"
        "static func run() -> bool:\n"
        "\treturn true\n"
    ),
    "tests/orphan_a_test.gd": (
        "class_name OrphanATest\n\n"
        "static func run() -> bool:\n"
        "\treturn OrphanBTest.run()\n"
    ),
    "tests/orphan_b_test.gd": (
        "class_name OrphanBTest\n\n"
        "static func run() -> bool:\n"
        "\treturn OrphanATest.run()\n"
    ),
})
result = count(case2)
report = report_of(result)
check(
    result.returncode == 0
    and report.get("suites", {}).get("count") == 1
    and report.get("suites", {}).get("names") == ["RegisteredTest"]
    and report.get("suites", {}).get("unreachable")
    == sorted(["tests/orphan_a_test.gd", "tests/orphan_b_test.gd"]),
    "two suites naming only each other count neither, list both unreachable, exit 0",
    f"expected only RegisteredTest counted, both orphans unreachable;"
    f" exit {result.returncode}, report={report or result.stdout}",
)

# -- 3: deleting a fixture with its _suites entry drops the count by one. ---
full = fixture_dir("ct-case3-full.")
write_tree(full, {
    "tests/test_bootstrap.gd": bootstrap(["ATest", "BTest"]),
    "tests/a_test.gd": "class_name ATest\n\nstatic func run() -> bool:\n\treturn true\n",
    "tests/b_test.gd": "class_name BTest\n\nstatic func run() -> bool:\n\treturn true\n",
})
full_report = report_of(count(full))

reduced = fixture_dir("ct-case3-reduced.")
write_tree(reduced, {
    "tests/test_bootstrap.gd": bootstrap(["ATest"]),
    "tests/a_test.gd": "class_name ATest\n\nstatic func run() -> bool:\n\treturn true\n",
})
reduced_report = report_of(count(reduced))

check(
    full_report.get("suites", {}).get("count") == 2
    and reduced_report.get("suites", {}).get("count") == 1,
    "deleting a fixture file with its _suites entry lowers the suite count by exactly one",
    f"expected 2 then 1; full={full_report}, reduced={reduced_report}",
)

# -- 4: renaming a file, class_name and _suites entry untouched, changes ----
#      neither count.
before_dir = fixture_dir("ct-case4-before.")
write_tree(before_dir, {
    "tests/test_bootstrap.gd": bootstrap(["ATest"]),
    "tests/a_test.gd": (
        "class_name ATest\n\n"
        'static func run() -> bool:\n\treturn _expect(true, "x").is_empty()\n'
    ),
})
before_report = report_of(count(before_dir))

after_dir = fixture_dir("ct-case4-after.")
write_tree(after_dir, {
    "tests/test_bootstrap.gd": bootstrap(["ATest"]),
    "tests/renamed_a_test.gd": (
        "class_name ATest\n\n"
        'static func run() -> bool:\n\treturn _expect(true, "x").is_empty()\n'
    ),
})
after_report = report_of(count(after_dir))

check(
    before_report
    and after_report
    and before_report["suites"]["count"] == after_report["suites"]["count"]
    and before_report["assertions"]["total"] == after_report["assertions"]["total"],
    "renaming a fixture file with class_name and _suites entry intact changes neither count",
    f"expected identical counts; before={before_report}, after={after_report}",
)

# -- 5: comment-stripped _expect( counting. ----------------------------------
case5 = fixture_dir("ct-case5.")
write_tree(case5, {
    "tests/test_bootstrap.gd": bootstrap(["CommentTest"]),
    "tests/comment_test.gd": (
        "class_name CommentTest\n\n"
        '# _expect(false, "in a comment") # not counted\n'
        'var s = "_expect(counted, inside a string)"\n'
        'var t = "# _expect(after a hash inside a string)"\n\n'
        "static func run() -> bool:\n\treturn true\n"
    ),
})
report = report_of(count(case5))
check(
    report.get("assertions", {}).get("by_file", {}).get("tests/comment_test.gd") == 2
    and report.get("assertions", {}).get("total") == 2,
    "_expect( in a comment is not counted; inside a string, and after a #"
    " inside a string, both are",
    f"expected 2 assertions from comment_test.gd; report={report}",
)

# -- 6: an empty or unparseable _suites literal exits 2. ---------------------
case6 = fixture_dir("ct-case6.")
write_tree(case6, {
    "tests/test_bootstrap.gd": "extends Node\n\nvar _suites: Array[Dictionary] = []\n",
    "tests/a_test.gd": "class_name ATest\n\nstatic func run() -> bool:\n\treturn true\n",
})
result = count(case6)
check(
    result.returncode == 2 and "tests/test_bootstrap.gd" in result.stderr,
    "an empty _suites literal exits 2 and names tests/test_bootstrap.gd",
    f"expected exit 2 naming the bootstrap; exit {result.returncode}, stderr={result.stderr!r}",
)

case6b = fixture_dir("ct-case6b.")
write_tree(case6b, {
    "tests/test_bootstrap.gd": (
        "extends Node\n\nvar _renamed_suites: Array[Dictionary] = [\n"
        '\t{"name": "ATest", "run": ATest.run},\n]\n'
    ),
    "tests/a_test.gd": "class_name ATest\n\nstatic func run() -> bool:\n\treturn true\n",
})
result = count(case6b)
check(
    result.returncode == 2 and "tests/test_bootstrap.gd" in result.stderr,
    "a renamed _suites array, unparseable by this reader, also exits 2",
    f"expected exit 2 naming the bootstrap; exit {result.returncode}, stderr={result.stderr!r}",
)

# -- 7: compare's exit codes and its decrease section. -----------------------
case7 = fixture_dir("ct-case7.")


def write_report(name, suites_count, names, by_file, total):
    path = case7 / name
    data = {
        "assertions": {"by_file": by_file, "total": total},
        "suites": {"count": suites_count, "names": names, "unreachable": []},
    }
    path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    return path


base_json = write_report(
    "base.json", 10, ["ATest", "BTest"],
    {"tests/a_test.gd": 5, "tests/b_test.gd": 3}, 8,
)

result = compare(base_json, write_report(
    "head-equal.json", 10, ["ATest", "BTest"],
    {"tests/a_test.gd": 5, "tests/b_test.gd": 3}, 8,
))
check(
    result.returncode == 0 and "| Suites | 10 | 10 | 0 |" in result.stdout,
    "compare exits 0 on equal counts, printing the both-counts table",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

result = compare(base_json, write_report(
    "head-increase.json", 11, ["ATest", "BTest", "CTest"],
    {"tests/a_test.gd": 5, "tests/b_test.gd": 3, "tests/c_test.gd": 4}, 12,
))
check(
    result.returncode == 0 and "Decrease detected" not in result.stdout,
    "compare exits 0 on an increase, with no decrease section",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

result = compare(base_json, write_report(
    "head-suite-drop.json", 9, ["ATest"], {"tests/a_test.gd": 5}, 5,
))
check(
    result.returncode == 1
    and "Decrease detected" in result.stdout
    and "BTest" in result.stdout,
    "compare exits 1 when suites fall, and names the lost suite",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

result = compare(base_json, write_report(
    "head-assertion-drop.json", 10, ["ATest", "BTest"],
    {"tests/a_test.gd": 2, "tests/b_test.gd": 3}, 5,
))
check(
    result.returncode == 1
    and "Decrease detected" in result.stdout
    and "tests/a_test.gd" in result.stdout
    and "| 5 | 2 |" in result.stdout,
    "compare exits 1 when assertions fall, naming the file with before/after",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

result = compare(base_json, write_report(
    "head-rename.json", 10, ["ATest", "BTest"],
    {"tests/renamed_a_test.gd": 5, "tests/b_test.gd": 3}, 8,
))
check(
    result.returncode == 0 and "Decrease detected" not in result.stdout,
    "a rename that preserves both totals produces no decrease and exits 0",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

missing = case7 / "does-not-exist.json"
result = compare(base_json, missing)
check(
    result.returncode == 2,
    "compare exits 2 on a missing report file",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

not_a_report = case7 / "not-a-report.json"
not_a_report.write_text(json.dumps({"foo": "bar"}), encoding="utf-8")
result = compare(base_json, not_a_report)
check(
    result.returncode == 2,
    "compare exits 2 on a file that is not a report this script produced",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

sys.exit(1 if failures else 0)
PY
}

part13 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import os
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
import wf

work_dir, repo_root = sys.argv[1], sys.argv[2]
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part13.", dir=work_dir))

CI = ".github/workflows/ci.yml"

# The whole "Determine Gates" step, exactly as it ships -- both the push
# path's shell logic and the pull_request path's embedded python program are
# one `shell: bash` block, so one extraction covers both. Extracted through
# wf.step_source the way Part 2 and Part 11 pull their steps, not
# hand-copied: a private copy of GODOT_DENY/glob_to_regex passes whatever it
# says, even after the real list drifts out from under it, which is exactly
# what happened to the version this part replaces (#299 review finding 2).
determine_gates = wf.step_source(CI, "Determine Gates", shell="bash")
step = part_dir / "determine-gates.sh"
step.write_text(determine_gates, encoding="utf-8")

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def run_step(env_overrides, cwd):
    """Run the extracted step exactly as the workflow does, in its own
    scratch RUNNER_TEMP and GITHUB_OUTPUT."""
    case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
    output_file = case / "github_output"
    output_file.write_text("", encoding="utf-8")

    env = dict(os.environ)
    env.update({"RUNNER_TEMP": str(case), "GITHUB_OUTPUT": str(output_file)})
    env.update(env_overrides)

    result = subprocess.run(
        ["bash", str(step)],
        capture_output=True,
        text=True,
        cwd=str(cwd),
        env=env,
    )
    outputs = dict(
        line.split("=", 1)
        for line in output_file.read_text().splitlines()
        if "=" in line
    )
    return result, outputs


def git(*args, cwd):
    subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True
    )


def make_repo():
    repo_dir = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
    git("init", "-q", cwd=repo_dir)
    git("config", "user.email", "test@example.invalid", cwd=repo_dir)
    git("config", "user.name", "Test", cwd=repo_dir)
    return repo_dir


def commit(repo_dir, files, message):
    for name, content in files.items():
        path = repo_dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    git("add", "-A", cwd=repo_dir)
    git("commit", "-q", "-m", message, cwd=repo_dir)
    return subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


# -- criteria 5/6: the pull_request path's embedded python program. ---------
# A stub `gh` that ignores its arguments and prints a fixed file list to
# stdout -- the same posture Part 8's stub `gh` uses for
# sync-human-credentials-label.py.
bin_dir = part_dir / "bin"
bin_dir.mkdir()
gh_stub = bin_dir / "gh"
gh_stub.write_text(
    "#!/usr/bin/env bash\nset -euo pipefail\ncat \"$GH_STUB_FILES\"\n",
    encoding="utf-8",
)
gh_stub.chmod(0o755)


def run_pull_request(files):
    case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
    files_path = case / "files.txt"
    files_path.write_text("\n".join(files) + "\n", encoding="utf-8")
    return run_step(
        {
            "EVENT_NAME": "pull_request",
            "PR_NUMBER": "1",
            "REPOSITORY": "o/r",
            "GH_TOKEN": "stub-token",
            "GH_STUB_FILES": str(files_path),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
        },
        cwd=part_dir,
    )


result, outputs = run_pull_request([".metrics/runs.csv"])
check(
    result.returncode == 0 and outputs.get("godot") == "false",
    "pull_request: [.metrics/runs.csv] alone prints godot=false (c5)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

result, outputs = run_pull_request([".metrics/runs.csv", "rules/board/board.gd"])
check(
    result.returncode == 0 and outputs.get("godot") == "true",
    "pull_request: .metrics/runs.csv plus a .gd file prints godot=true (c6)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

result, outputs = run_pull_request(
    [".metrics/runs.csv", ".metrics/runs/abc123.json"]
)
check(
    result.returncode == 0 and outputs.get("godot") == "false",
    "pull_request: multiple .metrics/* files print godot=false",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

# -- criterion 7: the push path's shell logic, all three outcomes. ----------
repo = make_repo()
before = commit(repo, {"README.md": "hello\n"}, "init")
after = commit(repo, {".metrics/runs.csv": "header\n"}, "add a ledger row")
result, outputs = run_step(
    {"EVENT_NAME": "push", "EVENT_BEFORE": before, "EVENT_AFTER": after},
    cwd=repo,
)
check(
    result.returncode == 0
    and outputs.get("godot") == "false"
    and outputs.get("control_plane") == "false",
    "push: every changed file under .metrics/ closes both gates (c7)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

repo = make_repo()
before = commit(repo, {"README.md": "hello\n"}, "init")
after = commit(
    repo,
    {".metrics/runs.csv": "header\n", "rules/board/board.gd": "extends Node\n"},
    "add a ledger row and a gd file",
)
result, outputs = run_step(
    {"EVENT_NAME": "push", "EVENT_BEFORE": before, "EVENT_AFTER": after},
    cwd=repo,
)
check(
    result.returncode == 0
    and outputs.get("godot") == "true"
    and outputs.get("control_plane") == "true",
    "push: a changed file outside .metrics/ opens both gates (c7)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

repo = make_repo()
after = commit(repo, {".metrics/runs.csv": "header\n"}, "init")
result, outputs = run_step(
    {"EVENT_NAME": "push", "EVENT_BEFORE": "0" * 40, "EVENT_AFTER": after},
    cwd=repo,
)
check(
    result.returncode == 0
    and outputs.get("godot") == "true"
    and outputs.get("control_plane") == "true",
    "push: an unreadable changed-file list fails safe, opening both gates (c7)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

repo = make_repo()
same = commit(repo, {"README.md": "hello\n"}, "init")
result, outputs = run_step(
    {"EVENT_NAME": "push", "EVENT_BEFORE": same, "EVENT_AFTER": same},
    cwd=repo,
)
check(
    result.returncode == 0
    and outputs.get("godot") == "true"
    and outputs.get("control_plane") == "true",
    "push: a successfully read but empty diff also fails safe"
    " (#299 review finding 5)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

# -- criterion 8: workflow_dispatch opens both gates unconditionally. -------
result, outputs = run_step({"EVENT_NAME": "workflow_dispatch"}, cwd=part_dir)
check(
    result.returncode == 0
    and outputs.get("godot") == "true"
    and outputs.get("control_plane") == "true",
    "workflow_dispatch opens both gates unconditionally (c8)",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 14: ledger_row.py's field derivation (#296).
#
# The reader side of the run-ledger schema (docs/RUN_LEDGER.md), covered
# end-to-end with fixture GitHub JSON and no network, no `gh`, and no merge.
# ---------------------------------------------------------------------------

part14 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import csv
import io
import json
import pathlib
import re
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
script = pathlib.Path(repo_root) / ".github" / "scripts" / "ledger_row.py"
case_dir = pathlib.Path(tempfile.mkdtemp(prefix="lr-case.", dir=work_dir))

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def session_record_body(**fields):
    return "<!-- agent-session-record\n" + json.dumps(fields) + "\n-->"


def run(pr, issue=None, run_url="https://example.invalid/ledger-run", n=[0]):
    n[0] += 1
    pr_path = case_dir / f"pr-{n[0]}.json"
    pr_path.write_text(json.dumps(pr), encoding="utf-8")
    args = [
        sys.executable, str(script),
        "--pr-json", str(pr_path),
        "--run-url", run_url,
    ]
    if issue is not None:
        issue_path = case_dir / f"issue-{n[0]}.json"
        issue_path.write_text(json.dumps(issue), encoding="utf-8")
        args += ["--issue-json", str(issue_path)]
    return subprocess.run(args, capture_output=True, text=True)


def rows_of(result):
    return list(csv.reader(io.StringIO(result.stdout)))


SESSION_A = dict(
    role="implementer", vendor="anthropic",
    model_requested="claude-sonnet-5", model_resolved="claude-sonnet-5",
    outcome="completed", duration_seconds=120.5, fix_round=0,
    run_url="https://example.invalid/run/1",
)
SESSION_B = dict(
    role="reviewer", vendor="claude",
    model_requested="claude-opus-5", model_resolved="claude-opus-5",
    outcome="completed", duration_seconds=30, fix_round=0,
    run_url="https://example.invalid/run/2",
)

# -- criterion 1: --help exits 0; the source has no third-party import and --
#    no subprocess/urllib/requests/gh call site. Matches on imports and call
#    sites, not on the bare word "gh" -- which appears legitimately inside
#    two `help=` strings.
help_result = subprocess.run(
    [sys.executable, str(script), "--help"], capture_output=True, text=True,
)
source = script.read_text(encoding="utf-8")
forbidden_import = re.search(
    r"^\s*(?:import|from)\s+(subprocess|urllib|requests)\b", source, re.MULTILINE,
)
forbidden_call = re.search(r"\b(?:subprocess|urllib|requests)\.\w+\(", source)
check(
    help_result.returncode == 0
    and forbidden_import is None
    and forbidden_call is None,
    "--help exits 0 and the source has no subprocess/urllib/requests import"
    " or call site (a gh invocation can only happen through one of those)",
    f"exit {help_result.returncode}, forbidden_import={forbidden_import},"
    f" forbidden_call={forbidden_call}, stderr={help_result.stderr!r}",
)

# -- criterion 2: the full fixture -- merge row plus two ordered session ----
#    rows.
full_pr = {
    "number": 300,
    "mergedAt": "2026-09-14T19:15:37Z",
    "body": "",
    "closingIssuesReferences": [{"number": 123}],
    "labels": [{"name": "review:pass"}],
    "comments": [
        {"body": "<!-- agent-fix-applied -->\nfirst fix"},
        {"body": "<!-- agent-fix-applied -->\nsecond fix"},
        {"body": session_record_body(**SESSION_A)},
        {"body": session_record_body(**SESSION_B)},
    ],
}
result = run(full_pr)
rows = rows_of(result)
check(
    result.returncode == 0
    and len(rows) == 3
    and rows[0][1:4] == ["merge", "123", "300"]
    and rows[0][9] == "2"
    and rows[0][10] == "pass"
    and rows[1][1] == "session"
    and rows[1][4:8] == ["implementer", "anthropic", "claude-sonnet-5", "claude-sonnet-5"]
    and rows[1][11] == "completed"
    and rows[1][12] == "120.5"
    and rows[2][1] == "session"
    and rows[2][4:8] == ["reviewer", "claude", "claude-opus-5", "claude-opus-5"]
    and rows[2][11] == "completed"
    and rows[2][12] == "30",
    "merge row plus two ordered session rows, fix_round=2, verdict=pass",
    f"exit {result.returncode}, rows={rows}, stderr={result.stderr!r}",
)

# -- criteria 3/4: every row round-trips through csv.reader into exactly ----
#    14 fields, a newline in a source value is stripped, and a comma+quote
#    value survives intact.
tricky_pr = {
    "number": 301,
    "mergedAt": "2026-09-14T19:15:37Z",
    "body": "",
    "comments": [{"body": session_record_body(
        role="a,b\"c\r\nsecond line", vendor="v", model_requested="m",
        model_resolved="m", outcome="completed", duration_seconds=1,
        fix_round=0, run_url="u",
    )}],
}
result = run(tricky_pr)
rows = rows_of(result)
check(
    result.returncode == 0
    and all(len(row) == 14 for row in rows)
    and all("\n" not in field and "\r" not in field for row in rows for field in row)
    and len(rows) == 2
    and rows[1][4] == 'a,b"c second line',
    "every row has 14 fields, no row break survives, comma+quote round-trips",
    f"rows={rows}, stderr={result.stderr!r}",
)

# -- criterion 5: no session-record comments yields exactly one merge row. --
result = run({
    "number": 302, "mergedAt": "2026-09-14T19:15:37Z", "body": "", "comments": [],
})
rows = rows_of(result)
check(
    result.returncode == 0 and len(rows) == 1 and rows[0][1] == "merge",
    "a pull request with no session-record comments yields exactly one merge row",
    f"rows={rows}, stderr={result.stderr!r}",
)

# -- criterion 6: verdict falls back to the last review-verdict comment, ----
#    then to empty.
result = run({
    "number": 303, "mergedAt": "2026-09-14T19:15:37Z", "body": "",
    "comments": [
        {"body": "<!-- agent-review-verdict -->\nVERDICT: FIX\nstale"},
        {"body": "<!-- agent-review-verdict -->\nVERDICT: DESIGN AMBIGUITY\nlatest"},
    ],
})
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][10] == "design-ambiguity",
    "no review:* label falls back to the LAST agent-review-verdict comment",
    f"rows={rows}, stderr={result.stderr!r}",
)

result = run({
    "number": 304, "mergedAt": "2026-09-14T19:15:37Z", "body": "", "comments": [],
})
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][10] == "",
    "neither a review:* label nor a verdict comment leaves verdict empty",
    f"rows={rows}, stderr={result.stderr!r}",
)

# -- criterion 7: tier_label is the closed issue's model:* label suffix, ----
#    empty without one or without --issue-json.
result = run(
    {"number": 305, "mergedAt": "2026-09-14T19:15:37Z", "body": "", "comments": []},
    issue={"labels": [{"name": "model:sonnet"}]},
)
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][8] == "sonnet",
    "tier_label is the model:* label's suffix",
    f"rows={rows}, stderr={result.stderr!r}",
)

result = run(
    {"number": 306, "mergedAt": "2026-09-14T19:15:37Z", "body": "", "comments": []},
    issue={"labels": []},
)
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][8] == "",
    "tier_label is empty when the issue carries no model:* label",
    f"rows={rows}, stderr={result.stderr!r}",
)

result = run({
    "number": 307, "mergedAt": "2026-09-14T19:15:37Z", "body": "", "comments": [],
})
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][8] == "",
    "tier_label is empty when --issue-json was not supplied",
    f"rows={rows}, stderr={result.stderr!r}",
)

# -- criterion 8: issue from closingIssuesReferences, then from a Closes #n -
#    match in the body.
result = run({
    "number": 308, "mergedAt": "2026-09-14T19:15:37Z", "body": "Closes #999",
    "closingIssuesReferences": [{"number": 123}], "comments": [],
})
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][2] == "123",
    "issue prefers closingIssuesReferences[0].number over a Closes #n body match",
    f"rows={rows}, stderr={result.stderr!r}",
)

result = run({
    "number": 309, "mergedAt": "2026-09-14T19:15:37Z",
    "body": "Fixes the bug.\nCloses #42\n", "comments": [],
})
rows = rows_of(result)
check(
    result.returncode == 0 and rows[0][2] == "42",
    "issue falls back to a Closes #n match in the pull request body",
    f"rows={rows}, stderr={result.stderr!r}",
)

# -- criterion 9: timestamp normalisation and determinism. ------------------
result = run({
    "number": 310, "mergedAt": "2026-09-14T19:15:37.482Z", "body": "",
    "comments": [],
})
rows = rows_of(result)
result_again = run({
    "number": 310, "mergedAt": "2026-09-14T19:15:37.482Z", "body": "",
    "comments": [],
})
check(
    result.returncode == 0
    and rows[0][0] == "2026-09-14T19:15:37Z"
    and result.stdout == result_again.stdout,
    "mergedAt normalises to YYYY-MM-DDTHH:MM:SSZ and repeats byte-identically",
    f"rows={rows}, again={result_again.stdout!r}, stderr={result.stderr!r}",
)

# -- criterion 10: a session record whose JSON does not parse is skipped, ---
#    named on stderr, and the rest of the rows still print with exit 0.
result = run({
    "number": 311, "mergedAt": "2026-09-14T19:15:37Z", "body": "",
    "comments": [
        {"body": "<!-- agent-session-record\nnot valid json\n-->"},
        {"body": session_record_body(**SESSION_A)},
    ],
})
rows = rows_of(result)
check(
    result.returncode == 0
    and len(rows) == 2
    and rows[1][4] == "implementer"
    and result.stderr.strip() != "",
    "a session-record comment with unparseable JSON is skipped with a"
    " diagnostic, exit 0, and every other row still prints",
    f"exit {result.returncode}, rows={rows}, stderr={result.stderr!r}",
)

# -- criterion 11: an unreadable or non-JSON --pr-json is fatal. ------------
missing = case_dir / "does-not-exist.json"
result = subprocess.run(
    [sys.executable, str(script), "--pr-json", str(missing), "--run-url", "u"],
    capture_output=True, text=True,
)
check(
    result.returncode != 0 and result.stdout == "" and result.stderr.strip() != "",
    "a missing --pr-json prints nothing to stdout, a diagnostic to stderr,"
    " and exits non-zero",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

not_json = case_dir / "not-json.json"
not_json.write_text("not actually json {{{", encoding="utf-8")
result = subprocess.run(
    [sys.executable, str(script), "--pr-json", str(not_json), "--run-url", "u"],
    capture_output=True, text=True,
)
check(
    result.returncode != 0 and result.stdout == "" and result.stderr.strip() != "",
    "a non-JSON --pr-json prints nothing to stdout, a diagnostic to stderr,"
    " and exits non-zero",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 15: the session-record writers (#297).
#
# `ledger_row.py` (Part 14) reads a three-line `<!-- agent-session-record`
# comment; the five steps checked here are what write one. Both halves of that
# contract are now pinned, and by the same fixture: each step is extracted and
# run against a stub `gh`, and the comment bodies it produces are fed straight
# into `ledger_row.py`. A writer that grows a ninth key, pretty-prints its
# JSON, or wraps the marker in prose fails here rather than silently producing
# ledger rows nobody notices are missing.
#
# The inventory is pinned the way Part 4 pins marker reads: a record step whose
# name is not in RECORDS fails until somebody states which role and which
# fix_round it is supposed to report. A new agent workflow that starts emitting
# records cannot do so unclassified.
#
# The other rule enforced here is the epic's central one: no record step may
# read a session's text. Every ledger field must come from a workflow
# expression or an action output, because a field a model could author is a
# field a model can get wrong.
#
# python3 only, no network, no credentials, no real repository, and every byte
# written under the harness's own work_dir.
# ---------------------------------------------------------------------------

part15 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import csv
import importlib.util
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
import wf

work_dir, repo_root = sys.argv[1], sys.argv[2]
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part15.", dir=work_dir))

MARKER = "<!-- agent-session-record"
FOOTER = "-->"

KEYS = [
    "role", "vendor", "model_requested", "model_resolved",
    "outcome", "duration_seconds", "fix_round", "run_url",
]

# (workflow, step name) -> (role, fix_round) the step is contracted to report.
# `fix_round` is "" for a role that has no fix round, an int where the step
# reports one.
RECORDS = {
    (".github/workflows/agent-02-implement.yml", "Record Implementer Session"):
        ("implementer", ""),
    (".github/workflows/agent-02-implement.yml", "Record Pre-PR Reviewer Session"):
        ("reviewer", ""),
    # 0, not the stubbed FIX_ROUND: this workflow opened the pull request in
    # the same run, so no prior fix can exist and the step says so outright.
    (".github/workflows/agent-02-implement.yml", "Record Pre-PR Fixer Session"):
        ("fixer", 0),
    (".github/workflows/agent-04-review.yml", "Record Reviewer Session"):
        ("reviewer", ""),
    # The prior-marker count "Resolve Fixer Model Tier" already computed,
    # threaded through as FIX_ROUND.
    (".github/workflows/agent-05-fix.yml", "Record Fixer Session"):
        ("fixer", 3),
}

EXPECTED_PER_WORKFLOW = {
    ".github/workflows/agent-02-implement.yml": 3,
    ".github/workflows/agent-04-review.yml": 1,
    ".github/workflows/agent-05-fix.yml": 1,
}

# A ledger field must not be read out of anything a model wrote.
FORBIDDEN = (
    "final-text-file", "assistant-text-file", "review-file", "report-file",
    "FINAL_TEXT", "ASSISTANT_TEXT", "REVIEW_FILE",
)

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def step_blocks(path):
    """(name, code) for every `- name:` step block in a workflow.

    Comment lines are dropped, YAML and embedded-program alike. A step whose
    rationale *quotes* the marker does not emit it, and a step's own comment
    naming `final-text-file` as the thing it deliberately does not read is the
    opposite of a violation -- this is #69's lesson applied to the check
    rather than to the workflow. It also keeps the block boundary honest: a
    step's leading comment block sits above its `- name:` line, so it is read
    as part of the previous step and would otherwise be attributed to it.
    """

    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    starts = [
        (n, re.match(r"^(\s*)- name: (.*)$", line))
        for n, line in enumerate(lines)
    ]
    starts = [(n, m) for n, m in starts if m]

    for index, (n, m) in enumerate(starts):
        end = starts[index + 1][0] if index + 1 < len(starts) else len(lines)
        code = [
            line for line in lines[n:end] if not line.strip().startswith("#")
        ]
        yield m.group(2).strip(), "\n".join(code)


# -- 1: the marker is what ledger_row.py reads. ------------------------------
spec = importlib.util.spec_from_file_location(
    "ledger_row",
    os.path.join(repo_root, ".github", "scripts", "ledger_row.py"),
)
ledger_row = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger_row)

check(
    ledger_row.SESSION_RECORD_HEADER == MARKER
    and ledger_row.SESSION_RECORD_FOOTER == FOOTER,
    f"the marker is exactly `{MARKER}`, matching ledger_row.py",
    f"ledger_row.py reads {ledger_row.SESSION_RECORD_HEADER!r} /"
    f" {ledger_row.SESSION_RECORD_FOOTER!r}, not {MARKER!r} / {FOOTER!r}",
)

# -- 2: every PR-scoped agent workflow emits the marker, and only from steps -
#    this check knows the contract of.
emitting = {}

for path, expected_count in EXPECTED_PER_WORKFLOW.items():
    found = [(name, block) for name, block in step_blocks(path) if MARKER in block]
    emitting[path] = found

    check(
        len(found) == expected_count,
        f"{path} has {expected_count} step(s) emitting the marker",
        f"{path} has {len(found)} step(s) emitting the marker, expected"
        f" {expected_count}: {[name for name, _ in found]}",
    )

    for name, block in found:
        check(
            (path, name) in RECORDS,
            f"{path}: `{name}` is a classified record step",
            f"{path} emits a session record from `{name}`, which this check"
            f" does not know. Add it to RECORDS with the role and fix_round it"
            f" reports.",
        )

        offenders = [needle for needle in FORBIDDEN if needle in block]
        check(
            not offenders,
            f"{path}: `{name}` reads no session text file",
            f"{path}: `{name}` references {offenders} -- a ledger field must"
            f" come from a workflow expression or an action output, never from"
            f" text a model wrote.",
        )

# -- 3: run each record step and read back what it posted. -------------------
bin_dir = part_dir / "bin"
bin_dir.mkdir()
gh_stub = bin_dir / "gh"
gh_stub.write_text(
    "#!/usr/bin/env bash\n"
    "set -uo pipefail\n"
    "body=\"\"\n"
    "while [ $# -gt 0 ]; do\n"
    "  if [ \"$1\" = \"--body-file\" ]; then body=\"$2\"; fi\n"
    "  shift\n"
    "done\n"
    "printf '%s' \"$body\" > \"$GH_STUB_CAPTURE_PATH\"\n"
    "cat \"$body\" > \"$GH_STUB_CAPTURE\"\n"
    "if [ \"${GH_STUB_EXIT:-0}\" != \"0\" ]; then\n"
    "  echo 'gh: stubbed refusal' >&2\n"
    "  exit \"$GH_STUB_EXIT\"\n"
    "fi\n",
    encoding="utf-8",
)
gh_stub.chmod(0o755)

outcome_file = part_dir / "agent-outcome.json"
outcome_file.write_text(
    json.dumps({
        "vendor": "anthropic",
        "model": "claude-sonnet-5",
        "reason": "budget_exhausted",
        "headline": "hit a limit",
        "assistant_text_chars": 1200,
    }),
    encoding="utf-8",
)

RUN_URL = "https://example.invalid/o/r/actions/runs/7"

BASE_ENV = {
    "PR_URL": "https://github.com/o/r/pull/300",
    "PR_NUMBER": "300",
    "VENDOR": "anthropic",
    "MODELS": "claude-opus-5, claude-sonnet-5",
    "MODEL_RESOLVED": "claude-sonnet-5",
    "OUTCOME_FILE": str(outcome_file),
    "DURATION_SECONDS": "42",
    "FIX_ROUND": "3",
    "RUN_URL": RUN_URL,
    "GITHUB_REPOSITORY": "o/r",
}


def run_record_step(
    path, name, overrides=None, exit_code="0", runner_temp=None
):
    """Run one record step as the workflow runs it, in its own scratch.

    `runner_temp` overrides the scratch the step sees, for the multi-session
    simulation in check 7: three steps of one job share one $RUNNER_TEMP, and
    that sharing is the whole thing being tested.
    """

    case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
    source = case / "step.py"
    source.write_text(
        wf.step_source(path, name, shell="python"), encoding="utf-8"
    )

    capture = case / "posted-body.md"
    capture_path = case / "posted-path.txt"

    env = dict(os.environ)
    env.update(BASE_ENV)
    env.update(overrides or {})
    env.update({
        "RUNNER_TEMP": str(runner_temp or case),
        "GH_STUB_CAPTURE": str(capture),
        "GH_STUB_CAPTURE_PATH": str(capture_path),
        "GH_STUB_EXIT": exit_code,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
    })

    result = subprocess.run(
        [sys.executable, str(source)],
        capture_output=True, text=True, cwd=str(case), env=env,
    )

    body = capture.read_text(encoding="utf-8") if capture.is_file() else None
    written_to = (
        capture_path.read_text(encoding="utf-8") if capture_path.is_file() else ""
    )
    return result, body, written_to, case


bodies = []

for (path, name), (role, fix_round) in RECORDS.items():
    result, body, written_to, case = run_record_step(path, name)

    if result.returncode != 0 or body is None:
        check(
            False,
            "",
            f"{path}: `{name}` did not post a record (exit"
            f" {result.returncode}): stdout={result.stdout!r},"
            f" stderr={result.stderr!r}",
        )
        continue

    lines = body.strip("\n").splitlines()
    shape_ok = (
        len(lines) == 3 and lines[0] == MARKER and lines[2] == FOOTER
    )
    check(
        shape_ok,
        f"{path}: `{name}` posts exactly three lines, marker and closer",
        f"{path}: `{name}` posted {len(lines)} line(s): {body!r}",
    )

    if not shape_ok:
        continue

    check(
        written_to.startswith(str(case)),
        f"{path}: `{name}` builds its body under $RUNNER_TEMP",
        f"{path}: `{name}` posted {written_to!r}, which is not under its"
        f" RUNNER_TEMP ({case})",
    )

    try:
        record = json.loads(lines[1])
    except ValueError as exc:
        check(False, "", f"{path}: `{name}` wrote unparseable JSON: {exc}")
        continue

    check(
        list(record) == KEYS,
        f"{path}: `{name}` writes exactly the eight contracted keys",
        f"{path}: `{name}` wrote keys {list(record)}, expected {KEYS}",
    )

    check(
        record.get("role") == role
        and record.get("vendor") == "anthropic"
        and record.get("model_requested") == "claude-opus-5"
        and record.get("model_resolved") == "claude-sonnet-5"
        and record.get("outcome") == "budget_exhausted"
        and record.get("duration_seconds") == 42
        and record.get("fix_round") == fix_round
        and record.get("run_url") == RUN_URL,
        f"{path}: `{name}` reports role={role!r}, the resolved vendor and"
        f" model, the classifier outcome, 42s and fix_round={fix_round!r}",
        f"{path}: `{name}` wrote {record!r}",
    )

    bodies.append(body)

# -- 4: an unset duration output degrades to the empty string, not a crash. --
path, name = ".github/workflows/agent-04-review.yml", "Record Reviewer Session"
result, body, _, _ = run_record_step(
    path, name, overrides={"DURATION_SECONDS": "", "VENDOR": ""}
)
record = json.loads(body.strip("\n").splitlines()[1]) if body else {}
check(
    result.returncode == 0
    and record.get("duration_seconds") == ""
    and record.get("vendor") == "",
    "an unset duration or vendor output becomes the empty string",
    f"exit {result.returncode}, record={record!r}, stderr={result.stderr!r}",
)

# -- 5: a refused `gh` warns and still exits 0. ------------------------------
result, _, _, _ = run_record_step(
    ".github/workflows/agent-05-fix.yml", "Record Fixer Session", exit_code="1"
)
check(
    result.returncode == 0 and "::warning::" in result.stdout,
    "a refused comment post prints a ::warning:: and exits 0",
    f"exit {result.returncode}, stdout={result.stdout!r},"
    f" stderr={result.stderr!r}",
)

# -- 6: ledger_row.py turns those exact bodies into one session row each. ----
pr_json = part_dir / "pr.json"
pr_json.write_text(
    json.dumps({
        "number": 300,
        "mergedAt": "2026-09-14T19:15:37Z",
        "body": "Closes #297",
        "comments": [{"body": body} for body in bodies],
    }),
    encoding="utf-8",
)

result = subprocess.run(
    [sys.executable,
     os.path.join(repo_root, ".github", "scripts", "ledger_row.py"),
     "--pr-json", str(pr_json), "--run-url", "https://example.invalid/ledger"],
    capture_output=True, text=True,
)
rows = list(csv.reader(io.StringIO(result.stdout)))
session_rows = [row for row in rows if row[1] == "session"]

check(
    result.returncode == 0
    and len(bodies) == len(RECORDS)
    and len(session_rows) == len(bodies)
    and all(row[5] == "anthropic" for row in session_rows)
    and all(row[6] == "claude-opus-5" for row in session_rows)
    and all(row[7] == "claude-sonnet-5" for row in session_rows)
    and all(row[11] == "budget_exhausted" for row in session_rows)
    and all(row[12] == "42" for row in session_rows)
    and all(row[13] == RUN_URL for row in session_rows)
    and sorted(row[4] for row in session_rows)
    == sorted(role for role, _ in RECORDS.values()),
    f"ledger_row.py reads the posted bodies as {len(bodies)} session row(s),"
    " one per comment, with matching field values",
    f"exit {result.returncode}, rows={rows}, stderr={result.stderr!r}",
)

# -- 7: three sessions in one job, each record reading its own outcome. ------
#
# The check above injects OUTCOME_FILE per case, so it cannot see the thing
# that actually went wrong in #307's first cycle: `run-agent-session`'s
# `outcome-file` output is a fixed per-job path, all three of
# agent-02-implement.yml's sessions write it, and all three record steps run at
# the *end* of the job -- so each of them read whichever session happened to
# run last, under its own session's name.
#
# So this runs the job's shape rather than a step's: the shared outcome slot is
# rewritten before each session's snapshot step, exactly as the classifier
# rewrites it, and only then are the three record steps run. Each must still
# report its own session's verdict. `reason` values are from the vocabulary
# docs/RUN_LEDGER.md pins for the `outcome` column, and all three differ, so a
# record reading the wrong file cannot accidentally pass.
JOB = ".github/workflows/agent-02-implement.yml"

SESSIONS = [
    ("Snapshot Implementer Session Outcome",
     "Record Implementer Session", "completed"),
    ("Snapshot Pre-PR Reviewer Session Outcome",
     "Record Pre-PR Reviewer Session", "budget_exhausted"),
    ("Snapshot Pre-PR Fixer Session Outcome",
     "Record Pre-PR Fixer Session", "session_error"),
]


def outcome_file_expr(path, name):
    """The OUTCOME_FILE expression one record step is wired to read."""

    for step_name, block in step_blocks(path):
        if step_name == name:
            # `.+?` rather than `\S+`: the value is a `${{ runner.temp }}`
            # expression, and those carry spaces inside the braces.
            m = re.search(r"^\s*OUTCOME_FILE:\s*(.+?)\s*$", block, re.M)
            return m.group(1) if m else None

    return None


def run_bash_step(path, name, runner_temp):
    """Run one `shell: bash` step against a given $RUNNER_TEMP."""

    case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
    source = case / "step.sh"
    source.write_text(
        wf.step_source(path, name, shell="bash"), encoding="utf-8"
    )

    env = dict(os.environ)
    env["RUNNER_TEMP"] = str(runner_temp)

    return subprocess.run(
        ["bash", str(source)],
        capture_output=True, text=True, cwd=str(case), env=env,
    )


exprs = {name: outcome_file_expr(JOB, name) for _, name, _ in SESSIONS}

check(
    all(exprs.values()) and len(set(exprs.values())) == len(exprs),
    f"{JOB}: its three record steps read three distinct outcome paths",
    f"{JOB}: record steps read {exprs!r} -- two record steps resolving to one"
    f" path at the end of the job means one of them reports the other"
    f" session's verdict.",
)


def simulate_job(sessions):
    """Run the job's sessions in order, then all of its record steps.

    `sessions` is (snapshot step, record step, reason or None); None means that
    session failed before its classifier wrote anything, which is the path
    where a stale slot would be read as this session's own verdict. Returns
    {record step: outcome it reported}.
    """

    sim = pathlib.Path(tempfile.mkdtemp(dir=part_dir, prefix="job."))
    slot = sim / "agent-outcome.json"

    for snapshot_name, _, reason in sessions:
        if reason is not None:
            # What the session's classifier does: overwrite the one slot.
            slot.write_text(
                json.dumps({
                    "vendor": "anthropic",
                    "model": "claude-sonnet-5",
                    "reason": reason,
                    "headline": reason,
                    "assistant_text_chars": 10,
                }),
                encoding="utf-8",
            )

        snapped = run_bash_step(JOB, snapshot_name, sim)
        check(
            snapped.returncode == 0,
            f"{JOB}: `{snapshot_name}` runs clean",
            f"{JOB}: `{snapshot_name}` exited {snapped.returncode}:"
            f" stdout={snapped.stdout!r}, stderr={snapped.stderr!r}",
        )

    reported = {}

    for _, record_name, _ in sessions:
        resolved = (exprs[record_name] or "").replace(
            "${{ runner.temp }}", str(sim)
        )
        result, body, _, _ = run_record_step(
            JOB, record_name,
            overrides={"OUTCOME_FILE": resolved}, runner_temp=sim,
        )

        if result.returncode != 0 or body is None:
            check(
                False,
                "",
                f"{JOB}: `{record_name}` posted nothing in the multi-session"
                f" simulation (exit {result.returncode}):"
                f" stderr={result.stderr!r}",
            )
            continue

        reported[record_name] = json.loads(
            body.strip("\n").splitlines()[1]
        ).get("outcome")

    return reported


reported = simulate_job(SESSIONS)
expected = {name: reason for _, name, reason in SESSIONS}

check(
    reported == expected,
    f"{JOB}: after three sessions share one outcome slot, each record still"
    f" reports its own session's verdict",
    f"{JOB}: records reported {reported!r}, expected {expected!r} -- a record"
    f" carrying another session's outcome is the epic's central field silently"
    f" wrong, and nothing downstream of .metrics/runs.csv can detect it.",
)

# -- 8: a session that never classified reports nothing, not its predecessor's.
#
# The corollary of check 7, and why the snapshot moves the file out of the
# shared slot instead of copying it: a session that died before its classifier
# ran leaves the previous session's verdict sitting in the slot, and "" is the
# contracted value for an outcome this job does not know.
stalled = [
    (SESSIONS[0][0], SESSIONS[0][1], "completed"),
    (SESSIONS[1][0], SESSIONS[1][1], None),
]
reported = simulate_job(stalled)

check(
    reported.get(SESSIONS[0][1]) == "completed"
    and reported.get(SESSIONS[1][1]) == "",
    f"{JOB}: a session that left no outcome file records an empty outcome"
    f" rather than the previous session's",
    f"{JOB}: records reported {reported!r}, expected the implementer's"
    f" `completed` and an empty reviewer outcome.",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 16: the smoke stage's verdicts and its job's shape (#312).
#
# The smoke stage exists to catch the one failure an export gate cannot: a
# build that is produced, published, downloaded, started -- and never reaches
# an end state. Its whole value is in the verdict it returns, and a verdict is
# exactly the thing that can quietly invert. `smoke-godot.sh` is therefore run
# here against four fake executables rather than a real build: a marker with
# exit 0, an exit 0 with no marker, a non-zero exit, and one that never exits
# at all. Fakes, not Godot, because this part must run on a bare runner in
# seconds and because the cases it pins -- above all "exited 0 having done
# nothing" -- are awkward to provoke from a real engine on purpose.
#
# The sleeper is the reason the timeout is a feature and not a comment: it
# sleeps far past the deliberately short SMOKE_TIMEOUT_SECONDS given to it, so
# a script that waited on its child instead of killing it would fail here by
# taking a minute, rather than by hanging a CI runner months from now.
#
# The second half asserts the job stays a thin wrapper: identical artifact name
# to the export job's upload, `chmod +x` before the run, logs uploaded on
# failure, everything under $RUNNER_TEMP -- and no `setup-godot`, no
# `export-godot.sh`, no Godot version literal anywhere in it. A smoke job that
# grew its own engine install would be verifying a rebuild rather than the
# bytes the export stage published, which is the one thing this stage promises.
#
# python3 and bash only, no network, no credentials, no engine, and every byte
# written under the harness's own work_dir.
# ---------------------------------------------------------------------------

part16 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

work_dir, repo_root = sys.argv[1], sys.argv[2]
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part16.", dir=work_dir))

SCRIPT = pathlib.Path(repo_root, ".github/scripts/smoke-godot.sh")
CI = pathlib.Path(".github/workflows/ci.yml")

# Short enough that a failing timeout is caught in seconds, long enough that a
# loaded runner's process spawn does not trip it. The sleeper sleeps twenty
# times this.
SHORT_TIMEOUT = 3
SLEEP_SECONDS = 60

failures = []


def check(ok, ok_msg, fail_msg):
    if ok:
        print(f"  ok   — {ok_msg}")
    else:
        failures.append(fail_msg)
        print(f"  FAIL — {fail_msg}", file=sys.stderr)


# --- The four fakes --------------------------------------------------------
# Each stands in for one thing an exported build can do. The marker's text is
# the engine's, character for character -- `SmokeMatchDriver.MARKER_FORMAT`
# filled in -- because a script that accepted some looser shape would pass a
# build that printed nothing of the kind.
FAKES = {
    "complete": (
        'echo "Smoke match complete: 4 rounds, 17 turns."\n'
        "exit 0\n"
    ),
    "no-marker": (
        'echo "booted, and quit again having played nothing"\n'
        "exit 0\n"
    ),
    "crashed": (
        'echo "SCRIPT ERROR: something the build did not survive" >&2\n'
        "exit 3\n"
    ),
    "hung": (
        'echo "waiting for a turn nobody is going to take"\n'
        f"sleep {SLEEP_SECONDS}\n"
    ),
}

for name, body in FAKES.items():
    fake = part_dir / name
    fake.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    fake.chmod(0o755)


def run_smoke(name):
    """Run the script against one fake. Returns (returncode, output, seconds)."""

    env = dict(os.environ)
    env["SMOKE_TIMEOUT_SECONDS"] = str(SHORT_TIMEOUT)
    env["SMOKE_LOG_DIR"] = str(part_dir / f"logs-{name}")

    started = time.monotonic()
    try:
        proc = subprocess.run(
            [str(SCRIPT), str(part_dir / name)],
            cwd=repo_root,
            env=env,
            capture_output=True,
            text=True,
            # A backstop on the harness itself, not the assertion: the
            # sleeper's own bound is checked below. Without it a script that
            # failed to cap its child would hang this test instead of failing
            # it.
            timeout=SLEEP_SECONDS + 30,
        )
    except subprocess.TimeoutExpired:
        return None, "", time.monotonic() - started

    return proc.returncode, proc.stdout + proc.stderr, time.monotonic() - started


code_pass, out_pass, _ = run_smoke("complete")
code_no_marker, out_no_marker, _ = run_smoke("no-marker")
code_crashed, out_crashed, _ = run_smoke("crashed")
code_hung, out_hung, elapsed_hung = run_smoke("hung")

check(
    code_pass == 0,
    "a run that exits 0 having printed the completion marker passes",
    f"smoke-godot.sh returned {code_pass!r} for a build that printed the"
    f" marker and exited 0; it must be the one case that passes."
    f"\n         Output: {out_pass.strip()[:400]}",
)

check(
    code_no_marker not in (0, None),
    "a run that exits 0 without the marker fails",
    f"smoke-godot.sh returned {code_no_marker!r} for a build that exited 0"
    f" having printed no marker. Exit 0 is never sufficient -- a build that"
    f" boots and quits having played nothing exits 0 too.",
)

check(
    code_crashed not in (0, None),
    "a run that exits non-zero fails",
    f"smoke-godot.sh returned {code_crashed!r} for a build that exited 3.",
)

check(
    code_hung not in (0, None),
    "a run that never exits fails",
    f"smoke-godot.sh returned {code_hung!r} for a build that never exits.",
)

check(
    elapsed_hung < SHORT_TIMEOUT + 25,
    f"the sleeper is killed at SMOKE_TIMEOUT_SECONDS"
    f" ({elapsed_hung:.1f}s against a {SHORT_TIMEOUT}s cap and a"
    f" {SLEEP_SECONDS}s sleep)",
    f"smoke-godot.sh took {elapsed_hung:.1f}s to report on a build that sleeps"
    f" {SLEEP_SECONDS}s under a {SHORT_TIMEOUT}s cap -- it is waiting on the"
    f" child rather than killing it, which is a CI runner held to the job"
    f" timeout with no diagnosis attached.",
)

# --- The three failures are told apart ------------------------------------
# One non-zero exit for three causes is a stage whose log says only that
# something went wrong. Each failure names itself, greppably.
VERDICTS = {
    "no-marker": (out_no_marker, r"exited 0 but printed no completion marker"),
    "crashed": (out_crashed, r"exited non-zero \(exit 3\)"),
    "hung": (out_hung, rf"timed out after {SHORT_TIMEOUT}s"),
}

for name, (out, pattern) in VERDICTS.items():
    check(
        re.search(pattern, out) is not None,
        f"the {name} failure reports its own distinct cause",
        f"smoke-godot.sh's output for the {name} case matches no"
        f" /{pattern}/ -- three causes reported alike is a stage whose log"
        f" says only that something went wrong."
        f"\n         Output: {out.strip()[:400]}",
    )

# Every failure path prints the captured output and the paths of both files it
# wrote: without them a CI reader has an uploaded artifact and no idea which
# file in it is which.
EVIDENCE = {
    "no-marker": (out_no_marker, "booted, and quit again having played nothing"),
    "crashed": (out_crashed, "SCRIPT ERROR: something the build did not survive"),
    "hung": (out_hung, "waiting for a turn nobody is going to take"),
}

for name, (out, echoed) in EVIDENCE.items():
    missing = [
        label
        for label, needle in (
            ("the captured output", echoed),
            ("the stdout/stderr file path", "smoke-stdout.log"),
            ("the engine log file path", "smoke-engine.log"),
        )
        if needle not in out
    ]
    check(
        not missing,
        f"the {name} failure prints the captured output and both file paths",
        f"smoke-godot.sh's {name} failure omits {', '.join(missing)}.",
    )

# --- The script verifies a build; it never produces one --------------------
# Asserted over non-comment lines: the header prose may name `export-godot.sh`
# as the script it is modelled on, and does. Running it would be another
# matter.
script_code = "\n".join(
    line
    for line in SCRIPT.read_text(encoding="utf-8").splitlines()
    if not line.lstrip().startswith("#")
)

for token, why in (
    ("--export-release", "exporting is the previous stage's job"),
    ("export-godot.sh", "the stage verifies the published bytes, never a rebuild"),
    ("setup-godot", "there is no engine to install to run an exported build"),
    ("--path", "the argument is a built executable, never a project directory"),
):
    check(
        token not in script_code,
        f"smoke-godot.sh runs no {token}",
        f"smoke-godot.sh's executable lines contain {token} -- {why}.",
    )

check(
    "--headless" in script_code and "-- --smoke" in script_code,
    "smoke-godot.sh runs the executable with --headless -- --smoke",
    "smoke-godot.sh does not invoke the executable with `--headless` and a"
    " bare `--` before `--smoke`; without the separator the flag never"
    " reaches OS.get_cmdline_user_args() and the build plays no match.",
)

# --- The job stays a thin wrapper ------------------------------------------
ci_lines = CI.read_text(encoding="utf-8").splitlines()


def job_block(job):
    """The lines of one job, from its key to the next thing at job indent.

    Stops at the first non-blank line indented two spaces or less, comments
    included -- the comment introducing the NEXT job sits there, and sweeping
    it in would have this part asserting things about a job it is not reading.
    """

    try:
        start = ci_lines.index(f"  {job}:")
    except ValueError:
        return None

    out = []
    for line in ci_lines[start + 1:]:
        if line.strip() and (len(line) - len(line.lstrip())) <= 2:
            break
        out.append(line)
    return "\n".join(out)


smoke = job_block("smoke")
export = job_block("export")
ci_job = job_block("ci")

if smoke is None or export is None or ci_job is None:
    missing = [
        n for n, b in (("smoke", smoke), ("export", export), ("ci", ci_job))
        if b is None
    ]
    print(
        f"  FAIL — {CI} declares no {', '.join(missing)} job",
        file=sys.stderr,
    )
    sys.exit(1)

check(
    re.search(r"^\s*needs:\s*\[changes, godot, export\]\s*$", smoke, re.M)
    is not None,
    "the smoke job needs [changes, godot, export]",
    "the smoke job's `needs:` is not [changes, godot, export] -- it has"
    " nothing to download until the export job has run.",
)

smoke_if = re.search(r"^\s*if:\s*(.+)$", smoke, re.M)
export_if = re.search(r"^\s*if:\s*(.+)$", export, re.M)
check(
    smoke_if is not None
    and export_if is not None
    and smoke_if.group(1).strip() == export_if.group(1).strip(),
    "the smoke job carries the export job's gate verbatim",
    f"the smoke job's gate is"
    f" {smoke_if.group(1).strip() if smoke_if else None!r} but the export"
    f" job's is {export_if.group(1).strip() if export_if else None!r}. A"
    f" docs-only pull request must skip both alike, so that `ci` -- which"
    f" counts `skipped` as passing -- stays green without either running.",
)

check(
    re.search(r"^\s*timeout-minutes:\s*\d+\s*$", smoke, re.M) is not None,
    "the smoke job declares a timeout-minutes backstop",
    "the smoke job declares no `timeout-minutes:` -- the script's own cap is"
    " the diagnosed bound, but nothing else bounds a runner wedged outside"
    " it.",
)

# The artifact name, character for character. A download naming anything else
# fails the stage for a reason that has nothing to do with the build.
smoke_artifact = re.findall(r"^\s*name:\s*(godot-linux-.+)$", smoke, re.M)
export_artifact = re.findall(r"^\s*name:\s*(godot-linux-.+)$", export, re.M)
check(
    len(smoke_artifact) == 1
    and len(export_artifact) == 1
    and smoke_artifact[0].strip() == export_artifact[0].strip(),
    "the smoke job downloads the exact artifact name the export job uploads",
    f"the smoke job downloads {smoke_artifact!r} while the export job uploads"
    f" {export_artifact!r}. These must be one string, head-SHA fallback"
    f" included.",
)

check(
    "uses: actions/download-artifact@v4" in smoke,
    "the smoke job downloads the published artifact",
    "the smoke job has no `actions/download-artifact@v4` step -- it must run"
    " the bytes the export stage published, not a rebuild.",
)

check(
    re.search(r"chmod \+x", smoke) is not None,
    "the smoke job chmod +x's the downloaded binary",
    "the smoke job never `chmod +x`'s the downloaded executable. The"
    " executable bit does not survive the artifact round trip, so the run"
    " would fail on a permission error rather than on the build.",
)

check(
    ".github/scripts/smoke-godot.sh" in smoke,
    "the smoke job runs the repository's smoke script",
    "the smoke job does not call `.github/scripts/smoke-godot.sh` -- the"
    " stage's logic lives in the script so that a local run and a CI run mean"
    " the same thing.",
)

# Steps, split on the `- name:` that opens each one, so a condition is read
# against the step it actually belongs to.
steps = []
for line in smoke.splitlines():
    if line.lstrip().startswith("- name:"):
        steps.append([line])
    elif steps:
        steps[-1].append(line)

upload_steps = [
    "\n".join(s) for s in steps if "uses: actions/upload-artifact" in "\n".join(s)
]
check(
    len(upload_steps) == 1
    and re.search(r"^\s*if:\s*failure\(\)\s*$", upload_steps[0], re.M) is not None,
    "the smoke job uploads its logs, and only when the run failed",
    "the smoke job has no single log-upload step conditioned on `failure()`."
    " A green run's logs say nothing the step log does not; a red one is"
    " exactly when the engine's own log is needed.",
)

for token, why in (
    ("setup-godot", "installing an engine here would verify a rebuild"),
    ("export-godot.sh", "the stage runs the published bytes, never a new build"),
    ("--export-release", "exporting is the previous stage's job"),
):
    check(
        token not in smoke,
        f"the smoke job references no {token}",
        f"the smoke job references {token} -- {why}.",
    )

# A version literal here would be a new pin site (Part 7's rule), and this job
# has no business naming an engine version at all: it never installs one.
version_literals = re.findall(
    r"\b\d+\.\d+(?:\.\d+)?-(?:stable|beta\d*|rc\d*|dev\d*)\b", smoke
) + re.findall(r"^\s*godot-version:\s*\S", smoke, re.M)
check(
    not version_literals,
    "the smoke job names no Godot version",
    f"the smoke job names Godot version(s) {version_literals!r}. It installs"
    f" no engine, so any version here is a new pin site that Part 7 would"
    f" have to keep in agreement for nothing.",
)

# Every path the job writes is under $RUNNER_TEMP: #84 is what Part 5
# remembers, and a job that downloads a binary into the checkout is the same
# class of mistake.
stray = []
for line in smoke.splitlines():
    m = re.match(r"^\s*(?:path|[A-Z][A-Z0-9_]*):\s*(\S.*?)\s*$", line)
    if not m:
        continue
    value = m.group(1)
    if "/" not in value or value.startswith((".github/", "./.github/")):
        continue
    if "runner.temp" not in value:
        stray.append(value)

check(
    not stray,
    "every path the smoke job names is under ${{ runner.temp }}",
    f"the smoke job writes outside $RUNNER_TEMP: {stray!r}. A downloaded"
    f" build inside the checkout is #84 repeating.",
)

needs = re.search(r"needs:\s*\[(.*?)\]", ci_job, re.S)
check(
    needs is not None and "smoke" in [n.strip() for n in needs.group(1).split(",")],
    "the ci aggregate check needs the smoke job",
    "`smoke` is not in the `ci` job's `needs:` list, so a failed smoke run"
    " would leave the one required status check green.",
)

# Part 5's rule, stated for this stage: changing how a gate runs must still
# run that gate. The deny-list already says so for validate-godot.sh and
# setup-godot/.
deny = re.search(r"GODOT_DENY = \[(.*?)^\s*\]", CI.read_text(encoding="utf-8"),
                 re.S | re.M)
check(
    deny is not None and "smoke-godot.sh" not in deny.group(1),
    "smoke-godot.sh is not on the Godot deny-list",
    "ci.yml's GODOT_DENY lists smoke-godot.sh, so a pull request changing how"
    " the smoke stage runs would skip the stage it changed.",
)

if not failures:
    print(f"  ok   — {len(FAKES)} fake builds judged, and the smoke job's"
          f" shape pinned")

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 17: red-gate.py picks the suites in scope and judges the base log
# (#327).
#
# Part 12's shape, for the same reason: red-gate.py's two modes are decided
# entirely by files, so synthetic fixture trees and fixture logs pin them
# without Godot, without git and without the repository's own tree, whose
# suites and log lines change over time. Every fixture is written under this
# harness's own work_dir via tempfile.mkdtemp(), never into the checkout.
#
# What each case is here to stop:
#
#   green/red      A gate that cannot tell a suite that failed at the merge
#                  base from one that passed there is not a gate.
#   no suite lines A bootstrap that failed to compile prints no PASS/FAIL line
#                  at all. Folding that into `red` would hide the most
#                  generous verdict this gate gives.
#   free-text FAIL Suites print their own violations as `FAIL <text>`
#                  (rules/tests/charge_lockout_test.gd:61 and siblings). A
#                  prefix match reads those as suite results and calls a green
#                  suite red.
#   comment-only   A docstring edit cannot honestly produce a red run, so it
#                  must not be asked to.
#   no test files  The epic is explicit that such a pull request neither
#                  passes nor fails this gate.
#   transitive     Attribution has to follow count-tests.py's reachability
#                  definition, not the file's own name.
#   deleted        A deleted file cannot be run at all.
#   bad inputs     Exit 2 is a broken gate and exit 1 is a verdict a label may
#                  downgrade. Blurring them makes the label downgrade a
#                  malfunction.
#
# python3 only, no network, no credentials: red-gate.py is invoked as a
# subprocess exactly as CI would run it, so what is checked is the script that
# actually ships.
# ---------------------------------------------------------------------------

part17 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
script = pathlib.Path(repo_root) / ".github" / "scripts" / "red-gate.py"

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def write_tree(base, files):
    for rel, content in files.items():
        path = base / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def fixture_dir(prefix):
    return pathlib.Path(tempfile.mkdtemp(prefix=prefix, dir=work_dir))


def bootstrap(entries):
    """A `_suites` literal in the shape tests/test_bootstrap.gd uses: a
    display name, which is what `_check()` prints, and a `X.run` Callable."""
    body = "".join(
        f'\t{{"name": "{display}", "run": {cls}.run}},\n' for display, cls in entries
    )
    return f"extends Node\n\nvar _suites: Array[Dictionary] = [\n{body}]\n"


def suite_source(class_name, functions=(), calls=()):
    lines = [f"class_name {class_name}", ""]
    for name, assertion in functions:
        lines.append(f"static func {name}() -> Array:")
        lines.append(f'\treturn _expect({assertion}, "{name}")')
        lines.append("")
    lines.append("static func run() -> bool:")
    for other in calls:
        lines.append(f"\tif not {other}.run():")
        lines.append("\t\treturn false")
    for name, _ in functions:
        lines.append(f"\tif not {name}().is_empty():")
        lines.append("\t\treturn false")
    lines.append("\treturn true")
    return "\n".join(lines) + "\n"


def plan(base_root, head_root, changed, name="changed.txt"):
    """Run `plan` and return (CompletedProcess, parsed JSON or {})."""
    listing = pathlib.Path(head_root).parent / name
    listing.write_text("\n".join(changed) + "\n", encoding="utf-8")
    result = subprocess.run(
        [
            sys.executable, str(script), "plan",
            "--base-root", str(base_root),
            "--head-root", str(head_root),
            "--changed-files", str(listing),
        ],
        capture_output=True,
        text=True,
    )
    try:
        return result, json.loads(result.stdout)
    except json.JSONDecodeError:
        return result, {}


def verdict(plan_path, log_path):
    return subprocess.run(
        [
            sys.executable, str(script), "verdict",
            "--plan", str(plan_path), "--base-log", str(log_path),
        ],
        capture_output=True,
        text=True,
    )


def write_plan(directory, document, name="plan.json"):
    path = pathlib.Path(directory) / name
    path.write_text(json.dumps(document, indent=2, sort_keys=True), encoding="utf-8")
    return path


def write_log(directory, text, name="base.log"):
    path = pathlib.Path(directory) / name
    path.write_text(text, encoding="utf-8")
    return path


# A tree with one registered suite that reaches a second suite only through
# its own run(). Reused by most cases below; each case gets its own copy so a
# case can edit its head without disturbing another's.
def standard_trees(prefix, head_beta, base_beta):
    case = fixture_dir(prefix)
    base_root = case / "base"
    head_root = case / "head"
    boot = bootstrap([("Alpha Suite", "AlphaTest"), ("Gamma Suite", "GammaTest")])
    alpha = suite_source("AlphaTest", calls=["BetaTest"])
    gamma = suite_source("GammaTest", functions=[("_test_gamma", "true")])
    for root, beta in ((base_root, base_beta), (head_root, head_beta)):
        files = {
            "tests/test_bootstrap.gd": boot,
            "tests/alpha_test.gd": alpha,
            "rules/tests/gamma_test.gd": gamma,
        }
        if beta is not None:
            files["tests/beta_test.gd"] = beta
        write_tree(root, files)
    return case, base_root, head_root


BETA_BASE = suite_source("BetaTest", functions=[("_test_beta", "true")])
BETA_HEAD = suite_source(
    "BetaTest",
    functions=[("_test_beta", "true"), ("_test_new_behaviour", "false")],
)

# -- 7: a test file reachable only transitively is attributed to the ---------
#       registered suite that reaches it.
case7, base7, head7 = standard_trees("rg-case7.", BETA_HEAD, BETA_BASE)
result, document = plan(base7, head7, ["tests/beta_test.gd", "rules/state.gd"])
in_scope = document.get("in_scope", [])
paths = {entry["path"]: entry for entry in document.get("paths", [])}
check(
    result.returncode == 0
    and document.get("gate_applies") is True
    and [entry["suite"] for entry in in_scope] == ["Alpha Suite"]
    and in_scope[0]["files"] == ["tests/beta_test.gd"]
    and in_scope[0]["functions"] == ["_test_new_behaviour"]
    and paths.get("rules/state.gd", {}).get("kind") == "production"
    and paths.get("tests/beta_test.gd", {}).get("kind") == "test",
    "a test file registered nowhere is attributed to the registered suite that"
    " reaches it, and a production path is reported as production",
    f"expected Alpha Suite in scope for tests/beta_test.gd;"
    f" exit {result.returncode}, document={document or result.stdout!r}",
)

plan7 = write_plan(case7, document)

# -- 1: a suite green at the merge base fails the gate, and is named. --------
green_log = write_log(case7, "PASS Alpha Suite\nPASS Gamma Suite\n", "green.log")
result = verdict(plan7, green_log)
check(
    result.returncode == 1
    and "Alpha Suite" in result.stdout
    and "green-at-base" in result.stdout
    and "asserts nothing the pull request changed" in result.stdout,
    "a suite that passed at the merge base exits 1, is named, and the report"
    " says the test asserts nothing the pull request changed",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

# -- 2: a suite red at the merge base satisfies the gate. -------------------
red_log = write_log(case7, "FAIL Alpha Suite\nPASS Gamma Suite\n", "red.log")
result = verdict(plan7, red_log)
check(
    result.returncode == 0
    and "| Alpha Suite | `red` |" in result.stdout
    and "_test_new_behaviour" in result.stdout
    and "verdict unit is the **registered test suite**" in result.stdout,
    "a suite that failed at the merge base exits 0, and the report is printed"
    " with the function names and the unit statement on a passing run too",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

# -- 3: a base log with no suite-level line at all. --------------------------
nothing_log = write_log(
    case7,
    "Godot Engine v4.7.2.stable.official\n"
    "SCRIPT ERROR: Parse Error: Identifier \"Combatant\" not declared.\n"
    "          at: GDScript::reload (res://tests/test_bootstrap.gd:51)\n",
    "nothing.log",
)
result = verdict(plan7, nothing_log)
check(
    result.returncode == 0
    and "| Alpha Suite | `did-not-load` |" in result.stdout
    and "No suite-level result line appears in the merge-base log at all"
    in result.stdout
    and "| Alpha Suite | `red` |" not in result.stdout,
    "a base log with no suite line reports every in-scope suite did-not-load,"
    " exits 0, and says so once at the top rather than calling it red",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

# -- 4: a suite's own `FAIL <violation>` output is not a suite result. -------
violation_log = write_log(
    case7,
    "FAIL beta_test.gd: expected lockout to clear on round end, got 2\n"
    "FAIL Alpha Suite is not this line, it is free text mentioning it\n"
    "PASS Alpha Suite\n"
    "PASS Gamma Suite\n",
    "violations.log",
)
result = verdict(plan7, violation_log)
check(
    result.returncode == 1 and "| Alpha Suite | `green-at-base` |" in result.stdout,
    "free-text `FAIL <violation>` lines are not read as suite results: the"
    " suite's own PASS line still decides, and the gate still exits 1",
    f"expected exit 1 with Alpha Suite green; exit {result.returncode},"
    f" stdout={result.stdout!r}",
)

violation_only_log = write_log(
    case7,
    "FAIL beta_test.gd: expected lockout to clear on round end, got 2\n"
    "FAIL Alpha Suite is not this line either\n",
    "violations-only.log",
)
result = verdict(plan7, violation_only_log)
check(
    result.returncode == 0 and "| Alpha Suite | `did-not-load` |" in result.stdout,
    "a log holding only free-text FAIL lines counts as no suite line at all,"
    " not as a red suite",
    f"expected did-not-load; exit {result.returncode}, stdout={result.stdout!r}",
)

# -- 5: a comment-only change to a test file is not in scope. ---------------
comment_head = BETA_BASE.replace(
    "static func run() -> bool:",
    "## Documented here, and nowhere else.\n"
    "# An ordinary comment too.\n"
    "static func run() -> bool:",
)
case5, base5, head5 = standard_trees("rg-case5.", comment_head, BETA_BASE)
result, document = plan(base5, head5, ["tests/beta_test.gd"])
paths = {entry["path"]: entry for entry in document.get("paths", [])}
check(
    result.returncode == 0
    and document.get("gate_applies") is False
    and document.get("in_scope") == []
    and paths.get("tests/beta_test.gd", {}).get("reason") == "comment-only",
    "a comment-only change to a test file is skipped with reason"
    " comment-only, and the gate does not apply",
    f"exit {result.returncode}, document={document or result.stdout!r}",
)

comment_plan = write_plan(case5, document)
result = verdict(comment_plan, write_log(case5, "PASS Alpha Suite\n"))
check(
    result.returncode == 0 and "the gate does not apply" in result.stdout,
    "verdict on a plan with nothing in scope exits 0 saying the gate does not"
    " apply, rather than passing or failing it",
    f"exit {result.returncode}, stdout={result.stdout!r}",
)

# -- 6: a pull request touching no test file at all. ------------------------
case6, base6, head6 = standard_trees("rg-case6.", BETA_BASE, BETA_BASE)
result, document = plan(
    base6, head6, ["rules/state.gd", "docs/hex-skirmish-game-spec.md"]
)
check(
    result.returncode == 0
    and document.get("gate_applies") is False
    and document.get("in_scope") == []
    and [entry["kind"] for entry in document.get("paths", [])]
    == ["production", "production"],
    "a pull request touching no test file puts no suite in scope and both"
    " paths are production",
    f"exit {result.returncode}, document={document or result.stdout!r}",
)

# -- 8: a deleted test file is not in scope. --------------------------------
case8, base8, head8 = standard_trees("rg-case8.", None, BETA_BASE)
result, document = plan(base8, head8, ["tests/beta_test.gd"])
paths = {entry["path"]: entry for entry in document.get("paths", [])}
check(
    result.returncode == 0
    and document.get("gate_applies") is False
    and paths.get("tests/beta_test.gd", {}).get("reason") == "deleted",
    "a test file deleted by the pull request is skipped with reason deleted",
    f"exit {result.returncode}, document={document or result.stdout!r}",
)

# The registry, a .uid sidecar and a non-test file under tests/ are skipped
# too, each with its own recorded reason -- the plan has to say why, not just
# leave them out.
case8b, base8b, head8b = standard_trees("rg-case8b.", BETA_HEAD, BETA_BASE)
write_tree(head8b, {
    "tests/beta_test.gd.uid": "uid://abc123\n",
    "tests/helpers/fixture_builder.gd": "class_name FixtureBuilder\n",
})
result, document = plan(
    base8b,
    head8b,
    [
        "tests/test_bootstrap.gd",
        "tests/beta_test.gd.uid",
        "tests/helpers/fixture_builder.gd",
    ],
)
reasons = {
    entry["path"]: entry["reason"] for entry in document.get("paths", [])
}
check(
    result.returncode == 0
    and document.get("gate_applies") is False
    and reasons.get("tests/test_bootstrap.gd") == "bootstrap-registry"
    and reasons.get("tests/beta_test.gd.uid") == "uid-file"
    and reasons.get("tests/helpers/fixture_builder.gd") == "not-a-test-file",
    "the bootstrap registry, a .uid sidecar and a non-test file under tests/"
    " are each skipped with their own recorded reason",
    f"exit {result.returncode}, reasons={reasons}, stdout={result.stdout!r}",
)

# A suite reachable from no registered suite is skipped, not failed: the
# orphan contract test already fails the build for it.
case8c, base8c, head8c = standard_trees("rg-case8c.", BETA_HEAD, BETA_BASE)
write_tree(head8c, {
    "tests/orphan_test.gd": suite_source(
        "OrphanTest", functions=[("_test_orphan", "true")]
    ),
})
result, document = plan(base8c, head8c, ["tests/orphan_test.gd"])
reasons = {
    entry["path"]: entry["reason"] for entry in document.get("paths", [])
}
check(
    result.returncode == 0
    and document.get("gate_applies") is False
    and reasons.get("tests/orphan_test.gd") == "unreachable",
    "a test file no registered suite reaches is skipped as unreachable, not"
    " demanded red",
    f"exit {result.returncode}, reasons={reasons}, stdout={result.stdout!r}",
)

# -- 9: unusable inputs exit 2, never 1. ------------------------------------
empty_log = write_log(case7, "", "empty.log")
result = verdict(plan7, empty_log)
check(
    result.returncode == 2,
    "an empty base log exits 2 -- a broken gate, not a verdict a label may"
    " downgrade",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

result = verdict(plan7, case7 / "does-not-exist.log")
check(
    result.returncode == 2,
    "a missing base log exits 2",
    f"exit {result.returncode}, stderr={result.stderr!r}",
)

result = verdict(case7 / "does-not-exist.json", red_log)
check(
    result.returncode == 2,
    "a missing plan exits 2",
    f"exit {result.returncode}, stderr={result.stderr!r}",
)

not_a_plan = case7 / "not-a-plan.json"
not_a_plan.write_text(json.dumps({"foo": "bar"}), encoding="utf-8")
result = verdict(not_a_plan, red_log)
check(
    result.returncode == 2,
    "a JSON file that is not a plan this script produced exits 2",
    f"exit {result.returncode}, stderr={result.stderr!r}",
)

broken_json = case7 / "broken.json"
broken_json.write_text("{ not json at all", encoding="utf-8")
result = verdict(broken_json, red_log)
check(
    result.returncode == 2,
    "a malformed plan exits 2",
    f"exit {result.returncode}, stderr={result.stderr!r}",
)

# The report names the escape hatch on every path, so a human reading a
# failing job knows the override exists and where its reason is recorded.
result = verdict(plan7, green_log)
check(
    "characterization-test" in result.stdout
    and "recorded in the pull request body" in result.stdout,
    "the report names the characterization-test escape hatch and where its"
    " reason is recorded",
    f"stdout={result.stdout!r}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 18: pipeline_metrics.py's ledger validation and derived figures (#339).
#
# Part 14's shape, for the same reason: this is the reader side of the same
# ledger schema, exercised with fixture CSVs written under the harness's own
# temp directory plus one pass against the real, committed `.metrics/runs.csv`
# -- python3 only, no network, no `gh`, no real repository beyond that one
# read-only fixture already checked in.
# ---------------------------------------------------------------------------

part18 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import csv
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
scripts_dir = pathlib.Path(repo_root) / ".github" / "scripts"
script = scripts_dir / "pipeline_metrics.py"
case_dir = pathlib.Path(tempfile.mkdtemp(prefix="pm-case.", dir=work_dir))

sys.path.insert(0, str(scripts_dir))
import ledger_row  # noqa: E402
import pipeline_metrics  # noqa: E402

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def row(**fields):
    base = {name: "" for name in ledger_row.HEADER}
    base.update(fields)
    return [base[name] for name in ledger_row.HEADER]


def write_ledger(name, data_rows, header=None):
    path = case_dir / name
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(list(header) if header is not None else list(ledger_row.HEADER))
        for data_row in data_rows:
            writer.writerow(data_row)
    return path


def run_cli(ledger_path, now="2026-09-15T12:00:00Z", weeks=None):
    args = [sys.executable, str(script), "--ledger", str(ledger_path), "--json", "--now", now]
    if weeks is not None:
        args += ["--weeks", str(weeks)]
    return subprocess.run(args, capture_output=True, text=True)


def model_of(result):
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


def collect_shares(node, found):
    if isinstance(node, dict):
        if set(node.keys()) == {"numerator", "denominator", "percent"}:
            found.append(node)
        else:
            for value in node.values():
                collect_shares(value, found)
    elif isinstance(node, list):
        for value in node:
            collect_shares(value, found)


# -- criterion 1: --help exits 0, the file is executable with the shebang, --
#    and the source has no subprocess/urllib/requests import or call site.
help_result = subprocess.run(
    [sys.executable, str(script), "--help"], capture_output=True, text=True,
)
source = script.read_text(encoding="utf-8")
forbidden_import = re.search(
    r"^\s*(?:import|from)\s+(subprocess|urllib|requests)\b", source, re.MULTILINE,
)
forbidden_call = re.search(r"\b(?:subprocess|urllib|requests)\.\w+\(", source)
check(
    help_result.returncode == 0
    and source.splitlines()[0] == "#!/usr/bin/env python3"
    and os.access(script, os.X_OK)
    and forbidden_import is None
    and forbidden_call is None,
    "--help exits 0, the shebang and executable bit are set, and the source"
    " has no subprocess/urllib/requests import or call site",
    f"exit {help_result.returncode}, forbidden_import={forbidden_import},"
    f" forbidden_call={forbidden_call}, executable={os.access(script, os.X_OK)},"
    f" stderr={help_result.stderr!r}",
)

# -- criterion 2: HEADER is imported, not restated. -------------------------
check(
    pipeline_metrics.HEADER is ledger_row.HEADER,
    "pipeline_metrics.HEADER is the same object as ledger_row.HEADER",
    f"pipeline_metrics.HEADER={pipeline_metrics.HEADER!r} is not ledger_row.HEADER",
)

# -- criteria 3/4: against the committed ledger, the model's top-level keys -
#    are exactly the six the epic asks for, and coverage matches the file.
real_ledger = pathlib.Path(repo_root) / ".metrics" / "runs.csv"
with real_ledger.open(newline="", encoding="utf-8") as f:
    reader = csv.reader(f)
    next(reader)
    real_data_rows = list(reader)
expected_merge = sum(1 for r in real_data_rows if r[1] == "merge")
expected_session = sum(1 for r in real_data_rows if r[1] == "session")
timestamps = [r[0] for r in real_data_rows]

real_result = run_cli(real_ledger)
real_model = model_of(real_result)
check(
    real_result.returncode == 0
    and list(real_model.keys()) == [
        "coverage", "delivery_frequency", "first_pass_yield",
        "tier_accuracy", "verdict_distribution", "fix_rounds",
    ],
    "running against the committed ledger exits 0 and the model's top-level"
    " keys are exactly the six the epic asks for",
    f"exit {real_result.returncode}, keys={list(real_model.keys())},"
    f" stderr={real_result.stderr!r}",
)

real_coverage = real_model.get("coverage", {})
check(
    real_coverage.get("merge_rows") == expected_merge
    and real_coverage.get("session_rows") == expected_session
    and real_coverage.get("rows")
    == expected_merge + expected_session + real_coverage.get("skipped_rows", -1)
    and real_coverage.get("first_timestamp") == min(timestamps)
    and real_coverage.get("last_timestamp") == max(timestamps),
    "coverage.merge_rows/session_rows/rows and first/last_timestamp match"
    " the committed ledger",
    f"coverage={real_coverage}, expected merge={expected_merge}"
    f" session={expected_session}",
)

# -- criterion 5: a missing ledger path is fatal. ---------------------------
missing_path = case_dir / "does-not-exist.csv"
result = run_cli(missing_path)
check(
    result.returncode != 0 and result.stdout == "" and str(missing_path) in result.stderr,
    "a missing ledger path exits non-zero, prints nothing to stdout, and"
    " names the path on stderr",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

# -- criterion 6: a header-only ledger is fatal. -----------------------------
header_only = write_ledger("header-only.csv", [])
result = run_cli(header_only)
check(
    result.returncode != 0
    and result.stdout == ""
    and "no data rows" in result.stderr,
    "a ledger holding only the header row exits non-zero, prints nothing to"
    " stdout, and says it holds no data rows",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

# -- criterion 7: a mismatched header is fatal. -----------------------------
bad_header = write_ledger("bad-header.csv", [], header=["not", "the", "header"])
result = run_cli(bad_header)
check(
    result.returncode != 0
    and result.stdout == ""
    and "header" in result.stderr.lower()
    and "match" in result.stderr.lower(),
    "a ledger whose first line is not the imported header exits non-zero,"
    " prints nothing to stdout, and says the header does not match",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

# -- criterion 8: a too-short row and an unparseable timestamp both degrade -
#    non-fatally, counted in coverage.skipped_rows.
degraded = write_ledger("degraded.csv", [
    row(timestamp="2026-09-15T00:00:00Z", event="merge", issue="1", pr="401",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    ["too", "few", "fields"],
    row(timestamp="not-a-timestamp", event="merge", issue="2", pr="402",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:01Z", event="merge", issue="3", pr="403",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
])
result = run_cli(degraded)
model = model_of(result)
check(
    result.returncode == 0
    and model.get("coverage", {}).get("skipped_rows") == 2
    and model.get("coverage", {}).get("merge_rows") == 2,
    "a wrong-field-count row and an unparseable-timestamp row are both"
    " skipped and counted in coverage.skipped_rows; every other row still"
    " contributes",
    f"exit {result.returncode}, coverage={model.get('coverage')},"
    f" stderr={result.stderr!r}",
)

# -- criterion 9: identical flags produce byte-identical stdout. ------------
result_a = run_cli(real_ledger)
result_b = run_cli(real_ledger)
check(
    result_a.returncode == 0 and result_a.stdout == result_b.stdout,
    "two runs with identical --ledger/--weeks/--now produce byte-identical"
    " stdout",
    f"a={result_a.stdout!r}, b={result_b.stdout!r}",
)

# -- criterion 10: every share is {numerator, denominator, percent}, null --
#     below MIN_DENOMINATOR_FOR_PERCENT.
shares = []
collect_shares(real_model, shares)
check(
    len(shares) >= 4
    and all(set(s.keys()) == {"numerator", "denominator", "percent"} for s in shares)
    and all(s["percent"] is None for s in shares if s["denominator"] < 10),
    "every share in the model has numerator/denominator/percent, and percent"
    " is null whenever the denominator is below 10",
    f"shares={shares}",
)

# -- criterion 11: first_pass_yield over fix_round 0, 1, 0. -----------------
fpy_ledger = write_ledger("fpy.csv", [
    row(timestamp="2026-09-15T00:00:00Z", event="merge", issue="1", pr="501",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:01Z", event="merge", issue="2", pr="502",
        tier_label="opus", fix_round="1", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:02Z", event="merge", issue="3", pr="503",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
])
result = run_cli(fpy_ledger)
fpy = model_of(result).get("first_pass_yield", {})
check(
    result.returncode == 0
    and fpy.get("numerator") == 2
    and fpy.get("denominator") == 3
    and fpy.get("percent") is None,
    "first_pass_yield over fix_round 0, 1, 0 reports numerator 2,"
    " denominator 3, percent null",
    f"first_pass_yield={fpy}",
)


# -- criterion 12: tier_accuracy escalation, non-escalation and ------------
#     unclassified, for a haiku merge row and its one session.
def tier_fixture(name, model_resolved):
    ledger = write_ledger(name, [
        row(timestamp="2026-09-15T00:00:00Z", event="merge", issue="1", pr="601",
            tier_label="haiku", fix_round="0", verdict="pass", run_url="u"),
        row(timestamp="2026-09-15T00:00:00Z", event="session", issue="1", pr="601",
            role="implementer", vendor="claude", model_requested="claude-haiku-4-5",
            model_resolved=model_resolved, outcome="completed",
            duration_seconds="10", run_url="u"),
    ])
    return model_of(run_cli(ledger))


haiku_escalated = tier_fixture("tier-escalated.csv", "claude-opus-5").get(
    "tier_accuracy", {}
).get("haiku", {})
check(
    haiku_escalated.get("escalated") == 1,
    "a haiku merge whose session resolved claude-opus-5 reports"
    " tier_accuracy.haiku.escalated == 1",
    f"haiku={haiku_escalated}",
)

haiku_not_escalated = tier_fixture(
    "tier-not-escalated.csv", "claude-haiku-4-5-20251001"
).get("tier_accuracy", {}).get("haiku", {})
check(
    haiku_not_escalated.get("escalated") == 0,
    "the same fixture with model_resolved claude-haiku-4-5-20251001 reports"
    " 0 escalated",
    f"haiku={haiku_not_escalated}",
)

haiku_unclassified = tier_fixture(
    "tier-unclassified.csv", "some-unrecognised-model"
).get("tier_accuracy", {}).get("haiku", {})
check(
    haiku_unclassified.get("unclassified") == 1
    and haiku_unclassified.get("share", {}).get("denominator") == 0,
    "the same fixture with an unrecognised model ID reports unclassified == 1"
    " and a share denominator of 0",
    f"haiku={haiku_unclassified}",
)

# -- criterion 13: verdict_distribution over one of each verdict, plus ------
#     an empty one and an off-vocabulary one.
verdict_ledger = write_ledger("verdicts.csv", [
    row(timestamp="2026-09-15T00:00:00Z", event="merge", issue="1", pr="701",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:01Z", event="merge", issue="2", pr="702",
        tier_label="opus", fix_round="0", verdict="fix", run_url="u"),
    row(timestamp="2026-09-15T00:00:02Z", event="merge", issue="3", pr="703",
        tier_label="opus", fix_round="0", verdict="design-ambiguity", run_url="u"),
    row(timestamp="2026-09-15T00:00:03Z", event="merge", issue="4", pr="704",
        tier_label="opus", fix_round="0", verdict="planning-failure", run_url="u"),
    row(timestamp="2026-09-15T00:00:04Z", event="merge", issue="5", pr="705",
        tier_label="opus", fix_round="0", verdict="", run_url="u"),
    row(timestamp="2026-09-15T00:00:05Z", event="merge", issue="6", pr="706",
        tier_label="opus", fix_round="0", verdict="something-else", run_url="u"),
])
result = run_cli(verdict_ledger)
verdict_distribution = model_of(result).get("verdict_distribution", {})
check(
    result.returncode == 0
    and verdict_distribution == {
        "pass": 1, "fix": 1, "design-ambiguity": 1, "planning-failure": 1,
        "none": 1, "other": 1,
    },
    "verdict_distribution over one of each named verdict, one empty and one"
    " off-vocabulary value reports 1 in each bucket",
    f"verdict_distribution={verdict_distribution}",
)

# -- criterion 14: fix_rounds over 0, 1, 2, 4 -- counts and the flagged list.
fixround_ledger = write_ledger("fixrounds.csv", [
    row(timestamp="2026-09-15T00:00:00Z", event="merge", issue="10", pr="801",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:01Z", event="merge", issue="11", pr="802",
        tier_label="opus", fix_round="1", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:02Z", event="merge", issue="12", pr="803",
        tier_label="opus", fix_round="2", verdict="pass", run_url="u"),
    row(timestamp="2026-09-15T00:00:03Z", event="merge", issue="13", pr="804",
        tier_label="opus", fix_round="4", verdict="pass", run_url="u"),
])
result = run_cli(fixround_ledger)
fix_rounds_model = model_of(result).get("fix_rounds", {})
needs_human_review = fix_rounds_model.get("needs_human_review", [])
check(
    result.returncode == 0
    and fix_rounds_model.get("0") == 1
    and fix_rounds_model.get("1") == 1
    and fix_rounds_model.get("2") == 1
    and fix_rounds_model.get("3+") == 1
    and len(needs_human_review) == 2
    and {
        (entry["issue"], entry["pr"], entry["fix_round"])
        for entry in needs_human_review
    } == {(12, 803, 2), (13, 804, 4)},
    "fix_rounds over 0, 1, 2, 4 reports counts 1/1/1/1 for 0/1/2/3+ and"
    " lists exactly the two tasks at 2 or more with their issue and pr",
    f"fix_rounds={fix_rounds_model}",
)

# -- criterion 15: delivery_frequency over three ISO weeks with 2, 0, 1 -----
#     merges, aligned so the whole window is three complete weeks.
delivery_ledger = write_ledger("delivery.csv", [
    row(timestamp="2026-08-24T10:00:00Z", event="merge", issue="20", pr="901",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    row(timestamp="2026-08-25T10:00:00Z", event="merge", issue="21", pr="902",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
    row(timestamp="2026-09-07T10:00:00Z", event="merge", issue="22", pr="903",
        tier_label="opus", fix_round="0", verdict="pass", run_url="u"),
])
result = run_cli(delivery_ledger, now="2026-09-14T00:00:00Z", weeks=3)
weeks_entries = model_of(result).get("delivery_frequency", {}).get("weeks", [])
check(
    result.returncode == 0
    and [entry["merges"] for entry in weeks_entries] == [2, 0, 1]
    and all("percent" not in entry for entry in weeks_entries),
    "delivery_frequency over three ISO weeks with 2, 0 and 1 merges reports"
    " one entry per week with those counts and no percentage on any entry",
    f"weeks={weeks_entries}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 19: render-pipeline-report.py's GitHub-derived figures, its rendering
# and its two failure classes (#340).
#
# Part 14's shape again, and Part 18's in particular -- this is the renderer
# sitting on top of the module Part 18 covers. python3 only, fixture ledgers
# and one fixture `--github-json` document, no network, no `gh` and no real
# repository beyond a read-only pass over the committed `.metrics/runs.csv`.
# The two `gh` paths are exercised by putting a temp directory on `PATH`:
# empty, to prove `--github-json` reaches no `gh` call at all, and holding a
# `gh` that exits 1, to prove an outage degrades four sections rather than
# the report.
# ---------------------------------------------------------------------------

part19 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import csv
import json
import os
import pathlib
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
scripts_dir = pathlib.Path(repo_root) / ".github" / "scripts"
script = scripts_dir / "render-pipeline-report.py"
case_dir = pathlib.Path(tempfile.mkdtemp(prefix="rpr-case.", dir=work_dir))

sys.path.insert(0, str(scripts_dir))
import ledger_row  # noqa: E402

NOW = "2026-09-15T12:00:00Z"

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def row(**fields):
    base = {name: "" for name in ledger_row.HEADER}
    base.update(fields)
    return [base[name] for name in ledger_row.HEADER]


def merge_row(timestamp, issue, pr, fix_round="0", tier_label="opus",
              verdict="pass"):
    return row(timestamp=timestamp, event="merge", issue=str(issue),
               pr=str(pr), tier_label=tier_label, fix_round=fix_round,
               verdict=verdict, run_url="u")


def write_ledger(name, data_rows, header=None):
    path = case_dir / name
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(list(header) if header is not None else list(ledger_row.HEADER))
        for data_row in data_rows:
            writer.writerow(data_row)
    return path


def write_github(name, issues=(), pull_requests=(), ci_runs=()):
    path = case_dir / name
    path.write_text(json.dumps({
        "issues": list(issues),
        "pull_requests": list(pull_requests),
        "ci_runs": list(ci_runs),
    }, indent=2), encoding="utf-8")
    return path


def ci_run(database_id, conclusion, started, completed,
           branch="main", event="push"):
    return {
        "databaseId": database_id, "workflowName": "CI",
        "headBranch": branch, "event": event, "status": "completed",
        "conclusion": conclusion, "startedAt": started, "updatedAt": completed,
        "url": "u",
    }


# A PATH with no `gh` on it at all, and one with a `gh` that always fails.
# Both hold only that, so nothing else can satisfy the lookup.
empty_bin = case_dir / "bin-empty"
empty_bin.mkdir()
failing_bin = case_dir / "bin-failing"
failing_bin.mkdir()
failing_gh = failing_bin / "gh"
failing_gh.write_text(
    "#!/bin/sh\n"
    "echo 'gh: could not resolve to a Repository' >&2\n"
    "exit 1\n",
    encoding="utf-8",
)
failing_gh.chmod(0o755)


def run_cli(ledger_path, github_json=None, now=NOW, weeks=None, path_dir=None,
            extra=()):
    args = [sys.executable, str(script), "--ledger", str(ledger_path),
            "--now", now]
    if github_json is not None:
        args += ["--github-json", str(github_json)]
    if weeks is not None:
        args += ["--weeks", str(weeks)]
    args += list(extra)

    env = dict(os.environ)
    if path_dir is not None:
        env["PATH"] = str(path_dir)
    return subprocess.run(args, capture_output=True, text=True, env=env)


def section(text, heading):
    """The body of `## heading`, up to the next `## `."""

    marker = f"\n## {heading}\n"
    if marker not in text:
        return ""
    body = text.split(marker, 1)[1]
    return body.split("\n## ", 1)[0]


# -- criterion 1: --help exits 0, executable, with the shebang. -------------
help_result = subprocess.run(
    [sys.executable, str(script), "--help"], capture_output=True, text=True,
)
source = script.read_text(encoding="utf-8")
check(
    help_result.returncode == 0
    and source.splitlines()[0] == "#!/usr/bin/env python3"
    and os.access(script, os.X_OK),
    "--help exits 0 and the file is executable with a python3 shebang",
    f"exit {help_result.returncode}, executable={os.access(script, os.X_OK)},"
    f" first line={source.splitlines()[0]!r}, stderr={help_result.stderr!r}",
)

# -- criteria 2/3/4: with GitHub state supplied and no `gh` anywhere on -----
#    PATH, the report renders in full, starting with the marker and carrying
#    a heading for each of the six headline metrics and three supporting
#    series.
basic_ledger = write_ledger("basic.csv", [
    merge_row("2026-09-02T00:00:00Z", 301, 901),
    merge_row("2026-09-03T00:00:00Z", 303, 903, fix_round="1"),
    merge_row("2026-09-04T00:00:00Z", 305, 905),
])
basic_github = write_github(
    "basic-github.json",
    issues=[{"number": 301, "title": "t", "body": "",
             "createdAt": "2026-09-01T00:00:00Z", "labels": []}],
)

result = run_cli(basic_ledger, basic_github, path_dir=empty_bin)
report = result.stdout
check(
    result.returncode == 0 and report.strip() != "",
    "with --github-json supplied and `gh` absent from PATH the script exits 0"
    " and prints the report, so no gh call is reached",
    f"exit {result.returncode}, stdout={report[:400]!r}, stderr={result.stderr!r}",
)
check(
    report.splitlines()[0] == "<!-- pipeline-report -->",
    "the first line of stdout is the <!-- pipeline-report --> marker",
    f"first line={report.splitlines()[0] if report else ''!r}",
)

HEADINGS = [
    "Lead time for change", "Delivery frequency", "Change failure rate",
    "Time to restore", "First-pass yield", "Planner tier accuracy",
    "Verdict distribution", "Fix rounds per task", "CI wall-clock duration",
]
missing_headings = [h for h in HEADINGS if f"\n## {h}\n" not in report]
check(
    not missing_headings,
    "the report carries a heading for each of the six headline metrics and"
    " each of the three supporting series",
    f"missing headings: {missing_headings}",
)

# -- criterion 5: the coverage paragraph's figures match the committed ------
#    ledger exactly.
real_ledger = pathlib.Path(repo_root) / ".metrics" / "runs.csv"
with real_ledger.open(newline="", encoding="utf-8") as f:
    reader = csv.reader(f)
    next(reader)
    real_rows = [r for r in reader if r]
real_timestamps = [r[0] for r in real_rows]

real_result = run_cli(real_ledger, basic_github)
real_report = real_result.stdout
coverage_line = ""
for line in real_report.splitlines():
    if line.startswith("Read "):
        coverage_line = line
        break
check(
    real_result.returncode == 0
    and f"Read {len(real_rows)} ledger rows" in coverage_line
    and min(real_timestamps) in coverage_line
    and max(real_timestamps) in coverage_line
    and "12 weeks" in coverage_line
    and "2026-09-15T12:00:00Z" in coverage_line
    and "0 rows were skipped" in coverage_line,
    "the coverage paragraph states the committed ledger's row count, its"
    " earliest and latest timestamp, the reporting window and the"
    " skipped-row count",
    f"exit {real_result.returncode}, coverage line={coverage_line!r},"
    f" rows={len(real_rows)}, first={min(real_timestamps) if real_timestamps else None}",
)

# -- criterion 6: a thin denominator renders `k of n` and no percent sign ---
#    anywhere; a denominator of 12 renders a percentage.
check(
    "%" not in report
    and "2 of 3 merges in the window landed without a fix round" in report
    and "0 of 3 merges in the window are attributable" in report,
    "with every denominator below 10 the whole report is free of a percent"
    " sign and renders its rates as `k of n`",
    f"report={report!r}",
)

wide_ledger = write_ledger("wide.csv", [
    merge_row(f"2026-09-0{1 + index // 4}T0{index % 4}:00:00Z",
              400 + index, 1000 + index,
              fix_round="0" if index < 8 else "1")
    for index in range(12)
])
wide = run_cli(wide_ledger, basic_github)
yield_line = ""
for line in wide.stdout.splitlines():
    if "landed without a fix round" in line:
        yield_line = line
        break
check(
    wide.returncode == 0 and "66.67%" in yield_line and "(8 of 12)" in yield_line,
    "a fixture whose first-pass-yield denominator is 12 renders that rate as"
    " a percentage alongside its counts",
    f"exit {wide.returncode}, yield line={yield_line!r}",
)

# -- criterion 7: lead time for change, with one covered and one excluded --
#    merge.
lead_ledger = write_ledger("lead.csv", [
    merge_row("2026-09-03T00:00:00Z", 330, 903),
    merge_row("2026-09-04T00:00:00Z", 999, 904),
])
lead_github = write_github(
    "lead-github.json",
    issues=[{"number": 330, "title": "t", "body": "",
             "createdAt": "2026-09-01T00:00:00Z", "labels": []}],
)
lead = run_cli(lead_ledger, lead_github)
lead_section = section(lead.stdout, "Lead time for change")
check(
    lead.returncode == 0
    and "2 days" in lead_section
    and "covers 1 merge" in lead_section
    and "1 merge excluded" in lead_section,
    "a merge at 2026-09-03T00:00:00Z whose Issue was created"
    " 2026-09-01T00:00:00Z reports a 2 day lead time, and the section states"
    " the merges covered and the merges excluded",
    f"exit {lead.returncode}, section={lead_section!r}",
)

# -- criterion 8: change failure rate, one attribution by each rule. --------
cfr_github = write_github(
    "cfr-github.json",
    issues=[{"number": 960, "title": "Finding from review",
             "body": "Discovered in #903 (https://example.invalid/903)",
             "createdAt": "2026-09-06T00:00:00Z",
             "labels": [{"name": "deferred-finding"}]}],
    pull_requests=[{"number": 950, "title": 'Revert "Add the thing (#901)"',
                    "mergedAt": "2026-09-05T00:00:00Z", "url": "u"}],
)
cfr = run_cli(basic_ledger, cfr_github)
cfr_section = section(cfr.stdout, "Change failure rate")
check(
    cfr.returncode == 0
    and "2 of 3" in cfr_section
    and "- #901" in cfr_section
    and "- #903" in cfr_section
    and "- #905" not in cfr_section,
    "one merge reverted by a later merged `Revert ... (#N)` pull request and"
    " one referenced by a later `deferred-finding` Issue give a numerator of"
    " 2 over a denominator of 3, naming both attributed pull requests",
    f"exit {cfr.returncode}, section={cfr_section!r}",
)

# -- criteria 9/10: time to restore and CI wall-clock duration over one -----
#     success/failure/failure/success sequence.
#     The three runs that must not count are in the fixture on purpose: a
#     pull-request run, a run off `main`, and an in-progress run whose
#     `updatedAt` is not a finish.
ci_github = write_github("ci-github.json", ci_runs=[
    ci_run(1, "success", "2026-09-10T00:00:00Z", "2026-09-10T00:10:00Z"),
    ci_run(2, "failure", "2026-09-10T01:00:00Z", "2026-09-10T01:20:00Z"),
    ci_run(3, "failure", "2026-09-10T02:00:00Z", "2026-09-10T02:30:00Z"),
    ci_run(4, "success", "2026-09-10T03:00:00Z", "2026-09-10T03:40:00Z"),
    ci_run(5, "failure", "2026-09-10T02:15:00Z", "2026-09-10T05:15:00Z",
           event="pull_request"),
    ci_run(6, "failure", "2026-09-10T02:20:00Z", "2026-09-10T06:20:00Z",
           branch="topic"),
    dict(ci_run(7, "", "2026-09-10T03:30:00Z", "2026-09-10T09:30:00Z"),
         status="in_progress"),
])
ci = run_cli(basic_ledger, ci_github)
restore_section = section(ci.stdout, "Time to restore")
check(
    ci.returncode == 0
    and "1 red period" in restore_section
    and "2h 40m" in restore_section,
    "a success/failure/failure/success run sequence on main reports exactly"
    " one red period lasting from the first failing run's start to the"
    " restoring run's completion (01:00 to 03:40 -- 2h 40m)",
    f"exit {ci.returncode}, section={restore_section!r}",
)

duration_section = section(ci.stdout, "CI wall-clock duration")
check(
    "Median 25m" in duration_section
    and "90th percentile 40m" in duration_section
    and "4 runs" in duration_section,
    "the CI wall-clock section reports the median (25m), the 90th percentile"
    " (40m) and the run count (4) over the window's main push runs, counting"
    " neither a pull-request run, nor a run off main, nor an in-progress one",
    f"section={duration_section!r}",
)

green_github = write_github("green-github.json", ci_runs=[
    ci_run(5, "success", "2026-09-10T00:00:00Z", "2026-09-10T00:10:00Z"),
    ci_run(6, "success", "2026-09-10T01:00:00Z", "2026-09-10T01:10:00Z"),
])
green = run_cli(basic_ledger, green_github)
green_section = section(green.stdout, "Time to restore")
check(
    green.returncode == 0
    and "No red periods" in green_section
    and "median" not in green_section.lower(),
    "a run set with no failures says there were no red periods rather than"
    " reporting a duration",
    f"exit {green.returncode}, section={green_section!r}",
)

# -- criterion 11: a failing `gh` degrades the four GitHub-derived sections -
#     and nothing else, and still exits 0.
degraded = run_cli(basic_ledger, github_json=None, path_dir=failing_bin)
github_sections = [
    "Lead time for change", "Change failure rate", "Time to restore",
    "CI wall-clock duration",
]
degraded_ok = all(
    section(degraded.stdout, heading).strip().startswith("Not available:")
    for heading in github_sections
)
ledger_intact = all(
    "Not available:" not in section(degraded.stdout, heading)
    for heading in ["Delivery frequency", "First-pass yield",
                    "Planner tier accuracy", "Verdict distribution",
                    "Fix rounds per task"]
)
check(
    degraded.returncode == 0
    and degraded_ok
    and ledger_intact
    and "2 of 3 merges in the window landed without a fix round" in degraded.stdout
    and degraded.stdout.count("Not available:") == len(github_sections),
    "a `gh` that fails renders exactly the four GitHub-derived sections as"
    " `Not available: <reason>`, leaves every ledger-derived section intact,"
    " and exits 0",
    f"exit {degraded.returncode}, stdout={degraded.stdout!r}",
)
check(
    "gh issue list" in section(degraded.stdout, "Lead time for change"),
    "the `Not available:` line names the reason -- the gh command that failed",
    f"section={section(degraded.stdout, 'Lead time for change')!r}",
)

# -- criterion 12: the three fatal ledger cases. ----------------------------
fatal_cases = [
    ("a missing ledger", case_dir / "does-not-exist.csv"),
    ("a header-only ledger", write_ledger("header-only.csv", [])),
    ("a wrong-header ledger",
     write_ledger("bad-header.csv", [], header=["not", "the", "header"])),
]
for label, path in fatal_cases:
    fatal = run_cli(path, basic_github)
    check(
        fatal.returncode != 0 and fatal.stdout == "" and fatal.stderr.strip() != "",
        f"{label} exits non-zero with the diagnostic on stderr and nothing on"
        " stdout",
        f"{label}: exit {fatal.returncode}, stdout={fatal.stdout!r},"
        f" stderr={fatal.stderr!r}",
    )

# -- criterion 13: identical inputs produce byte-identical stdout. ----------
first = run_cli(basic_ledger, ci_github, weeks=6)
second = run_cli(basic_ledger, ci_github, weeks=6)
check(
    first.returncode == 0 and first.stdout == second.stdout,
    "two runs with identical --ledger, --github-json, --weeks and --now"
    " produce byte-identical stdout",
    f"a={first.stdout!r}\nb={second.stdout!r}",
)

# -- criterion 14: --json emits the combined model, both halves present. ----
combined = run_cli(basic_ledger, ci_github, extra=["--json"])
try:
    model = json.loads(combined.stdout)
except json.JSONDecodeError:
    model = {}
check(
    combined.returncode == 0
    and set(model.keys()) == {"ledger", "github"}
    and model.get("github", {}).get("available") is True
    and "coverage" in model.get("ledger", {}),
    "--json emits one combined model carrying the ledger half and the GitHub"
    " half",
    f"exit {combined.returncode}, keys={list(model.keys())},"
    f" stdout={combined.stdout[:400]!r}",
)

# -- criterion 15: GitHub state that cannot be parsed degrades, never ------
#     aborts.
malformed = case_dir / "malformed.json"
malformed.write_text('{"issues": []}', encoding="utf-8")
unparseable = run_cli(basic_ledger, malformed, path_dir=empty_bin)
check(
    unparseable.returncode == 0
    and unparseable.stdout.count("Not available:") == len(github_sections)
    and "pull_requests" in unparseable.stdout,
    "GitHub state missing a required key degrades every GitHub-derived"
    " section with a reason naming the key, and still exits 0",
    f"exit {unparseable.returncode}, stdout={unparseable.stdout!r}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 20: pipeline-report.yml's workflow shape and ci.yml's gate (#341).
#
# The renderer that pipeline-report.yml calls has its own coverage (Part 18,
# Part 19); this part covers the workflow wrapped around it -- the schedule,
# the credential posture, the publish-or-not gate, and the three new
# GODOT_DENY entries in ci.yml. Text inspection for the shape checks, an
# actual run of the extracted "Render" step's shell source for the failure
# path (the same technique Part 13 uses on "Determine Gates"), and Part 13's
# own harness reused unmodified for the gate. No network, no `gh`, no real
# repository.
# ---------------------------------------------------------------------------

part20 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import os
import pathlib
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
import wf

work_dir, repo_root = sys.argv[1], sys.argv[2]
root = pathlib.Path(repo_root)
WF_REL = ".github/workflows/pipeline-report.yml"
CI_REL = ".github/workflows/ci.yml"
LABELS_REL = ".github/scripts/bootstrap-labels.sh"

text = (root / WF_REL).read_text(encoding="utf-8")
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part20.", dir=work_dir))

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def block_from(marker, stop_marker):
    """The nested content under a `marker:` line, at whatever indent it
    sits at -- `workflow_dispatch:` is nested under `on:`, `permissions:`
    is not. Ends at the next line back at or above `marker:`'s own indent,
    the same rule Part 9 uses to find the end of a dispatch block.
    `stop_marker` only names the boundary for a clearer failure message."""
    lines = text.splitlines()
    collected = []
    marker_indent = None
    for line in lines:
        if marker_indent is None:
            m = re.match(rf"^(\s*){re.escape(marker)}:\s*$", line)
            if m:
                marker_indent = len(m.group(1))
            continue
        if not line.strip():
            collected.append(line)
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= marker_indent and not line.lstrip().startswith("#"):
            break
        collected.append(line)
    if marker_indent is None:
        raise LookupError(f"no `{marker}:` line found before {stop_marker!r}")
    return "\n".join(collected)


def non_comment_lines(s):
    return [
        line for line in s.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


# -- c1: exactly one weekly schedule cron; workflow_dispatch present; every --
#        declared input is type: string.
crons = re.findall(r'^\s*-\s*cron:\s*"([^"]+)"', text, re.M)
check(
    len(crons) == 1,
    f"exactly one schedule cron expression ({crons!r})",
    f"expected exactly one `cron:` entry, found {crons!r}",
)

if len(crons) == 1:
    fields = crons[0].split()
    weekly = (
        len(fields) == 5
        and fields[2] == "*"  # day of month: every day
        and fields[3] == "*"  # month: every month
        and fields[4] != "*"  # day of week: a specific weekday
    )
    check(
        weekly,
        f"the cron expression ({crons[0]!r}) is weekly, not daily or finer",
        f"cron {crons[0]!r} does not look weekly (day-of-week field must"
        " pin one weekday)",
    )

check(
    re.search(r"^\s*workflow_dispatch:\s*$", text, re.M) is not None,
    "workflow_dispatch is declared",
    "no `workflow_dispatch:` trigger found",
)

dispatch_block = block_from("workflow_dispatch", "the next top-level key")
input_names = re.findall(r"^\s{6}([a-zA-Z0-9_]+):\s*$", dispatch_block, re.M)
input_types = re.findall(r"^\s*type:\s*(\S+)\s*$", dispatch_block, re.M)
check(
    len(input_names) >= 1,
    f"workflow_dispatch declares at least one input ({input_names!r})",
    f"found no input keys in the workflow_dispatch block:\n{dispatch_block}",
)
check(
    len(input_types) == len(input_names) and all(t == "string" for t in input_types),
    f"every declared dispatch input is `type: string` ({dict(zip(input_names, input_types))!r})",
    f"expected one `type: string` per input, got types={input_types!r}"
    f" for inputs={input_names!r}",
)

# -- c2: permissions is exactly {contents: read, issues: write}. -----------
perm_block = block_from("permissions", "concurrency")
perms = dict(re.findall(r"^\s+(\w[\w-]*):\s*(\w+)\s*$", perm_block, re.M))
check(
    perms == {"contents": "read", "issues": "write"},
    f"permissions is exactly contents: read, issues: write ({perms!r})",
    f"expected {{'contents': 'read', 'issues': 'write'}}, got {perms!r}",
)

# -- c3: no AI credits spent -- checked against non-comment lines only, so --
#        prose in the file's own header explaining the constraint (which
#        names these same strings) cannot trip it.
code_text = "\n".join(non_comment_lines(text))
check(
    "secrets." not in code_text,
    "no `secrets.` expression outside comments",
    "found a `secrets.` expression in a non-comment line",
)
check(
    "run-agent-session" not in code_text,
    "no reference to .github/actions/run-agent-session outside comments",
    "found a run-agent-session reference in a non-comment line",
)
check(
    re.search(r"\bclaude\b|\bcopilot\b", code_text, re.I) is None,
    "no invocation of claude or copilot outside comments",
    "found a claude/copilot CLI reference in a non-comment line",
)

# -- c4: concurrency group and cancel-in-progress. --------------------------
concurrency_block = block_from("concurrency", "jobs")
check(
    re.search(r"^\s*group:\s*pipeline-report\s*$", concurrency_block, re.M)
    is not None,
    "concurrency group is pipeline-report",
    f"concurrency block does not pin group: pipeline-report:\n{concurrency_block}",
)
check(
    re.search(r"^\s*cancel-in-progress:\s*true\s*$", concurrency_block, re.M)
    is not None,
    "cancel-in-progress is true",
    f"concurrency block does not set cancel-in-progress: true:\n{concurrency_block}",
)

# -- c5: the Publish step (the only `gh issue edit`) never runs unless the --
#        Render step succeeded, and Render never masks its own failure with
#        continue-on-error.
step_texts = re.split(r"\n(?=      - name: )", text)
publish_steps = [s for s in step_texts if "gh issue edit" in s]
check(
    len(publish_steps) == 1,
    f"exactly one step calls `gh issue edit` ({len(publish_steps)} found)",
    f"expected exactly one step calling gh issue edit, found {len(publish_steps)}",
)
if publish_steps:
    publish_step = publish_steps[0]
    if_line = re.search(r"^\s*if:\s*(.+)$", publish_step, re.M)
    check(
        if_line is not None
        and "render" in if_line.group(1)
        and "always()" not in if_line.group(1),
        f"the publish step's `if:` gates on the render step's outcome"
        f" ({if_line.group(1) if if_line else None!r})",
        "the step calling gh issue edit has no if: gating it on the render"
        " step's outcome (or uses always()), so a failed render could"
        " still publish",
    )

render_steps = [s for s in step_texts if re.search(r"- name: Render\b", s)]
check(
    len(render_steps) == 1 and "continue-on-error" not in render_steps[0],
    "the Render step does not use continue-on-error",
    "the Render step uses continue-on-error, which would hide a failure"
    " reason along with the failure",
)

# -- c6: the render failure path, run for real: writes $GITHUB_STEP_SUMMARY --
#        and exits non-zero; the success path sets a `rows` output and
#        leaves $GITHUB_STEP_SUMMARY untouched.
render_source = wf.step_source(WF_REL, "Render", shell="bash")
render_script = part_dir / "render.sh"
render_script.write_text(render_source, encoding="utf-8")


def run_render(stub_body, weeks="12"):
    case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
    fake_scripts = case / ".github" / "scripts"
    fake_scripts.mkdir(parents=True)
    stub = fake_scripts / "render-pipeline-report.py"
    stub.write_text(stub_body, encoding="utf-8")
    stub.chmod(0o755)

    output_file = case / "github_output"
    output_file.write_text("", encoding="utf-8")
    summary_file = case / "github_step_summary"
    summary_file.write_text("", encoding="utf-8")
    scratch = pathlib.Path(tempfile.mkdtemp(dir=case))

    env = dict(os.environ)
    env.update({
        "RUNNER_TEMP": str(scratch),
        "GITHUB_OUTPUT": str(output_file),
        "GITHUB_STEP_SUMMARY": str(summary_file),
        "WEEKS": weeks,
    })

    result = subprocess.run(
        ["bash", str(render_script)],
        capture_output=True,
        text=True,
        cwd=str(case),
        env=env,
    )
    return result, output_file.read_text(), summary_file.read_text()


failing_stub = (
    "#!/usr/bin/env python3\n"
    "import sys\n"
    "print('pipeline_metrics: ledger unreadable', file=sys.stderr)\n"
    "sys.exit(1)\n"
)
result, outputs, summary = run_render(failing_stub)
check(
    result.returncode != 0,
    "a failing render exits the Render step non-zero",
    f"exit {result.returncode}, stderr={result.stderr!r}",
)
check(
    "ledger unreadable" in summary,
    "a failing render's diagnostic reaches $GITHUB_STEP_SUMMARY",
    f"summary={summary!r}",
)
check(
    "rows=" not in outputs,
    "a failing render sets no `rows` output",
    f"outputs={outputs!r}",
)

succeeding_stub = (
    "#!/usr/bin/env python3\n"
    "print('<!-- pipeline-report -->')\n"
    "print('# Pipeline Report')\n"
    "print()\n"
    "print('Read 7 ledger rows from `.metrics/runs.csv`, ...')\n"
)
result, outputs, summary = run_render(succeeding_stub)
check(
    result.returncode == 0,
    "a succeeding render exits the Render step zero",
    f"exit {result.returncode}, stderr={result.stderr!r}",
)
check(
    "rows=Read 7 ledger rows" in outputs,
    "a succeeding render sets the `rows` output from the rendered coverage line",
    f"outputs={outputs!r}",
)
check(
    summary == "",
    "a succeeding render leaves $GITHUB_STEP_SUMMARY untouched",
    f"summary={summary!r}",
)

# -- c6b: the Summary step, run for real against the `rows` output the -----
#         succeeding render above actually produced -- backticks and all.
#         `rows` must reach $GITHUB_STEP_SUMMARY through the step's `env:`
#         block, not through direct `${{ }}` interpolation into the shell,
#         or the backtick pair in the rendered coverage line triggers
#         command substitution and eats the ledger path.
summary_source = wf.step_source(WF_REL, "Summary", shell="bash")
summary_script = part_dir / "summary.sh"
summary_script.write_text(summary_source, encoding="utf-8")

rows_line = outputs.strip()
assert rows_line.startswith("rows="), f"unexpected GITHUB_OUTPUT: {outputs!r}"
rows_value = rows_line[len("rows="):]

summary_case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
summary_file = summary_case / "github_step_summary"
summary_file.write_text("", encoding="utf-8")

summary_env = dict(os.environ)
summary_env.update({
    "NUMBER": "99",
    "ROWS": rows_value,
    "GITHUB_STEP_SUMMARY": str(summary_file),
})

summary_result = subprocess.run(
    ["bash", str(summary_script)],
    capture_output=True,
    text=True,
    cwd=str(summary_case),
    env=summary_env,
)
summary_text = summary_file.read_text()
check(
    summary_result.returncode == 0,
    "the Summary step exits zero against the backtick-bearing `rows` output",
    f"exit {summary_result.returncode}, stderr={summary_result.stderr!r}",
)
check(
    "Read 7 ledger rows from `.metrics/runs.csv`, ..." in summary_text,
    "the full coverage sentence, backticks and ledger path intact, reaches"
    " $GITHUB_STEP_SUMMARY",
    f"summary={summary_text!r}",
)
check(
    "Permission denied" not in summary_result.stderr,
    "the backticks in `rows` are not executed as command substitution",
    f"stderr={summary_result.stderr!r}",
)

# -- c7: ci.yml's GODOT_DENY carries the three new paths, and a pull -------
#        request touching only them resolves godot=false, control_plane=true.
#        Same extraction and harness Part 13 uses on "Determine Gates".
determine_gates = wf.step_source(CI_REL, "Determine Gates", shell="bash")
gate_step = part_dir / "determine-gates.sh"
gate_step.write_text(determine_gates, encoding="utf-8")

NEW_PATHS = [
    ".github/scripts/pipeline_metrics.py",
    ".github/scripts/render-pipeline-report.py",
    ".github/workflows/pipeline-report.yml",
]
for path in NEW_PATHS:
    check(
        path in determine_gates,
        f"GODOT_DENY carries {path!r}",
        f"{path!r} not found in ci.yml's Determine Gates step",
    )

bin_dir = part_dir / "bin"
bin_dir.mkdir(exist_ok=True)
gh_stub = bin_dir / "gh"
if not gh_stub.exists():
    gh_stub.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\ncat \"$GH_STUB_FILES\"\n",
        encoding="utf-8",
    )
    gh_stub.chmod(0o755)

files_case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
files_path = files_case / "files.txt"
files_path.write_text("\n".join(NEW_PATHS) + "\n", encoding="utf-8")

run_case = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
output_file = run_case / "github_output"
output_file.write_text("", encoding="utf-8")
scratch = pathlib.Path(tempfile.mkdtemp(dir=run_case))

env = dict(os.environ)
env.update({
    "RUNNER_TEMP": str(scratch),
    "GITHUB_OUTPUT": str(output_file),
    "EVENT_NAME": "pull_request",
    "PR_NUMBER": "1",
    "REPOSITORY": "o/r",
    "GH_TOKEN": "stub-token",
    "GH_STUB_FILES": str(files_path),
    "PATH": f"{bin_dir}:{os.environ['PATH']}",
})

result = subprocess.run(
    ["bash", str(gate_step)],
    capture_output=True,
    text=True,
    cwd=str(part_dir),
    env=env,
)
gate_outputs = dict(
    line.split("=", 1)
    for line in output_file.read_text().splitlines()
    if "=" in line
)
check(
    result.returncode == 0
    and gate_outputs.get("godot") == "false"
    and gate_outputs.get("control_plane") == "true",
    "a pull request touching only the three new paths resolves"
    " godot=false, control_plane=true",
    f"exit {result.returncode}, outputs={gate_outputs}, stderr={result.stderr!r}",
)

# -- c8: bootstrap-labels.sh's pipeline-report label description fits the --
#        100-character cap GitHub enforces.
labels_text = (root / LABELS_REL).read_text(encoding="utf-8")
label_match = re.search(r"^pipeline-report\|[0-9A-Fa-f]{6}\|(.+)$", labels_text, re.M)
check(
    label_match is not None,
    "bootstrap-labels.sh defines a pipeline-report label",
    "no `pipeline-report|RRGGBB|description` line found in bootstrap-labels.sh",
)
if label_match:
    description = label_match.group(1)
    check(
        len(description) <= 100,
        f"pipeline-report label description fits the 100-char cap"
        f" ({len(description)} chars)",
        f"{len(description)} chars, cap is 100:\n{description}",
    )

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 21: release-preflight.py's verdicts (#223).
#
# The release workflow (T2, not yet built) fetches JSON and hands it to this
# script; the script owns every decision. Covered end-to-end with fixture
# GitHub JSON and no network, no `gh`, and no tag or release ever created --
# Part 14's shape, for the same reason: this is a standalone decision script
# read via `subprocess`, not a step embedded in a workflow file.
# ---------------------------------------------------------------------------

part21 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import json
import pathlib
import re
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
script = pathlib.Path(repo_root) / ".github" / "scripts" / "release-preflight.py"
case_dir = pathlib.Path(tempfile.mkdtemp(prefix="rp-case.", dir=work_dir))

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


COMMIT = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

RUNS_OK = {"workflow_runs": [
    {"id": 111, "status": "completed", "run_started_at": "2026-09-14T10:00:00Z"},
]}
JOBS_OK = {"jobs": [
    {"name": "Godot Export", "conclusion": "success"},
    {"name": "Godot Smoke Run", "conclusion": "success"},
]}
ARTIFACTS_OK = {"artifacts": [
    {"id": 9, "name": f"godot-linux-{COMMIT}", "expired": False},
]}
TAGS_EMPTY: list = []


def write(name, data, n=[0]):
    n[0] += 1
    path = case_dir / f"{name}-{n[0]}.json"
    if isinstance(data, str):
        path.write_text(data, encoding="utf-8")
    else:
        path.write_text(json.dumps(data), encoding="utf-8")
    return path


def run(*, commit=COMMIT, version="0.2.0", on_main="true",
         runs=RUNS_OK, jobs=JOBS_OK, artifacts=ARTIFACTS_OK, tags=TAGS_EMPTY):
    args = [
        sys.executable, str(script),
        "--commit", commit,
        "--version", version,
        "--on-main", on_main,
        "--runs-json", str(write("runs", runs)),
        "--jobs-json", str(write("jobs", jobs)),
        "--artifacts-json", str(write("artifacts", artifacts)),
        "--tags-json", str(write("tags", tags)),
    ]
    return subprocess.run(args, capture_output=True, text=True)


def kv(result):
    return dict(
        line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
    )


# -- criterion: the script is standard-library only, with no subprocess, ----
#    urllib.request, http or socket import or call site anywhere in its
#    source. Matches import statements and call sites, not the module
#    docstring's own prose about what it does not do.
source = script.read_text(encoding="utf-8")
forbidden = re.search(
    r"^\s*(?:import|from)\s+(subprocess|urllib\.request|http|socket)\b"
    r"|\b(?:subprocess|socket)\.\w+\(",
    source, re.MULTILINE,
)
check(
    script.stat().st_mode & 0o111 != 0
    and source.startswith("#!/usr/bin/env python3\n")
    and forbidden is None,
    "release-preflight.py is executable, starts with the python3 shebang,"
    " and its source names no subprocess/urllib.request/http/socket",
    f"executable={script.stat().st_mode & 0o111 != 0}, forbidden={forbidden}",
)

# -- criterion: the success case. --------------------------------------------
result = run()
out = kv(result)
check(
    result.returncode == 0
    and out.get("verdict") == "ok"
    and out.get("tag") == "v0.2.0"
    and out.get("run_id") == "111"
    and out.get("artifact_name") == f"godot-linux-{COMMIT}"
    and "artifact_id" in out,
    "a passing commit prints verdict=ok with tag, run_id, artifact_id and"
    " artifact_name",
    f"exit {result.returncode}, out={out}, stderr={result.stderr!r}",
)

# -- criterion: bad-version, five ways. --------------------------------------
for bad_version in ("v0.2.0", "1.0.0", "0.2", "0.2.0-rc1", ""):
    result = run(version=bad_version)
    out = kv(result)
    check(
        result.returncode != 0 and out.get("reason") == "bad-version",
        f"version {bad_version!r} is refused as bad-version",
        f"version={bad_version!r}: exit {result.returncode}, out={out}",
    )

# -- criterion: not-on-main. -------------------------------------------------
result = run(on_main="false")
out = kv(result)
check(
    result.returncode != 0 and out.get("reason") == "not-on-main",
    "--on-main false is refused as not-on-main",
    f"exit {result.returncode}, out={out}",
)

# -- criterion: no-run, from an empty and from an all-incomplete runs set. ---
result = run(runs={"workflow_runs": []})
out = kv(result)
check(
    result.returncode != 0 and out.get("reason") == "no-run",
    "an empty runs JSON is refused as no-run",
    f"exit {result.returncode}, out={out}",
)

result = run(runs={"workflow_runs": [
    {"id": 5, "status": "in_progress", "run_started_at": "2026-09-14T10:00:00Z"},
]})
out = kv(result)
check(
    result.returncode != 0 and out.get("reason") == "no-run",
    "a runs JSON with only an incomplete run is refused as no-run",
    f"exit {result.returncode}, out={out}",
)

# -- criterion: stage-not-passed, every way the issue names. -----------------
STAGE_CASES = {
    "export skipped": {"jobs": [
        {"name": "Godot Export", "conclusion": "skipped"},
        {"name": "Godot Smoke Run", "conclusion": "success"},
    ]},
    "smoke skipped": {"jobs": [
        {"name": "Godot Export", "conclusion": "success"},
        {"name": "Godot Smoke Run", "conclusion": "skipped"},
    ]},
    "smoke failed": {"jobs": [
        {"name": "Godot Export", "conclusion": "success"},
        {"name": "Godot Smoke Run", "conclusion": "failure"},
    ]},
    "export absent": {"jobs": [
        {"name": "Godot Smoke Run", "conclusion": "success"},
    ]},
}
for label, jobs in STAGE_CASES.items():
    result = run(jobs=jobs)
    out = kv(result)
    check(
        result.returncode != 0
        and out.get("reason") == "stage-not-passed"
        and out.get("message", "").strip() != "",
        f"{label} is refused as stage-not-passed naming the offending job",
        f"{label}: exit {result.returncode}, out={out}",
    )

# -- criterion: artifact-missing and artifact-expired. -----------------------
result = run(artifacts={"artifacts": []})
out = kv(result)
check(
    result.returncode != 0
    and out.get("reason") == "artifact-missing"
    and COMMIT in out.get("message", ""),
    "no matching artifact is refused as artifact-missing, naming the artifact",
    f"exit {result.returncode}, out={out}",
)

result = run(artifacts={"artifacts": [
    {"id": 9, "name": f"godot-linux-{COMMIT}", "expired": True},
]})
out = kv(result)
check(
    result.returncode != 0
    and out.get("reason") == "artifact-expired"
    and COMMIT in out.get("message", ""),
    "an expired artifact is refused as artifact-expired, naming the artifact",
    f"exit {result.returncode}, out={out}",
)

# -- criterion: tag-exists. --------------------------------------------------
result = run(tags=["v0.2.0"])
out = kv(result)
check(
    result.returncode != 0
    and out.get("reason") == "tag-exists"
    and "v0.2.0" in out.get("message", ""),
    "an existing v0.2.0 tag is refused as tag-exists, naming the tag",
    f"exit {result.returncode}, out={out}",
)

# -- criterion: exactly one reason= line per refusal. ------------------------
result = run(version="not-a-version")
reason_lines = [l for l in result.stdout.splitlines() if l.startswith("reason=")]
check(
    len(reason_lines) == 1,
    "a refusal prints exactly one reason= line",
    f"reason_lines={reason_lines!r}",
)

# -- criterion: two completed runs -- the later run_started_at wins. ---------
result = run(runs={"workflow_runs": [
    {"id": 111, "status": "completed", "run_started_at": "2026-09-14T10:00:00Z"},
    {"id": 222, "status": "completed", "run_started_at": "2026-09-14T12:00:00Z"},
]})
out = kv(result)
check(
    result.returncode == 0 and out.get("run_id") == "222",
    "with two completed runs, the later run_started_at is selected and its"
    " run_id is reported",
    f"exit {result.returncode}, out={out}",
)

# -- criterion: an unreadable or non-JSON input file is fatal, names the -----
#    file, and never prints verdict=ok.
missing = case_dir / "does-not-exist.json"
result = subprocess.run(
    [
        sys.executable, str(script),
        "--commit", COMMIT, "--version", "0.2.0", "--on-main", "true",
        "--runs-json", str(missing),
        "--jobs-json", str(write("jobs", JOBS_OK)),
        "--artifacts-json", str(write("artifacts", ARTIFACTS_OK)),
        "--tags-json", str(write("tags", TAGS_EMPTY)),
    ],
    capture_output=True, text=True,
)
check(
    result.returncode != 0
    and "verdict=ok" not in result.stdout
    and str(missing) in result.stderr,
    "a missing --runs-json is fatal, names the file on stderr, and never"
    " prints verdict=ok",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

not_json = write("not-json", "not actually json {{{")
result = subprocess.run(
    [
        sys.executable, str(script),
        "--commit", COMMIT, "--version", "0.2.0", "--on-main", "true",
        "--runs-json", str(not_json),
        "--jobs-json", str(write("jobs", JOBS_OK)),
        "--artifacts-json", str(write("artifacts", ARTIFACTS_OK)),
        "--tags-json", str(write("tags", TAGS_EMPTY)),
    ],
    capture_output=True, text=True,
)
check(
    result.returncode != 0
    and "verdict=ok" not in result.stdout
    and str(not_json) in result.stderr,
    "a non-JSON --runs-json is fatal, names the file on stderr, and never"
    " prints verdict=ok",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 22: release.yml's workflow shape (#223).
#
# Part 21 covers the decision; this part covers the machine wrapped around it.
# Patterned on Part 16's second half, and for the same reason: a stage whose
# whole value is that it publishes the verified bytes, unattended, is a stage
# whose shape can quietly invert while the YAML goes on looking right. A
# rebuild step added here would publish bytes nobody smoke-ran; a `push`
# trigger would make releasing automatic; a `--prerelease` behind an
# expression would ship a 0.x build as stable; a create split into
# tag-then-upload would leave half a release behind on failure.
#
# The artifact-name chain is asserted the way Part 16 asserts it for the smoke
# job, with one more link in it: `ci.yml` uploads under `godot-linux-<sha>`,
# `release-preflight.py` looks for `godot-linux-<commit>`, and release.yml
# must take the name from the script's output rather than spell it a third
# time. Those two expressions are the pair that has to agree; a literal in the
# workflow is how they would stop agreeing.
#
# Text inspection only -- pyyaml is not guaranteed on a bare runner, which is
# why the harness carries its own extractor. No network, no `gh`, no release
# ever created.
# ---------------------------------------------------------------------------

part22 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import pathlib
import re
import sys

sys.path.insert(0, sys.argv[1])
import wf

work_dir, repo_root = sys.argv[1], sys.argv[2]
root = pathlib.Path(repo_root)

WF_REL = ".github/workflows/release.yml"
CI_REL = ".github/workflows/ci.yml"
PREFLIGHT_REL = ".github/scripts/release-preflight.py"

wf_path = root / WF_REL
if not wf_path.exists():
    print(f"  FAIL — {WF_REL} does not exist", file=sys.stderr)
    sys.exit(1)

text = wf_path.read_text(encoding="utf-8")

# Full-line comments dropped for every token scan below, so the workflow may
# explain in prose what it must not do (`git tag`, `setup-godot`) without the
# explanation reading as the offence. Structural scans keep the original text:
# indentation is what stands in for a parser here.
code = "\n".join(
    line for line in text.splitlines() if not line.strip().startswith("#")
)

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


def top_block(key):
    """The lines nested under a top-level `key:`, to the next column-0 key."""

    lines = text.splitlines()
    try:
        start = lines.index(f"{key}:")
    except ValueError:
        return None

    out = []
    for line in lines[start + 1:]:
        if line.strip() and not line[0].isspace():
            break
        out.append(line)
    return "\n".join(out)


def entries(block, indent):
    """Non-comment keys at exactly `indent` spaces inside `block`."""

    return [
        line.strip()
        for line in block.splitlines()
        if line.strip()
        and not line.strip().startswith("#")
        and (len(line) - len(line.lstrip())) == indent
    ]


# --- The trigger: workflow_dispatch, and nothing else ----------------------
on_block = top_block("on")
check(
    on_block is not None and entries(on_block, 2) == ["workflow_dispatch:"],
    "workflow_dispatch is the only trigger",
    f"release.yml's `on:` block declares"
    f" {entries(on_block, 2) if on_block else None!r}. Publishing is a"
    f" decision a person makes; any other trigger is a route that reaches it"
    f" without one.",
)

input_names = entries(on_block or "", 6)
check(
    input_names == ["commit:", "version:"],
    "the dispatch inputs are exactly commit and version",
    f"release.yml declares inputs {input_names!r}, expected"
    f" ['commit:', 'version:'].",
)

required = re.findall(r"^\s*required:\s*(\S+)\s*$", on_block or "", re.M)
types = re.findall(r"^\s*type:\s*(\S+)\s*$", on_block or "", re.M)
check(
    required == ["true", "true"] and types == ["string", "string"],
    "both inputs are `required: true` and `type: string`",
    f"release.yml's inputs declare required={required!r} type={types!r}."
    f" Both must be required, and both `string` -- a `number` input reaches"
    f" the shell as a float, which Part 9 exists to remember.",
)

# --- Credential posture ----------------------------------------------------
permissions = top_block("permissions")
check(
    permissions is not None
    and sorted(entries(permissions, 2)) == ["actions: read", "contents: write"],
    "permissions are exactly contents: write and actions: read",
    f"release.yml's `permissions:` block is"
    f" {sorted(entries(permissions, 2)) if permissions else None!r}, expected"
    f" exactly ['actions: read', 'contents: write'].",
)

check(
    "secrets." not in code,
    "release.yml reads no secret",
    "release.yml references `secrets.` -- publishing runs on GITHUB_TOKEN"
    " alone, so a second credential here is a new key to leak.",
)

check(
    "GH_TOKEN: ${{ github.token }}" in code,
    "gh runs on GITHUB_TOKEN",
    "release.yml never sets `GH_TOKEN: ${{ github.token }}`, so its `gh`"
    " calls have no credential at all.",
)

uses = re.findall(r"^\s*uses:\s*(\S+)\s*$", code, re.M)
check(
    uses and all(u.startswith("actions/checkout@") for u in uses),
    f"the only action used is actions/checkout ({uses!r})",
    f"release.yml uses {uses!r}. A third-party action in the one job that can"
    f" write a release is a supply-chain hole with publish rights.",
)

# --- Concurrency: serialized, never cancelled ------------------------------
concurrency = top_block("concurrency")
check(
    concurrency is not None
    and re.search(r"^\s*group:\s*release\s*$", concurrency, re.M) is not None
    and "cancel-in-progress" not in concurrency,
    "releases are serialized under group `release` and never cancelled",
    f"release.yml's `concurrency:` block is {concurrency!r}. It must group on"
    f" `release` and must NOT cancel in progress -- a run cancelled between"
    f" `gh release create` and its rollback leaves the half release behind.",
)

# --- No rebuild anywhere in it ---------------------------------------------
for token, why in (
    ("setup-godot", "installing an engine here would publish a rebuild"),
    ("export-godot.sh", "the published bytes are the artifact, never a new build"),
    ("smoke-godot.sh", "the smoke stage already ran; re-running it is not releasing"),
    ("--export-release", "exporting is ci.yml's job, two stages earlier"),
):
    check(
        token not in code,
        f"release.yml references no {token}",
        f"release.yml references {token} -- {why}.",
    )

version_literals = re.findall(
    r"\b\d+\.\d+(?:\.\d+)?-(?:stable|beta\d*|rc\d*|dev\d*)\b", code
) + re.findall(r"^\s*godot-version:\s*\S", code, re.M)
check(
    not version_literals,
    "release.yml names no Godot version",
    f"release.yml names Godot version(s) {version_literals!r}. It installs no"
    f" engine, so any version here is a new pin site Part 7 would have to"
    f" keep in agreement for nothing.",
)

# --- One creating call, carrying everything --------------------------------
creates = re.findall(r"gh release create", code)
check(
    len(creates) == 1,
    "exactly one `gh release create` invocation",
    f"release.yml contains {len(creates)} `gh release create` invocations,"
    f" expected exactly 1.",
)

for flag, why in (
    ("--target", "the release must point at the dispatched commit, not at a branch tip"),
    ("--prerelease", "everything before 1.0 ships as a pre-release"),
    ("--generate-notes", "the notes are generated, not hand-written in this file"),
):
    check(
        flag in code,
        f"the create call carries {flag}",
        f"the `gh release create` call carries no {flag} -- {why}.",
    )

# `--prerelease` with nothing conditional around it. An expression on that
# line is the one way a 0.x build ships as stable.
prerelease_lines = [
    line.strip() for line in code.splitlines() if "--prerelease" in line
]
check(
    all(
        re.fullmatch(r"--prerelease\s*\\?", line) is not None
        for line in prerelease_lines
    ),
    "--prerelease is a literal flag with no expression around it",
    f"`--prerelease` appears as {prerelease_lines!r}. It must be an"
    f" unconditional literal: no input, variable or expression may turn it"
    f" off.",
)

check(
    '"${assets[@]}"' in code,
    "the create call publishes the downloaded assets in the same invocation",
    "the `gh release create` call carries no asset argument, so the release"
    " would be created empty and the assets uploaded (or not) afterwards.",
)

for token, why in (
    ("git tag", "the tag is created by `gh release create --target`, in one call"),
    ("git push", "nothing here pushes to the repository"),
    ("--draft", "a draft published in a second step is two windows, not one"),
):
    check(
        token not in code,
        f"release.yml contains no {token}",
        f"release.yml contains {token} -- {why}.",
    )

# --- Rollback: guarded on the create step, and after it --------------------
steps = []
for line in code.splitlines():
    if line.lstrip().startswith("- name:"):
        steps.append([line])
    elif steps:
        steps[-1].append(line)
steps = ["\n".join(s) for s in steps]

create_steps = [s for s in steps if "gh release create" in s]
delete_steps = [s for s in steps if "gh release delete" in s]

create_id = None
if create_steps:
    m = re.search(r"^\s*id:\s*(\S+)\s*$", create_steps[0], re.M)
    create_id = m.group(1) if m else None

check(
    len(delete_steps) == 1 and "--cleanup-tag" in delete_steps[0],
    "one rollback step deletes the release and its tag together",
    f"release.yml has {len(delete_steps)} `gh release delete` step(s), and"
    f" the rollback must pass `--cleanup-tag` -- a tag surviving a failed"
    f" create refuses the next attempt with `tag-exists` for a release that"
    f" does not exist.",
)

delete_if = (
    re.search(r"^\s*if:\s*(.+)$", delete_steps[0], re.M) if delete_steps else None
)
check(
    create_id is not None
    and delete_if is not None
    and f"steps.{create_id}.outcome" in delete_if.group(1)
    and "failure()" in delete_if.group(1),
    "the rollback runs only when the create step itself failed",
    f"the rollback step's `if:` is"
    f" {delete_if.group(1).strip() if delete_if else None!r}, which must name"
    f" both `failure()` and `steps.{create_id}.outcome` -- `failure()` alone"
    f" also fires for a later step, and the outcome alone is read on runs"
    f" where nothing failed.",
)

check(
    create_steps
    and delete_steps
    and code.index(delete_steps[0]) > code.index(create_steps[0]),
    "the rollback step appears after the create step",
    "release.yml's `gh release delete` step is not after its"
    " `gh release create` step; a rollback declared first cleans up nothing.",
)

# --- Preflight, then download, then create: in that file order -------------
order = []
for marker in (
    ".github/scripts/release-preflight.py",
    "gh run download",
    "gh release create",
):
    order.append((marker, code.find(marker)))

check(
    all(pos != -1 for _, pos in order)
    and [pos for _, pos in order] == sorted(pos for _, pos in order),
    "preflight, then artifact download, then release creation",
    f"release.yml's steps are out of order: {order!r}. Nothing may be"
    f" downloaded before the preflight passes, and nothing published before"
    f" the download.",
)

# --- The artifact name, end to end -----------------------------------------
# `ci.yml` uploads it, `release-preflight.py` looks for it, release.yml
# downloads whatever the script said. The first two are the expressions that
# must agree; the third must not spell the name at all.
ci_text = (root / CI_REL).read_text(encoding="utf-8")
ci_names = [
    n.strip() for n in re.findall(r"^\s*name:\s*(godot-linux-.+)$", ci_text, re.M)
]
preflight_text = (root / PREFLIGHT_REL).read_text(encoding="utf-8")
script_name = re.search(
    r'artifact_name\s*=\s*f"([^"{]*)\{args\.commit\}"', preflight_text
)

check(
    ci_names
    and script_name is not None
    and all(n.startswith(script_name.group(1)) for n in ci_names),
    f"ci.yml uploads and release-preflight.py looks for the same"
    f" {script_name.group(1) if script_name else None!r} name shape",
    f"ci.yml uploads {ci_names!r} but release-preflight.py builds"
    f" {script_name.group(1) if script_name else None!r}<commit>. A release"
    f" that looks for a name nothing uploads refuses every commit with"
    f" `artifact-missing`.",
)

check(
    "godot-linux-" not in code,
    "release.yml spells no artifact name of its own",
    "release.yml contains a literal `godot-linux-` name. The name it"
    " downloads must come from the preflight's `artifact_name` output, or"
    " this file becomes a third spelling that can drift from the other two.",
)

check(
    re.search(r"steps\.\w+\.outputs\.artifact_name", code) is not None
    and re.search(r"steps\.\w+\.outputs\.run_id", code) is not None,
    "the download names the run and artifact the preflight reported",
    "release.yml's download step does not read `artifact_name` and `run_id`"
    " from the preflight's outputs, so it is downloading from a run the"
    " script did not judge.",
)

# --- The refusal path reports, in the summary, and fails -------------------
preflight_steps = [
    s for s in steps if ".github/scripts/release-preflight.py" in s
]
check(
    len(preflight_steps) == 1,
    "exactly one step runs the preflight",
    f"release.yml runs the preflight in {len(preflight_steps)} steps; the"
    f" decision is made once or it is not a decision.",
)

refusal = preflight_steps[0] if preflight_steps else ""
check(
    "GITHUB_STEP_SUMMARY" in refusal
    and re.search(r"reason=", refusal) is not None
    and re.search(r"message=", refusal) is not None
    and re.search(r"^\s*exit 1\s*$", refusal, re.M) is not None,
    "a refusal writes reason= and message= to the step summary and fails",
    "the preflight step does not write both `reason=` and `message=` to"
    " $GITHUB_STEP_SUMMARY and `exit 1`. An operator must see which of the"
    " seven refusal reasons it was without opening the raw log.",
)

check(
    all(
        marker in code
        for marker in ("sha256sum", "$GITHUB_STEP_SUMMARY")
    ),
    "the published assets are checksummed into the step summary",
    "release.yml never runs `sha256sum` into $GITHUB_STEP_SUMMARY, so the"
    " run that published the bytes leaves no record of which bytes they"
    " were.",
)

published = create_steps[0] if create_steps else ""
check(
    "GITHUB_STEP_SUMMARY" in published
    and "$url" in published
    and "$TAG" in published
    and "$RUN_ID" in published,
    "the successful path reports the release URL, the tag and the source run",
    "the create step does not write the release URL, the tag and the source"
    " CI run id to $GITHUB_STEP_SUMMARY.",
)

# --- This is the only workflow that can publish ----------------------------
PUBLISHERS = (
    "gh release create",
    "gh release upload",
    "softprops/action-gh-release",
    "ncipollo/release-action",
    "actions/create-release",
    "actions/upload-release-asset",
)
others = []
for path in sorted(pathlib.Path(".github/workflows").glob("*.yml")):
    if path.as_posix() == WF_REL:
        continue
    body = "\n".join(
        line for line in path.read_text(encoding="utf-8").splitlines()
        if not line.strip().startswith("#")
    )
    for token in PUBLISHERS:
        if token in body:
            others.append((path.as_posix(), token))

check(
    not others,
    f"release.yml is the only workflow that can publish a release",
    f"these workflows can publish a release too: {others!r}. One publishing"
    f" path is what makes the preflight unavoidable.",
)

# --- House rules -----------------------------------------------------------
unset = [
    line
    for line, src in wf.all_steps(WF_REL)
    if not src.lstrip().startswith("set -euo pipefail")
]
check(
    not unset,
    "every embedded shell program begins `set -euo pipefail`",
    f"release.yml has run: blocks at line(s) {unset!r} that do not begin"
    f" `set -euo pipefail`.",
)

stray = []
for line in code.splitlines():
    m = re.match(r"^\s*(?:path|[A-Z][A-Z0-9_]*):\s*(\S.*?)\s*$", line)
    if not m:
        continue
    value = m.group(1)
    if "/" not in value or value.startswith((".github/", "./.github/")):
        continue
    if "runner.temp" not in value:
        stray.append(value)

check(
    not stray,
    "every path release.yml names is under ${{ runner.temp }}",
    f"release.yml names paths outside $RUNNER_TEMP: {stray!r}. A downloaded"
    f" build inside the checkout is #84 repeating.",
)

sys.exit(1 if failures else 0)
PY
}

# ---------------------------------------------------------------------------
# Part 23: red-main.py's decision and rendering (#224).
#
# The escalation workflow (T2, not yet built) fetches JSON and hands it to
# this script; the script owns every decision and every rendered byte.
# Covered end-to-end with fixture GitHub JSON and no network, no `gh`, and no
# Issue ever created -- Part 21's shape, for the same reason: this is a
# standalone decision script read via `subprocess`, not a step embedded in a
# workflow file.
# ---------------------------------------------------------------------------

part23 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import json
import pathlib
import re
import subprocess
import sys
import tempfile

work_dir, repo_root = sys.argv[1], sys.argv[2]
script = pathlib.Path(repo_root) / ".github" / "scripts" / "red-main.py"
case_dir = pathlib.Path(tempfile.mkdtemp(prefix="rm-case.", dir=work_dir))

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


RUN_URL = "https://github.com/o/r/actions/runs/{id}"

RUN1 = {
    "id": 111, "conclusion": "failure", "event": "push", "head_branch": "main",
    "head_sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
    "html_url": RUN_URL.format(id=111),
    "run_started_at": "2026-09-14T10:00:00Z",
    "updated_at": "2026-09-14T10:05:00Z",
}
RUN2 = {
    **RUN1, "id": 222, "html_url": RUN_URL.format(id=222),
    "run_started_at": "2026-09-14T11:00:00Z", "updated_at": "2026-09-14T11:05:00Z",
}
RUN3_GREEN = {
    **RUN1, "id": 333, "conclusion": "success", "html_url": RUN_URL.format(id=333),
    "run_started_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:05:00Z",
}

JOBS_RED = {"jobs": [
    {"name": "Godot Export", "conclusion": "success", "id": 1,
     "started_at": "2026-09-14T10:00:00Z", "steps": []},
    {"name": "Godot Smoke Run", "conclusion": "failure", "id": 2,
     "started_at": "2026-09-14T10:00:10Z", "steps": [
         {"name": "Setup", "number": 1, "conclusion": "success"},
         {"name": "Run smoke", "number": 2, "conclusion": "failure"},
     ]},
]}
JOBS_GREEN = {"jobs": [
    {"name": "Godot Export", "conclusion": "success", "id": 1,
     "started_at": "2026-09-14T12:00:00Z", "steps": []},
]}
JOBS_NO_RED_JOB = {"jobs": [
    {"name": "Godot Export", "conclusion": "success", "id": 1,
     "started_at": "2026-09-14T10:00:00Z", "steps": []},
]}
JOBS_RED_JOB_NO_RED_STEP = {"jobs": [
    {"name": "Godot Export", "conclusion": "failure", "id": 1,
     "started_at": "2026-09-14T10:00:00Z", "steps": [
         {"name": "Setup", "number": 1, "conclusion": "success"},
     ]},
]}

COMMIT_DIRECT = {
    "message": "Fix the thing\n\nmore detail",
    "changed_files": ["rules/actions/move_action.gd"],
    "pull_requests": [],
}
COMMIT_PR = {**COMMIT_DIRECT, "pull_requests": [{"number": 7}]}
COMMIT_LEDGER_SUBJECT = {
    "message": "chore(ledger): record run 111",
    "changed_files": ["docs/x.md"],
    "pull_requests": [],
}
COMMIT_METRICS_PATHS = {
    "message": "update metrics",
    "changed_files": [".metrics/runs.csv", ".metrics/other.csv"],
    "pull_requests": [],
}

ISSUE_NONE = None


def write(name, data, n=[0]):
    n[0] += 1
    path = case_dir / f"{name}-{n[0]}.json"
    if isinstance(data, str):
        path.write_text(data, encoding="utf-8")
    else:
        path.write_text(json.dumps(data), encoding="utf-8")
    return path


def run(*, run_=RUN1, jobs=JOBS_RED, commit=COMMIT_DIRECT, issue=ISSUE_NONE,
        body_out=None, comment_out=None):
    if body_out is None:
        body_out = pathlib.Path(tempfile.mktemp(prefix="body-", suffix=".md", dir=case_dir))
    if comment_out is None:
        comment_out = pathlib.Path(tempfile.mktemp(prefix="comment-", suffix=".md", dir=case_dir))
    args = [
        sys.executable, str(script),
        "--run-json", str(write("run", run_)),
        "--jobs-json", str(write("jobs", jobs)),
        "--commit-json", str(write("commit", commit)),
        "--issue-json", str(write("issue", issue)),
        "--body-out", str(body_out),
        "--comment-out", str(comment_out),
    ]
    result = subprocess.run(args, capture_output=True, text=True)
    return result, body_out, comment_out


def kv(result):
    return dict(
        line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
    )


# -- criterion: standard-library only, no subprocess/urllib/requests/gh. ----
source = script.read_text(encoding="utf-8")
forbidden = re.search(
    r"^\s*(?:import|from)\s+(subprocess|urllib\.request|http|socket|requests)\b"
    r"|\b(?:subprocess|socket)\.\w+\("
    r"|\bgh\s+(?:issue|api|run)\b",
    source, re.MULTILINE,
)
check(
    script.stat().st_mode & 0o111 != 0
    and source.startswith("#!/usr/bin/env python3\n")
    and forbidden is None,
    "red-main.py is executable, starts with the python3 shebang, and its"
    " source names no subprocess/urllib/requests/http/socket/gh",
    f"executable={script.stat().st_mode & 0o111 != 0}, forbidden={forbidden}",
)

# -- criterion: red, no open Issue -- action=open. ---------------------------
result, body1_path, comment1_path = run(run_=RUN1, jobs=JOBS_RED, commit=COMMIT_DIRECT, issue=ISSUE_NONE)
out = kv(result)
body1 = body1_path.read_text(encoding="utf-8")
comment1 = comment1_path.read_text(encoding="utf-8")
marker1 = json.loads(re.search(r"<!--\s*red-main-state\s+(\{.*?\})\s*-->", body1, re.DOTALL).group(1))
check(
    result.returncode == 0
    and out.get("action") == "open"
    and "a1b2c3d" in body1
    and "Fix the thing" in body1
    and "Godot Smoke Run" in body1
    and "Run smoke" in body1
    and RUN1["html_url"] in body1
    and "direct-push" in body1
    and "2026-09-14T10:00:00Z" in body1
    and marker1["failures"] == 1
    and marker1["first_failure_run_id"] == 111
    and RUN1["html_url"] in comment1,
    "a red run on main from push with no open Issue opens, naming the short"
    " SHA, subject, failing job, first failing step, run URL, provenance and"
    " first-red timestamp, with failures=1",
    f"exit {result.returncode}, out={out}, body={body1!r}, marker={marker1!r}",
)

# -- criterion: red, open Issue -- action=update, marker preserved. ---------
issue1 = {"number": 42, "body": body1}
result, body2_path, comment2_path = run(run_=RUN2, jobs=JOBS_RED, commit=COMMIT_DIRECT, issue=issue1)
out = kv(result)
body2 = body2_path.read_text(encoding="utf-8")
marker2 = json.loads(re.search(r"<!--\s*red-main-state\s+(\{.*?\})\s*-->", body2, re.DOTALL).group(1))
check(
    result.returncode == 0
    and out.get("action") == "update"
    and "reason" not in out
    and marker2["first_failure_run_id"] == marker1["first_failure_run_id"]
    and marker2["first_failure_at"] == marker1["first_failure_at"]
    and marker2["failures"] == 2,
    "a second red run against the open Issue updates, preserving"
    " first_failure_run_id/first_failure_at while failures reads 2",
    f"exit {result.returncode}, out={out}, marker2={marker2!r}",
)

# -- criterion: green, open Issue -- action=close with interval and links. --
issue2 = {"number": 42, "body": body2}
result, body3_path, comment3_path = run(run_=RUN3_GREEN, jobs=JOBS_GREEN, commit=COMMIT_DIRECT, issue=issue2)
out = kv(result)
comment3 = comment3_path.read_text(encoding="utf-8")
expected_interval = 7500  # 2026-09-14T12:05:00Z - 2026-09-14T10:00:00Z
check(
    result.returncode == 0
    and out.get("action") == "close"
    and out.get("interval_seconds") == str(expected_interval)
    and out.get("first_failure_run_id") == "111"
    and str(expected_interval) in comment3
    and RUN1["html_url"] in comment3
    and RUN3_GREEN["html_url"] in comment3,
    "a green run with the open Issue closes with the correct interval and a"
    " comment linking both the first failing run and the restoring run",
    f"exit {result.returncode}, out={out}, comment={comment3!r}",
)

# -- criterion: green, no open Issue -- already-green. -----------------------
result, _, _ = run(run_=RUN3_GREEN, jobs=JOBS_GREEN, commit=COMMIT_DIRECT, issue=ISSUE_NONE)
out = kv(result)
check(
    result.returncode == 0 and out.get("action") == "none" and out.get("reason") == "already-green",
    "a green run with no open Issue prints action=none reason=already-green",
    f"exit {result.returncode}, out={out}",
)

# -- criterion: cancelled/skipped -- inconclusive. ---------------------------
for conclusion in ("cancelled", "skipped"):
    result, _, _ = run(run_={**RUN1, "conclusion": conclusion}, issue=ISSUE_NONE)
    out = kv(result)
    check(
        result.returncode == 0 and out.get("action") == "none" and out.get("reason") == "inconclusive",
        f"a {conclusion} run prints action=none reason=inconclusive",
        f"exit {result.returncode}, out={out}",
    )

# -- criterion: not main / not push -- not-main-push. ------------------------
for override in ({"head_branch": "other"}, {"event": "pull_request"}):
    result, _, _ = run(run_={**RUN1, **override}, issue=ISSUE_NONE)
    out = kv(result)
    check(
        result.returncode == 0 and out.get("action") == "none" and out.get("reason") == "not-main-push",
        f"a run with {override} prints action=none reason=not-main-push",
        f"exit {result.returncode}, out={out}",
    )

# -- criterion: already-recorded is a no-op, writing no body or comment. -----
recorded_body_path = pathlib.Path(tempfile.mktemp(prefix="body-", suffix=".md", dir=case_dir))
recorded_comment_path = pathlib.Path(tempfile.mktemp(prefix="comment-", suffix=".md", dir=case_dir))
result, _, _ = run(
    run_=RUN2, jobs=JOBS_RED, commit=COMMIT_DIRECT, issue=issue2,
    body_out=recorded_body_path, comment_out=recorded_comment_path,
)
out = kv(result)
check(
    result.returncode == 0
    and out.get("action") == "none"
    and out.get("reason") == "already-recorded"
    and not recorded_body_path.exists()
    and not recorded_comment_path.exists(),
    "re-running an already-recorded run id prints action=none"
    " reason=already-recorded and writes no body or comment file",
    f"exit {result.returncode}, out={out}, body_exists={recorded_body_path.exists()},"
    f" comment_exists={recorded_comment_path.exists()}",
)

# -- criterion: provenance classification, all four ways. --------------------
result, body_pr, _ = run(run_=RUN1, jobs=JOBS_RED, commit=COMMIT_PR, issue=ISSUE_NONE)
check(
    result.returncode == 0 and "pull-request" in body_pr.read_text(encoding="utf-8"),
    "a commit with an associated pull request renders provenance pull-request",
    body_pr.read_text(encoding="utf-8"),
)

result, body_ledger, _ = run(run_=RUN1, jobs=JOBS_RED, commit=COMMIT_LEDGER_SUBJECT, issue=ISSUE_NONE)
check(
    result.returncode == 0 and "bookkeeping" in body_ledger.read_text(encoding="utf-8"),
    "a chore(ledger): subject with no pull request renders provenance bookkeeping",
    body_ledger.read_text(encoding="utf-8"),
)

result, body_metrics, _ = run(run_=RUN1, jobs=JOBS_RED, commit=COMMIT_METRICS_PATHS, issue=ISSUE_NONE)
check(
    result.returncode == 0 and "bookkeeping" in body_metrics.read_text(encoding="utf-8"),
    "changed paths entirely under .metrics/ render provenance bookkeeping",
    body_metrics.read_text(encoding="utf-8"),
)

result, body_direct, _ = run(run_=RUN1, jobs=JOBS_RED, commit=COMMIT_DIRECT, issue=ISSUE_NONE)
check(
    result.returncode == 0 and "direct-push" in body_direct.read_text(encoding="utf-8"),
    "a commit touching rules/ with no pull request and no bookkeeping shape"
    " renders provenance direct-push",
    body_direct.read_text(encoding="utf-8"),
)

# -- criterion: unknown job/step fallback. -----------------------------------
result, body_no_job, _ = run(run_=RUN1, jobs=JOBS_NO_RED_JOB, commit=COMMIT_DIRECT, issue=ISSUE_NONE)
check(
    result.returncode == 0
    and "Failing job:** unknown" in body_no_job.read_text(encoding="utf-8")
    and "First failing step:** unknown" in body_no_job.read_text(encoding="utf-8"),
    "no red job in --jobs-json renders both the job and the step as unknown",
    body_no_job.read_text(encoding="utf-8"),
)

result, body_no_step, _ = run(run_=RUN1, jobs=JOBS_RED_JOB_NO_RED_STEP, commit=COMMIT_DIRECT, issue=ISSUE_NONE)
check(
    result.returncode == 0
    and "Failing job:** Godot Export" in body_no_step.read_text(encoding="utf-8")
    and "First failing step:** unknown" in body_no_step.read_text(encoding="utf-8"),
    "a red job with no red step renders the step as unknown",
    body_no_step.read_text(encoding="utf-8"),
)

# -- criterion: a missing or unparseable marker recovers rather than raises. -
for bad_body in ("no marker here at all", "<!-- red-main-state {not json} -->"):
    issue_bad = {"number": 42, "body": bad_body}
    result, _, _ = run(run_=RUN1, jobs=JOBS_RED, commit=COMMIT_DIRECT, issue=issue_bad)
    out = kv(result)
    check(
        result.returncode == 0
        and out.get("action") == "update"
        and out.get("reason") == "state-recovered"
        and "Traceback" not in result.stderr,
        f"an open Issue body {bad_body!r} recovers as action=update"
        " reason=state-recovered with no traceback",
        f"exit {result.returncode}, out={out}, stderr={result.stderr!r}",
    )

# -- criterion: a missing or non-JSON --*-json file is fatal, names the -----
#    file on stderr, and prints no key=value line on stdout.
missing = case_dir / "does-not-exist.json"
args = [
    sys.executable, str(script),
    "--run-json", str(missing),
    "--jobs-json", str(write("jobs", JOBS_RED)),
    "--commit-json", str(write("commit", COMMIT_DIRECT)),
    "--issue-json", str(write("issue", ISSUE_NONE)),
]
result = subprocess.run(args, capture_output=True, text=True)
check(
    result.returncode != 0
    and result.stdout.strip() == ""
    and str(missing) in result.stderr,
    "a missing --run-json is fatal, names the file on stderr, and prints no"
    " key=value line on stdout",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

not_json = write("not-json", "not actually json {{{")
args = [
    sys.executable, str(script),
    "--run-json", str(not_json),
    "--jobs-json", str(write("jobs", JOBS_RED)),
    "--commit-json", str(write("commit", COMMIT_DIRECT)),
    "--issue-json", str(write("issue", ISSUE_NONE)),
]
result = subprocess.run(args, capture_output=True, text=True)
check(
    result.returncode != 0
    and result.stdout.strip() == ""
    and str(not_json) in result.stderr,
    "a non-JSON --run-json is fatal, names the file on stderr, and prints no"
    " key=value line on stdout",
    f"exit {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}",
)

sys.exit(1 if failures else 0)
PY
}

part24 () {
  python3 - "$work_dir" "$repo_root" <<'PY'
import os
import pathlib
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
import wf

work_dir, repo_root = sys.argv[1], sys.argv[2]
part_dir = pathlib.Path(tempfile.mkdtemp(prefix="part24.", dir=work_dir))

RED_MAIN_WF = ".github/workflows/red-main.yml"
RED_MAIN_PY = ".github/scripts/red-main.py"
BOOTSTRAP = ".github/scripts/bootstrap-labels.sh"

failures = []


def check(condition, ok, why):
    if condition:
        print(f"  ok   — {ok}")
    else:
        failures.append(why)
        print(f"  FAIL — {why}", file=sys.stderr)


# -- criterion 1: red-main.yml shape by text inspection. --------------------
wf_path = pathlib.Path(repo_root) / RED_MAIN_WF
wf_text = wf_path.read_text(encoding="utf-8")

check(
    "workflow_run:" in wf_text
    and "types: [completed]" in wf_text
    and "branches: [main]" in wf_text,
    "red-main.yml triggers on workflow_run for CI with [completed] and [main]",
    "trigger check"
)

check(
    "workflow_dispatch:" in wf_text
    and "run_id:" in wf_text
    and "type: string" in wf_text,
    "red-main.yml has workflow_dispatch with run_id input of type: string",
    "dispatch check"
)

check(
    re.search(r"if:.*github\.event\.workflow_run\.event", wf_text) or
    re.search(r'EVENT.*push', wf_text),
    "red-main.yml has a job-level or step-level if: checking for push event",
    "no push event guard found"
)

check(
    "permissions:" in wf_text
    and "contents: read" in wf_text
    and "issues: write" in wf_text
    and not re.search(r"^\s+(pull-requests|checks|actions|statuses|deployments|packages|code-scanning|security-events|dependabot-alerts|dependabot-updates):", wf_text, re.MULTILINE),
    "red-main.yml has exactly contents: read and issues: write permissions (no others)",
    "permissions check found extra permissions"
)

check(
    "GH_TOKEN: ${{ github.token }}" in wf_text,
    "red-main.yml sets GH_TOKEN to github.token, not secrets.*",
    "token check"
)

check(
    "secrets." not in wf_text,
    "red-main.yml contains no secrets.* reference",
    "secrets reference found"
)

check(
    "run-agent-session" not in wf_text,
    "red-main.yml does not invoke run-agent-session",
    "run-agent-session found"
)

check(
    "claude" not in wf_text and "copilot" not in wf_text,
    "red-main.yml does not invoke model CLI (claude/copilot)",
    "model CLI invocation found"
)

check(
    not re.search(r"^\s*continue-on-error:", wf_text, re.MULTILINE),
    "red-main.yml contains no continue-on-error line",
    "continue-on-error found"
)

check(
    "concurrency:" in wf_text
    and "group: red-main" in wf_text
    and "cancel-in-progress: false" in wf_text,
    "red-main.yml has concurrency group red-main with cancel-in-progress: false",
    "concurrency check"
)

check(
    "gh label list" in wf_text,
    "red-main.yml ensures label exists before querying",
    "label list/create not found"
)

check(
    "gh issue list" in wf_text and "--label" in wf_text and "red-main" in wf_text,
    "red-main.yml uses label for issue lookup, not title search",
    "issue list by label not found"
)

check(
    not any(cli in wf_text for cli in ["claude ", "copilot ", "anthropic "]),
    "red-main.yml contains no model CLI invocations",
    "model CLI found in workflow"
)

# -- criterion 2: bootstrap-labels.sh has red-main entry. ------------------
bootstrap_path = pathlib.Path(repo_root) / BOOTSTRAP
bootstrap_text = bootstrap_path.read_text(encoding="utf-8")

check(
    "red-main|" in bootstrap_text,
    "bootstrap-labels.sh has a red-main label entry",
    "red-main entry not found in bootstrap"
)

# Extract and check description length
desc_match = re.search(r"red-main\|[^|]*\|(.{1,100})\n", bootstrap_text)
if desc_match:
    desc = desc_match.group(1)
    check(
        len(desc) <= 100,
        f"bootstrap-labels.sh red-main description is {len(desc)} chars (≤100)",
        f"description too long: {len(desc)} chars"
    )
else:
    check(False, "bootstrap-labels.sh has valid red-main entry", "malformed entry")

# -- criterion 3: ci.yml GODOT_DENY has both new files. -------------------
CI_WF = ".github/workflows/ci.yml"
ci_path = pathlib.Path(repo_root) / CI_WF
ci_text = ci_path.read_text(encoding="utf-8")

check(
    ".github/workflows/red-main.yml" in ci_text
    and ".github/scripts/red-main.py" in ci_text,
    "ci.yml GODOT_DENY list includes both red-main.yml and red-main.py",
    "ci.yml missing new files in GODOT_DENY"
)

# -- criterion 4: gate harness test for new files (reuse Part 13). ---------
determine_gates = wf.step_source(CI_WF, "Determine Gates", shell="bash")
step = part_dir / "determine-gates.sh"
step.write_text(determine_gates, encoding="utf-8")

# Reuse TestHarness from shared module instead of duplicating Part 13's harness
harness = wf.TestHarness(part_dir)

# Test: PR touching only red-main files should gate correctly
result, outputs = harness.run_pull_request(step, [".github/workflows/red-main.yml", ".github/scripts/red-main.py"], cwd=part_dir)
check(
    result.returncode == 0
    and outputs.get("godot") == "false"
    and outputs.get("control_plane") == "true",
    "PR touching only red-main files: godot=false, control_plane=true",
    f"exit {result.returncode}, outputs={outputs}, stderr={result.stderr!r}",
)

# -- criterion 5: Decide Action parses output with proper grep | while wrapping.
decide_action_src = wf.step_source(".github/workflows/red-main.yml", "Decide Action", shell="bash")
check(
    "(grep -E" in decide_action_src and "|| true) | while" in decide_action_src,
    "Decide Action wraps grep with parentheses before pipe to handle empty results",
    "grep pattern not wrapped in parentheses"
)

# -- criterion 6: Execute Action has proper retry logic and summary writes.
execute_action_src = wf.step_source(".github/workflows/red-main.yml", "Execute Action", shell="bash")

# Check for retry logic: each mutation should have sleep and two gh calls
check(
    execute_action_src.count("gh issue create") >= 2 and "sleep 1" in execute_action_src,
    "Execute Action retries gh issue create with sleep",
    "retry pattern not found"
)

check(
    execute_action_src.count("gh issue edit") >= 2 and "sleep 1" in execute_action_src,
    "Execute Action retries gh issue edit with sleep",
    "retry pattern not found"
)

check(
    execute_action_src.count("gh issue close") >= 2 and "sleep 1" in execute_action_src,
    "Execute Action retries gh issue close with sleep",
    "retry pattern not found"
)

# Check that all gh mutation failures write to step summary
comment_failures = execute_action_src.count("gh issue comment failed")
check(
    comment_failures >= 2 and ("$GITHUB_STEP_SUMMARY" in execute_action_src),
    "Execute Action writes failure reasons to GITHUB_STEP_SUMMARY",
    f"comment failures={comment_failures}, summary writes found"
)

# -- criterion 7: Execute Action execution against stub gh with failure modes.
# Extract the Execute Action step and test it against fail-then-succeed stub
execute_action = part_dir / "execute-action.sh"
execute_action.write_text(execute_action_src, encoding="utf-8")

# fail-then-succeed stub: exits non-zero first time, then succeeds
# Uses a counter file to track attempts
def create_fail_then_succeed_stub(stub_path, counter_file):
    stub_path.write_text(
        f"""#!/usr/bin/env bash
set -euo pipefail
counter_file="{counter_file}"
mkdir -p "$(dirname "$counter_file")"
if [ ! -f "$counter_file" ]; then
    echo "0" > "$counter_file"
fi
attempt=$(<"$counter_file")
echo $((attempt + 1)) > "$counter_file"

# First gh call (any operation): fail with exit 42
# Second gh call onwards: succeed
if [ "$attempt" = "0" ]; then
    # First attempt always fails
    exit 42
fi

# Second attempt onwards: succeed and print URL for create operations
if [[ "$1" == "issue" && "$2" == "create" ]]; then
    echo "https://github.com/test/repo/issues/123"
fi
exit 0
""",
        encoding="utf-8",
    )
    stub_path.chmod(0o755)

# Test: Execute Action with fail-then-succeed stub
case_dir = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
counter_file = case_dir / "attempts"
bin_subdir = case_dir / "bin"
bin_subdir.mkdir()

gh_stub_fail = bin_subdir / "gh"
create_fail_then_succeed_stub(gh_stub_fail, counter_file)

# Create mock input files for Execute Action
body_file = case_dir / "body.md"
body_file.write_text("Issue body\n", encoding="utf-8")
comment_file = case_dir / "comment.md"
comment_file.write_text("Comment body\n", encoding="utf-8")
step_summary = case_dir / "step_summary"
step_summary.write_text("", encoding="utf-8")
github_output = case_dir / "github_output"
github_output.write_text("", encoding="utf-8")

result = subprocess.run(
    ["bash", str(execute_action)],
    capture_output=True,
    text=True,
    cwd=str(case_dir),
    env={
        "RUNNER_TEMP": str(case_dir),
        "GITHUB_STEP_SUMMARY": str(step_summary),
        "GITHUB_OUTPUT": str(github_output),
        "ACTION": "open",
        "REASON": "test reason",
        "TITLE": "Test Issue",
        "GITHUB_REPOSITORY": "test/repo",
        "RED_MAIN_LABEL": "red-main",
        "PATH": f"{bin_subdir}:{os.environ.get('PATH', '')}",
        "GH_TOKEN": "test-token",
    },
)

# With fail-then-succeed stub, should eventually exit 0 and have retried exactly twice
attempts = int(counter_file.read_text().strip())
check(
    result.returncode == 0 and attempts == 2,
    "Execute Action with fail-then-succeed stub: retries exactly once, exits 0",
    f"exit {result.returncode}, attempts={attempts}, stderr={result.stderr!r}"
)

# Test: Execute Action with always-failing stub
# Verify exactly 2 attempts, non-zero exit, error annotation, and reason in summary
def create_always_fail_stub(stub_path, counter_file):
    stub_path.write_text(
        f"""#!/usr/bin/env bash
set -euo pipefail
counter_file="{counter_file}"
mkdir -p "$(dirname "$counter_file")"
if [ ! -f "$counter_file" ]; then
    echo "0" > "$counter_file"
fi
attempt=$(<"$counter_file")
echo $((attempt + 1)) > "$counter_file"
# Always fail, regardless of operation
exit 42
""",
        encoding="utf-8",
    )
    stub_path.chmod(0o755)

case_dir_fail = pathlib.Path(tempfile.mkdtemp(dir=part_dir))
counter_file_fail = case_dir_fail / "attempts"
bin_subdir_fail = case_dir_fail / "bin"
bin_subdir_fail.mkdir()

gh_stub_fail_always = bin_subdir_fail / "gh"
create_always_fail_stub(gh_stub_fail_always, counter_file_fail)

# Create mock input files for Execute Action
body_file_fail = case_dir_fail / "body.md"
body_file_fail.write_text("Issue body\n", encoding="utf-8")
comment_file_fail = case_dir_fail / "comment.md"
comment_file_fail.write_text("Comment body\n", encoding="utf-8")
step_summary_fail = case_dir_fail / "step_summary"
step_summary_fail.write_text("", encoding="utf-8")
github_output_fail = case_dir_fail / "github_output"
github_output_fail.write_text("", encoding="utf-8")

result_fail = subprocess.run(
    ["bash", str(execute_action)],
    capture_output=True,
    text=True,
    cwd=str(case_dir_fail),
    env={
        "RUNNER_TEMP": str(case_dir_fail),
        "GITHUB_STEP_SUMMARY": str(step_summary_fail),
        "GITHUB_OUTPUT": str(github_output_fail),
        "ACTION": "open",
        "REASON": "test failure reason",
        "TITLE": "Test Issue",
        "GITHUB_REPOSITORY": "test/repo",
        "RED_MAIN_LABEL": "red-main",
        "PATH": f"{bin_subdir_fail}:{os.environ.get('PATH', '')}",
        "GH_TOKEN": "test-token",
    },
)

# With always-fail stub, should exit non-zero with exactly 2 attempts
attempts_fail = int(counter_file_fail.read_text().strip())
summary_content = step_summary_fail.read_text()
has_error = "::error::" in result_fail.stderr or "::error::" in result_fail.stdout
has_reason_in_summary = "test failure reason" in summary_content

check(
    result_fail.returncode != 0 and attempts_fail == 2 and has_error and has_reason_in_summary,
    "Execute Action with always-fail stub: exactly 2 attempts, non-zero exit, error annotation, reason in summary",
    f"exit {result_fail.returncode}, attempts={attempts_fail}, has_error={has_error}, has_reason={has_reason_in_summary}, summary={summary_content!r}"
)

sys.exit(1 if failures else 0)
PY
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
run_part "Part 9: no float-valued dispatch inputs" part9
run_part "Part 10: plan-review request assembly (#226/#227)" part10
run_part "Part 11: verdict extraction in both modes (#230)" part11
run_part "Part 12: count-tests.py suites, assertions and compare (#283)" part12
run_part "Part 13: run ledger gate logic, pull_request and push (#295)" part13
run_part "Part 14: ledger_row.py field derivation (#296)" part14
run_part "Part 15: session-record writers (#297)" part15
run_part "Part 16: smoke stage verdicts and job shape (#312)" part16
run_part "Part 17: red-gate.py scope and merge-base verdict (#327)" part17
run_part "Part 18: pipeline_metrics.py ledger validation and figures (#339)" part18
run_part "Part 19: pipeline report rendering and GitHub figures (#340)" part19
run_part "Part 20: pipeline-report.yml shape and ci.yml gate (#341)" part20
run_part "Part 21: release preflight verdicts (#223)" part21
run_part "Part 22: release workflow shape (#223)" part22
run_part "Part 23: red-main.py decision and rendering (#224)" part23
run_part "Part 24: red-main.yml workflow shape and gate logic (#360)" part24

echo
if [ "$failures" -eq 0 ]; then
  echo "All workflow logic checks passed."
else
  echo "$failures check(s) failed." >&2
fi

exit $((failures > 0))

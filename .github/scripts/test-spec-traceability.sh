#!/usr/bin/env bash
# Structural check harness for the spec-traceability index.
#
# Two things are pinned here, and both are things that fail silently when they
# break -- which is exactly how a traceability index goes stale in the first
# place:
#
#   1. `docs/spec-traceability.json` parses against `spec_traceability.py`'s
#      own schema (T1, #383) with no errors -- no duplicate `TR-NNNN` id, no
#      `active` entry with an empty `modules` list, no malformed section.
#   2. Every path the index cites, in either `modules` or `tests`, actually
#      exists in the tree, and every top-level section §1-§12 the spec
#      declares has an index entry that resolves to it. An index that cites a
#      file which has since moved, or a spec section a nobody ever indexed,
#      is wrong in a way nothing else here catches.
#
# Both checks are run against the real tree (Part 1) and, separately, against
# fixtures written under `mktemp -d` (Part 2) -- so each failure path is
# proven to fail rather than assumed to. Neither part re-implements any of
# `spec_traceability.py`'s own schema validation; both call `load_index` and
# `parse_sections` and read what comes back.
#
# Part 3 covers `spec-impact-report.py` (T3, #385), the tool that diffs the
# spec between two refs and classifies what it touches. Each fixture case is
# a one-commit throwaway git repo under `mktemp -d` with its own
# `docs/hex-skirmish-game-spec.md` and `docs/spec-traceability.json`; the
# base text is the commit, the head text is a working-tree edit on top of
# it, and the report is produced by running the real script against that
# fixture repo -- never by importing it, which the module's own header
# forbids.
#
# Needs nothing but python3 -- no network, no credentials, no `gh`, no `jq`
# dependency, and it never touches a real GitHub repository. Same posture as
# `test-issue-dependencies.sh`.
#
# Usage: .github/scripts/test-spec-traceability.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts="$repo_root/.github/scripts"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

failures=0

pass() { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1" >&2; failures=$((failures + 1)); }

# The shared check, run once against the real tree in Part 1 and once per
# fixture in Part 2, so every path through it is exercised the same way.
cat > "$work_dir/check_traceability.py" <<'PY'
"""Shared traceability check, invoked with:

    check_traceability.py <scripts-dir> <repo-root> <index-path> <spec-path>

Loads the index and the spec through spec_traceability.py's own functions --
load_index() for schema validation, parse_sections() and resolve() for the
section-coverage check below -- and adds exactly the two things that module
does not already check: that every cited path exists, and that every
top-level spec section resolves to an entry. Exits 0 with no output problem,
non-zero with a FAIL line per defect naming the entry id, the section number,
or the offending path.
"""
import pathlib
import sys

scripts_dir, repo_root, index_path, spec_path = sys.argv[1:5]
sys.path.insert(0, scripts_dir)
import spec_traceability as st

repo_root = pathlib.Path(repo_root)
failed = False

index, errors = st.load_index(index_path)
for err in errors:
    failed = True
    entry_id = err.get("id", "?")
    print(f"FAIL - schema: {err['type']} (id={entry_id}): {err['message']}")

if index is not None:
    for entry in index.get("entries", []):
        if not isinstance(entry, dict):
            continue
        entry_id = entry.get("id", "?")
        for field in ("modules", "tests"):
            for path in entry.get(field, []) or []:
                if not (repo_root / path).exists():
                    failed = True
                    print(
                        f"FAIL - entry {entry_id}: {field} path does not "
                        f"exist: {path}"
                    )

    spec_text = pathlib.Path(spec_path).read_text()
    for section in st.parse_sections(spec_text):
        section_id = section["id"]
        if "." in section_id:
            continue
        entry, _kind = st.resolve(section_id, index)
        if entry is None:
            failed = True
            print(f"FAIL - section {section_id} has no index entry (unmapped)")

if failed:
    sys.exit(1)

print("ok - index loads cleanly, every cited path exists, every top-level section is mapped")
sys.exit(0)
PY

check() {
  # args: index_path spec_path
  python3 "$work_dir/check_traceability.py" "$scripts" "$repo_root" "$1" "$2"
}

# ---------------------------------------------------------------------------
# Part 1: the real tree.
# ---------------------------------------------------------------------------

echo "Checking the traceability index against the real tree"

real_index="$repo_root/docs/spec-traceability.json"
real_spec="$repo_root/docs/hex-skirmish-game-spec.md"

if output="$(check "$real_index" "$real_spec" 2>&1)"; then
  pass "the real index and spec pass every structural check"
else
  fail "the real index/spec failed structural checks:
$output"
fi

# ---------------------------------------------------------------------------
# Part 2: fixtures proving each failure path actually fails.
# ---------------------------------------------------------------------------

echo
echo "Proving each failure path against fixtures"

mkdir -p "$work_dir/fixtures"

# -- a cited module path that does not exist ---------------------------------

python3 - "$real_index" "$work_dir/fixtures/missing-module.json" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
for entry in data["entries"]:
    if entry["id"] == "TR-0002":
        entry["modules"] = list(entry["modules"]) + [
            "rules/combat/does_not_exist.gd"
        ]
        break
json.dump(data, open(dst, "w"))
PY

if output="$(check "$work_dir/fixtures/missing-module.json" "$real_spec" 2>&1)"; then
  fail "a cited module path that does not exist should have failed; got:
$output"
elif grep -q "TR-0002" <<<"$output" \
   && grep -q "rules/combat/does_not_exist.gd" <<<"$output"; then
  pass "a missing module path fails, naming both the entry id and the path"
else
  fail "expected TR-0002 and the missing path named; got:
$output"
fi

# -- a top-level section's entry removed from the index ----------------------

python3 - "$real_index" "$work_dir/fixtures/missing-section.json" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
data["entries"] = [e for e in data["entries"] if e.get("section") != "7"]
json.dump(data, open(dst, "w"))
PY

if output="$(check "$work_dir/fixtures/missing-section.json" "$real_spec" 2>&1)"; then
  fail "removing section 7's entry should have failed; got:
$output"
elif grep -q "section 7 has no index entry" <<<"$output"; then
  pass "a top-level section removed from the index is reported as unmapped"
else
  fail "expected section 7 to be named unmapped; got:
$output"
fi

# -- a spec fixture adding a section with no index entry ---------------------

cp "$real_spec" "$work_dir/fixtures/spec-with-13.md"
printf '\n---\n\n## 13. A New Section\n\nNot yet in the index.\n' \
  >> "$work_dir/fixtures/spec-with-13.md"

if output="$(check "$real_index" "$work_dir/fixtures/spec-with-13.md" 2>&1)"; then
  fail "an unmapped section 13 should have failed; got:
$output"
elif grep -q "section 13 has no index entry" <<<"$output"; then
  pass "a spec section with no index entry is reported as unmapped, not clean"
else
  fail "expected section 13 to be named unmapped; got:
$output"
fi

# -- a duplicate id, and an active entry with no modules ---------------------

python3 - "$real_index" "$work_dir/fixtures/defects.json" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
entries = data["entries"]

duplicate = next(dict(e) for e in entries if e["id"] == "TR-0002")
entries.append(duplicate)

entries.append(
    {
        "id": "TR-9999",
        "section": "7.9",
        "status": "active",
        "modules": [],
        "tests": [],
        "note": "fixture: active entry with no modules",
    }
)
data["entries"] = entries
json.dump(data, open(dst, "w"))
PY

if output="$(check "$work_dir/fixtures/defects.json" "$real_spec" 2>&1)"; then
  fail "a duplicate id and an active entry with no modules should have failed; got:
$output"
elif grep -q "duplicate_id" <<<"$output" && grep -q "active_empty_modules" <<<"$output"; then
  pass "a duplicate id and an active entry with no modules are both reported"
else
  fail "expected both defects named; got:
$output"
fi

echo
echo "Checking spec-impact-report.py against inline fixtures"

impact_script="$scripts/spec-impact-report.py"

fixture_spec="$work_dir/fixture-spec.md"
fixture_index="$work_dir/fixture-index.json"

cat > "$fixture_spec" <<'SPEC'
## 1. Fixture Section

Baseline normative line A.
Baseline normative line B.

### 1.1 Fixture Subsection

Sub baseline normative line.

## 2. Unmapped Section

Only unmapped normative line.
SPEC

cat > "$fixture_index" <<'JSON'
{
  "entries": [
    {
      "id": "TR-0001",
      "section": "1",
      "status": "active",
      "modules": ["rules/fixture_module.gd"],
      "tests": ["rules/fixture_test.gd"],
      "note": "fixture entry for spec-impact-report.py's own tests"
    }
  ]
}
JSON

# Builds a throwaway one-commit git repo at $1: docs/hex-skirmish-game-spec.md
# committed as the fixture spec above, docs/spec-traceability.json committed
# as the fixture index above, and (unless $2 is "no-dummy-files") empty dummy
# files at the paths the index cites, so the path-existence check passes.
make_impact_fixture() {
  local dir="$1" dummy_files="${2:-dummy-files}"
  rm -rf "$dir"
  mkdir -p "$dir/docs"
  cp "$fixture_spec" "$dir/docs/hex-skirmish-game-spec.md"
  cp "$fixture_index" "$dir/docs/spec-traceability.json"
  if [ "$dummy_files" = "dummy-files" ]; then
    mkdir -p "$dir/rules"
    touch "$dir/rules/fixture_module.gd" "$dir/rules/fixture_test.gd"
  fi
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" add -A
  git -C "$dir" commit -q -m base >/dev/null
}

run_impact() {
  # args: dir, then CLI args...
  local dir="$1"
  shift
  (cd "$dir" && python3 "$impact_script" "$@")
}

# -- a normative line deleted classifies likely-superseded -------------------

dir="$work_dir/impact-superseded"
make_impact_fixture "$dir"
python3 - "$dir/docs/hex-skirmish-game-spec.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("Baseline normative line B.\n", "")
open(path, "w").write(text)
PY

if output="$(run_impact "$dir" --base HEAD)"; then
  if grep -q "likely-superseded" <<<"$output" \
     && grep -q "rules/fixture_module.gd" <<<"$output" \
     && grep -q "rules/fixture_test.gd" <<<"$output"; then
    pass "a section whose normative line was deleted classifies likely-superseded"
  else
    fail "expected likely-superseded naming both fixture paths; got:
$output"
  fi
else
  fail "spec-impact-report.py exited nonzero unexpectedly for the superseded fixture:
$output"
fi

# -- a normative line only added classifies needs-review ---------------------

dir="$work_dir/impact-needs-review"
make_impact_fixture "$dir"
python3 - "$dir/docs/hex-skirmish-game-spec.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "Baseline normative line B.\n",
    "Baseline normative line B.\nAdditional normative line C.\n",
)
open(path, "w").write(text)
PY

if output="$(run_impact "$dir" --base HEAD)"; then
  if grep -q "needs-review" <<<"$output"; then
    pass "a section with only added normative lines classifies needs-review"
  else
    fail "expected needs-review; got:
$output"
  fi
else
  fail "spec-impact-report.py exited nonzero unexpectedly for the needs-review fixture:
$output"
fi

# -- only a revision note added classifies still-valid ------------------------

dir="$work_dir/impact-still-valid"
make_impact_fixture "$dir"
python3 - "$dir/docs/hex-skirmish-game-spec.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "Baseline normative line B.\n",
    "Baseline normative line B.\n\n"
    "> **Revised 2026-01-01.** Note only, no rule changed.\n",
)
open(path, "w").write(text)
PY

if output="$(run_impact "$dir" --base HEAD)"; then
  if grep -q "still-valid" <<<"$output"; then
    pass "a section whose only change is a revision note classifies still-valid"
  else
    fail "expected still-valid; got:
$output"
  fi
else
  fail "spec-impact-report.py exited nonzero unexpectedly for the still-valid fixture:
$output"
fi

# -- a changed subsection with no entry of its own resolves to its parent ----

dir="$work_dir/impact-parent"
make_impact_fixture "$dir"
python3 - "$dir/docs/hex-skirmish-game-spec.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "Sub baseline normative line.",
    "Sub baseline normative line changed.",
)
open(path, "w").write(text)
PY

if output="$(run_impact "$dir" --base HEAD)"; then
  if grep -q "Section 1.1" <<<"$output" \
     && grep -q "TR-0001" <<<"$output" \
     && grep -qi "parent" <<<"$output"; then
    pass "a changed subsection with no entry of its own resolves to its parent's entry"
  else
    fail "expected section 1.1 to resolve via the parent's TR-0001, and say so; got:
$output"
  fi
else
  fail "spec-impact-report.py exited nonzero unexpectedly for the parent-resolution fixture:
$output"
fi

# -- a changed section with no entry anywhere is unmapped, and exits 1 -------

dir="$work_dir/impact-unmapped"
make_impact_fixture "$dir"
python3 - "$dir/docs/hex-skirmish-game-spec.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "Only unmapped normative line.",
    "Changed unmapped normative line.",
)
open(path, "w").write(text)
PY

set +e
output="$(run_impact "$dir" --base HEAD)"
status=$?
set -e
if [ "$status" -eq 1 ] && grep -qi "unmapped" <<<"$output" \
   && grep -q "Unmapped Section" <<<"$output"; then
  pass "a changed section with no entry anywhere is reported unmapped, and exits 1"
else
  fail "expected exit 1 and an unmapped-sections heading naming section 2; got (exit $status):
$output"
fi

# -- an index citing a missing path aborts the run ---------------------------

dir="$work_dir/impact-missing-path"
make_impact_fixture "$dir" no-dummy-files
python3 - "$dir/docs/spec-traceability.json" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
data["entries"][0]["modules"] = list(data["entries"][0]["modules"]) + [
    "rules/does_not_exist.gd"
]
json.dump(data, open(path, "w"))
PY
git -C "$dir" commit -q -am "cite a missing path" >/dev/null

set +e
output="$(run_impact "$dir" --base HEAD 2>&1)"
status=$?
set -e
if [ "$status" -ne 0 ] && grep -q "rules/does_not_exist.gd" <<<"$output" \
   && ! grep -q "spec section(s) changed" <<<"$output"; then
  pass "an index citing a missing path aborts the run instead of reporting an impact set"
else
  fail "expected a nonzero exit naming the missing path, and no impact set printed; got (exit $status):
$output"
fi

# -- end-to-end: the real repository, unmodified ------------------------------

echo
echo "Running spec-impact-report.py against the real repository"

if output="$(cd "$repo_root" && python3 "$impact_script" --base HEAD 2>&1)"; then
  pass "spec-impact-report.py --base HEAD exits 0 against the real repository"
else
  fail "spec-impact-report.py --base HEAD failed against the real repository:
$output"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "All spec traceability checks passed."
else
  echo "$failures check(s) failed." >&2
fi

exit $((failures > 0))

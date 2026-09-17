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
if [ "$failures" -eq 0 ]; then
  echo "All spec traceability checks passed."
else
  echo "$failures check(s) failed." >&2
fi

exit $((failures > 0))

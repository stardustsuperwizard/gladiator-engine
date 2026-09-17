#!/usr/bin/env bash
# Regression check for the spec-to-code traceability index.
#
# The index is a contract between the spec and the codebase:
#   1. `spec_traceability.load_index` loads and validates the JSON schema
#   2. All cited module and test paths must exist in the working tree
#   3. Every top-level spec section has a traceability entry
#
# Checks 2 and 3 are not part of `spec_traceability.py`'s public API -- they
# are this harness's own responsibility. They are written once, as
# `check_missing_paths` / `check_unmapped_sections` in a helper module
# generated into the scratch directory, and both halves of this script call
# that same module:
#
#   Part 1 runs it against the real tree (docs/spec-traceability.json and
#   docs/hex-skirmish-game-spec.md) and fails the build when it finds
#   anything.
#
#   Part 2 runs it against fixtures written into the scratch directory, so
#   each failure path is proven to fail rather than assumed to -- and so a
#   regression in the checking code itself (not just in the fixture's
#   understanding of it) turns Part 2 red too.
#
# The harness needs nothing but python3 and bash; no network, no credentials,
# no `gh`, and it never touches a real repository.
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

# ---------------------------------------------------------------------------
# Shared checking code, importable by both Part 1 and Part 2's fixtures.
# ---------------------------------------------------------------------------

helpers="$work_dir/check_helpers.py"
cat > "$helpers" <<'PY'
import os
import spec_traceability


def check_missing_paths(root, index):
    """Return (entry_id, path) pairs for modules/tests paths absent under root."""
    results = []
    if not index:
        return results
    for entry in index.get('entries', []):
        entry_id = entry.get('id', '?')
        cited = list(entry.get('modules', []) or []) + list(entry.get('tests', []) or [])
        for path in cited:
            full = os.path.join(root, path)
            if not os.path.exists(full):
                results.append((entry_id, path))
    return results


def check_unmapped_sections(spec_text, index):
    """Return sorted top-level section numbers present in spec_text but not in index.

    No ceiling is applied here: a spec section is checked regardless of its
    number, so a section added past whatever the spec currently tops out at
    is still reported as unmapped.
    """
    sections = spec_traceability.parse_sections(spec_text)
    top_level = set()
    for section in sections:
        section_id = section.get('id', '')
        if section_id and '.' not in section_id:
            top_level.add(section_id)

    indexed_sections = set()
    if index:
        for entry in index.get('entries', []):
            section = entry.get('section', '')
            if section and '.' not in section:
                indexed_sections.add(section)

    unmapped = top_level - indexed_sections
    return sorted(unmapped, key=lambda s: int(s))


def format_schema_error(error):
    """Render a `load_index` error dict with the identifying fields it carries.

    `load_index` attaches 'id', 'section' and 'module' unevenly across its
    error types (and only 'index' for an entry too malformed to have an id).
    Printing 'message' alone makes two entries failing the same way
    byte-identical -- an operator reading a red build cannot tell which entry
    to open -- so whatever identifying fields the error carries are appended.
    """
    details = []
    for key in ('id', 'section', 'module', 'index'):
        value = error.get(key)
        if value is None or value == '':
            continue
        label = 'path' if key == 'module' else key
        details.append(f"{label}={value}")
    message = error.get('message', 'unknown error')
    if details:
        return f"{message} ({', '.join(details)})"
    return message
PY

# ---------------------------------------------------------------------------
# Part 1: Validate the real tree
# ---------------------------------------------------------------------------

echo "Loading and validating spec traceability index"

real_check_output=$(python3 - "$repo_root" "$scripts" "$work_dir" <<'PY'
import sys
import os
sys.path.insert(0, sys.argv[2])
sys.path.insert(0, sys.argv[3])
import spec_traceability
from check_helpers import (
    check_missing_paths,
    check_unmapped_sections,
    format_schema_error,
)

repo_root = sys.argv[1]
index_path = os.path.join(repo_root, "docs/spec-traceability.json")
spec_path = os.path.join(repo_root, "docs/hex-skirmish-game-spec.md")

index, errors = spec_traceability.load_index(index_path)

messages = []

if errors:
    # Schema errors leave the index unusable; report them and stop there,
    # same as the rest of this harness's callers do -- which means one schema
    # error suppresses the missing-path and unmapped-section checks below, so
    # each reported line has to be identifiable on its own. Every line carries
    # the structured id/section/path fields load_index attaches, not just the
    # generic message, so two entries failing the same way are distinguishable.
    for error in errors:
        messages.append(f"Index schema error: {format_schema_error(error)}")
else:
    for entry_id, path in check_missing_paths(repo_root, index):
        messages.append(f"Entry {entry_id} cites missing path: {path}")

    with open(spec_path, 'r') as f:
        spec_text = f.read()

    for section in check_unmapped_sections(spec_text, index):
        messages.append(f"Top-level section §{section} has no index entry")

for message in messages:
    print(message)
PY
)

if [ -n "$real_check_output" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        fail "$line"
    done <<< "$real_check_output"
else
    pass "Index and spec are structurally sound"
fi

# ---------------------------------------------------------------------------
# Part 2: Test failure paths with fixtures
# ---------------------------------------------------------------------------

echo "Testing failure paths with fixtures"

# Test 1: Index citing a missing module path
echo "  Test 1: Missing module path should fail"
fixture_1_root="$work_dir/fixture_1_root"
mkdir -p "$fixture_1_root/rules/combat"
touch "$fixture_1_root/rules/combat/exists.gd"
fixture_1="$work_dir/fixture_1.json"
cat > "$fixture_1" <<'JSON'
{
  "spec": "docs/hex-skirmish-game-spec.md",
  "entries": [
    {
      "id": "TR-9999",
      "section": "1",
      "status": "active",
      "modules": ["rules/combat/exists.gd", "rules/combat/does_not_exist.gd"],
      "tests": [],
      "note": "Test fixture"
    }
  ]
}
JSON

if test_1_output=$(python3 - "$fixture_1" "$fixture_1_root" "$scripts" "$work_dir" 2>&1 <<'PY'
import sys
import json
sys.path.insert(0, sys.argv[3])
sys.path.insert(0, sys.argv[4])
from check_helpers import check_missing_paths

with open(sys.argv[1]) as f:
    index = json.load(f)

results = check_missing_paths(sys.argv[2], index)
missing = [path for _, path in results]
ids = [entry_id for entry_id, _ in results]

assert "rules/combat/does_not_exist.gd" in missing, f"missing path not detected: {results}"
assert "rules/combat/exists.gd" not in missing, f"existing path wrongly flagged: {results}"
assert "TR-9999" in ids, f"entry id not attached to result: {results}"
print("check_missing_paths correctly flagged rules/combat/does_not_exist.gd for TR-9999")
PY
); then
    pass "$test_1_output"
else
    fail "Missing module path not detected by check_missing_paths: $test_1_output"
fi

# Test 2: Spec section with no index entry, including one past the old §1-12
# ceiling that used to make this check invisible.
echo "  Test 2: Spec section with no index entry should fail (including §13)"
fixture_2="$work_dir/fixture_2.json"
fixture_2_spec="$work_dir/fixture_2_spec.md"
cat > "$fixture_2" <<'JSON'
{
  "spec": "docs/hex-skirmish-game-spec.md",
  "entries": [
    {
      "id": "TR-0001",
      "section": "1",
      "status": "unimplemented",
      "modules": [],
      "tests": [],
      "note": "Only section 1"
    }
  ]
}
JSON

cat > "$fixture_2_spec" <<'SPEC'
# Main Title

## 1. First Section

Content for section 1 - in the index.

## 13. Extension Section

Content for section 13 - not in the index, and past the old §1-12 ceiling!
SPEC

if test_2_output=$(python3 - "$fixture_2_spec" "$fixture_2" "$scripts" "$work_dir" 2>&1 <<'PY'
import sys
import json
sys.path.insert(0, sys.argv[3])
sys.path.insert(0, sys.argv[4])
from check_helpers import check_unmapped_sections

with open(sys.argv[1]) as f:
    spec_text = f.read()
with open(sys.argv[2]) as f:
    index = json.load(f)

unmapped = check_unmapped_sections(spec_text, index)
assert unmapped == ["13"], f"expected only section 13 unmapped, got {unmapped}"
print("check_unmapped_sections correctly flagged §13 as unmapped")
PY
); then
    pass "$test_2_output"
else
    fail "Spec section with no index entry not detected by check_unmapped_sections: $test_2_output"
fi

# Test 3: Duplicate entry ID
echo "  Test 3: Duplicate ID should fail"
fixture_3="$work_dir/fixture_3.json"
cat > "$fixture_3" <<'JSON'
{
  "spec": "docs/hex-skirmish-game-spec.md",
  "entries": [
    {
      "id": "TR-0001",
      "section": "1",
      "status": "active",
      "modules": ["rules/board/board.gd"],
      "tests": [],
      "note": "First entry"
    },
    {
      "id": "TR-0001",
      "section": "2",
      "status": "active",
      "modules": ["rules/board/hex_coord.gd"],
      "tests": [],
      "note": "Duplicate ID"
    }
  ]
}
JSON

if test_3_output=$(python3 - "$fixture_3" "$scripts" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
import spec_traceability

index, errors = spec_traceability.load_index(sys.argv[1])
dup_errors = [e for e in errors if e.get('type') == 'duplicate_id']
assert dup_errors, f"no duplicate_id error reported: {errors}"
message = dup_errors[0]['message']
assert 'TR-0001' in message, f"message does not name the ID: {message}"
print(message)
PY
); then
    pass "Duplicate ID correctly detected: $test_3_output"
else
    fail "Duplicate ID not detected: $test_3_output"
fi

# Test 4: Active entry with no modules
echo "  Test 4: Active entry with no modules should fail"
fixture_4="$work_dir/fixture_4.json"
cat > "$fixture_4" <<'JSON'
{
  "spec": "docs/hex-skirmish-game-spec.md",
  "entries": [
    {
      "id": "TR-0001",
      "section": "1",
      "status": "active",
      "modules": [],
      "tests": [],
      "note": "No modules"
    }
  ]
}
JSON

if test_4_output=$(python3 - "$fixture_4" "$scripts" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
import spec_traceability

index, errors = spec_traceability.load_index(sys.argv[1])
empty_errors = [e for e in errors if e.get('type') == 'active_empty_modules']
assert empty_errors, f"no active_empty_modules error reported: {errors}"
error = empty_errors[0]
assert error.get('id') == 'TR-0001', f"error does not name the ID: {error}"
assert error.get('section') == '1', f"error does not name the section: {error}"
# Carry the structured fields spec_traceability.load_index already attaches,
# not just the generic message string, so the ID and section are visible.
print(f"{error['message']} (id={error['id']}, section={error['section']})")
PY
); then
    pass "Active entry with no modules correctly detected: $test_4_output"
else
    fail "Active entry with no modules not detected: $test_4_output"
fi

# Test 5: Both defects in one index. Tests 3 and 4 each prove a single defect
# from its own fixture, which leaves co-reporting inferred rather than
# asserted -- a load that stopped at the first error would still pass both.
# This fixture carries the duplicate TR-NNNN id and the module-less active
# entry together, and both must come back from the one load.
echo "  Test 5: Duplicate ID and module-less active entry in one index should both be reported"
fixture_combined_errors="$work_dir/fixture_combined_errors.json"
cat > "$fixture_combined_errors" <<'JSON'
{
  "spec": "docs/hex-skirmish-game-spec.md",
  "entries": [
    {
      "id": "TR-0001",
      "section": "1",
      "status": "active",
      "modules": ["rules/board/board.gd"],
      "tests": [],
      "note": "First entry"
    },
    {
      "id": "TR-0001",
      "section": "2",
      "status": "active",
      "modules": ["rules/board/hex_coord.gd"],
      "tests": [],
      "note": "Duplicate ID"
    },
    {
      "id": "TR-0002",
      "section": "3",
      "status": "active",
      "modules": [],
      "tests": [],
      "note": "No modules"
    }
  ]
}
JSON

if test_5_output=$(python3 - "$fixture_combined_errors" "$scripts" "$work_dir" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
sys.path.insert(0, sys.argv[3])
import spec_traceability
from check_helpers import format_schema_error

index, errors = spec_traceability.load_index(sys.argv[1])

dup_errors = [e for e in errors if e.get('type') == 'duplicate_id']
empty_errors = [e for e in errors if e.get('type') == 'active_empty_modules']

assert dup_errors, f"no duplicate_id error reported from combined fixture: {errors}"
assert empty_errors, f"no active_empty_modules error reported from combined fixture: {errors}"

assert dup_errors[0].get('id') == 'TR-0001', f"duplicate error does not name the ID: {dup_errors[0]}"
assert empty_errors[0].get('id') == 'TR-0002', f"empty-modules error does not name the ID: {empty_errors[0]}"
assert empty_errors[0].get('section') == '3', f"empty-modules error does not name the section: {empty_errors[0]}"

print("; ".join(format_schema_error(e) for e in dup_errors + empty_errors))
PY
); then
    pass "Both defects reported from one index: $test_5_output"
else
    fail "Combined duplicate ID and module-less active entry not both reported: $test_5_output"
fi

# ---------------------------------------------------------------------------
# Final report
# ---------------------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    echo "All checks passed."
    exit 0
else
    echo "$failures check(s) failed."
    exit 1
fi

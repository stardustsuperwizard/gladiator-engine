#!/usr/bin/env bash
# Run the Godot suite against a merge base carrying only a pull request's test
# changes (#328).
#
# Single source of truth for "run the merge base with these tests overlaid", so
# a local run and `ci.yml`'s `red-gate` job mean the same thing -- the same
# value `.github/scripts/export-godot.sh` was extracted for (#269). The job
# resolves two commits, calls this, and hands the log to
# `.github/scripts/red-gate.py verdict`; nothing about which suites matter or
# what the log means lives here.
#
# `validate-godot.sh` is deliberately NOT reused for this run. That script is
# defined to fail on a red suite and to demand the `All N test suites passed.`
# line before it believes a zero exit -- and a red suite is precisely what this
# stage expects to see. Reusing it would turn the expected outcome into a
# failed step. The engine-binary resolution below is the same as its, so a
# local run still behaves identically in the one respect that matters to
# whoever is running it by hand.
#
# Exit codes:
#   0    The merge-base run was attempted and its output captured -- whatever
#        the engine itself returned. A non-zero engine exit is the EXPECTED
#        outcome of this stage, not a failure of it.
#   127  No engine binary. The same code and the same "could not validate"
#        meaning `validate-godot.sh` gives it: not a verdict, an inability to
#        reach one.
#   1    The run could not be attempted: the merge base does not resolve, or an
#        overlay directory is missing from the head tree.
#   2    Bad arguments.
#
# Usage:
#   .github/scripts/red-gate-base.sh --merge-base <commit> --scratch <dir> \
#       [--head-root <dir>] [--log <path>]
#
# Requires `godot` on PATH, or GODOT_BIN pointing at the binary.

set -euo pipefail

# The two directories `count-tests.py`'s SCANNED_DIRS names, which is what
# makes a path a test path throughout this gate. Overlaid WHOLE, not as a
# patch: an unchanged test file is byte-identical either way, `git apply`
# introduces a context-conflict failure mode that has nothing to do with what
# is being measured, and removing the base's copy first is what makes a test
# file the pull request DELETED actually absent from the overlay.
overlay_dirs=("tests" "rules/tests")

# Two levels up: this script lives at .github/scripts/, so the repo root is
# ../../ from here. Getting this wrong does not fail loudly -- Godot pointed at
# a directory with no project.godot hangs rather than erroring.
head_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
merge_base=""
scratch=""
log=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --merge-base)
      merge_base="${2:-}"
      shift 2
      ;;
    --scratch)
      scratch="${2:-}"
      shift 2
      ;;
    --head-root)
      head_root="${2:-}"
      shift 2
      ;;
    --log)
      log="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --merge-base <commit> --scratch <dir>" \
        "[--head-root <dir>] [--log <path>]" >&2
      exit 2
      ;;
  esac
done

if [ -z "$merge_base" ] || [ -z "$scratch" ]; then
  echo "Both --merge-base and --scratch are required." >&2
  echo "Usage: $0 --merge-base <commit> --scratch <dir>" \
    "[--head-root <dir>] [--log <path>]" >&2
  exit 2
fi

# Everything this script writes goes under the caller's scratch directory --
# CI passes a path under $RUNNER_TEMP, and Part 5 of test-workflow-logic.sh is
# an absolute check with an empty allow-list. #84 is what it remembers.
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd)"
head_root="$(cd "$head_root" && pwd)"
worktree="$scratch/base"
log="${log:-$scratch/base-run.log}"
mkdir -p "$(dirname "$log")"

# Resolve the binary: explicit override, then PATH, then the standard macOS app
# bundle -- Godot.app installs no CLI symlink, so PATH alone finds nothing on a
# stock Mac and the script would report "install Godot" to someone who has it
# installed. As in export-godot.sh, an explicit GODOT_BIN is not trusted
# blindly: a bogus override must fail the same way as no override at all, not
# with a raw "No such file" from the shell.
godot_bin="${GODOT_BIN:-}"
if [ -n "$godot_bin" ] && ! command -v "$godot_bin" >/dev/null 2>&1; then
  godot_bin=""
fi
if [ -z "$godot_bin" ]; then
  if command -v godot >/dev/null 2>&1; then
    godot_bin="godot"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    godot_bin="/Applications/Godot.app/Contents/MacOS/Godot"
  else
    echo "Godot binary not found on PATH or at /Applications/Godot.app." >&2
    echo "Install Godot 4 or set GODOT_BIN to its path." >&2
    echo "The merge-base run could not be performed." >&2
    exit 127
  fi
fi

# Capture the status with `|| status=$?`, never `if ! cmd`. After a negated
# command $? is the status of the negation -- always 0 -- so the negated form
# reports the failure and then exits 0 (validate-godot.sh:43-48).
status=0
resolved="$(git -C "$head_root" rev-parse --verify "${merge_base}^{commit}" \
  2>/dev/null)" || status=$?
if [ "$status" -ne 0 ] || [ -z "$resolved" ]; then
  echo "Merge base does not resolve to a commit in $head_root: $merge_base" >&2
  echo "The merge-base run could not be performed." >&2
  exit 1
fi

for dir in "${overlay_dirs[@]}"; do
  if [ ! -d "$head_root/$dir" ]; then
    echo "Overlay directory missing from the head tree: $head_root/$dir" >&2
    echo "The merge-base run could not be performed." >&2
    exit 1
  fi
done

# A DETACHED WORKTREE under the scratch directory, never a second checkout
# inside the tree -- the same shape ci.yml's `test-ratchet` job uses, and for
# the same reason (#84).
#
# A local re-run has to behave like the first one, and `git worktree add`
# refuses a path that already exists. Removing the directory and then pruning
# the registration that outlives it is enough; there is no status to mask.
if [ -e "$worktree" ]; then
  rm -rf "$worktree"
fi
git -C "$head_root" worktree prune
git -C "$head_root" worktree add --detach "$worktree" "$resolved"

for dir in "${overlay_dirs[@]}"; do
  rm -rf "${worktree:?}/$dir"
  mkdir -p "$(dirname "$worktree/$dir")"
  cp -R "$head_root/$dir" "$worktree/$dir"
done

"$godot_bin" --version

# stdout AND stderr, together, into one file. NOT `--log-file`: `_check()`
# prints `PASS` through `print` and `FAIL` through `printerr`
# (tests/test_bootstrap.gd:160-166), the verdict depends on both lines being
# present, and whether Godot's own log file captures the second is not
# something this gate should have to rely on. Not `| tee` either -- a pipeline
# reports the last command's status, which would hide the engine's.
#
# The headers below also guarantee the log is never blank: `red-gate.py
# verdict` treats an empty log as an input it cannot judge (exit 2, a broken
# gate) rather than as a generous pass, and "the engine printed literally
# nothing" should not be indistinguishable from "the log was never written".
{
  echo "# red-gate merge-base run"
  echo "# merge base: $resolved"
  echo "# worktree:   $worktree"
  echo "# overlay:    ${overlay_dirs[*]} from $head_root"
} > "$log"

echo "# --- import pass ---" >> "$log"
import_status=0
"$godot_bin" --headless --path "$worktree" --import >> "$log" 2>&1 \
  || import_status=$?

# The import pass is NOT allowed to end the run the way validate-godot.sh ends
# on it. A test file that references a class the pull request introduces makes
# the merge base fail to parse, and that is one of the outcomes this stage
# exists to observe -- reported downstream as `did-not-load`, not as a broken
# gate. Both statuses are recorded and neither is an error here.
echo "# --- boot and quit ---" >> "$log"
boot_status=0
"$godot_bin" --headless --path "$worktree" --quit >> "$log" 2>&1 \
  || boot_status=$?

echo "Merge-base import pass exited ${import_status}."
echo "Merge-base boot exited ${boot_status}."
echo "Merge-base run log: $log"
echo
cat "$log"

# Exit 0 on a red merge-base run, on purpose. Judging that log is
# `red-gate.py verdict`'s job, not this script's.
exit 0

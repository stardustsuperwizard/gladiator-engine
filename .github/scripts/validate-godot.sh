#!/usr/bin/env bash
# Godot headless validation for gladiator-engine.
#
# Single source of truth for "run the repository validation", so a passing
# local run means the same thing as a passing CI run.
#
# Usage: tools/validate-godot.sh [project-path]
# Requires `godot` on PATH, or GODOT_BIN pointing at the binary.
#
# Adapted from mikeys_game_bones-rules-moba (EXTRACTION_LOG.md #20).

set -euo pipefail

# Two levels up: this script lives at .github/scripts/, so the repo root is
# ../../ from here. Getting this wrong does not fail loudly -- Godot pointed at
# a directory with no project.godot hangs rather than erroring.
project_path="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
log_dir="$(mktemp -d)"

# Resolve the binary: explicit override, then PATH, then the standard macOS
# app bundle -- Godot.app installs no CLI symlink, so PATH alone finds nothing
# on a stock Mac and the script would report "install Godot" to someone who
# has it installed.
godot_bin="${GODOT_BIN:-}"
if [ -z "$godot_bin" ]; then
  if command -v godot >/dev/null 2>&1; then
    godot_bin="godot"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    godot_bin="/Applications/Godot.app/Contents/MacOS/Godot"
  else
    echo "Godot binary not found on PATH or at /Applications/Godot.app." >&2
    echo "Install Godot 4 or set GODOT_BIN to its path." >&2
    echo "Validation could not be performed." >&2
    exit 127
  fi
fi

"$godot_bin" --version

run_pass() {
  local label="$1" log="$2"
  shift 2

  # Capture the status with `|| status=$?`, not `if ! cmd; then`. After a
  # negated command $? is the status of the negation -- always 0 -- so the
  # negated form reports the failure and then exits 0, and a Godot pass that
  # returned 1 still produces a green build.
  local status=0
  "$godot_bin" --headless --path "$project_path" "$@" --log-file "$log" || status=$?

  if [ "$status" -ne 0 ]; then
    echo "Godot ${label} failed (exit ${status})." >&2
    cat "$log" >&2 || true
    exit "$status"
  fi
}

# Pass 1: import -- resources and scenes resolve.
run_pass "import pass" "$log_dir/godot-import.log" --import

# Pass 2: boot and quit -- scripts parse, autoloads initialize, suites run.
run_pass "headless validation" "$log_dir/godot-headless.log" --quit

# A zero exit is not by itself proof the suites ran. test_bootstrap.gd makes a
# truncated run non-zero, but it cannot cover the case where the bootstrap
# autoload never loads at all: if that script fails to compile, none of its
# code runs, Godot still boots and quits cleanly, and this pass returns 0
# having executed no suite whatsoever. Require the completion line before
# believing the zero.
if ! grep -Eq 'All [0-9]+ test suites passed\.' "$log_dir/godot-headless.log"; then
  echo "Godot headless validation exited 0 but ran no test suites." >&2
  echo "The test bootstrap autoload most likely failed to load. Full log:" >&2
  cat "$log_dir/godot-headless.log" >&2 || true
  exit 1
fi

echo "Godot headless validation passed."

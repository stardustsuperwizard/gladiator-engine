#!/usr/bin/env bash
# Headless smoke run of an already-built gladiator-engine executable.
#
# Single source of truth for "does the build we just published actually reach
# its end state", so a passing local run means the same thing as a passing CI
# run (#312's `smoke` job calls this script unchanged, as a thin wrapper).
# Mirrors .github/scripts/export-godot.sh in structure and error handling.
#
# It verifies a build; it never produces one. There is no engine install here,
# no export, and no project directory: the argument is the binary itself, the
# same bytes the export stage published. Rebuilding would verify something
# other than what was shipped.
#
# Usage: .github/scripts/smoke-godot.sh <path-to-executable>
#
# Environment:
#   SMOKE_TIMEOUT_SECONDS  hard wall-clock cap on the run (default 120).
#   SMOKE_LOG_DIR          where the captured output and engine log are
#                          written (default: a fresh mktemp -d). The CI job
#                          sets this so it can upload the files on failure.
#
# Requires `timeout` (coreutils) on PATH, which every CI runner has.
#
# Adapted from mikeys_game_bones-rules-moba (EXTRACTION_LOG.md #20).

set -euo pipefail

# The completion marker, defined in the engine by
# `SmokeMatchDriver.MARKER_FORMAT` and printed by the smoke bootstrap autoload
# on the one path that means the match played to its end. Anchored at both
# ends: a line that merely quotes the marker inside a longer sentence is not
# the driver reporting success (the same trap Part 4 of
# test-workflow-logic.sh pins for the control plane's markers).
completion_marker='^Smoke match complete: [0-9]+ rounds, [0-9]+ turns\.$'

# Wall-clock cap. The failure this bounds is a build that boots and then waits
# forever -- for input, for a signal, for a turn nobody takes -- which without
# a cap is not a failing job but a hung one, holding a runner until the job
# timeout kills it with no diagnosis attached.
timeout_seconds="${SMOKE_TIMEOUT_SECONDS:-120}"

executable="${1:-}"

if [ -z "$executable" ]; then
  echo "Usage: $0 <path-to-executable>" >&2
  echo "Smoke run could not be performed: no executable given." >&2
  exit 2
fi

if [ ! -f "$executable" ]; then
  echo "Smoke run could not be performed: no such file: $executable" >&2
  exit 2
fi

if [ ! -x "$executable" ]; then
  # Worth its own message rather than letting the shell report "Permission
  # denied": the executable bit does not survive an artifact round trip, so
  # this is the expected state of a freshly downloaded build and the fix is
  # one `chmod +x` away.
  echo "Smoke run could not be performed: not executable: $executable" >&2
  echo "Hint: chmod +x it first -- the executable bit is lost by" \
    "upload-artifact/download-artifact." >&2
  exit 2
fi

# Resolve the timeout tool. GNU coreutils installs it as `timeout`; Homebrew
# coreutils on macOS installs it as `gtimeout` unless the g-less names are on
# PATH. Without one of them there is no hard cap, and a smoke stage that can
# hang is the one thing this script exists to prevent -- so refuse rather than
# run uncapped.
timeout_bin=""
if command -v timeout >/dev/null 2>&1; then
  timeout_bin="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_bin="gtimeout"
else
  echo "Smoke run could not be performed: no 'timeout' on PATH." >&2
  echo "Install GNU coreutils (macOS: 'brew install coreutils' provides" \
    "gtimeout)." >&2
  exit 127
fi

log_dir="${SMOKE_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$log_dir"

# Two files, because they fail differently. `run_output` is everything the
# process wrote to either stream, and is what the marker is matched against;
# `engine_log` is the engine's own log, which it keeps writing and flushing
# through a crash that costs us the tail of the pipe.
run_output="$log_dir/smoke-stdout.log"
engine_log="$log_dir/smoke-engine.log"

: > "$run_output"

# Everything this script prints on the way out of a failure, in one place so
# no failure path can forget half of it: the captured output, and where the
# files it wrote actually are (a CI reader needs the paths to find them in the
# uploaded artifact; a local reader needs them because the default log
# directory is a fresh mktemp -d).
report_failure () {
  echo "Captured output:" >&2
  cat "$run_output" >&2 || true
  echo "Captured output file: $run_output" >&2
  echo "Engine log file: $engine_log" >&2
}

# Any log the engine left behind in its user data directory, copied next to
# ours so a crash that happened before --log-file was opened is still legible.
# Best-effort by design: no such file is the normal case, not an error.
collect_user_logs () {
  local user_data="${XDG_DATA_HOME:-${HOME:-}/.local/share}/godot/app_userdata"
  [ -d "$user_data" ] || return 0

  local found
  while IFS= read -r found; do
    [ -n "$found" ] || continue
    cp "$found" "$log_dir/user-$(basename "$found")" 2>/dev/null || true
    echo "Copied engine user log: $log_dir/user-$(basename "$found")" >&2
  done < <(find "$user_data" -type f -name '*.log' 2>/dev/null || true)
}

# `-- --smoke`, after a bare `--`: the flag is read off
# `OS.get_cmdline_user_args()`, so the separator is what makes the engine hand
# it to the project instead of trying to interpret it. `--log-file` is an
# engine option and so belongs before the separator.
#
# --kill-after: SIGTERM first so the engine gets a chance to flush, then
# SIGKILL if it ignores that. A build wedged badly enough to ignore SIGTERM
# still must not hold the runner.
#
# Capture the status with `|| status=$?`, not `if ! cmd; then`: after a negated
# command $? is the status of the negation, always 0, so the negated form
# reports the failure and then exits 0 (EXTRACTION_LOG.md #20).
status=0
"$timeout_bin" --signal=TERM --kill-after=10 "$timeout_seconds" \
  "$executable" --headless --log-file "$engine_log" -- --smoke \
  > "$run_output" 2>&1 || status=$?

# The engine writes the log itself; if it died before opening one, make the
# file exist anyway so the path this script reports is a path that resolves.
[ -f "$engine_log" ] || : > "$engine_log"

if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
  # 124 is `timeout` reporting that it killed the child; 137 is the shell's
  # 128+SIGKILL, which is what the --kill-after escalation leaves behind.
  echo "Smoke run timed out after ${timeout_seconds}s and was killed." >&2
  collect_user_logs
  report_failure
  exit 1
fi

if [ "$status" -ne 0 ]; then
  echo "Smoke run exited non-zero (exit ${status})." >&2
  collect_user_logs
  report_failure
  exit "$status"
fi

# Same `|| status=$?` capture as the run itself, rather than `if ! grep`:
# `grep -q` is the last verdict this script reaches, and a negated form here
# would be the one place a miss could report green.
marker_status=0
grep -Eq "$completion_marker" "$run_output" || marker_status=$?

if [ "$marker_status" -ne 0 ]; then
  # Exit 0 is never sufficient, and this is the check the whole stage exists
  # for: a build that boots, draws nothing, plays nothing and quits cleanly
  # exits 0 too. Only the marker says a match reached its end state.
  echo "Smoke run exited 0 but printed no completion marker." >&2
  echo "Expected a line matching: ${completion_marker}" >&2
  collect_user_logs
  report_failure
  exit 1
fi

echo "Smoke run passed: $(grep -E "$completion_marker" "$run_output" | tail -n 1)"

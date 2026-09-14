#!/usr/bin/env bash
# Godot headless export for gladiator-engine.
#
# Single source of truth for "export a runnable Linux build", so a passing
# local run means the same thing as a passing CI run (#270's CI job calls
# this script unchanged). Mirrors .github/scripts/validate-godot.sh in
# structure and error handling.
#
# Usage: .github/scripts/export-godot.sh [project-path] [output-path]
# Requires `godot` on PATH, or GODOT_BIN pointing at the binary, and a
# matching set of Linux export templates installed for that binary's engine
# version.
#
# Adapted from mikeys_game_bones-rules-moba (EXTRACTION_LOG.md #20).

set -euo pipefail

# The preset this script exports. --export-release takes this as a literal
# string naming a [preset.N] block in export_presets.cfg by its name=, so it
# must match that file exactly.
preset="Linux"

# Error markers meaning the export failed even though Godot exited 0 -- a
# zero exit is not by itself proof of success (EXTRACTION_LOG.md #20).
# Defined once, here, as a single extended regular expression. Narrow a
# marker if a clean export ever false-positives on it, and say why in a
# comment; do not delete one to lean on the output-file checks below instead
# -- catching an error Godot reported while exiting 0 is the whole point.
error_markers='ERROR:|SCRIPT ERROR:|Failed to export|No export template found|Cannot export project'

# The missing-template markers get an extra hint line below, naming the
# engine version and the directory Godot looks in for templates -- a
# developer without templates installed should not have to read a 200-line
# log to learn that.
missing_template_markers='No export template found|Cannot export project'

# Two levels up: this script lives at .github/scripts/, so the repo root is
# ../../ from here. Getting this wrong does not fail loudly -- Godot pointed
# at a directory with no project.godot hangs rather than erroring.
project_path="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
output_path="${2:-$project_path/build/linux/gladiator-engine.x86_64}"

# Build output never lands in a tracked path -- create the directory here
# rather than relying on one already existing under build/.
mkdir -p "$(dirname "$output_path")"

# binary_format/embed_pck=false in export_presets.cfg means the export
# writes the executable above and a sibling .pck alongside it, named from
# the same base with its own extension swapped for .pck.
pck_path="${output_path%.*}.pck"

log_dir="$(mktemp -d)"
export_log="$log_dir/godot-export.log"

# Resolve the binary: explicit override, then PATH, then the standard macOS
# app bundle -- Godot.app installs no CLI symlink, so PATH alone finds
# nothing on a stock Mac and the script would report "install Godot" to
# someone who has it installed. Unlike a bare PATH lookup, an explicit
# GODOT_BIN is not trusted blindly: a bogus override must fail the same way
# as no override at all, not with a raw "No such file" from the shell.
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
    echo "Export could not be performed." >&2
    exit 127
  fi
fi

engine_version="$("$godot_bin" --version)"
echo "$engine_version"

# Pass 1: import -- resources and scenes resolve. An unimported project does
# not export. Capture the status with `|| status=$?`, not `if ! cmd; then`:
# after a negated command $? is the status of the negation, always 0, so the
# negated form reports the failure and then exits 0 (EXTRACTION_LOG.md #20).
status=0
"$godot_bin" --headless --path "$project_path" --import || status=$?
if [ "$status" -ne 0 ]; then
  echo "Godot import pass failed (exit ${status})." >&2
  exit "$status"
fi

# Pass 2: the export itself, same `|| status=$?` capture as above.
status=0
"$godot_bin" --headless --path "$project_path" \
  --export-release "$preset" "$output_path" \
  --log-file "$export_log" || status=$?

if [ "$status" -ne 0 ]; then
  echo "Godot export failed (exit ${status})." >&2
  cat "$export_log" >&2 || true
  exit "$status"
fi

if grep -Eq "$error_markers" "$export_log"; then
  echo "Godot export exited 0 but logged an error." >&2
  if grep -Eq "$missing_template_markers" "$export_log"; then
    echo "Hint: this looks like a missing export template for ${engine_version}." \
      "Godot looks for templates under" \
      "~/.local/share/godot/export_templates/<version>/ on Linux" \
      "(the equivalent user data directory on other hosts)." >&2
  fi
  echo "Full log:" >&2
  cat "$export_log" >&2 || true
  exit 1
fi

if [ ! -s "$output_path" ]; then
  echo "Godot export exited 0 but the output executable is missing or empty: $output_path" >&2
  cat "$export_log" >&2 || true
  exit 1
fi

if [ ! -s "$pck_path" ]; then
  echo "Godot export exited 0 but the output .pck is missing or empty: $pck_path" >&2
  cat "$export_log" >&2 || true
  exit 1
fi

echo "Godot export passed."

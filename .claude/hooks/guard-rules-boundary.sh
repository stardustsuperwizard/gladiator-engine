#!/usr/bin/env bash
# PreToolUse (Bash, gated to `git commit`): a pre-flight look at staged files
# in rules/ for two of the architectural commitments.
#
# ADVISORY ONLY. Always exits 0. This is NOT a second enforcement point.
#
# The contract tests own enforcement -- extraction_contract_test.gd,
# ambient_rng_contract_test.gd, base_class_contract_test.gd and
# tests/inbound_type_contract_test.gd -- and a violation fails the build there
# whatever this script says. `rules.instructions.md` warns that a second copy
# of a rule is this project's primary correctness risk, and that applies to
# checks as much as to combat math. So this file deliberately reproduces only
# the two that are honestly one grep, and it never blocks:
#
#   - outward references, which are three fixed path prefixes
#   - ambient RNG, which is three fixed function names
#
# The base-class and inbound-type contracts are NOT checked here. Both need
# real derivation (the set of game-side `class_name`s; the allowed built-in
# list), and a half-accurate local copy that disagreed with the scanner would
# be worse than no copy. Their tests are the only word on them.
#
# The value is latency, not authority: a CI round-trip costs minutes and, on
# the Claude-vendor path, API credit. Catching an obvious slip before the
# commit is cheap. Trusting this instead of the suite is not.
#
# Shape adapted from Claude-Code-Game-Studios (MIT) -- see THIRD_PARTY_NOTICES.md.

set +e

if command -v jq >/dev/null 2>&1; then
	command="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
else
	command="$(grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')"
fi

case "$command" in
	*"git commit"*) ;;
	*) exit 0 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root" || exit 0

staged="$(git diff --cached --name-only 2>/dev/null | grep -E '^rules/.*\.gd$')"
[ -z "$staged" ] && exit 0

findings=""

while IFS= read -r file; do
	[ -f "$file" ] || continue

	# The one-way arrow. `rules/` may not name the game side by path.
	hits="$(grep -nE 'res://(scripts|scenes|resources)/' "$file" 2>/dev/null)"
	if [ -n "$hits" ]; then
		findings="$findings
  $file -- outward reference (one-way dependency arrow):
$(echo "$hits" | sed 's/^/    /')"
	fi

	# Randomness is an explicit input. Word boundaries so `state.rng.randi()`
	# -- which is the correct call -- is not reported.
	hits="$(grep -nE '(^|[^.[:alnum:]_])(randi|randf|randi_range|randf_range)[[:space:]]*\(' "$file" 2>/dev/null)"
	if [ -n "$hits" ]; then
		findings="$findings
  $file -- ambient RNG (randomness must come from GameState):
$(echo "$hits" | sed 's/^/    /')"
	fi
done <<< "$staged"

if [ -n "$findings" ]; then
	{
		echo "=== rules/ boundary pre-flight (advisory, not authoritative) ==="
		echo "$findings"
		echo ""
		echo "The contract tests decide. Run .github/scripts/validate-godot.sh."
		echo "==============================================================="
	} >&2
fi

exit 0

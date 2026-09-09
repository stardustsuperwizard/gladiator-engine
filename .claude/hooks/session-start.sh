#!/usr/bin/env bash
# SessionStart hook: print the repository's live state.
#
# Everything here is DERIVED from the tree, never restated from a document.
# That is the whole point: AGENTS.md's "Current state" section has already been
# wrong once and carries a dated correction saying so. Prose goes stale; a
# `find` does not.
#
# Advisory only. Always exits 0 -- a broken hook must never stop a session.
#
# Shape adapted from Claude-Code-Game-Studios (MIT) -- see THIRD_PARTY_NOTICES.md.

set +e

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root" || exit 0

echo "=== gladiator-engine ==="

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$branch" ] && echo "Branch: $branch"

dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
if [ "$dirty" != "0" ]; then
	echo "Working tree: $dirty uncommitted path(s)"
fi

echo ""
echo "Recent commits:"
git log --oneline -3 2>/dev/null | sed 's/^/  /'

# --- What is actually built -------------------------------------------------
# `TurnAction` subclasses are the unit of progress through spec §6, so listing
# them is the most honest one-line answer to "where is this project". Derived,
# so it cannot disagree with the tree.
#
# Keyed on `extends TurnAction`, NOT on living in rules/actions/. That
# directory also holds shared machinery -- `ChargeLockout` is a `RefCounted`
# legality predicate, not an action -- and counting by directory reported it
# as a fifth action the day it landed. The base class is the actual claim.
if [ -d rules/actions ]; then
	actions="$(grep -rl '^extends TurnAction' rules/actions --include='*.gd' 2>/dev/null \
		| xargs -r -n1 basename 2>/dev/null | sed 's/\.gd$//' | sort | tr '\n' ' ')"
	echo ""
	echo "Actions built (TurnAction subclasses): ${actions:-none}"
fi

# Spec §6's core actions, by name. The one hardcoded list in this file, and
# so the one line here that can go stale: it is keyed on a document rather
# than derived. It prints nothing once all of them exist, which is the state
# as of ChargeAction (#146). Add a name here if spec §6 ever gains an action.
missing=""
for a in move_action guard_action charge_action; do
	[ -f "rules/actions/$a.gd" ] || missing="$missing ${a%_action}"
done
[ -n "$missing" ] && echo "Not yet built (spec §6 core actions):$missing"

if [ ! -d rules/cards ]; then
	echo "rules/cards/ does not exist -- the card system is unbuilt (spec §4, §10)."
fi

# --- Can this session actually validate? ------------------------------------
# Exit code 127 from validate-godot.sh means "could not validate", which is a
# different claim from "validated". Better to know at minute zero than at the
# completion checklist.
if [ -n "$GODOT_BIN" ] && [ -x "$GODOT_BIN" ]; then
	echo ""
	echo "Godot: \$GODOT_BIN ($GODOT_BIN)"
elif command -v godot >/dev/null 2>&1; then
	echo ""
	echo "Godot: $(command -v godot)"
elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
	echo ""
	echo "Godot: /Applications/Godot.app (no CLI symlink; the script resolves it)"
else
	echo ""
	echo "Godot: NOT FOUND. .github/scripts/validate-godot.sh will exit 127."
	echo "  That is 'could not validate', not 'validated'. Say so rather than"
	echo "  reporting a clean run. CI pins 4.7.1-stable."
fi

echo "======================="
exit 0

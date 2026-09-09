#!/usr/bin/env bash
# Status line: ctx% | model | branch | actions built | godot
#
# Receives the session JSON on stdin, prints one line.
# Everything after the model is derived from the tree, for the same reason the
# SessionStart hook is: a status line that restates a document would go stale
# with it.
#
# Shape adapted from Claude-Code-Game-Studios (MIT) -- see THIRD_PARTY_NOTICES.md.

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
	model="$(echo "$input" | jq -r '.model.display_name // "?"')"
	pct="$(echo "$input" | jq -r '.context_window.used_percentage // empty')"
	cwd="$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')"
else
	model="$(echo "$input" | grep -oE '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')"
	pct="$(echo "$input" | grep -oE '"used_percentage"[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | sed 's/.*: *//')"
	cwd="$(echo "$input" | grep -oE '"current_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')"
	[ -z "$model" ] && model="?"
fi

[ -z "$cwd" ] && cwd="."
cd "$cwd" 2>/dev/null || true

if [ -n "$pct" ]; then ctx="ctx ${pct}%"; else ctx="ctx --"; fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -z "$branch" ] && branch="(no git)"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then branch="${branch}*"; fi

# Progress through spec §6, counted rather than claimed.
if [ -d rules/actions ]; then
	n="$(find rules/actions -name '*.gd' 2>/dev/null | wc -l | tr -d ' ')"
	actions=" | ${n} action$([ "$n" = "1" ] || echo s)"
else
	actions=""
fi

# A session that cannot run the suite should be reminded on every line, not
# once at startup.
if [ -n "$GODOT_BIN" ] && [ -x "$GODOT_BIN" ]; then
	godot=""
elif command -v godot >/dev/null 2>&1; then
	godot=""
elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
	godot=""
else
	godot=" | no godot"
fi

printf '%s | %s | %s%s%s' "$ctx" "$model" "$branch" "$actions" "$godot"

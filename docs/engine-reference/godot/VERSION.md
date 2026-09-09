# Godot — version pin

| Field | Value |
| --- | --- |
| **Pinned version** | `4.7.1-stable` |
| **Where the pin lives** | `.github/actions/setup-godot/action.yml` (`godot-version` default); `project.godot` declares `config/features=PackedStringArray("4.7")` |
| **Docs last verified** | 2026-09-09 against `godotengine/godot-docs` @ `stable` |

Both pins have to move together. `setup-godot` downloads
`Godot_v${GODOT_VERSION}_linux.x86_64.zip` from `godotengine/godot-builds`, and
every call site passes the default, so changing the default changes CI
everywhere at once.

## The knowledge gap

A model's training data lags the engine. Anything after that lag is territory
where a confident answer and a correct answer come apart, and GDScript fails
late — a renamed method is a runtime error, not a parse error, so a wrong
suggestion survives review and dies in a test run.

Treat **4.5 onward** as the gap. Verify against
`docs.godotengine.org/en/stable/` or the migration pages listed in
`README.md` before using an API you have not seen in this repo already.

The cheapest check is usually the repo itself: `rules/` and `tests/` are
written against 4.7 and already compile.

## Version timeline

| Version | Relevance here |
| --- | --- |
| 4.5 | `Resource.duplicate(true)` narrowed — see `breaking-changes.md`. Directly affects the template/runtime split in `rules/fighters/`. |
| 4.6 | `AStar*` returns an empty path from a disabled start point — recorded because Move deliberately does not use `AStar`. `.tscn` format changed (backward- and forward-compatible). |
| 4.7 | Overrides of a method with a typed return now inherit that return type. Affects every `TurnAction` subclass. |

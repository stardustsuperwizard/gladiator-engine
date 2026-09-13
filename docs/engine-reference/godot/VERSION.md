# Godot — version pin

| Field | Value |
| --- | --- |
| **Pinned version** | `4.7.2-stable` |
| **Canonical pin** | `.github/actions/setup-godot/action.yml`, the `godot-version` input default |
| **Docs last verified** | 2026-09-13 against `godotengine/godot` `CHANGELOG.md` @ `4.7.2-stable`; the 4.5–4.7 tables below were last checked 2026-09-09 against `godotengine/godot-docs` @ `stable` |

`setup-godot` downloads `Godot_v${GODOT_VERSION}_linux.x86_64.zip` from
`godotengine/godot-builds`.

## Where the pin actually lives

Six places, and they have to move together:

| Site | Form |
| --- | --- |
| `.github/actions/setup-godot/action.yml` | the `godot-version` input default — canonical |
| `.github/workflows/godot-validation.yml` | its own `godot-version` input default, forwarded to `setup-godot` |
| `.github/workflows/agent-02-implement.yml` | an explicit `godot-version:` at the call site |
| `.github/workflows/copilot-setup-steps.yml` | an explicit `godot-version:` at the call site |
| `.github/workflows/gdscript-lint.yml` | an explicit `godot-version:` at the call site |
| `project.godot` | `config/features` carries the same major.minor; the test bootstrap enforces it as a runtime floor |

> **Revised 2026-09-09, later the same day.** This section previously listed
> two sites and said "every call site passes the default, so changing the
> default changes CI everywhere at once." That was false when written. Three
> workflows pass an explicit version that overrides the default, and
> `godot-validation.yml` declares a fourth. Bumping the default alone would
> have left four surfaces on the old engine — silently, because each would
> still have gone green on it.

Do not hand-check this list. Part 7 of `.github/scripts/test-workflow-logic.sh`
fails the build when any site disagrees with the canonical pin, when
`project.godot` disagrees on major.minor, or when this file stops naming the
version it documents. Adding a new call site needs no edit here; adding a new
*kind* of site does.

**Part 7 asks only whether the pins agree, never whether they are current.**
"Is there a newer Godot, and should we take it" needs the network and a
judgement, so it belongs to a command rather than a test — `/godot-upgrade`,
filed as #153 and not yet built. Until it exists, that check is the manual
procedure in `README.md`.

> **Revised 2026-09-13.** This section previously said "`4.7.2-stable` is out
> and this project is on `4.7.1-stable`; whether to take it is #154." The pin
> is now `4.7.2-stable`, taken that day under #154 / #241. The evidence: the
> upstream changelog for the tag
> (`raw.githubusercontent.com/godotengine/godot/4.7.2-stable/CHANGELOG.md`,
> the `## 4.7.2 - 2026-08-17` section) carries no entry that passes this
> directory's filter — its one GDScript entry is an editor autocomplete icon,
> and nothing touches `Resource`/`RefCounted` semantics, the `.tres`/`.tscn`
> format, `ConfigFile`, or `--headless`/`--import`/`--quit` exit codes. The
> nearest miss is a Core crash fix for a log file that cannot be opened
> ([GH-121926](https://github.com/godotengine/godot/pull/121926)), which
> `validate-godot.sh` exercises through `--log-file`; it removes a crash
> rather than changing behaviour, so it earns no row in
> `breaking-changes.md`. `GODOT_BIN=Godot_v4.7.2-stable_linux.x86_64
> .github/scripts/validate-godot.sh` printed
> `4.7.2.stable.official.ed1daf0bf`, ran all 56 suites green and exited 0.
> No row was added to `breaking-changes.md` or `deprecated-apis.md`, because
> nothing in 4.7.2 passes the filter — the absence is the finding, not an
> oversight.
>
> Patch releases have no `tutorials/migrating/upgrading_to_godot_4.7.2.rst`
> migration page, and none was looked for. That absence is a property of how
> upstream publishes, and is not evidence either way about breakage.

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

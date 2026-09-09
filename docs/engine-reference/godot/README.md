# Godot engine reference

What changed in Godot after a model's training data ends, filtered to what
touches *this* project. Adapted from `Claude-Code-Game-Studios` — see
`THIRD_PARTY_NOTICES.md`.

## Why this exists

`docs/godot-implementation-guide.md` answers *how do we do this in Godot 4
without hitting the engine's sharp edges*. It is written against the engine as
a whole and does not date.

This directory answers a narrower and more perishable question: **which APIs
did the engine change recently enough that a model will confidently suggest the
old one?** An agent session reasoning from training data will reach for
`Resource.duplicate(true)` or assume `AStar2D.get_point_path` behaves as it did
in 4.5, and nothing in the guide contradicts it.

The split is the same one `AGENTS.md` draws between the spec, the plan and the
guide: one question per document.

## Files

| File | Answers |
| --- | --- |
| `VERSION.md` | Which Godot are we on, and where does the knowledge gap start? |
| `deprecated-apis.md` | Which API did this replace, and since when? |
| `breaking-changes.md` | What changed in 4.5, 4.6 and 4.7 that touches this project? |

## Maintaining it

**Every row cites an upstream source.** The rows here were taken from the
official migration pages in `godotengine/godot-docs` @ `stable`, fetched
2026-09-09:

- `tutorials/migrating/upgrading_to_godot_4.5.rst`
- `tutorials/migrating/upgrading_to_godot_4.6.rst`
- `tutorials/migrating/upgrading_to_godot_4.7.rst`

Do not add a row from memory — that is the exact failure mode this directory
exists to catch, and a wrong row here is worse than no row, because it will be
trusted. If you cannot cite it, leave it out and say so in the PR.

**Filter aggressively.** Upstream lists every change in the engine; most of it
is rendering, particles, XR, GLTF import and C# interop, none of which this
project has. A row earns its place here only if it could plausibly reach
`rules/`, `scripts/`, `tests/` or the headless validation path. The value is in
what has been left out.

**When the pin moves,** bump `VERSION.md`, read the new migration page, and add
only the rows that pass that filter.

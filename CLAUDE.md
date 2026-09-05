# CLAUDE.md

There is one source of truth for how to work in this repo. This file is a
pointer to it, not a copy.

## Read first

- `AGENTS.md` — project context, the two architectural commitments, working
  rules, testing and completion requirements. Tool-agnostic; read it in full
  before any change.

## Then, depending on what you are touching

| Working on | Also read |
| --- | --- |
| Game rules and mechanics | `docs/hex-skirmish-game-spec.md` |
| Anything in `rules/`, or Godot specifics anywhere | `docs/godot-implementation-guide.md` |
| Build order, scope, what to build next | `docs/moba-to-hex-skirmish-extraction-plan.md` §5–§7 |
| Anything sourced from `mikeys_game_bones-rules-moba` | `AUDIT_NOTES.md`, then log the decision in `EXTRACTION_LOG.md` |
| Anything in `rules/` | `.github/instructions/rules.instructions.md` |
| `.github/workflows/`, `.github/agents/`, `.github/actions/` | `docs/AGENT_WORKFLOW.md` |
| Opening a PR | `.github/pull_request_template.md`, `CONTRIBUTING.md` |

## Before the control plane works

Every agent workflow triggers on a label name, and a fresh clone has none of
them. Run `.github/scripts/bootstrap-labels.sh` once, and set the
`ANTHROPIC_API_KEY` repository secret, or nothing fires and nothing says why.

## Current state

No code yet. The next work is extraction plan §5.1 ("Slice 0"). Everything in
§5.3 is explicitly deferred — check that list before building something that
feels obviously missing, because it may be missing on purpose.

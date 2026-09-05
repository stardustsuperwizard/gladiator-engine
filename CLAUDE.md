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

## Working without an Issue

A review, audit, exploratory, or bootstrap session is not an implementer
session, and the scope rules written for implementers do not all transfer. The
clearest case is the PR template telling an implementation session not to file
the out-of-scope work it discovers: that exists to stop an implementer widening
its own Issue, and it inverts when deciding what should become work is the
point of the session. File discovered work when asked, and link it from the PR.

Such a PR has no originating Issue and so no `Closes #<issue>` line. Say that
explicitly at the top instead of leaving the template's placeholder in.

Put this marker on the **first non-blank line** of the body:

```text
<!-- no-originating-issue -->
```

`issue-linking.yml` gates on the branch prefix — `copilot/*` and `claude/*` —
so without the marker such a PR lands in a job whose only success path is a
closing reference it was never supposed to have, and whose repair step would
otherwise scan the body and silently link the PR to any open Implementation
Task it merely mentions. Prose saying there is no Issue is for the reader; the
marker is what the workflow reads. It is inert on a PR that does close a task.

The first non-blank line specifically, matched exactly rather than searched
for: a search anywhere in the body would find the marker in boilerplate that
merely contains it — the PR template's own header comment above all, since that
file becomes the body of every new PR. That gate must fail closed, which is
also why the template describes the marker instead of spelling it out.

A branch outside those two prefixes (`bootstrap/*`, say) does not trigger the
job at all. Include the marker anyway when the PR genuinely has no Issue — it
costs nothing and stays correct if the branch is ever renamed.

## Before the control plane works

Every agent workflow triggers on a label name, and a fresh clone has none of
them. Run `.github/scripts/bootstrap-labels.sh` once, and set the
`ANTHROPIC_API_KEY` repository secret, or nothing fires and nothing says why.

## Current state

No code yet. The next work is extraction plan §5.1 ("Slice 0"). Everything in
§5.3 is explicitly deferred — check that list before building something that
feels obviously missing, because it may be missing on purpose.

# Agent Instructions

Adapted from `mikeys_game_bones-rules-moba`'s `AGENTS.md` (extraction plan
§3.5). Process, not code — see `EXTRACTION_LOG.md` #12.

## Project

`gladiator-engine` is a Godot 4 rules engine for **turn-based hex-grid
combat**. Two players, small rosters of fighters, a fixed number of rounds,
and combat resolved by a dice pool with symbol matching.

Three documents, three jobs — keep them that way:

| Document | Answers |
| --- | --- |
| `docs/hex-skirmish-game-spec.md` | *What are the rules?* Mechanics only, engine-agnostic. |
| `docs/moba-to-hex-skirmish-extraction-plan.md` | *What gets built, in what order, and what came from where?* |
| `docs/godot-implementation-guide.md` | *How is that done in Godot 4 without hitting the engine's sharp edges?* |

Do not put Godot specifics in the spec, and do not put mechanics in the guide.

**The current state is: no code.** The next thing to build is extraction plan
§5.1, "Slice 0" — a board, two fighters, one Attack routed through the
authority object, and tests asserting the result against the tabletop rules
worked by hand. Do not build ahead of it.

The mechanics are inherited from a settled tabletop game, so the rules are not
up for redesign. The numbers are: expect dice counts, damage values, and point
costs to be tuned, which is why they live in data files rather than in the
resolver.

## The two architectural commitments

Everything else is negotiable. These are not.

1. **`rules/` has a strictly one-way dependency arrow.** The game depends on
   the rules, never the reverse, enforced by a contract test. This is what
   keeps simulation deterministic and identical wherever it runs.
2. **Every action goes through one authority object** — including in local
   hotseat, where it looks like pure ceremony. UI gathers intent; the
   authority validates and resolves; the UI renders what comes back and never
   mutates state itself. If hotseat ever calls the rules module directly, the
   calling convention has to be rebuilt for anything else — AI, undo, replays,
   networking.

A third, which falls out of the first two: **the resolver takes its randomness
as an explicit input.** Combat is a dice pool, so "pure simulation" is only
true if the seed and generator position live in the game state. Never read an
ambient RNG from inside `rules/`.

## Working Rules

- Read the complete task before making changes.
- Read the relevant project documentation before implementing.
- Inspect existing code before introducing new abstractions.
- Make the smallest change that satisfies the task.
- Do not implement functionality listed as out of scope — extraction plan §5.3
  is a list of things that are deliberately not being built yet.
- Do not refactor unrelated code.
- **Do not add third-party dependencies or addons.** This project builds what
  it needs. Inherited directly from the source repo, which deleted its own
  framework layer after roughly two-thirds of it proved unreachable. A testing
  framework (GdUnit4 or GUT) is the one sanctioned exception. If a task looks
  like it wants a plugin, say so rather than adding one.
- New abstractions need a second caller before they earn a name.

## Architecture

- Rules code stays free of the scene tree: `RefCounted` or `Resource`, never
  `Node`. No autoload access, no `await`, no `_process`. See
  `docs/godot-implementation-guide.md` §1.
- Game content — fighters, weapons, cards — ships as data (`.tres`), not as
  class hierarchies.
- Prefer composition and existing extension points over new abstractions.
- A new player action should be a new action subclass and nothing else: no
  edit to the authority object, no registry to update. If adding an action
  requires touching the gate, the gate is wrong.
- If a requested feature conflicts with the documented architecture, explain
  the conflict rather than silently working around it.

## Testing

- The unit tests that assert combat resolution against the tabletop rules
  *are* the specification. Write them alongside the resolver, not after.
- Existing tests represent established behavior.
- Do not weaken, remove, or skip tests merely to make an implementation pass.
- Add tests for new behavior when practical.
- Tests run headless (`godot --headless`).
- Report validation that could not be performed.

## Completion

Before declaring a task complete:

1. Verify the acceptance criteria — extraction plan §7 for the standing ones.
2. Run the test suite, including the `rules/` contract test.
3. Confirm determinism where relevant: same state + same seed + same actions →
   same result.
4. Summarize what changed.
5. Call out assumptions, limitations, and unresolved design questions rather
   than leaving them implicit.

## Agent Roles

Planning, implementation, and review run as separate sessions on different
models. See `docs/AGENT_WORKFLOW.md` for role definitions, model routing, and
the handoff contract; `.github/agents/` for the cloud agent profiles and
`.claude/agents/` for their local Claude Code counterparts.

The control plane is label-driven. **Every trigger is keyed on a label name,
and a fresh clone has none of them** — run `.github/scripts/bootstrap-labels.sh`
once before expecting any workflow to fire.

Claude-vendor sessions bill to the `ANTHROPIC_API_KEY` secret, which is API
credit and **not** covered by a Claude Pro or Max subscription. Whether a
subscription could pay for them instead is an open question with a written-up
answer — see *Open: paying for Claude sessions with a subscription instead of
API credits* in `docs/AGENT_WORKFLOW.md`. The Copilot-vendor path
(`agent:*:copilot`) needs no Anthropic billing at all.

## Path-scoped instructions

Copilot picks these up automatically via `applyTo:` frontmatter; Claude Code
does not, so check manually before editing:

| Directory | Also read |
| --- | --- |
| `rules/**` | `.github/instructions/rules.instructions.md` |

## Issue Dependencies

One Issue waiting on another is written in that Issue's `## Dependencies`
table — `Blocked by` or `Blocks`, one row per edge — and the Issue doing the
blocking gets the `blocker` label. The label is what turns the table into
GitHub's native dependency relationship, which is what the control plane
orders by.

Write the row and add the label. Do not create the relationship by hand. The
full contract is *Declaring Issue dependencies* in
`.github/copilot-instructions.md`.

## Recording decisions

- Extraction decisions (extract / adapt / rebuild / reject) go in
  `EXTRACTION_LOG.md`, one row, with the rationale.
- Findings about the source repo go in `AUDIT_NOTES.md`.
- When a document is revised because it was **wrong** — not merely
  incomplete — say so in the document, dated, with what it previously claimed.
  A settled decision that leaves no trace of why it was settled gets
  re-litigated. (Practice taken from the source repo; `EXTRACTION_LOG.md` #13.)

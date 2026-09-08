# Agent Instructions

Adapted from `mikeys_game_bones-rules-moba`'s `AGENTS.md` (extraction plan
§3.5). Process, not code — see `EXTRACTION_LOG.md` #12.

## Project

`gladiator-engine` is a Godot 4 rules engine for **turn-based hex-grid
combat**. Two players, small rosters of fighters, a fixed number of rounds,
and combat resolved by a dice pool rolled against a target number.

Three documents, three jobs — keep them that way:

| Document | Answers |
| --- | --- |
| `docs/hex-skirmish-game-spec.md` | *What are the rules?* Mechanics only, engine-agnostic. |
| `docs/moba-to-hex-skirmish-extraction-plan.md` | *What gets built, in what order, and what came from where?* |
| `docs/godot-implementation-guide.md` | *How is that done in Godot 4 without hitting the engine's sharp edges?* |

Do not put Godot specifics in the spec, and do not put mechanics in the guide.

**Current state (2026-09-08): Slice 0 is built, and the spec has moved ahead of
it.** Extraction plan §5.1 is merged — the hex board with cube distance and
symmetric line of sight; the `FighterTemplate`/`Fighter` model over authored
`.tres`; `DeterministicRng` and a serializable, digestible `GameState`; the
dice pool with flanking and surrounding; and `AttackAction` and `PassAction`
resolving through `Authority`/`ActionRunner`, with the hand-worked combat tests
§5.1 asks for and contract tests behind both architectural commitments.

**The code does not match spec §3, §6 and §7 as revised 2026-09-08.** Still in
the tree and no longer in the rules: `WeaponTemplate` and
`FighterTemplate.weapons`; `DiceProfile`'s symbol faces and `DicePool`'s
success-set matching; the weapon `AttackAction` takes through `_init()`. Not
yet in the tree and now required: the fighter's `range`, `attack` and `damage`
stats, and the `CombatProfile` holding the target numbers, the flank and
surround modifiers, the long-range threshold and the clamp.

Reconciling the two is the next work, and it comes **before** the rest of §5.2.
Move, Charge and Guard all touch resolution — Charge resolves an attack, Guard
modifies a save target — so building them against the old model means paying
for them twice. The hand-worked combat tests are the bulk of that cost: their
expectations are derived from symbol faces and have to be re-derived against
target numbers.

After that, the rest of §5.2 in the spec's own build order (§12): the remaining
core actions (Move, Charge, Guard, Focus) → status effects → the card system →
scoring and the end phase → victory conditions. There is still no UI and no
hotseat loop, so §5.4's "play a full 3-round match" is some way off. Do not
build ahead of the order above, and check §5.3 before building something that
feels obviously missing — it may be missing on purpose.

**The spec is the authority on mechanics, and an implementation session does
not redesign them.** Most of the rules are inherited from a settled tabletop
game — the board, the round and turn structure, the core actions, flanking and
surrounding, scoring and victory. Where that inheritance holds, reasoning from
the tabletop original is sound.

**It does not hold everywhere, and the exceptions are deliberate.** Spec §7's
combat resolution diverges on purpose: symbol-faced dice were replaced by d6
against a target number, and the fighter/weapon split was collapsed into a
single six-stat fighter with weapons demoted to presentation. Both are dated
and argued in the spec itself (§3, §7). Do not "restore" either by appeal to
the tabletop rules or to an older document — check the spec's revision notes
before concluding a rule is wrong.

Rules changes happen by **revising the spec first**, as an owner decision, with
the dated revision note the spec's own convention requires. A session that
believes a rule is wrong says so and stops; it does not correct it in the
resolver, and a rule that lives only in code is a bug regardless of how right
it is.

The numbers are a different matter. Dice counts, damage values, target numbers,
modifiers and point costs are all expected to be tuned, which is why they live
in data files rather than in the resolver — see spec §12.

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

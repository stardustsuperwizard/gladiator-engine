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

**Current state (2026-09-08): Slice 0 is built, and the code is reconciled with
the revised spec.** Extraction plan §5.1 is merged — the hex board with cube
distance and symmetric line of sight; the `FighterTemplate`/`Fighter` model over
authored `.tres`; `DeterministicRng` and a serializable, digestible `GameState`;
the dice pool with flanking and surrounding; and `AttackAction` and `PassAction`
resolving through `Authority`/`ActionRunner`, with the hand-worked combat tests
§5.1 asks for and contract tests behind both architectural commitments.

> **Revised 2026-09-08, later the same day.** This section previously said the
> code did not match spec §3, §6 and §7 as revised that morning, and that
> reconciling the two was the next work and came **before** the rest of §5.2.
> That was true when written and is no longer: epic #83 closed with all six of
> its tasks merged (#84–#89). `WeaponTemplate`, `FighterTemplate.weapons`,
> `DiceProfile`'s symbol faces and `DicePool`'s success-set matching are gone
> from the tree; the fighter's `range_hexes`, `attack` and `damage` stats,
> `CombatProfile` and `ConstructionBudget` are in it; and the hand-worked combat
> tests have been re-derived against target numbers. Do not plan reconciliation
> work — it is done.

**Built, against the spec's own sections:** §2's board in full. §3's data model —
six-stat `FighterTemplate`, runtime `Fighter`, `CombatProfile`,
`ConstructionBudget`, `GameState`, `DeterministicRng`. §7's resolution — d6
against a target number, the two separate target-number charts, the engagement
bonus, damage, defeat and push-back. §8's flanking and surrounding. §9's damage
and defeat.

**Not built, and the next work: §6's remaining core actions.** `AttackAction`
and `PassAction` are the only two `TurnAction` subclasses in the tree. Move,
Charge and Guard are now unblocked — the reason to hold them, that they all
touch resolution and resolution was about to change under them, no longer
applies.

A suggested order within that, which is not quite §6's own listing:

- **Move** first. §12 warns that movement and distance are different problems:
  §2's distance is a direct coordinate calculation, while movement must route
  *around* blocked and occupied hexes and needs a real search. It also needs the
  `"moved"` status-flag constant, which does not exist yet — `Fighter` carries
  the flag *mechanism* (`set_status_flag`, `has_status_flag`,
  `clear_status_flag`) and no rule names a flag through it.
- **Guard** next. Small, and `CombatProfile.guard_modifier` is authored in
  `resources/combat/combat_profile.tres` and read by nothing until it exists.
- **Charge** third. It is Move plus Attack composed, plus the `"charged"` flag
  and §6's lockout rule, so it wants both of the above first.
- **Focus/Mulligan** discards and draws cards, and there is no card system. It
  belongs with the card work rather than with the other three.

Round-level flag clearing (§10 step 5) arrives with the first flag that needs
clearing, which is Guard's.

After that, the rest of §5.2 in the spec's own build order (§12): status effects
→ the card system → scoring and the End Segment → victory conditions.
`PlayerState` already carries the empty `hand`, `deck`, `discard` and `scored`
arrays the card system fills; `rules/cards/` does not exist yet. There is still
no UI and no hotseat loop — `scripts/` holds `Authority` and `ActionRunner`, and
`scenes/main.tscn` is a stub — so §5.4's "play a full 3-round match" is some way
off. Do not build ahead of the order above, and check §5.3 before building
something that feels obviously missing — it may be missing on purpose.

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

`docs/AGENT_ROLE_DESIGN.md` answers the separate question of **why these are
the roles** — the test a proposed new agent has to pass (a tool boundary, a
cost tier, or a context wall; a job title is none of them), why an
orchestrator-and-specialists shape does not fit this control plane, and the
conditions that would make a fifth or sixth role worth adding. Read it before
proposing one.

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

One contract per directory, reached by two different mechanisms:

| Directory | Contract | Copilot loads it via | Claude Code loads it via |
| --- | --- | --- | --- |
| `rules/**` | `.github/instructions/rules.instructions.md` | `applyTo:` frontmatter | `rules/CLAUDE.md` |

`rules/CLAUDE.md` exists only to point at the contract. Both vendors get the
same text; neither has its own copy to drift from. Adding a second scoped
contract means adding both halves — the `applyTo:` file and a `CLAUDE.md` in
the directory that points to it.

> **Revised 2026-09-09.** This section previously said Claude Code does not
> pick path-scoped instructions up and that a session had to "check manually
> before editing." That was true and is no longer: a directory-scoped
> `CLAUDE.md` is loaded when a session touches files in that directory, so the
> manual step is gone. If a session ever finds itself editing `rules/` without
> having seen the contract, the pointer file is missing or misnamed — the
> instruction to check manually is the fallback, not the plan.

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
  `EXTRACTION_LOG.md`, one row, with the rationale. That log is scoped to
  `mikeys_game_bones-rules-moba`, whose commit its header pins. Material from
  any other outside repository goes in `THIRD_PARTY_NOTICES.md` instead, using
  the same four verdicts, and carrying that source's licence notice — MIT and
  most others require the notice to travel with the work, and reproducing it
  costs nothing next to being wrong about what counts as substantial.
- Findings about the source repo go in `AUDIT_NOTES.md`.
- When a document is revised because it was **wrong** — not merely
  incomplete — say so in the document, dated, with what it previously claimed.
  A settled decision that leaves no trace of why it was settled gets
  re-litigated. (Practice taken from the source repo; `EXTRACTION_LOG.md` #13.)

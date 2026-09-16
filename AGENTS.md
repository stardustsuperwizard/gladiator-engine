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

A fourth answers a question about the boundary *around* the game rather than
about the game, added 2026-09-15:

| Document | Answers |
| --- | --- |
| `docs/headless-authority-and-client-sdk.md` | *How does a third party play without our client?* |

It is not build-order work and says so at the top, as plan §5.5 does. Content
licensing is a related question and is **tracked outside this repository** —
what matters inside it is the engineering constraint in *Before the card
system* below, which that document reaches independently as its constraint 8.

**Current state (2026-09-15): Slice 0, spec reconciliation, and the core action
framework are all built and merged.** Extraction plan §5.1 is in the tree: the
hex board with cube distance and symmetric line of sight; the
`FighterTemplate`/`Fighter` model over authored `.tres`; `DeterministicRng` and
a serializable, digestible `GameState`; the dice pool with flanking and
surrounding; and `AttackAction` and `PassAction` resolving through
`Authority`/`ActionRunner` with hand-worked combat tests and contract tests
behind both architectural commitments.

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

> **Revised 2026-09-12.** This section previously said Move, Guard, and Charge
> were "not built" and the "next work". All five core actions except Focus/Mulligan
> are now merged: `MoveAction`, `GuardAction`, and `ChargeAction` (with
> `ChargeLockout`) are in the tree alongside `AttackAction` and `PassAction`.
> §10 step 5 (round-level flag clearing) was claimed to "arrive with the first
> flag that needs clearing, which is Guard's" — that was stale even then (Move
> shipped the first flag) and is now false entirely (`EndSegment` implements
> clearing generally). Epic #181 (the Combat Segment turn sequencer) is merged:
> `TurnSequence` (whose Turn is next), `DefaultActionStep`, and `RoundDriver`
> let a full round play through the gate. Epic #203 (hotseat UI) is merged:
> `scenes/main.tscn` is no longer a stub; `HotseatMatch`, `HotseatSession`,
> `ActionOptions`, `BoardView`, and `MatchSetup` make it a real, playable
> hotseat scene — two players can complete a Combat Segment start to finish
> through it.

**Built, against the spec's own sections:** §2's board in full. §3's data model —
six-stat `FighterTemplate`, runtime `Fighter`, `CombatProfile`,
`ConstructionBudget`, `GameState`, `DeterministicRng`. §5's round structure and
turn resolution (Combat Segment, Turn, Action/Power Steps, auto-Guard default).
§7's resolution — d6 against a target number, the two separate target-number
charts, the engagement bonus, damage, defeat and push-back. §8's flanking and
surrounding. §9's damage and defeat. §6's five core actions (all but
Focus/Mulligan). §10's End Segment: only step 5's round-level flag clearing in
`EndSegment` (steps 1–4 are card-system-blocked; step 6's final-round branch is
unbuilt, #173).

**Built as core mechanics:** Epic #181's turn sequencer — `TurnSequence`
(rules/state/turn_sequence.gd, determining which Turn is next) and
`DefaultActionStep` (rules/actions/default_action_step.gd, providing auto-Guard)
— both reside in `rules/` and drive the core action sequencing. `RoundDriver`
(scripts/round_driver.gd) orchestrates these during a full round.

**Built but as a UI framework, not core mechanics:** Epic #203's hotseat scene
lets two players sit down at `main.tscn`, draft fighters and settings with
`MatchSetup`, and play the match through `HotseatMatch`, which routes actions
through `ActionOptions` and renders the board with `BoardView`.

**Not built, and the next work:** §11 (victory determination) and §10 step 6's
final-round branch (both via #173, which also addresses the match ending with no
one deciding who won), and the card system, which unblocks Focus/Mulligan and
steps 1–4 of §10. `PlayerState`
carries empty `hand`, `deck`, `discard` and `scored` arrays that the card
system fills; `rules/cards/` does not exist yet. Do not build ahead of §5.2's
build order (§12), and check §5.3 before building something that feels
obviously missing — it may be missing on purpose.

**Before the card system — one constraint, revised 2026-09-15.** The card
schema must be able to load content **served from outside this repository**,
not only from a `res://rules/cards/*.tres` path compiled into the build. A card
system that only ever reads compiled-in paths works perfectly in hotseat and is
a retrofit afterwards, so this is cheap now and expensive later.

`docs/headless-authority-and-client-sdk.md` reaches the same requirement from
the API side, where it is constraint 8: a third-party client cannot be required
to have shipped with card text in order to render a match. That is the reason
that matters for anyone working in this tree.

> **Revised 2026-09-15, later the same day.** This section previously said
> `rules/cards/` must not be created until a licence boundary was settled, and
> pointed at a `docs/licensing-and-content-boundary.md` that is no longer in
> this repository. **Owner decision: mechanic-only cards live in this
> repository under its MIT licence, like everything else here, and creating
> `rules/cards/` is not gated on anything.** A card that is purely a rule
> — "+1 Health" — carries no expression a licence could protect anyway. The
> content-ownership question is real but is tracked outside this repository;
> do not reintroduce it here, and do not treat its absence as license to add
> authored art, flavour text or lore to `resources/` without asking.

**§4's Setup Sequence is unbuilt too, and was absent from both lists above
until 2026-09-15.** `MatchSetup` says as much in its own first paragraph: it is
spec §4's *placeholder*, not §4 — no roster building against
`ConstructionBudget`, no deployment rules, no mulligan, no roll-off, no
feature-token placement. It hands back a hardcoded board with a fixed roster so
that the parts above it have something to run on.

Only the mulligan there is card-blocked. §5.2's roll-off is not — turn order is
today the order `MatchSetup` happened to add its players in, and neither the
loser's compensating ability draw nor the later-round behind-on-points
tiebreak exists. Feature tokens are absent from `Board` as well (`board.gd`
puts them out of scope), which leaves §11's second tiebreaker nothing to count
and §2's "holding" nothing to hold. A match therefore cannot legally start any
more than it can legally end.

**Known rough edges from the UI work:** #214 (the selected fighter is not
cleared when passing to the next Turn, leaving the board display confused) and
#215 (scene files lack `uid://` headers, making them fragile to refactoring).
Neither blocks play, but both are worth fixing soonish.

**Control-plane state (2026-09-15).** The *Agent Roles* section below describes
how the control plane works. This is what of it exists — a run of
infrastructure work landed on 2026-09-13 and 2026-09-14, after the revision
note above, and almost none of it was visible anywhere else in this file:

- **The run ledger.** `.metrics/runs.csv` is an append-only,
  version-controlled record of control-plane runs: one row per merge, one per
  agent session. `.github/workflows/run-ledger.yml` is its only writer, it
  derives every field from GitHub's own JSON through
  `.github/scripts/ledger_row.py` rather than from any model's prose, and it is
  built never to fail a merge — a lost row is a gap in a ledger, a red run is a
  signal that the merge itself went wrong. The session rows come from the
  `<!-- agent-session-record -->` JSON comments that `agent-02-implement.yml`,
  `agent-04-review.yml` and `agent-05-fix.yml` post. Schema and vocabularies:
  `docs/RUN_LEDGER.md`.
- **The pipeline report.** `.github/workflows/pipeline-report.yml` runs
  weekly (and on dispatch), spends no AI credits, and publishes a
  credit-free markdown report to the pinned `pipeline-report` Issue. It
  derives delivery frequency, first-pass yield, planner tier accuracy,
  verdict distribution and fix rounds from `.metrics/runs.csv` via
  `.github/scripts/pipeline_metrics.py`, and lead time for change, change
  failure rate, time to restore and CI wall-clock duration from GitHub's own
  state, via `.github/scripts/render-pipeline-report.py`. It reads the
  ledger; it never writes it.
- **The test ratchet**, documented under *Testing* below.
- **An export job.** `ci.yml`'s `export` job builds a Linux artifact via
  `.github/scripts/export-godot.sh` against `export_presets.cfg`. Every scrap
  of export logic lives in the script, so a local run and the CI job mean the
  same thing, and the build goes under `$RUNNER_TEMP` — never into the
  checkout.
- **A smoke driver, and a smoke stage.** `scripts/smoke_bootstrap.gd` and
  `scripts/smoke_match_driver.gd` play a scripted headless match behind a
  `--smoke` command-line flag, and `ci.yml`'s `smoke` job runs it against the
  exported artifact — it needs `export`, downloads the Linux build, and calls
  `.github/scripts/smoke-godot.sh`, which holds every scrap of the logic so a
  local run and the CI job mean the same thing.

  > **Corrected 2026-09-15.** This entry previously read "a smoke driver, but
  > not a smoke stage" and said the CI job "does **not** exist (#312)". That
  > was true when written and had already stopped being true: #312 landed in
  > `cf3cbe5` (PR #318) and #313 followed in `770324a` (PR #326), both before
  > the 2026-09-15 revisions elsewhere in this file, and neither updated this
  > entry. The correction is documentary — the job is in `ci.yml` and can be
  > read there. **What is not corrected, because it was not verified:** no
  > commit in the tree references #319, the failing `--smoke` driver, so treat
  > that one as open until its Issue says otherwise. A session with no Godot
  > binary cannot settle it either way, which is the situation the correction
  > was made from.
- **One Godot pin, in one place.** 4.7.2-stable, as the input default of
  `.github/actions/setup-godot`. No call site restates it, and Part 7 of
  `.github/scripts/test-workflow-logic.sh` fails a *second* literal even when
  it matches today's value. Change the version there and nowhere else.
- **The release stage.** `.github/workflows/release.yml`, dispatched by hand
  against a commit and version, decides releasability via
  `.github/scripts/release-preflight.py` and publishes the artifact a `ci.yml`
  run already exported and smoke-ran. Releasing is manual on purpose — see
  `docs/RELEASING.md` — and nothing else in this repository publishes a
  release.

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
  This is enforced: `ci.yml`'s `red-gate` job runs a pull request's new and
  changed tests against the merge base and fails when one of them already
  passes there — the unit is the test suite, and `red-gate.py`'s docstring
  says why. `characterization-test` is the human-only override, for the
  genuine case: a refactor whose new test covers behavior that already
  worked. The ratchet and the red gate bound opposite directions — the
  ratchet stops a test being removed or gutted, the red gate stops a test
  being added that asserts nothing.
- Existing tests represent established behavior.
- Do not weaken, remove, or skip tests merely to make an implementation pass.
  This is enforced: `ci.yml`'s `test-ratchet` job fails a pull request whose
  suite count or `_expect(` assertion count is lower than its merge base's,
  and `test-removal-approved` is the human-only override.
- Add tests for new behavior when practical.
- Tests run headless (`godot --headless`), against Godot **4.7.2-stable** —
  pinned once, as `.github/actions/setup-godot`'s input default.
- `.github/scripts/validate-godot.sh` is the local entry point. It exits **127**
  when no Godot binary is on the `PATH`. That is *could not validate*, not
  *validated*, and the two must not be reported as the same thing.
- CI exports a playable Linux build (`ci.yml`'s `export` job) and runs it
  (`ci.yml`'s `smoke` job). **Corrected 2026-09-15** — this previously said
  "nothing yet runs that artifact," which #312 stopped being true; see the
  control-plane entry above for the full correction. A green unit suite still
  says the code is correct rather than that the exported game starts; it is the
  `smoke` job, not the suite, that speaks to the second. #319 (the `--smoke`
  driver failing) is unverified by this correction and should be treated as
  open.
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

A fifth role, plan review, checks a planner's sub-issues against their parent
epic before any task is dispatched — read-only, and its verdict is advice
rather than a dispatch gate. What it has no v1 of is a **workflow**: there is
no `agent-07-*.yml`, no `agent:plan-reviewer:*` label, and no dispatch path
that reads a verdict, so a `PLAN FIX` sitting on an epic binds nothing until a
human acts on it.

It is not, however, local-only. The cloud profile
(`.github/agents/07-plan-reviewer.agent.md`), the deterministic request
assembler as a composite action (`.github/actions/build-plan-review-request/`)
and plan-verdict parsing inside `extract-review-verdict` are all in the tree.
See *Plan review* in `docs/AGENT_WORKFLOW.md` for the eight checks it works and
the three verdicts. The agent contract lives in **two** files that must be
edited together — `.claude/agents/plan-reviewer.md` and
`.github/agents/07-plan-reviewer.agent.md`.

> **Revised 2026-09-15.** This section previously called plan review
> "local-only in v1." That was true when written and stopped being true within
> the week: #243 added the cloud profile and #245 the control-plane wiring. The
> load-bearing claim was always *no workflow reads the verdict*, which still
> holds; "local-only" was a loose restatement of it that a session could
> reasonably have read as licence to edit the local half of the role contract
> and leave the cloud half behind.

The control plane is label-driven. **Every trigger is keyed on a label name,
and a fresh clone has none of them** — run `.github/scripts/bootstrap-labels.sh`
once before expecting any workflow to fire.

**Three vendors, and the third segment of a label picks which pays.**
`agent:{role}:copilot` runs the Copilot CLI on a Copilot licence and needs no
Anthropic billing at all. `agent:{role}:anthropic` and `agent:{role}:claude`
both run Claude Code, on the same models with the same tools, and differ only
in the credential: `anthropic` spends the `ANTHROPIC_API_KEY` secret, which is
Anthropic Platform API credit; `claude` spends the `CLAUDE_CODE_OAUTH_TOKEN`
secret, which is a Claude Pro or Max subscription.

Pick between the last two on which budget should absorb the run, never on what
the run can do — they are the same session. See *One workflow per role, three
vendors* in `docs/AGENT_WORKFLOW.md`, and *Resolved: paying for Claude sessions
with a subscription instead of API credits* for why it is two vendors rather
than one vendor and a flag.

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

## Local session hooks

`.claude/settings.json` wires two hooks for Claude Code sessions: a
`SessionStart` hook that reports the branch, which `TurnAction` subclasses
exist, and whether a Godot binary is present; and a `PreToolUse` hook on
`git commit` that greps staged `rules/` files for outward references and
ambient RNG.

**The second is advisory and always exits 0.** It is not a second enforcement
point, and it deliberately reproduces only the two rules that are honestly one
grep — the base-class and inbound-type contracts need real derivation and are
left alone rather than half-copied. Enforcement belongs to the contract tests
(`extraction_contract_test.gd`, `ambient_rng_contract_test.gd`,
`base_class_contract_test.gd`, `tests/inbound_type_contract_test.gd`), and a
violation fails the build there whatever the hook said. A hook that stayed
quiet is not a check that passed.

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
- Control-plane **runs** are recorded automatically and never by hand.
  `run-ledger.yml` appends to `.metrics/runs.csv` on merge; that file is
  append-only, has exactly one writer, and `ci.yml` closes its gates when a
  pull request touches nothing else. Do not hand-edit it, sort it, or
  regenerate it in a pull request. `docs/RUN_LEDGER.md` is the schema.
- When a document is revised because it was **wrong** — not merely
  incomplete — say so in the document, dated, with what it previously claimed.
  A settled decision that leaves no trace of why it was settled gets
  re-litigated. (Practice taken from the source repo; `EXTRACTION_LOG.md` #13.)

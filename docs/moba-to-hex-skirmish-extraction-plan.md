# Extraction Plan: mikeys_game_bones-rules-moba → Hex Skirmish Game

**Audience:** Coding agent (Claude Code or equivalent) with read access to
`stardustsuperwizard/mikeys_game_bones-rules-moba` and write access to the new
hex-skirmish project.

**Objective:** Identify and adapt genuinely portable pieces of the MOBA repo's
architecture into the new turn-based, hex-grid skirmish game — as one-time
copies adapted to the new project, not as a shared package/addon dependency
between the two repos.

---

## 0. Ground Rules (read this before touching anything)

- **This repo explicitly rejected being a reusable framework.** Issue #276
  (2026-08-30) deleted `addons/` and reversed the earlier "portable engine
  other games can host" goal after roughly two-thirds of that layer proved
  unreachable. `AGENTS.md`: *"Do not add third-party dependencies or
  addons... this project builds what it needs."* Do not resurrect that
  pattern here. Extraction means: read the source, understand the contract,
  write a new adapted version in the hex-skirmish repo. Do not add
  hex-skirmish as a dependent of `mikeys_game_bones-rules-moba`, and do not
  turn `rules/` back into an addon.
- `rules/` keeps a strict one-way dependency arrow (game → rules, never the
  reverse), enforced by `rules/tests/extraction_contract_test.gd`. That
  discipline is worth replicating in the new repo's own rules module — not
  because the code transfers, but because the same reason it exists there
  (client and server must run identical simulation) applies to a
  turn-based resolver too.
- Do not assume anything in `docs/` is shipped code. `docs/GAME_MODES.md`
  and `AGENTS.md` describe target architecture and reference issues
  (#277, #278, #280) by design intent, not necessarily by merged state.
  **Verify actual implementation status in Section 1 before planning around
  any of it.**
- Log every decision (extract / adapt / rebuild) with a one-line rationale
  in `EXTRACTION_LOG.md` at the new project root.
- Engine-specific practice — scene-tree discipline, Resources as game data,
  hex coordinates, RNG determinism, testing, version control — lives in
  `docs/godot-implementation-guide.md`, not here and not in the game spec.
  This plan says *what* to build and in what order; that guide says how to do
  it in Godot 4 without stepping on the engine's sharp edges.

---

## 1. Pre-Flight Audit (time-boxed — see Section 6 for when)

> **Re-sequenced.** This was originally "do this first." It no longer is.
> Section 2 already rules out most of the source repo, and Section 3 finds
> only two items with a real payoff: the session layer (3.2) and the workflow
> docs (3.5). Reading another codebase for days before writing a line of this
> one is how a project stalls before it starts. Do 3.5 immediately (zero
> risk), build the Section 5.1 slice, and return here when you actually reach
> networking. Time-box it to a single session when you do.

1. Read, in this order: `AGENTS.md`, `docs/GAME_MODES.md`,
   `docs/rules/README.md`, `docs/pulp_moba_rpg_ruleset.md`,
   `.github/instructions/rules.instructions.md`,
   `rules/tests/extraction_contract_test.gd`.
2. Check the actual merge/implementation status of:
   - **#277 (authority gate / command taxonomy)** — is it merged? Is it
     already a general verb-registration system, or still hardcoded to
     attack/cast? This determines whether Section 3 below is "adapt" or
     "design from scratch using the same idea."
   - **#278 (session layer / lobby)** — is host/join working? Does it
     already support single-player-vs-bots as a first-class session mode
     (per `AGENTS.md`, it's meant to)? That mode-parity is directly useful
     for hex-skirmish's own single-player/LAN/dedicated-server requirement.
   - **#280 (character system)** — confirm this is Discipline/ability-loadout
     specific (six Disciplines, 4 actions + 1 passive) before ruling it out
     for hex-skirmish's fixed-roster-of-fighters model.
3. Map the shared type contract in `scripts/`: `Actor`, `Controller`,
   `ActorBody3D`, `Action`, `ActionResult`. Note how combat is composed onto
   these (per `docs/GAME_MODES.md`: combat is a *component*, e.g.
   `MobaBasicAttackCycle.start(target)` runs against an entity with no
   `Controller` and no body — that's how the tower-defense mode gets
   stationary attackers for free). This composition pattern is worth
   understanding even though the combat math it carries isn't reusable.
4. Write findings to `AUDIT_NOTES.md`, explicitly answering: is #277 usable
   as-is, adaptable, or a from-scratch build using its design principle?
   Same question for #278.

---

## 2. What NOT to Extract (confirmed by repo docs, not assumption)

- **Combat resolution** — `MobaDamage`, `MobaFormulas`, `MobaCooldowns`,
  `MobaAbilityAction`/`MobaAbilityCaster`, `MobaTargeting`/`MobaProjectile`,
  `MobaEffectContainer`, `MobaCrowdControlTracker`, `MobaStateMachine`,
  `MobaDeathHandler`. All of this is real-time, cooldown/tick-driven combat
  with skillshot/projectile targeting. The hex-skirmish spec's combat is a
  discrete dice-pool + symbol-matching resolution with flanking bonuses
  (spec §7–8) — a different resolution model, not a reskin of this one.
  **Rebuild.**
- **Movement / pathing** — note the MOBA repo currently has *no* navigation
  system at all (`planned_features.md` §2.1: click-to-move and AI chase are
  straight lines). There's nothing to extract here either way; hex-step
  movement is new work regardless.
- **Character/Discipline/ability system (#280)** — a loadout-theorycrafting
  system (primary/secondary Discipline, 4 actions + 1 passive, respec
  between matches) built for a persistent, player-owned, cross-match
  character. Hex-skirmish's spec is a fixed roster of 3–5 fighters with
  stats/weapons/cards defined per Section 3 of the design doc — a
  differently-shaped data model. Don't force-fit; design new, though
  "templates ship as data, not as a class concept" (a stated principle in
  `AGENTS.md`) is worth keeping as a design constraint.
- **Combat HUD (`rules/ui/`)** — built around cooldown timers, ability
  icons, skillshot indicators. Not applicable to a turn/action-step UI.

---

## 3. What to Adapt (pending Section 1 audit results)

### 3.1 Authority gate (#277) — highest-leverage item, if it's general
- If the audit confirms #277 landed as a general command taxonomy (not
  hardcoded verbs): study its registration contract and build hex-skirmish's
  own authority gate the same way — register `Move`, `Attack`, `Charge`,
  `Guard`, `Focus`, and Power Step instant-card plays as verbs, each
  validated server-side before resolution. Don't import the MOBA's actual
  verb implementations; adapt the *registration mechanism*.
- If #277 is still hardcoded or unmerged: don't wait on it. Build
  hex-skirmish's authority gate using the same principle (generic verb
  registration, not hardcoded action types) so hex-skirmish doesn't repeat
  the mistake the MOBA repo is trying to avoid.

### 3.2 Session layer / lobby (#278)
- If host/join and single-player-vs-bots-as-a-session-mode are working:
  study the session state machine (connecting → lobby → in-game) and the
  single-player/LAN/dedicated-server mode handling — this is close to
  exactly what hex-skirmish needs, since it has the same three deployment
  targets.
- Team/player assignment will need genuine changes either way: the MOBA
  model is almost certainly built around fixed teams of individual players.
  Hex-skirmish needs N-players-split-M-teams (spec brief: either one player
  per team, or e.g. 5 players sharing one team) — extend rather than assume
  parity.

### 3.3 Rules module discipline
- Adapt the *pattern*, not the code: a `rules/` (or similarly named) module
  in the new repo with a one-way dependency from game code, and an
  equivalent to `extraction_contract_test.gd` enforcing it. This is what
  makes deterministic client/server simulation tractable for a turn-based
  resolver, the same way it does for the MOBA's real-time one.

### 3.4 Actor/Controller/Action/ActionResult composition pattern
- Worth reading closely, not copying: entities that need combat capability
  without a controller or body (the tower-defense stationary-attacker case)
  suggests hex-skirmish's `Fighter` could similarly decouple "has stats and
  can take actions" from "has a controller/is player-driven" — potentially
  useful if you ever want AI-controlled or objective-token-holding entities
  that participate in combat resolution without being a full player unit.

### 3.5 Dev/agent workflow
- `docs/AGENT_WORKFLOW.md` (role definitions, model routing for
  planning/implementation/review across separate sessions) and the
  `AGENTS.md` working rules (read full issue, smallest change necessary,
  don't refactor unrelated code, validate before declaring done) are
  process, not code — copy directly and adapt file paths. This is
  genuinely portable regardless of what happens with the game code.

---

## 4. Suggested New Repo Structure

```
gladiator-engine/
  docs/
    hex-skirmish-game-spec.md          # mechanics; engine-agnostic
    moba-to-hex-skirmish-extraction-plan.md
    godot-implementation-guide.md      # Godot 4 / GDScript specifics
  rules/                 # new module, one-way-dependency pattern adapted from 3.3
    tests/
      extraction_contract_test.gd   # adapted, not copied
  net/                    # authority gate (3.1) + session layer (3.2), adapted
  board/                  # hex grid, LOS, distance — new (spec §2)
  combat/                 # dice-pool resolution, flanking — new (spec §7-8)
  fighters/               # roster/stats/weapons — new (spec §3), informed by 3.4
  cards/                  # scoring/ability decks — new (spec §4-10)
  ui/                     # lobby (informed by 3.2), in-game — new
  AUDIT_NOTES.md
  EXTRACTION_LOG.md
```

---

## 5. MVP Scope and Build Discipline

**The discipline this section enforces: build the smallest slice that proves
the rules engine works and can run authoritatively — not the smallest slice
that looks like a finished game.** Do not build LAN, dedicated server,
lobby, or N-players-per-team support until the items below are done and
proven. Each of those is a transport/scope change on top of a working core,
not a parallel track to build alongside it.

### 5.1 Slice 0 — the smallest proof (build this first)

5.2 is the right first *milestone*, but it is not the smallest *slice*: a full
three-round match with cards, scoring, and victory conditions is a lot of
surface to build before anything is proven. Build this first, ideally in one
sitting:

- A hex board with blocked hexes, cube-coordinate distance, and line of sight
  (spec §2).
- Two fighters, one weapon each.
- Exactly one action — **Attack** — routed through the authority object (5.2)
  and returning a `TurnResult`.
- Unit tests that deal a known board state and a known seed, resolve the
  attack, and assert the outcome matches what the tabletop rules produce when
  worked by hand. Include at least one flanked case and one surrounded case
  (spec §8).

When those tests pass, the dice-pool resolver — the thing spec §12 calls the
core loop worth getting right first — is proven, and everything in 5.2 becomes
additive rather than exploratory.

### 5.2 In scope for MVP

- **Rules module as pure simulation.** Takes a `TurnAction`, returns a
  `TurnResult`. No UI or network code inside it. This is what gets unit
  tested against the tabletop spec by hand: deal a known board state, feed
  it a known action, confirm the result matches what the tabletop rules
  produce.
- **Determinism, dice included.** Spec §7 combat is a dice pool, so "pure
  simulation" is only true if the randomness is an explicit input. The rules
  module must never touch a global RNG; it takes its randomness from state it
  was handed, and the seed *and* generator state are part of the game state.
  The same starting state plus the same action sequence must reproduce the
  same match, in a fresh process, every time. Get this wrong on day one and
  replays, save/load, deterministic tests, and network sync all break
  together later — this is the correction worth making before any combat code
  exists. See `godot-implementation-guide.md` §5.
- **Fully serializable game state.** Board, fighters, hands, decks, discard
  piles, scored piles, scores, round/turn counters, and the RNG seed and
  state. This mostly falls out of a pure rules core, but state it as a
  requirement: it is what makes save/load, replays, and (later) handing a
  state snapshot to a joining client possible at all.
- **Balance values in data, not in the resolver.** Dice counts, damage
  values, health, saves, point values, card effects. The mechanics are
  inherited from a settled tabletop game, but the numbers will still be
  tuned — and tuning must not mean editing combat code. See
  `godot-implementation-guide.md` §3.
- **A single authority object that every action goes through, even in
  hotseat.** This is the one architectural decision worth getting right on
  day one. Local two-player hotseat with no network at all — but the UI
  never calls the rules module directly; it always goes through an
  in-process "authority" object that validates and resolves. If hotseat
  bypasses this and calls the rules engine directly, LAN and dedicated
  server both require rebuilding the calling convention later. If
  everything routes through the same authority object from the start, LAN
  is a transport swap — moving *where* that object lives — not a rules
  change. Networking undersells this, though: the same chokepoint is also
  what gives you replays, undo, save/load, and headless AI search (run the
  resolver thousands of times to evaluate candidate moves). Those pay off
  even if this never ships multiplayer.
- **One hardcoded team/session shape:** 2 teams, 1 controlling player each,
  fixed roster size (per the spec's 3–5 fighters). This validates the core
  loop without solving N-players-per-team yet.
- **A full 3-round match, playable start to finish**, using the spec's
  actual rules: board, core actions (Section 6), combat resolution
  (Section 7), flanking (Section 8), status/defeat (Section 9), end-of-round
  scoring (Section 10), victory determination (Section 11).

### 5.3 Explicitly deferred (not MVP, do not build yet)

- **LAN transport** (ENet host/join). Bolt on once the authority-object
  pattern is proven in hotseat — if 5.2 is done right, this should be close
  to a drop-in swap of where the authority object runs, not a rewrite.
- **Dedicated server as a headless build.** Mechanically the same authority
  object with no local client attached. Cheap once the pattern's proven,
  premature before.
- **N-players-split-M-teams, lobby UI, matchmaking, reconnection handling.**
  All real work; none of it blocks validating whether the core loop is fun.
- **The generalized authority-gate/verb-registration pattern** referenced in
  Section 3.1. Worth adopting once there are more verbs than the MVP's five
  core actions justify designing a registration system for. Premature here.
- **Anything from Section 2** (real-time combat, Discipline/loadout system,
  cooldown HUD) — already ruled out, restated here so it isn't accidentally
  reconsidered "for the MVP."

### 5.4 MVP "done" test

You can play a full 3-round hotseat match end to end; the rules module has
unit tests mirroring the tabletop spec's combat resolution math; the authority
object is the *only* thing that ever calls into the rules module; and
replaying a recorded action sequence against its recorded seed reproduces the
identical final state. At that point, adding networking is a transport change, not a rules change
— which is the whole point of building it this way.

---

## 6. Order of Operations

Revised: the audit moved to the end, and the generalized verb-registration
gate moved with it. The original ordering put Section 3.1 third while 5.3
listed it as explicitly deferred — a contradiction resolved here in favour of
5.3.

1. Section 3.5 (workflow docs) — zero-risk, do first, sets up how the rest of
   this plan gets executed.
2. Section 3.3 (rules module discipline) plus the determinism and
   serialization requirements in 5.2 — establishes the architecture
   everything else is built against, and the contract test that keeps it
   honest.
3. Section 5.1 (Slice 0) — board, one Attack, resolved through the single
   authority object, with tests mirroring the tabletop math by hand. Nothing
   below this line starts until those tests pass.
4. The rest of 5.2's MVP, following the spec's own build order (§12):
   remaining core actions → status effects → card system → scoring/end
   phase → win conditions. Reference Section 3.4's composition pattern when
   designing the `Fighter` data model.
5. Section 1 audit — here, not earlier, and time-boxed. Confirm the real
   status of #277/#278 when you are actually about to need networking.
6. Section 3.2 (session layer) — adapt lobby/session flow; extend for
   N-players-split-M-teams.
7. Section 3.1 (generalized authority gate / verb registration) — only once
   there are enough verbs to justify a registration system, per 5.3.

---

## 7. Acceptance Criteria

MVP criteria first; the rest apply only once the corresponding deferred work
in 5.3 is actually being built.

**MVP (Section 5.1–5.2):**

- **Determinism:** replaying a recorded action sequence against its recorded
  seed reproduces the identical final state, in a fresh process.
- **Serialization:** a match can be saved mid-round, reloaded, and continue
  with behaviour identical to the unsaved run.
- **Data-driven balance:** changing a weapon's dice count or a fighter's
  health is an edit to a data file, not to a script.
- **Single chokepoint:** no code path outside the authority object calls into
  `rules/`, and a test asserts it.

**Post-MVP:**

- **Authority gate:** a new verb can be registered and server-validated
  without modifying the gate itself (mirrors #277's stated design goal).
- **Rules module:** an equivalent extraction-contract test fails the build
  if game code creates a dependency from `rules/` back into game-specific
  code.
- **Session layer:** single-player, LAN, and dedicated-server all drive the
  same session state machine with different transport configs, and support
  N-players-split-M-teams.
- **Fighter model:** supports both "1 fighter roster per player" and "one
  team's roster split across multiple players" without schema changes.

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
  (2026-08-30) reversed the earlier "portable engine other games can host"
  goal after roughly two-thirds of that layer proved unreachable; the code
  removal followed across #285–#289 (PRs #291/#295/#298/#299). *Verified
  2026-09-04: `addons/` survives on disk as an empty husk with zero tracked
  files. Nothing to resurrect.* Treat issue numbers in this plan as unreliable
  citations generally — describe the mechanism, not the issue. `AGENTS.md`: *"Do not add third-party dependencies or
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

## 1. Pre-Flight Audit — **DONE 2026-09-04**

> **Completed early, and it was worth it.** This was re-sequenced to run late
> (build first, audit when networking arrives). It then ran immediately anyway,
> because the source repo became available and a bounded pass was cheap. That
> was the right call: the audit found the repo ~130 PRs past this plan's
> premises, and two findings that change what gets built (see 3.1 and 3.5).
>
> **Findings are in `AUDIT_NOTES.md`; decisions are in `EXTRACTION_LOG.md`.**
> Audited at `ef29ad3`, Godot 4.7. The questions below are answered there —
> kept here for the record, not as outstanding work. What remains unaudited is
> listed under *Deferred* in `AUDIT_NOTES.md`, and none of it blocks Slice 0.

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

## 3. What to Adapt (audit complete — see `AUDIT_NOTES.md`)

### 3.1 Authority gate (#277) — **resolved: adapt, and it is tiny**

> **Revised 2026-09-04.** This section previously asked whether #277 was "a
> general verb-registration system or still hardcoded," and planned to "adapt
> the *registration mechanism*." That was a false dichotomy. There is no
> registry, and there should not be one.

The entire mechanism in the source repo is ~40 lines across four files:
`Action` (a base class holding an actor and declaring `execute() -> ActionResult`),
`ActionResult` (`success`, `reason`), `Authority.can_perform(action, requester_id)`
(one ownership check), and `ActionRunner.run(action, requester_id)` (gate, then
execute). Generality comes from subclassing, not registration —
`command_taxonomy_contract_test.gd` asserts exactly that: a new command is one
new `Action` subclass, requiring no edit to `ActionRunner` or `Authority`.

- Build the same shape here: a `TurnAction` base with `resolve()`, a
  `TurnResult`, an authority check, a runner. It is small enough to belong to
  Slice 0 rather than a later phase.
- The predicate changes. The source checks peer ownership (`owner_id == 0`, or
  requester is the owning peer). Ours must also gate on turn order — "is it
  this player's turn, and is this their fighter" — which the real-time original
  has no equivalent of.
- **Do not import the MOBA's `Action` subclasses.** The base contract is the
  portable part; every concrete verb in that repo is real-time combat.

### 3.2 Session layer / lobby (#278) — **confirmed working; adapt when networking starts**

> **Revised 2026-09-04.** This section expected "a session state machine
> (connecting → lobby → in-game)." There isn't one, and the thing that exists
> instead is more useful — see below.

- Host/join and single-player-vs-bots are working and genuinely first-class:
  `session_manager.gd` is an autoload with an `OFFLINE`/`LISTEN_SERVER`/
  `DEDICATED_SERVER` mode enum over ENet, with the dedicated path reachable at
  boot from a CLI flag or environment variable. Close to exactly what we need,
  and the same three deployment targets.
- Not a state machine: a mode enum plus scene transitions driven by a
  *replicated property whose setter emits a change signal*
  (`LobbyManager.match_starting`), chosen over a one-shot RPC so late-joining
  peers read state rather than miss an event. That idiom is the portable idea
  here; adapt it rather than the state machine we went looking for.
- `LISTEN_SERVER` makes the host's own machine the authority. That is right
  for LAN and casual play and unusable for a match whose result is meant to
  count, since the host is running the binary that decides it. The mode stays;
  what changes is which mode a ranked match is allowed to use. See §5.5.
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

### 3.5 Dev/agent workflow — **DONE 2026-09-04**

> **Revised 2026-09-04.** This section said these docs were "process, not code
> — copy directly and adapt file paths." That holds for `AGENTS.md`. It does
> not hold for `docs/AGENT_WORKFLOW.md`, which is 1,976 lines of GitHub Actions
> control plane: label taxonomy (and label *colors*), model routing and pricing
> tables, four workflow entry points, dependency automation driven by a
> `blocker` label. This repo has no issues, no labels, no Actions, and one
> contributor. Copying it would import an organisation, not a practice.

- **Done:** `AGENTS.md` and `CLAUDE.md` written at this repo's root, adapting
  the source's *Working Rules*, *Testing*, and *Completion* sections and its
  "one source of truth, this file is a pointer" structure.
- **Taken from `AGENT_WORKFLOW.md`:** one principle — planning, implementation,
  and review work better as separate sessions. Revisit the rest if this repo
  ever grows an issue tracker and a second contributor.
- **Taken as a practice:** when a document is revised because it was *wrong*,
  it says so, dated, with what it previously claimed. The callouts in this
  section and in 3.1, 3.2, and Section 1 are that practice applied to this
  plan.

---

## 4. Repo Structure — **BUILT 2026-09-04**

> **Revised 2026-09-04.** This section previously listed `board/`, `combat/`,
> `fighters/`, `cards/`, `net/` and `ui/` as *siblings* of `rules/`. That
> would have emptied the rules module of everything it exists to hold: the hex
> board, the dice resolver, the fighter model and the card system **are** the
> rules. With them outside, `rules/` contains only its own contract test and
> the one-way dependency arrow guards nothing. They are nested under `rules/`
> below, matching how the source repo organises its own module.

```
gladiator-engine/
  project.godot           # Godot 4.7; TestBootstrap autoload
  AGENTS.md               # working rules (3.5)
  CLAUDE.md               # pointer to AGENTS.md
  AUDIT_NOTES.md          # Section 1 findings
  EXTRACTION_LOG.md       # every extract/adapt/rebuild/reject decision
  docs/
    hex-skirmish-game-spec.md            # mechanics; engine-agnostic
    moba-to-hex-skirmish-extraction-plan.md
    godot-implementation-guide.md        # Godot 4 / GDScript specifics
  rules/                  # pure simulation; no scene tree, no ambient RNG
    README.md
    board/                # hex coords, distance, LOS, occupancy (spec §2)
    combat/               # dice-pool resolution, flanking (spec §7-8)
    fighters/             # runtime fighter/weapon model (spec §3, §9)
    cards/                # scoring/ability decks (spec §4, §10)
    state/                # GameState, TurnAction, TurnResult, RNG (spec §3)
    tests/
      extraction_contract_test.gd   # adapted from source, string-literal bug fixed
      contract_scanner_test.gd      # proves the scanner can actually fail
  scripts/                # game side: Authority, runner, session (3.1, 3.2)
  scenes/                 # views; main.tscn placeholder for now
  resources/              # .tres templates: fighters, weapons, cards
  tests/
    test_bootstrap.gd     # headless suite runner; result becomes exit code
  .github/
    scripts/validate-godot.sh   # the one way to run validation
    workflows/                  # CI + agent control plane
    actions/                    # setup-godot, lint-gdscript, agent plumbing
  .gdlintrc
```

**Boundary rule.** `rules/` may not reference `res://scripts/`,
`res://scenes/` or `res://resources/` — enforced on every build. It also does
not use game-side types by global `class_name`, which is a hole the source
repo leaves open (its contract test checks paths only, and its `rules/`
depends on `Action`/`ActionResult` from `scripts/`). `TurnAction` and
`TurnResult` therefore live in `rules/state/`, since they are the resolver's
own signature; `Authority` stays in `scripts/`, since "who may act right now"
is a turn-order and session question the rules have no opinion about. See
`rules/README.md`.

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
- **Per-recipient state projection.** The `PlayerView` filter that keeps one
  player's hand, deck order, and unrevealed feature tokens out of what the
  other player's client receives (§5.5, guide §9.2). Deferred as *code*, not as
  a *constraint*: serialization built in the MVP should not make it harder, and
  spec §3's visibility rule is what it filters against.
- **Ruleset identity handshake.** Client sends a hash of its rules code at
  connect; server refuses a mismatch with "update required" instead of playing
  a match the two ends disagree about (guide §9.3).
- **Server-supplied balance data.** Serving `.tres` values from the authority
  so a balance change does not require a client release (§5.5).
- **N-players-split-M-teams, lobby UI, matchmaking, reconnection handling.**
  All real work; none of it blocks validating whether the core loop is fun.
- ~~**The generalized authority-gate/verb-registration pattern** referenced in
  Section 3.1.~~ **Struck 2026-09-04.** There is nothing to defer: the audit
  found generality comes from subclassing, not a registry, and costs the same
  as the hardcoded form. Building hardcoded-first and generalising later would
  be strictly more work. Now part of Slice 0 — see the revised 3.1.
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

### 5.5 Deployment posture — operator-run authority

> **New 2026-09-05.** This plan described three deployment targets (§3.2:
> single-player, LAN, dedicated server) without ever saying which of them is
> allowed to be authoritative, because nothing required an answer. A stated
> goal now does: **ship only a client to players, and run centrally every
> server whose results are meant to count** — what a league needs, where every
> match must have been resolved by the same ruleset. Recorded here because the
> answer changes decisions in §5.3, §7, and guide §5, and those decisions are
> free now and expensive after there is networking code to revise.

None of this is MVP work and none of it changes §5.1. It is written down so
the deferred networking work is shaped correctly when it arrives.

**It is possible, and the two commitments in `AGENTS.md` are what make it so.**
Client and dedicated server are two export presets over one project (guide
§9.1), and "every action goes through one authority object" means a league
build is that object living on an operator-run server rather than in the
player's process. The client still contains `rules/`; it just stops being the
copy that decides.

Four constraints follow, and they are the whole of it:

1. **The server's `rules/` is the only copy whose output counts.** The
   client's copy is advisory — legal-move highlighting, animation, preview.
   A client must never commit its own locally resolved result as state.
2. **The server rolls, and the seed never leaves it.** A client that knows the
   seed and generator position knows the dice that have not happened yet. See
   guide §5, revised for this reason.
3. **What crosses the wire is a per-player view.** `GameState` holds both
   players' hands and every face-down token (spec §3), so sending it whole
   leaks the opponent's hand to anyone willing to read the packets. Guide §9.2.
4. **Ranked play requires an operator-run authority.** `LISTEN_SERVER` is for
   offline, LAN, and development. Enforce this at the league level — ranked
   matches are played against servers the operator runs, and results are
   reported by that server rather than by either client — not by trying to
   strip host code out of the client export, which buys nothing.

**One lever worth noticing.** §5.2 already requires balance values in data
rather than in the resolver. If the authority *serves* those values at match
start and the client uses what it is handed rather than its local `.tres`,
then dice counts, damage, health and point costs become server-side config: a
balance patch reaches an entire league without a client release. Resolver
*logic* changes still need a new client build, which is what the §9.3
handshake's version gate is for — refusing an out-of-date client is a clear
failure, and a silent disagreement about the rules is not.

**What this is not.** None of the above makes the client tamper-proof, and it
is not trying to. A modified client can lie about what it wants to do; it
cannot make the server agree, and that is the property a league actually
needs.

---

## 6. Order of Operations

Revised: the audit moved to the end, and the generalized verb-registration
gate moved with it. The original ordering put Section 3.1 third while 5.3
listed it as explicitly deferred — a contradiction resolved here in favour of
5.3.

1. ~~Section 3.5 (workflow docs)~~ — **done 2026-09-04.** `AGENTS.md` and
   `CLAUDE.md` written; `AGENT_WORKFLOW.md` rejected with reasons.
2. Section 3.3 (rules module discipline) plus the determinism and
   serialization requirements in 5.2 — establishes the architecture
   everything else is built against, and the contract test that keeps it
   honest.
3. Section 5.1 (Slice 0) — board, one Attack, resolved through the single
   authority object, with tests mirroring the tabletop math by hand. Now also
   carries the `TurnAction`/`TurnResult`/authority/runner shape from the
   revised 3.1, which is small enough to belong here. **This is the next work.**
   Nothing below this line starts until those tests pass.
4. The rest of 5.2's MVP, following the spec's own build order (§12):
   remaining core actions → status effects → card system → scoring/end
   phase → win conditions. Reference Section 3.4's composition pattern when
   designing the `Fighter` data model.
5. ~~Section 1 audit~~ — **done 2026-09-04**, ahead of schedule and worth it.
   See `AUDIT_NOTES.md`. What remains unaudited (lobby team assignment, the
   `GAME_MODES.md` composition pattern, `sim/`) is listed there and blocks
   nothing before networking.
6. Section 3.2 (session layer) — adapt the mode enum and the replicated-
   property idiom; extend for N-players-split-M-teams. Audit `lobby_manager.gd`
   properly at this point, not before.
7. ~~Section 3.1 (verb registration)~~ — **struck**; folded into step 3.

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

**Post-MVP, operator-run authority (§5.5) — apply only if that posture is
being built:**

- **Information containment:** no payload a client receives contains another
  player's hand, undrawn deck order, or an unrevealed feature token. Asserted
  against the serialized bytes, not against the sending code.
- **Rules identity:** a client whose rules-code hash does not match the
  server's is refused at connect with a stated reason, rather than admitted
  and allowed to diverge.
- **Balance without a release:** changing a weapon's dice count for a running
  league is a server-side data change, with no client build shipped.
- **Authority location:** a ranked match is resolved by an operator-run
  server; `LISTEN_SERVER` cannot produce a result that counts.

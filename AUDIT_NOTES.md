# Audit Notes — `mikeys_game_bones-rules-moba`

Required output of extraction plan §1.

**Source repo:** `/Users/mike/Documents/GitHub/mikeys_game_bones-rules-moba`
**Audited at:** `ef29ad3` (main, 2026-09-04) — Godot 4.7
**Audited on:** 2026-09-04

Read: `AGENTS.md`, `CLAUDE.md`, `rules/README.md`, `docs/AGENT_WORKFLOW.md`
(headings), `rules/tests/extraction_contract_test.gd`,
`rules/tests/command_taxonomy_contract_test.gd`, `scripts/authority.gd`,
`scripts/action_runner.gd`, `scripts/action.gd`, `scripts/action_result.gd`,
`scripts/controller.gd`, `scripts/session_manager.gd`,
`scripts/lobby_manager.gd` (partial), plus `git log` and directory structure.

---

## Headline

**The plan's premises are directionally right and factually stale.** The source
repo has moved roughly 130 PRs past the point the plan was written against
(latest merge is #407; the plan reasons about #276–#280). The architectural
conclusions still hold. Several specifics do not, and two of them change what
gets built here.

The two findings that change the build:

1. **The authority-gate question was a false dichotomy, and the answer is
   better than either option.** Extraction plan §3.1 asks whether #277 is a
   general verb-registration system or hardcoded verbs. It is neither. The
   whole mechanism is ~30 lines of polymorphism with no registry at all, and
   it is *already* general. See Q1.
2. **§3.5's "copy directly" does not survive contact with the file.**
   `docs/AGENT_WORKFLOW.md` is 1,976 lines, and the overwhelming majority of
   it describes a GitHub Actions control plane this repo does not have. See
   Q5.

---

## Q1 — #277 authority gate: usable as-is, adaptable, or from scratch?

**Verdict: adapt, and it is drastically smaller than the plan assumed.**

The entire mechanism is four files totalling about 40 lines:

| File | Lines | What it does |
| --- | --- | --- |
| `scripts/action.gd` | 13 | Base `Action`: holds an `actor`, declares `execute() -> ActionResult` |
| `scripts/action_result.gd` | 10 | `success: bool`, `reason: StringName` |
| `scripts/authority.gd` | 9 | `Authority.can_perform(action, requester_id) -> bool` — one ownership check |
| `scripts/action_runner.gd` | 8 | `ActionRunner.run(action, requester_id)` — gate, then `execute()` |

`Authority.can_perform()` in full is a single expression: the actor is unowned
(`owner_id == 0`, AI/server-local) or the requester is the actor's owning peer.
That is the entire authority model.

**There is no verb registry, and the design is explicit that there should not
be one.** `rules/tests/command_taxonomy_contract_test.gd` states the invariant
directly: *"a new player-originated command is one `Action` subclass … and
requires no edit to `ActionRunner` or `Authority`."* The test proves it by
defining a throwaway `Action` subclass inside the test file and running it
through `ActionRunner` twice — once with a matching `requester_id` (expect
success), once mismatched (expect denial) — with no change to either
production file.

Generality here comes from subclassing, not registration. Open/closed for free.

**Consequences for our plan:**

- §3.1's "study its registration contract" is moot — there is no registration
  contract to study. The adaptation is: `TurnAction` base class with
  `resolve()`, a `TurnResult`, an authority check, and a runner. Small enough
  to write in Slice 0.
- §5.3 defers "the generalized authority-gate/verb-registration pattern" as
  premature, and §6 step 7 schedules it last. **Both should be struck.** There
  is nothing to defer: the general form costs the same as the hardcoded form.
  Building a hardcoded version first and generalising later would be strictly
  more work.
- The ownership check itself does not transfer as-is. It is peer-ownership for
  a real-time game; ours needs "is it this player's turn, and do they own this
  fighter" — turn order is a gating condition the MOBA has no equivalent of.
  Same shape, different predicate.

---

## Q2 — #278 session layer: usable as-is, adaptable, or from scratch?

**Verdict: adapt. Working, and close to what we need — but not the shape the
plan guessed.**

`scripts/session_manager.gd` (112 lines, an autoload) is real and complete:

- `Mode` enum: `OFFLINE`, `LISTEN_SERVER`, `DEDICATED_SERVER`.
- `host(port, dedicated)` / `join(address, port)` / `go_offline()` over
  `ENetMultiplayerPeer`.
- Dedicated server reachable at boot from `--dedicated-server` or
  `MIKEYS_DEDICATED_SERVER=true`, because a dedicated server has no operator to
  click a menu.
- Single-player-vs-bots is genuinely a first-class mode, confirming what
  `AGENTS.md` claims. `go_offline()` restores an `OfflineMultiplayerPeer`
  rather than assigning `null`, specifically because `MultiplayerSpawner.spawn()`
  refuses to run with no peer and offline would otherwise produce neither
  player nor bots.

**Correction to §3.2:** the plan expects "a session state machine (connecting →
lobby → in-game)". There is no state machine. There is a mode enum plus scene
transitions driven by `LobbyManager.match_starting`, a replicated property
whose setter emits a change signal (chosen over a one-shot RPC so late-joining
peers have state to read rather than a missed event). That property-plus-signal
idiom is the genuinely portable idea here, and it is worth more to us than the
state machine we went looking for.

Two useful details for later: `LobbyManager` keys avatars by
`peer_id -> Actor` in a `Dictionary[int, Actor]`, and session mode is
deliberately allowed to decide exactly one thing (whether `WorldManager` spawns
a local player). That restraint is worth copying.

**Not yet answered:** whether team/player assignment is fixed-teams-of-
individuals, and therefore how much work N-players-split-M-teams really is.
`lobby_manager.gd` is 397 lines and I read the first 60. Deferred — it does not
block anything before networking.

---

## Q3 — #280 character system: confirmed out of scope?

**Verdict: confirmed. Rule out, as §2 already concluded.**

`AGENTS.md` states the decision directly (dated 2026-08-31): one primary and
one secondary Discipline, four action abilities drawn from those two, a
respecable stat pool, free weapon choice, fully editable between matches, and
*"Do not reopen these in an implementation session."* `MobaAbility.Discipline`
enumerates six disciplines. This is a persistent, player-owned, cross-match
character built around loadout theorycrafting as the retention loop.

Our spec is a fixed roster of 3–5 fighters with per-fighter stats and weapons.
Different data model, different purpose. No change to §2.

The one principle worth keeping, which `AGENTS.md` states as a constraint:
**"Templates ship as data, not as a class concept."** Already reflected in our
plan §5.2 and `godot-implementation-guide.md` §3.

---

## Q4 — the rules-module contract test (§3.3)

**Verdict: adapt, closely. The best single artefact in the source repo for our
purposes.**

`rules/tests/extraction_contract_test.gd` (129 lines) is a static source
scanner: walk `res://rules/` recursively, and fail if any `.gd`, `.json`, or
`.tres` file references `res://scripts/`, `res://scenes/`, or
`res://resources/`. Exactly the lint-style enforcement predicted in
`docs/godot-implementation-guide.md` §2 — GDScript's global `class_name`
namespace means nothing structural can enforce this.

Two design details worth copying verbatim in spirit:

- **`EXEMPT_FILES` holds full paths, not filenames**, with the rationale in a
  comment: a suffix match would exempt any future file anywhere under `rules/`
  that happened to share the name, "a standing invitation to park a real
  violation in a file named after a contract test."
- The exemption exists because a contract test necessarily *names* the
  forbidden prefixes as scan-target data. The comment draws the right
  distinction: a path in a scanner's string list is opened with `DirAccess`,
  not called as a type, so the module still runs standalone.

**Known weakness to fix rather than inherit:** comment stripping is naive —
it takes `line.split("#")[0]`, which corrupts any line with `#` inside a string
literal. The file admits this ("a full solution would parse strings"). Ours
should at minimum not split inside quotes.

Also worth noting: the source repo's `rules/` has accumulated four orphaned
`.uid` files from deleted violation-test scratch files (`test_viol.gd.uid`,
`violation_test.gd.uid`, and two more). Minor, but a reminder that `.uid` files
outlive their scripts if deleted carelessly — see guide §8.

---

## Q5 — the workflow docs (§3.5)

**Verdict: partially portable. The plan's "copy directly and adapt file paths"
does not hold.**

- **`AGENTS.md` (118 lines) — adapt, high value.** Its *Working Rules*,
  *Testing*, and *Completion* sections are almost entirely project-agnostic
  and directly useful. Its *Project* and *Architecture* sections are
  MOBA-specific. Note it carries a dated "Revised 2026-08-30" callout
  explaining what a previous version got wrong and why — a habit worth
  stealing outright.
- **`CLAUDE.md` (100 lines) — adapt the idea, not the content.** Its whole
  premise is "one source of truth; this is a pointer to it," including a table
  of path-scoped instructions that Copilot picks up via `applyTo:` frontmatter
  but Claude Code does not. Good pattern; the specific pointers are all to
  files we do not have.
- **`docs/AGENT_WORKFLOW.md` (1,976 lines) — do NOT copy.** Perhaps 30 lines
  are portable: the principle that planning, implementation, and review run as
  separate sessions on different models, and that a PR which keeps coming back
  justifies a better model. The rest is a GitHub Actions control plane — label
  taxonomy and label *colors*, four workflow entry points, model routing
  tables, per-1M-token pricing, cloud-agent tier availability, a dependency
  chain driven by a `blocker` label and `issue_dependencies.py`, `/execute-task`
  and `/feature-status` slash commands. `gladiator-engine` has no issues, no
  labels, no Actions, and one contributor. Copying this would be importing an
  organisation, not a practice.

The dependency-declaration machinery (`AGENTS.md` *Issue Dependencies*,
`CLAUDE.md`'s section on it) is in the same category: real, well-built,
irrelevant until there are issues to order.

---

## Corrections to the extraction plan's stated premises

| Plan says | Actually |
| --- | --- |
| "Issue #276 (2026-08-30) deleted `addons/`" | The deletion happened across #285/#286/#288/#289 (PRs #291/#295/#298/#299). #276 is cited in `AGENTS.md` as the *decision* to stop being a framework; the code removal is separate work. Substance holds. |
| implied: `addons/` is gone | The directory still exists on disk with **0 tracked files** — an empty husk holding a stray `.DS_Store`. Nothing to resurrect; nothing to worry about. |
| `#277`, `#278`, `#280` as live open questions | All three are settled and merged. The repo is ~130 PRs past them. |
| §3.4: `Actor`/`Controller`/`Action`/`ActionResult` as the shared contract | Confirmed accurate, and `AGENTS.md` explicitly freezes these five types: "Do not change the shared types … unless the Issue explicitly requires it." |
| §2: MOBA repo has no navigation system | Not re-verified this pass; irrelevant either way, since hex movement is new work regardless. |

**Practical lesson:** issue numbers in the plan are unreliable as citations.
Prefer describing the mechanism over citing the issue that produced it.

---

## Deferred, with reasons

- **`lobby_manager.gd` beyond line 60** — team/player assignment shape, and
  therefore the true cost of N-players-split-M-teams. Nothing before
  networking depends on it.
- **`docs/GAME_MODES.md` composition pattern (§3.4)** — the "combat as a
  component on an entity with no `Controller` and no body" idea. Worth reading
  when the `Fighter` data model is designed, not before.
- **`.github/instructions/rules.instructions.md`** — the path-scoped rules
  contract. Read when writing our own contract test, if the 129-line test
  above leaves anything unclear.
- **`sim/`, the Python balance harness** — not examined. Potentially
  interesting much later for balance tuning; no bearing on the MVP.

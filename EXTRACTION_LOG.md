# Extraction Log

Required by extraction plan §0: every decision (extract / adapt / rebuild)
gets a one-line rationale. Newest entries at the bottom.

**Source repo:** `mikeys_game_bones-rules-moba` @ `ef29ad3` (2026-09-04),
Godot 4.7. Findings behind these decisions are in `AUDIT_NOTES.md`.

Verdicts: **extract** = copied near-verbatim · **adapt** = rewritten here from
a source contract · **rebuild** = new work, source not usable · **reject** =
deliberately not brought over.

---

## 2026-09-04 — Audit pass

| # | Item | Verdict | Rationale |
| --- | --- | --- | --- |
| 1 | `addons/` framework layer | reject | Source repo deleted it (#285–#289) after ~2/3 proved unreachable; plan §0 forbids resurrecting it. Confirmed empty: 0 tracked files. |
| 2 | `rules/tests/extraction_contract_test.gd` | adapt | Static source scanner enforcing the one-way dependency arrow. Directly applicable; GDScript can't enforce this structurally. Fixing its naive `#`-comment stripping rather than inheriting it. |
| 3 | `Action` / `ActionResult` / `Authority` / `ActionRunner` | adapt | ~40 lines total. The single-chokepoint pattern our plan §5.2 calls the day-one decision, already proven in the source. Predicate changes (peer ownership → turn ownership); shape does not. |
| 4 | Command taxonomy (#277) | adapt | Not a verb registry — generality comes from `Action` subclassing, proven by `command_taxonomy_contract_test.gd`. Nothing to register, so nothing to defer. Supersedes plan §3.1's either/or framing. |
| 5 | Session layer (#278) | adapt (deferred) | Working `OFFLINE`/`LISTEN_SERVER`/`DEDICATED_SERVER` enum over ENet, single-player-vs-bots first-class. Not the state machine §3.2 predicted. Revisit when networking starts. |
| 6 | Replicated-property-plus-signal idiom (`LobbyManager.match_starting`) | adapt (deferred) | Chosen over one-shot RPC so late joiners read state instead of missing an event. More portable than the state machine we went looking for. Networking-time. |
| 7 | Combat resolution (`MobaDamage`, `MobaFormulas`, cooldowns, projectiles, CC, state machine) | reject | Real-time, tick/cooldown-driven, skillshot targeting. Our spec §7 is discrete dice-pool + symbol matching. Different resolution model, confirmed by inspection. |
| 8 | Movement / pathing | rebuild | Source has no navigation system; hex movement is new work regardless. |
| 9 | Character/Discipline system (#280) | reject | Confirmed Discipline-specific and frozen by source `AGENTS.md` (2026-08-31). Persistent cross-match loadout character vs. our fixed 3–5 fighter roster: different data model. |
| 10 | "Templates ship as data, not as a class concept" | extract (principle) | Stated constraint in source `AGENTS.md`; already reflected in our plan §5.2 and guide §3. |
| 11 | Combat HUD (`rules/ui/`) | reject | Cooldown timers, ability icons, skillshot indicators. No analogue in a turn/action-step UI. |
| 12 | `AGENTS.md` | adapt | *Working Rules* / *Testing* / *Completion* are project-agnostic and useful now. *Project* / *Architecture* are MOBA-specific and rewritten. |
| 13 | Dated-revision callout habit (`AGENTS.md` "Revised 2026-08-30") | extract (practice) | Recording what a doc previously said and why it was wrong prevents re-litigating settled decisions. Already used in our plan §1 and §6. |
| 14 | `CLAUDE.md` pointer pattern | adapt | "One source of truth, this is a pointer" is right; every specific pointer in it is to a file we don't have. |
| 15 | `docs/AGENT_WORKFLOW.md` (1,976 lines) | ~~reject (except principle)~~ **→ adapt (see #24)** | Portable content is ~30 lines: planner/implementer/reviewer as separate sessions. The rest is a GitHub Actions control plane — labels, model routing, pricing tables, dependency automation. This repo has no issues, labels, or Actions. Copying it imports an organisation, not a practice. Overrides plan §3.5's "copy directly." |
| 16 | Issue-dependency machinery (`blocker` label, `issue_dependencies.py`) | ~~reject (for now)~~ **→ adapt (see #24)** | Well-built and irrelevant until there are issues to order. |
| 17 | `docs/GAME_MODES.md` composition pattern (§3.4) | deferred | Read when designing the `Fighter` data model, not before. |
| 18 | `sim/` Python balance harness | deferred | Possibly useful for balance tuning much later; no bearing on the MVP. |

## 2026-09-04 — Project scaffold

| # | Item | Verdict | Rationale |
| --- | --- | --- | --- |
| 19 | `tests/test_bootstrap.gd` | adapt | Zero-dependency headless suite runner whose result becomes the exit code, with `call_deferred("_finalize")` queued before any suite so an aborting suite still reports. Source kept the suite list and the run calls as two hand-synced lists, then added drift detection to catch them disagreeing; ours derives both from one `_suites` array, so the drift cannot occur. |
| 20 | `.github/scripts/validate-godot.sh` | adapt | Two passes (`--import`, then `--headless --quit`). Keeps two hard-won details: capture status with `|| status=$?` rather than `if ! cmd` (after a negation `$?` is always 0, so a failing pass exited green), and grep for the "All N test suites passed." line, because exit 0 proves nothing if the bootstrap autoload failed to compile. Added macOS app-bundle resolution — Godot.app installs no CLI symlink. |
| 21 | Repo structure (plan §4) | rebuild | Plan listed `board/`, `combat/`, `fighters/`, `cards/` as siblings of `rules/`, which would leave the rules module holding nothing and the dependency arrow guarding nothing. Nested under `rules/`, matching the source repo's own organisation. §4 revised. |
| 22 | `rules/` boundary: no inbound game types | rebuild | Source's contract test forbids *path* references only, so its `rules/` legitimately depends on `Action`/`ActionResult` from `scripts/` by global `class_name` — its README calls this "limited inbound dependencies." We close it: `TurnAction`/`TurnResult` live in `rules/state/`, `Authority` stays game-side. |
| 23 | Scanner self-test (`contract_scanner_test.gd`) | rebuild | Source has no test of its own scanner; four orphaned `.uid` files in its `rules/` suggest violation fixtures were planted as files and deleted carelessly. Ours tests the pure line-checking function on synthetic input instead — including the `#`-inside-a-string case the source's `split("#")` silently missed. Verified end-to-end: a planted violation fails the build with exit 1. |

## 2026-09-04 — Full control-plane port

**Reverses #15 and #16.** Those entries judged the agent control plane as
importing an organisation rather than a practice, on the grounds that this repo
has no issues, labels, Actions, or second contributor. Owner's decision: bring
all of it, cleaned up. A large amount of engineering went into making these work
and a fresh game project is exactly where that investment pays back. The
judgement in #15/#16 was about cost/benefit at this repo's size, not about
quality; the owner is better placed to weigh it.

| # | Item | Verdict | Rationale |
| --- | --- | --- | --- |
| 24 | Agent control plane — 7 `agent-0*.yml` workflows, 4 composite actions, 4 agent profiles, 5 classifier/scope scripts, `copilot-instructions.md`, `code-review` skill | adapt | Ported whole and cleaned. Project-description, architecture, 3D-scene, input and physics sections rewritten for a 2D turn-based game; the scope, PR-contract, validation and completion machinery kept intact. |
| 25 | `.claude/` local control plane — 4 subagents, 6 slash commands, `settings.json` | adapt | Local counterparts of the cloud agents. Name references cleaned; model pins already current (Opus 5 / Sonnet 5 / Haiku 4.5). |
| 26 | Issue plumbing — `ISSUE_TEMPLATE/*`, `issue-{dependencies,linking}.yml`, `issue_dependencies.py`, `sync-issue-dependencies.py` | adapt | Copied intact; nothing in them was MOBA-specific. |
| 27 | `docs/AGENT_WORKFLOW.md` | adapt | Only 6 repo-specific references in 1,976 lines — far more portable than #15 judged. Ported with a provenance header: its `#NNN` citations point at the source repo's issues and are kept as prior art, not work items. |
| 28 | `CONTRIBUTING.md` | extract | Fully generic squash-merge policy; copied verbatim. |
| 29 | `.gdlintrc` | adapt | Kept the file, dropped the `max-file-lines: 1200` raise. That raise existed for one MOBA class that repeatedly hit the ceiling; a fresh repo starts at gdtoolkit's default of 1000 with no legacy debt. The reasoning ("when a file approaches the limit, split it") is what ported. |
| 30 | `.github/scripts/bootstrap-labels.sh` | **new** | No source equivalent. The source documents that the eight `agent:{role}:{vendor}` labels "must already exist" and have no `ensure_label` guard anywhere — a footnote in a repo that has them, and total inertia in one that does not. Creates all 20 labels idempotently. |
| 31 | `balance-fast.yml`, `balance-deep.yml`, `instructions/sim.instructions.md` | reject | Drive the `sim/` Python balance harness, which was not ported and does not exist here. |
| 32 | `validate-godot.sh` relocation | note | Moved from `tools/` to `.github/scripts/` so every inherited call site resolves unmodified. Its self-relative project-root derivation needed `../..` instead of `..`; getting that wrong does not error, it hangs — Godot pointed at a directory with no `project.godot` waits rather than failing. |

## 2026-09-05 — Deployment posture

Not extraction decisions: new design decisions, recorded here because plan §0
asks for every decision and there is nowhere else that keeps them. They follow
from a stated goal the plan did not previously carry — ship only a client to
players and run every server whose results count, the shape a league needs.
Written up in plan §5.5. **Narrows #5:** the session layer's three modes are
still all adopted, but `LISTEN_SERVER` is now ruled out for ranked play.

| # | Item | Verdict | Rationale |
| --- | --- | --- | --- |
| 33 | Authority-side dice rolling | note | Guide §5 called it "the safe default," weighed only against lockstep's bit-identical evaluation order. Promoted to a rule for a reason it had missed: a client holding the seed and generator position can compute rolls that have not happened yet. An information leak, not a desync risk. |
| 34 | Per-recipient state projection (`PlayerView`) | **new** | No source equivalent — the MOBA has no hidden information to protect. Spec §3 holds both players' hands and every face-down token, so a state snapshot sent to a client leaks the opponent's hand. Deferred as code (plan §5.3); the spec §3 visibility rule it filters against is written now, since it is the part that decides what a leak even is. |
| 35 | Ruleset identity handshake | **new** | "Everyone runs the same rules" is enforced by the server refusing an unrecognised client, not by the client being tamper-proof. A build-time hash over `rules/**/*.gd`, checked at connect. Guide §9.3. |
| 36 | Server-supplied balance data | note | Falls out of plan §5.2's existing "balance values in data, not in the resolver" — if the authority serves the `.tres` values, a balance patch reaches a league without a client release. Recorded because the payoff is invisible from §5.2 alone. |
| 37 | Spec §3 visibility rule | **new** | The spec described `GameState` without saying which parts each player may see, because at one table nobody has to ask. Stated explicitly: hand, undrawn deck order, face-down tokens. Discard and scored piles are treated as public — the tabletop convention, and the one assumption here worth confirming against the physical game. |

## 2026-09-05 — AI opponent scope

| # | Item | Verdict | Rationale |
| --- | --- | --- | --- |
| 38 | AI opponent | deferred (post-MVP feature) | Owner's decision: a feature release, not MVP; two human players is the shape being built. Recorded because AI was previously in neither list — every mention across the spec, `AGENTS.md` and the plan is a *justification for the authority chokepoint*, never a work item, so §5.3 could not answer "is this out of scope or just unwritten." Now it answers. Carries three notes for the eventual build: the AI is a game-side controller and not a `rules/` component; it consumes the same per-recipient projection as #34, which therefore has a non-network consumer that may arrive first; and scoring candidate moves under a dice-pool resolver is an unsettled design question, not an implementation detail. |

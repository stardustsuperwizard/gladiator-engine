# Headless Authority and the Client SDK

**New 2026-09-15.** Owner decision, recorded before the work it shapes exists.

## What this document is for

It answers one question: **how does somebody who is not us build a client for
this game?**

The goal is an authoritative game service that players reach with an interface
*they* chose or built — a high-fidelity 3D client on an expensive machine, a
sprite-based web client, a terminal client, an LLM-driven agent — all playing
the same match against the same authority, with no interface privileged over
any other.

`docs/moba-to-hex-skirmish-extraction-plan.md` §5.5 already settled the
*deployment posture*: ship a client, run centrally every server whose results
are meant to count. This document extends that decision to the case §5.5 did
not consider — **that the client might not be ours** — and works out what the
authority has to serve, what an SDK actually contains, and what the tree needs
before any of it is possible.

It is a fourth document alongside the three in `AGENTS.md`, and it keeps their
discipline about scope:

| Document | Answers |
| --- | --- |
| `docs/hex-skirmish-game-spec.md` | *What are the rules?* |
| `docs/moba-to-hex-skirmish-extraction-plan.md` | *What gets built, in what order?* |
| `docs/godot-implementation-guide.md` | *How is that done in Godot 4?* |
| **this document** | *How does a third party play the game without our client?* |

Do not put mechanics here — they belong in the spec. Do not put Godot
specifics here — they belong in the guide. This document is about the boundary
between the authority and anything outside it.

**Content ownership is a related question and is tracked outside this
repository.** It reaches the same conclusion this document reaches in
constraint 8 — content is *served*, not *shipped* — by a different route. Only
the architectural reason is recorded here, and it stands on its own.

---

## 0. Status: none of this is the next work

Same posture as plan §5.5, for the same reason. Extraction plan §5.2's build
order is unchanged by this document. The next work is still §11 victory
determination and §10 step 6 (#173), and then the card system.

This is written now because several decisions below are **free today and
expensive later**. The clearest is constraint 8's: whether the card schema can
load served content is settled the moment the card system is built, and the
card system is close behind the next thing on the list.

An implementation session must not read this document as authorisation to
build an HTTP server, a transport layer, or an SDK package. It is
authorisation to *shape* the deferred work correctly when it arrives, and to
refuse changes that would make the work below harder. Section 11 says exactly
what is and is not actionable now.

> **Owner decision, 2026-09-15.** The public API is **a future release, not
> MVP**. Design and build with an eye toward it; do not build it first, and do
> not let it displace anything in §5.2's order. Recorded in extraction plan
> §5.3 alongside the rest of the deferred work, which is where a session
> checking scope will look — this document is not that list and must not
> become a way around it.

---

## 1. The premise this replaces

The question that motivated this document was posed as a latency problem:

> Games need the rules loaded client-side to hide latency. The client runs the
> rules, sends the result, and the authoritative server re-runs the rules to
> verify the client made the correct move.

That is **client-side prediction with server reconciliation**, and it is a
real-time technique. It exists because a player who presses "move forward"
cannot wait 80ms to see their own avatar respond. `docs/godot-implementation-guide.md`
§9 already says it does not apply here:

> the traffic is a handful of small messages per turn, and none of the
> latency-hiding machinery a real-time game needs applies.

For this game it is not merely unnecessary. **It is impossible by
construction,** and the thing that makes it impossible is a rule we chose on
purpose. Plan §5.5 constraint 2: *the server rolls, and the seed never leaves
it.* Combat is a dice pool (spec §7). A client that does not hold the seed and
the generator position cannot predict the outcome of an Attack at all, and a
client that *does* hold them knows every die that has not been rolled yet.
There is no version of client-side prediction here that is not also a cheat.

So: **a client never computes a result for the authority to verify.** Delete
that idea. What replaces it is the subject of the next section, and it is a
smaller problem.

---

## 2. What a third-party client actually needs

Strip away prediction and what a client wants the rules for is **affordance**,
not resolution:

- which hexes this fighter can reach, and at what cost;
- which targets are in range and in line of sight;
- what the dice pool would be, and against what target number;
- which actions are available at all, given the Step, the turn order, and the
  fighter's status flags.

`docs/godot-implementation-guide.md` §9.1 calls exactly this out — "legal-move
highlighting, animation, preview" — and correctly labels the client's rules
copy *advisory*.

Note what affordance is **not**: it is not stochastic. Every item in that list
is derivable from open state. Spec §3.4 makes the board, every fighter's
position and damage and status flags, both scores, and the counters visible to
both players. Flanking and surrounding (spec §8) are geometry over open state.
Target numbers are a chart. **A client can be told the complete dice pool and
the target number without learning a single unrolled die.**

That is the whole trick, and it is why this is a much easier problem than the
one we thought we had.

---

## 3. The decision: serve affordances, not rules

> **Decision.** The authority computes the legal action set and serves it with
> the per-player state projection. Clients are not required to contain a copy
> of `rules/`, and the SDK does not ship one.

### Why

The rules are GDScript. GDScript does not travel. A React client, a Python
agent, and a Unity client cannot run `rules/` without us solving a
cross-language portability problem we have no other reason to solve.

But a turn boundary in this game is measured in seconds — a human is reading
the board, or it is the opponent's Turn entirely. The round trip that fetches
"here are your legal actions" is a round trip the client was already making to
learn the opponent's move. Serving affordances costs one payload of a few
kilobytes on a request that already exists.

And the affordances are **authoritative by construction**, because they are
computed by the same `rules/` that resolves the action. A client-side copy can
only ever agree with the server by luck and vigilance; a served list agrees by
identity. The entire class of "the client highlighted a move the server then
refused" bugs does not exist.

### The alternatives, and why they were rejected

Recorded so this is not re-litigated, following the convention of plan §5.3.

- **Port `rules/` to a portable core** (Rust or C compiled to WASM plus native,
  with Godot binding to it). **Rejected for now.** It contradicts `AGENTS.md`'s
  "do not add third-party dependencies or addons" and its requirement that
  rules code be `RefCounted`/`Resource` Godot-native, and it is a rewrite of
  the module we just finished building. Not struck permanently — see §12's open
  questions. It becomes worth reconsidering only when a real client author
  demands instant offline affordance and the served list has been shown to be
  insufficient, in that order.
- **Let each client author reimplement the rules.** **Rejected permanently.**
  This is the desync factory that guide §9.3's ruleset handshake exists to
  detect. Two implementations are two rulesets, and they will disagree.
- **Ship a GDScript rules library and require clients to be Godot clients.**
  **Rejected.** It defeats the stated goal. "Bring your own interface" that
  means "bring your own Godot interface" is not the thing being built.

### The consequence for AI and agent clients

This decision is worth more to an agent-driven client than to a human one. An
LLM handed *"here are your nine legal actions, with previews"* is
dramatically more reliable than one handed a rulebook and asked to derive
legality from it. We would have had to build that endpoint for agent clients
regardless. Building it once and letting human-facing clients use it too is
strictly less work than the alternative.

This also supersedes part of plan §5.3's AI note. That note says an AI
opponent "needs the per-recipient projection" — still true — and implies the AI
reads `rules/` directly to evaluate candidates. An in-process AI still may. An
*external* agent client cannot, and does not need to: the legal action set is
its candidate list.

---

## 4. What "the SDK" actually is

It is not one artifact. It is four tiers with different lifecycles and sharply
different importance.

### Tier 0 — the wire contract. This is the product.

A machine-readable description of the API: endpoints, the per-player view
schema, action envelopes, the result schema, and the failure vocabularies.
OpenAPI plus JSON Schema.

Everything else on this list is a convenience generated from Tier 0. If we
ship only Tier 0 and it is good, people will build clients. If we ship
beautiful language bindings over an underspecified contract, they will not.

The single most important thing Tier 0 has to get right is already correct in
the tree and must survive the trip to the wire: **the two failure vocabularies
are separate.** `scripts/authority.gd` and `scripts/action_runner.gd` both
state it in their docstrings — an `Authority.REFUSED_*` means the command
never reached `resolve()`, a `TurnAction.FAILURE_*` means it reached
`resolve()` and could not resolve. Most game APIs collapse these into one
`error` string and the client author can never tell "it is not your turn" from
"that hex is out of range." See §6.

### Tier 1 — the ruleset and content bundle, as data

Served, not compiled in:

- **Balance values** — the `.tres` contents as JSON. Plan §5.5 already wants
  the authority serving these so a balance patch does not need a client
  release. For third-party clients it is not a lever, it is mandatory: they
  have no `.tres` to read.
- **`ruleset_id`** — the identity of the rules *code*, per guide §9.3.
- **`content_pack_id`** — the identity of the card/champion *content*. A
  separate axis from the rules version, and separately versioned: a client
  needing a rules update and a client needing a content update are different
  situations with different remedies. Splitting the identifiers costs one
  field.

### Tier 2 — generated transport bindings

TypeScript, Python, C#, GDScript. Thin. Generated from Tier 0, not hand-written
and not hand-maintained. They do HTTP, auth, retries and types. **They contain
no rules.**

### Tier 3 — a portable rules core for local affordance

The thing §3 decided not to build. Listed here so the tier numbering does not
imply it was forgotten.

---

## 5. Constraints

Plan §5.5 states four constraints for the operator-run posture. They all still
hold, unchanged. Third-party clients add these.

5. **The authority serves the legal action set, and that set is projected too.**
   A legal-action list that names a card in hand leaks the hand to whoever
   receives it, exactly as a full `GameState` would. The projection applies to
   affordances, state, and results alike.

6. **A preview may contain anything derivable from open state, and nothing
   else.** Dice pool composition, target number, reachable set, target
   legality: all fine, all open under spec §3.4. A predicted roll, a sampled
   outcome, or anything computed from the generator position: never. This is
   constraint 2 restated at the level the affordance endpoint operates on, and
   it is the one an implementer is most likely to violate by accident while
   trying to be helpful.

7. **No client is privileged.** Our own reference client uses the same public
   API as everybody else's, with no private endpoint, no extra field, and no
   back door. This is not a fairness gesture — it is the only mechanism that
   *tells us* whether the SDK is sufficient. A first-party client with a
   shortcut is a first-party client that cannot detect the gap.

   **This constrains a networked client and nothing else.** It says a client
   that talks to the authority over a wire must talk to it through the public
   API. It does not say every client must talk over a wire. The hotseat scene
   merged under epic #203 constructs `Authority` directly and submits through
   `ActionRunner` in-process, which is the second architectural commitment
   working exactly as intended — there is no API for it to bypass, so there is
   nothing here for it to violate. `ActionOptions` computing affordances
   locally is likewise correct and is the very pattern §3 endorses: it asks
   `rules/` its own predicates rather than re-deriving them. **Nothing in this
   document asks for a line of the existing client to change.**

8. **Content is served, never assumed.** A client may not be required to have
   shipped with card text, champion names, or art in order to render a match.
   A third party cannot be expected to hold our content, and a content update
   must not require every client in the world to ship a release. Ownership
   questions reach the same requirement by another route; this one stands
   without them.

---

## 6. The wire contract, sketched

Illustrative, not prescriptive. It exists so the next agent has something
concrete to argue with rather than a blank page. Names and shapes are open;
the properties they encode are not.

### Endpoints

```
GET  /v1/ruleset
     -> { ruleset_id, content_pack_id, schema_version }

GET  /v1/content/{content_pack_id}
     -> display data for cards, fighters, champions

POST /v1/matches
     -> { match_id, ... }

GET  /v1/matches/{match_id}/view
     -> { state_digest, view: {...}, legal_actions: [...] }

POST /v1/matches/{match_id}/actions
     body: { expected_digest, action: {...} }
     -> { ok, state_digest, result: {...} }

GET  /v1/matches/{match_id}/events?since={cursor}
     -> the opponent's moves, as they resolve
```

### The action envelope

```json
{ "kind": "move", "actor_id": "f1", "params": { "to": { "q": 3, "r": -1 } } }
```

### The result envelope, preserving both vocabularies

```json
{ "ok": false, "layer": "authority", "reason": "authority_not_your_turn" }
{ "ok": false, "layer": "action",    "reason": "move_action_out_of_range" }
```

The `layer` field is the wire expression of the separation `authority.gd`
protects. A client author can act on it: `layer: "authority"` means *stop, it
is not your move to make*; `layer: "action"` means *your move, try a different
one*. Collapsing them loses that, and the docstrings in the tree explain at
length why it must not be lost.

### A legal action, with its preview

```json
{
  "kind": "attack",
  "actor_id": "f1",
  "params": { "target_id": "f4" },
  "preview": { "pool": 5, "target_number": 4, "engagement_bonus": 1 }
}
```

Everything in `preview` is derivable from open state. Nothing in it is a roll.

---

## 7. Actions have to become data, without a registry

This is the one place where the API requirement collides head-on with an
architectural commitment, and the collision has a clean resolution that an
implementer must not improvise around.

**The problem.** `TurnAction` subclasses are constructed in-process today.
There is no `from_dict`, no serialized command form, and nothing in the tree
turns the string `"move"` into a `MoveAction`. An HTTP API needs exactly that.

**The commitment it appears to violate.** Both `scripts/authority.gd` and
`scripts/action_runner.gd` say it, twice each, in their class docstrings:

> There is no command-kind enum, registry, factory or dispatch table here, and
> there must never be one: adding a command is one new `TurnAction` subclass
> and no edit to this file.

A wire format *is* a kind-to-constructor mapping. It looks like the forbidden
thing.

**The resolution.** Read the commitment precisely: it forbids a registry
*here* — inside the gate and inside the runner. It does not forbid one from
existing. The deserializer is a transport concern, and transport lives
game-side in `scripts/`, for the same reason `Authority` itself lives in
`scripts/` and not in `rules/`: turn order, ownership, session and now
encoding are things `rules/` has no opinion about.

So:

- the `kind` → constructor map lives in `scripts/`, in its own file, as a
  sibling of `ActionRunner` and not a member of it;
- `ActionRunner.run()` still takes a constructed `TurnAction` and stays written
  entirely against the base, with no edit;
- `Authority.refusal()` still asks an action for `actor_id()` and nothing
  else;
- `rules/` gains nothing and references none of it, so the one-way arrow and
  its contract test are untouched.

Adding a command therefore costs one `TurnAction` subclass plus one line in a
transport table — and the transport table is not the gate. If a session finds
itself editing `action_runner.gd` or `authority.gd` to add a command kind, it
has taken the wrong route and should stop.

---

## 8. `GameState.digest()` is the concurrency token

Already in the tree, at `rules/state/game_state.gd:411`, and better suited to
this than it looks.

`to_dict()` builds its keys in a fixed order and populates `players` and
`fighters` by walking the explicit `_turn_order` and `_fighter_order` arrays.
The class docstring says why: *"Two states built by the same sequence of calls
therefore stringify identically, character for character, which is what makes
`digest()` a usable identity."* `digest()` is SHA-256 over that string.

A stable content hash over the whole match state is precisely a
compare-and-swap token:

- the client submits `expected_digest` with every action;
- the authority refuses the action if the state has moved on;
- two clients racing on the same match resolve deterministically, with the
  loser told to re-fetch rather than silently overwriting;
- a retried request is idempotent for free, because the retry carries a digest
  that no longer matches.

If the authority is backed by a conditional-write store — DynamoDB's condition
expressions, a Postgres `WHERE digest = ...` — this maps onto it directly with
nothing invented.

The single most valuable property of the serverless story is already built and
was built for a different reason. Do not weaken `to_dict()`'s ordering
guarantees; they are now load-bearing twice.

---

## 9. Deployment shape

A turn is already a pure function: `(state, action, requester) -> (state', result)`.
`ActionRunner.run()` is that function. The state serializes whole, including
the generator position (spec §3.4). This is a natural fit for a
request-per-turn service and there is no architectural obstacle.

The obstacle is **runtime, not design**. The rules are GDScript, so an
authority process is a Godot headless binary. On a function-as-a-service
platform that means a container image rather than a native runtime, and cold
start and image size are real costs to measure before committing. A small
long-lived container running the authority, with functions only at the thin
edges, is the more boring answer and probably the right first one.

What must not happen, under any deployment pressure: **reimplementing the
rules in a more deployment-friendly language.** Two implementations are two
rulesets. If runtime cost ever genuinely forces a portable core, that is §12's
open question and it is a port — one implementation moving — never a second
implementation appearing alongside the first.

The Godot export side is guide §9.1's two-presets-over-one-source-tree.
`export_presets.cfg` currently holds exactly one preset (`Linux`,
`dedicated_server=false`); the server preset does not exist yet.

---

## 10. What blocks this, in order

Assessed against the tree at 2026-09-15. The first two are hard blockers —
there is nothing safe to ship an SDK against until they exist.

1. **Per-recipient projection (`PlayerView`).** Deferred in plan §5.3,
   specified in guide §9.2, and the rule it filters against is spec §3.4.
   Today the only thing that could cross a wire is a full `GameState`, which
   holds both players' `hand`, `deck`, `discard` and every face-down feature
   token. Guide §9.2: *"no amount of client-side discipline can take that back:
   the bytes arrived."* It applies to `TurnResult` and, per §5 above, to the
   legal action set as well.
2. **Actions as data.** §7. Nothing in the tree serializes a command.
3. **Authentication and session.** `Authority` takes `requester_id` as a bare
   `String` with nothing behind it. That is correct for hotseat and correct for
   `Authority`'s scope — it answers entitlement, not identity — but something
   above it has to establish that a requester is who they claim. That belongs
   game-side, never in `rules/`.
4. **A match cannot legally start or end.** Spec §4 Setup is unbuilt —
   `MatchSetup`'s own class docstring says it is spec §4's *placeholder*, not
   §4 — "no roster building against `ConstructionBudget`, no deployment rules,
   no mulligan, no roll-off" — and `AGENTS.md` adds that feature tokens are
   absent from `Board` as well. Spec §11 victory and §10
   step 6 are #173. An API without `POST /matches` and a terminal state is not
   an API.
5. **Ruleset identity handshake.** Guide §9.3. It is the SDK's version pin and
   the thing that turns a rules-version mismatch into a clear refusal instead
   of a silent disagreement. Third-party clients make this more important than
   §9.3 assumed, not less: we control our own client's release cadence and we
   will not control anyone else's.
6. **The exported headless build's smoke coverage needs confirming.** A
   headless authority is a *deliverable* under this document, so "the exported
   build actually plays a match" stops being a nice-to-have and becomes a
   precondition.

   What is verified in the tree at 2026-09-15: the `smoke` job **does** exist
   in `ci.yml` — it needs `export`, downloads the Linux artifact, and runs
   `.github/scripts/smoke-godot.sh` against it. #312 landed in `cf3cbe5`
   (PR #318) and #313 followed in `770324a` (PR #326).

   What is **not** verified: whether it passes. No commit in the tree
   references #319, the failing `--smoke` driver, and this session had no
   Godot binary available to run anything locally — `.github/scripts/validate-godot.sh`
   exits 127 here, which `AGENTS.md` is emphatic means *could not validate*
   rather than *validated*. Check #319's status before treating this blocker as
   cleared.

   Note that `AGENTS.md` still says in two places that the smoke job does not
   exist. It is stale on that point; see the dated correction there.

None of this reorders §5.2. The card system, which is next, is also what first
makes the projection load-bearing — before cards there is no hidden information
to leak.

---

## 11. Work order for the next agent

Read this section as the operative one. The rest is context for it.

### Do not build now

- No HTTP server, no transport layer, no SDK package, no OpenAPI document.
- No `PlayerView` ahead of the card system — guide §9.2 asks for the projection
  to be built *with* serialization of hidden state, and there is no hidden
  state until cards exist.
- Nothing from plan §5.3. That list is unchanged by this document.
- Do not add a dependency, an addon, or a second language to the tree on the
  strength of anything written here.

### Do now — these are genuinely independent and genuinely urgent

1. **Make the card schema able to load served content**, when the card system
   is built — not only compiled-in `res://rules/cards/*.tres` paths. This is
   constraint 8 at the point it actually binds, and it is the one an
   implementer can get wrong without noticing, because a compiled-in loader
   works perfectly in hotseat and is a retrofit afterwards. `AGENTS.md` carries
   this under *Before the card system*.
2. **Confirm the smoke stage is actually green, and close out #319.** #312 has
   landed — the job exists and is wired. Whether the `--smoke` driver it calls
   still fails is the open part. A headless build that *provably* plays a match
   is the precondition for a headless authority being a deliverable at all.
   This is existing work under epic #220; this document raises its priority
   rather than adding to it.

### Do when you are next in the neighbourhood

These cost nothing if done while adjacent code is open and are expensive as
retrofits.

3. **When the card system lands**, build the per-recipient projection with it,
   not after it. Guide §9.2 gives the reason and the shape. The failure mode is
   silent: a leaked hand looks exactly like a working game.
4. **When #173 lands**, make sure a finished match is representable as a
   serialized view — a client has to be able to *see* that it won.
5. **Whenever you touch an action**, keep it expressible as data. A `TurnAction`
   subclass whose constructor takes a live object reference rather than ids and
   plain values has made §7 harder for no gain. Ids and JSON-compatible values
   only, which is what `GameState`'s opaque-payload seam already assumes.
6. **Do not weaken `GameState.to_dict()`'s ordering guarantees.** §8. They were
   built for replay identity and are now also the concurrency mechanism.

### If you believe this document is wrong

Say so and stop, the same way `AGENTS.md` requires for a rule you believe is
wrong. This is an owner decision with a date on it. Revise it here, in the
document's own convention, with a dated revision note — do not work around it
in code, and do not let a design decision live only in an implementation.

---

## 12. Open questions

Real ones. None blocks the build order; all will need an answer before a public
SDK exists.

- **Does the served affordance list scale?** A Move's reachable set is bounded
  and small. A card system with many playable cards in hand, each with targets,
  could make the legal action set large enough that enumerating it every turn
  is wasteful. Unknown until the card system exists. If it becomes a problem,
  the fix is probably lazy expansion — enumerate kinds eagerly and targets on
  request — not client-side rules.
- **Does Tier 3 ever become necessary?** §3 rejected it "for now" on the
  grounds that a turn boundary is seconds long. That reasoning fails if a
  future client wants a genuinely offline mode, or if drag-to-preview
  interactions make per-hover round trips unacceptable. Revisit only on a
  concrete client author's concrete complaint.
- **What is the event delivery mechanism?** The sketch in §6 shows polling
  because polling is the thing every possible client can do. Long-poll, SSE and
  WebSocket are all better for some clients and worse for others, and the answer
  is probably "polling always works, SSE when you can."
- **How is a match authenticated across a client we did not write?** Related to
  blocker 3 but not the same question. Accounts, match tokens, and whether a
  client is even the unit of identity are all unanswered.
- **How do stochastic candidate moves get scored by an agent client?** Plan
  §5.3 flags this as a genuine open design question for an in-process AI, and it
  does not get easier when the agent is external. Noted, not owned here.

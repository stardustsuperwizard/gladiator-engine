# Hex Skirmish Game — Mechanics Spec

A functional design doc for a 2-player, turn-based, hex-grid skirmish game.
Names below are generic/placeholder — swap in your own theme, fighters, and card flavor.

This document is deliberately engine-agnostic: it describes mechanics, not an
implementation. Engine specifics live in `godot-implementation-guide.md`;
build order and architecture live in
`moba-to-hex-skirmish-extraction-plan.md`.

---

## 1. Overview

- 2 players, each controlling a small roster of fighters (3–5 is typical).
- Played over a fixed number of rounds (e.g. 3).
- Each round = a **Combat Phase** (players alternate taking turns) followed by an **End Phase** (scoring, hand refresh, cleanup).
- Players win by accumulating the most points across the game.

---

## 2. Board

- A hex grid. Hex types:
  - **Normal** — no special property.
  - **Starting** — where fighters deploy at game start.
  - **Edge** — outermost ring of the board.
  - **Blocked** — fighters can't move into or through it; also blocks line-of-sight.
  - **Hazard** — entering or being placed here applies a negative status.
- Each hex holds at most one fighter.
- Objective/feature tokens can also occupy hexes; a fighter standing on one is "holding" it.

**Line of sight:** draw a line between hex centers. If it touches/crosses a blocked hex, there's no visibility between them.

**Distance:** always the shortest hex-step path between two hexes, blocked hexes included in the count.

---

## 3. Data Model

> **Revised 2026-09-08.** This section previously split a fighter's combat
> profile across a `Fighter` and a separate `Weapon` entity, and gave each
> weapon a `type: melee | ranged` that selected which die symbols counted as
> successes. That was wrong on both counts, and §6 and §7 were revised with it.
>
> The source tabletop game has no selectable weapons — a fighter's attack
> profile is printed on its card and is part of what the fighter *is*. Modelling
> a weapon as a separate, swappable entity imported an equipment system the
> rules never had, and put balance-bearing numbers (range, dice, damage) on the
> wrong side of the mechanics/presentation line. `melee | ranged` compounded it:
> it read as a descriptive category but was really a hit-probability dial, so
> range and accuracy were welded together where no rule said they should be.
>
> Weapons are now presentation only (§3.3), the six combat stats belong to the
> fighter, and symbol-matched dice are replaced by a d6 against a target number
> (§7).

### 3.1 Entities

```
Fighter {
  id, owner, position
  stats: { move, save, health, range, attack, damage }
  statusFlags: [moved, charged, guarded, hazard, ...]
  damageCounter: int
  tags: [ ]            // used to gate which abilities/cards apply
  abilityTags: [ ]     // optional special rules usable during combat
  enhanced: bool        // "powered up" state, see Section 9
}

CombatProfile {                     // one per game; every tuning dial in §7
  dieSides                           // 6
  attackTarget, saveTarget           // baselines: both 5
  engagementRange                    // 1 — see §7.3, and abilities may raise it
  engagementModifier                 // attacker is engaged
  attackFlankModifier                // TARGET flanked
  attackSurroundModifier             // TARGET surrounded
  saveFlankModifier                  // ATTACKER flanked
  saveSurroundModifier               // ATTACKER surrounded
  guardModifier                      // defender guarded, §6
  minTarget, maxTarget               // the clamp, see §7.3
}

ConstructionBudget {                // §3.2; validates an authored fighter
  totalPoints                        // 15
  minPerStat, maxPerStat             // 1 and 5
}

Hex {
  coord, type: normal | starting | edge | blocked | hazard
  occupantId, featureToken
}

Card {
  id, deckType: scoring | ability
  subtype: instant | attachment   // ability deck only
  effect, value
}

GameState {
  board, fighters, round, turnOrder, turnsTaken
  perPlayer: { hand, deck, discard, scored, score }
  rngSeed, rngState      // see Section 12 — dice are part of the state
}
```

### 3.2 The six combat stats

Every fighter is described by six numbers, which pair off across the table —
each is answered by something the opponent could have bought instead:

| Stat | What it does | Answered by |
| --- | --- | --- |
| **Move** | Hexes this fighter may cross in a Move (§6) | opponent's Range |
| **Range** | Furthest distance at which it may attack (§7.2) | opponent's Move |
| **Attack** | Dice rolled when attacking (§7.3) | opponent's Save |
| **Save** | Dice rolled when defending (§7.3) | opponent's Attack |
| **Damage** | Points added to the target's counter on a Hit (§7.5) | opponent's Health |
| **Health** | Counter value at which this fighter is defeated (§9) | opponent's Damage |

There is no seventh number. A fighter is these six and nothing else.

#### The construction budget

Every fighter is built from the same **15 points**, with a **minimum of 1** and
a **maximum of 5** in each of the six. The floor spends 6 of the 15, so a build
is really an allocation of the **9 discretionary points** left over, and no
fighter can be absent from any part of the game — every fighter can move,
survive a hit, and make an attack.

This is a rule about which fighters are *legal*, not about play, so it belongs
to authoring rather than resolution: nothing in §7 reads the budget, and an
implementation should assert it over authored fighters rather than compute
with it.

The reference fighters satisfy it exactly:

| | Move | Save | Health | Range | Attack | Damage | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Warrior | 4 | 2 | 3 | 1 | 3 | 2 | **15** |
| Archer | 5 | 1 | 2 | 4 | 2 | 1 | **15** |

The ceiling of 5 is what stops a single stat from being the whole build, and it
binds hardest on Damage and Health, which are the pair that decides how many
hits a fight lasts. A Damage-5 fighter defeats *any* legal fighter in one hit,
because 5 is also the Health ceiling — that is the sharpest edge the budget
allows, and it costs 5 of the 9 discretionary points to reach.

Two cautions for implementers:

- **`damage` is not `damageCounter`.** The stat is what this fighter *deals*
  per Hit; the counter is what has been *dealt to* it. They are different
  numbers on the same record.
- **The pairing table is not symmetric in practice.** Move buys objective play
  as well as combat play — it reaches feature tokens (§10) and it feeds §11's
  tiebreakers — while Range buys only combat. Expect Move to be the first stat
  that needs repricing.

### 3.3 Weapons are presentation, not mechanics

A fighter's weapon carries **no mechanical weight whatsoever**. It has no
range, no dice, no damage, no type, and no ability tags. Nothing in resolution
reads it, and no entity for it appears above.

What a fighter can do is described entirely by §3.2's six stats. What that
looks like — sword, spear, bow, rifle, staff — is a presentation choice made
over an already-settled combat profile, and two fighters with identical stats
and different weapons are mechanically identical. An implementation is free to
constrain the *choice* for readability (a fighter with Range 1 should probably
not appear to be holding a bow), but that is a presentation-layer rule and does
not belong in this document.

This is stated as a negative because it is load-bearing: an implementer looking
for where range or damage lives should find this paragraph rather than conclude
the spec forgot something.

### 3.4 Serialization and visibility

The whole of `GameState` must be serializable. Combat is stochastic
(Section 7), so the generator's seed *and* its current position belong in the
state alongside everything else — a state snapshot that omits them cannot
reproduce the match that follows it.

**Visibility.** Serializable is not the same as public. Three parts of the
state are hidden from the opponent:

- a player's **hand**, until a card is played or revealed;
- the **order of an undrawn deck**, which is shuffled in Setup (Section 4);
- a **face-down feature token**, until the reveal step in Setup.

Everything else is open to both players: the board, every fighter's position,
damage counter and status flags, discard and scored piles, both scores, and
the round and turn counters. Two players at one table can see all of it.

This is a rule about the game, not about any implementation of it — the same
rule a physical copy enforces with a card back. It is stated here because it
is the only place that can settle what an implementation may show to whom, and
an implementation that hands a player the whole state is not playing this
game.

---

## 4. Setup Sequence

1. Each player picks a roster and two decks: a **Scoring deck** (defines win conditions/point sources) and an **Ability deck** (one-shot and attachment effects).
2. Shuffle both decks. Draw starting hands (e.g. 3 scoring cards, 5 ability cards). Each player may do one mulligan: set aside any cards from one or both hands, redraw replacements, shuffle the set-aside cards back in.
3. Roll-off to decide board orientation and which player controls which territory.
4. Alternately place a set number of feature tokens face-down in empty hexes, respecting minimum spacing and a "at least one per territory" rule. Reveal them once all are placed.
5. Alternate deploying fighters into empty starting hexes in your own territory.

---

## 5. Round Structure

- Fixed number of rounds (e.g. 3).
- **Combat Phase:** players alternate turns until each has taken a set number of turns (e.g. 4 each).
  - Turn order for round 1 decided by roll-off; loser gets a bonus ability-card draw as compensation.
  - In later rounds, ties on the roll-off favor whichever player is currently behind on points.
- **Turn = Action Step + Power Step:**
  - **Action Step:** pick exactly one core action (below) and resolve it.
  - **Power Step:** players alternately play instant-speed cards, use standing abilities, or pass; the step ends when both players pass in a row.
- **End Phase** runs once both players have used all their turns for the round (see Section 10).

---

## 6. Core Actions

One per Action Step, targeting one friendly fighter:

- **Move** — step through adjacent empty hexes up to the fighter's Move stat; must end in a different hex than it started; gain a "moved" flag.
- **Attack** — pick a valid visible target within the fighter's Range, run the Combat Resolution algorithm (Section 7). There is no weapon to choose: an attack is fully described by the acting fighter's stats and the distance to the target.
- **Charge** — combined Move + Attack on the same fighter in one action, only usable if the fighter has no "moved"/"charged" flag yet this round; produces a distinct "charged" flag instead of "moved."
- **Guard** — apply a defensive flag that lowers this fighter's save target by `guardModifier` (§7.3) and prevents it being pushed, until cleared at end of round.
- **Focus/Mulligan** — discard any number of cards from hand, draw replacements of the same type, plus one bonus card.

**Lockout rule:** a fighter with a "charged" flag can't Move/Attack/Guard again until all friendly fighters share that flag (a soft round-level restriction, not a permanent one).

**Charge carries no attack-type restriction, and never did.** Any fighter may
Charge, including one with a long Range. This is worth stating because the
`melee | ranged` field deleted in §3 is the field a reader might expect to
gate it — but no rule here ever consulted that field outside resolution, so
nothing is lost. The attack half of a Charge resolves exactly as a standalone
Attack does, §7.3's engagement bonus included, measured from wherever the move
half ended. A long-ranged fighter that charges is therefore trading its reach
for contact, and buying the engagement bonus with the exposure that comes of
standing next to someone — which is the decision Charge should present.

---

## 7. Combat Resolution

> **Revised 2026-09-08.** This section previously resolved combat by rolling
> dice with named symbol faces and counting the symbols that appeared in a
> success set — criticals, plus the weapon's `type` symbol, plus symbol types
> unlocked by flanking. It now rolls plain d6 against a target number.
>
> The symbol model was replaced because it could not express a modifier. A
> success set is membership, not magnitude, so "−1 to this attack" had no
> representation at all; the only way to make an attack harder was to author a
> different die. That blocked §7.3's positional modifiers outright, and it meant
> the game's accuracy dial had exactly as many settings as someone had painted
> faces. A target number gives the same probabilities, every value between
> them, and modifiers as plain arithmetic.
>
> The translation is deliberate rather than approximate. The old die was
> `[critical, melee, ranged, melee, opening, advantage]`: a melee attack
> succeeded on 3 of 6 faces, which is target 4+; a ranged attack on 2 of 6,
> which is target 5+; flanking unlocked one further face and surrounding two,
> which are −1 and −2 to the target.
>
> **The attack chart preserves those numbers, and arrives back at them from a
> different direction.** The old die made a melee attack 3-in-6 and a ranged
> attack 2-in-6 — 4+ and 5+ — as a property of the *weapon*. The chart below
> makes an engaged attack 4+ and an unengaged one 5+, as a property of *where
> the fighter is standing*. The same two numbers, sorted by position instead of
> by equipment, which is the whole point of the revision: a bow held in contact
> is no less accurate than a sword, and a sword swung at reach is not a thing
> that happens.
>
> **The save chart deliberately does not preserve the old numbers.** Revised
> again 2026-09-08, in the same pass: its baseline moved from 4+ to 5+, its
> flanking rows from −1/−2 to −2/−3, and Guard was given a number (−1) where §6
> had only promised it "improves save results." This is a balance change, not a
> translation — a neutral save drops from 3-in-6 to 2-in-6, making the game
> markedly more lethal, while a defender whose attacker is boxed in saves better
> than the old model ever allowed. It widens the gap between a good position and
> a bad one on both sides of the roll.
>
> **Both charts were then restated as pure bonuses**, in a third pass the same
> day: the attack baseline moved from 4+ to 5+ and the long-range *penalty*
> became an engagement *bonus*. That is a reframing rather than a retune — the
> two forms agree at every distance except two hexes, which the threshold model
> left as a free window and this one closes. `longRangeThreshold` and
> `longRangeModifier` are gone; `engagementRange` and `engagementModifier`
> replace them.

### 7.1 Declare ability tags

If the attacking fighter has ability tags (§3.1), the attacker may pick one to
apply for this attack. Tags are opt-in and declared before any die is rolled.

### 7.2 Establish a legal target

An attack requires all of the following. Any failure refuses the action
outright, changing nothing:

- the target is an enemy fighter, and not the attacker itself;
- the distance from attacker to target (§2) is **less than or equal to the
  attacker's Range**, the boundary inclusive;
- the two hexes have line of sight (§2);
- the target is not already defeated (§9).

Range is measured in hexes by §2's distance rule, which counts through blocked
hexes. It is not a pathfinding question.

### 7.3 Roll both pools

Both sides roll plain **d6**. A die is a success when its result is greater
than or equal to that side's **effective target number**.

Each side starts from a baseline target in §3.1's `CombatProfile` and applies
every modifier that currently holds. Modifiers are additive, and a **lower
target is easier**.

**The two charts are not the same chart.** Their baselines agree at 5+ and both
are written as bonuses, but nothing else about them does: the conditions they
read are different, the magnitudes are different, and an implementation must
not collapse them into one shared set of dials. That the two numbers currently
match is a coincidence of tuning, not a rule — they are separate authored
values and either may move alone.

**Attack — baseline `attackTarget`, 5+**

| Condition | Effect |
| --- | --- |
| *(baseline)* | 5+ |
| Attacker is **engaged** | −1 |
| Target is flanked (§8) | −1 |
| Target is surrounded (§8) | −2 |

An attacker is **engaged** when the distance to the target is at most
`engagementRange` — 1, so ordinarily when the two are adjacent.

These stack, which produces the familiar melee ladder: an engaged attacker is
4+, engaged against a flanked target 3+, engaged against a surrounded target
2+. An attacker striking from outside engagement simply never takes the first
row, so flanking alone reads 4+ and surrounding 3+. **Range buys reach;
contact buys accuracy**, and a ranged fighter that closes to contact gets the
engagement bonus like anyone else — at the cost of being adjacent, which §8
then prices against it on the save chart.

`engagementRange` is a dial rather than the constant 1 because a special rule
should be able to move it. The intended shape:

> **Polearm.** This fighter's `engagementRange` is 2. It counts as engaged
> against a target within two hexes.

No ability implements this yet — §7.1's tag system is unbuilt — but the rule is
written against a parameter so that adding one later is authoring rather than
a change to resolution.

**Save — baseline `saveTarget`, 5+**

| Condition | Effect |
| --- | --- |
| *(baseline)* | 5+ |
| Defender is guarded (§6) | −1 |
| **Attacker** is flanked (§8) | −2 |
| **Attacker** is surrounded (§8) | −3 |

An unguarded defender against an unflanked attacker saves on 5+; guarded, 4+;
against a flanked attacker, 3+; against a surrounded one, 2+.

**Read the save chart's flanking rows carefully: they key on the *attacker's*
adjacency, not the defender's.** A defender who is flanked does not save worse
— that same board state is already priced on the attack chart, and charging it
twice would count one fact on both sides of one comparison. What the save chart
prices is the *attacker* being boxed in: a fighter swinging while surrounded is
easier to turn aside.

Guard stacks with the flanking rows. A guarded defender whose attacker is
surrounded is at `5 − 1 − 3 = 1`, which the clamp below raises to 2+ — the one
case where the clamp binds today. Flanked and surrounded remain alternatives,
never cumulative with each other (§8).

**Both charts are written as bonuses.** Every row on both is a subtraction:
each starts at 5+, the worst either roll can be, and every advantage a fighter
has earned brings it down. Nothing in the game currently *raises* either
target, so both land in 2+ to 5+.

That is deliberate and worth keeping. A player reads one question — "what do I
have going for me here?" — and never has to track which way a sign points. A
penalty added later should be looked at hard, and probably re-expressed as a
bonus the other side gets.

**Engagement is a property of the shot, not of the fighter.** It is measured
against the distance actually being attacked across, never against the
attacker's Range stat. A fighter with Range 5 standing next to its target is
engaged and attacks at 4+; the same fighter shooting from four hexes away is
not, and attacks at 5+. Accuracy is decided by where you choose to stand, which
keeps positioning a live decision every turn rather than one settled at
character creation.

**"Engaged" and "adjacent" are not synonyms, and must not be implemented as
one.** Engagement is this chart's condition and is measured in
`engagementRange`, which an ability may raise. §8's flanking and surrounding
are measured in literal adjacency — distance 1 — always, for everyone. A
Polearm fighter reaches further to *attack*; it does not flank from two hexes
away, does not help a teammate surround from two hexes away, and does not
become harder to walk past. Sharing a word here would quietly turn one special
rule into four.

**The effective target is then clamped to `[minTarget, maxTarget]` — `[2, 6]`.**
The clamp is what preserves the old model's two absolutes: a natural 6 always
succeeds, and a natural 1 always fails, no matter how modifiers stack. It also
reserves the two results for the critical and fumble concepts, which no rule
consumes yet.

The attacker rolls **Attack** dice; the defender rolls **Save** dice. Count the
successes in each pool.

**Draw order is part of the rules, not an implementation detail.** The attack
pool is rolled in full before the save pool, one draw per die. Combat is a
function of state and action (§12), and a hand-checkable result depends on both
players agreeing which die came off the generator first.

### 7.4 Compare totals

- Attacker's successes > defender's → **Hit**
- Equal → **Drawn**
- Defender's successes > attacker's → **Miss**

### 7.5 On Hit

Apply the attacker's **Damage** stat (+ any modifiers) to the target's damage
counter; check for defeat (§9); if not defeated, optionally push the target
back one hex, away from the attacker.

### 7.6 On Drawn

No damage, but a push-back may still apply.

### 7.7 On Miss

Nothing happens by default, though a large success margin on either side can
unlock a small bonus (e.g. attacker steps into the vacated hex; defender
negates part of the damage or the push).

### 7.8 Balance note: what Range costs, and where

Range costs accuracy at every distance it is actually used for. A fighter only
takes the engagement bonus in contact, so any attack made at reach — by a
Range-8 sharpshooter or a Range-2 spearman alike — is a 5+ before flanking. The
fighter that closed to contact is a 4+. That is the whole price, it is charged
per attack rather than at character creation, and it does not scale with the
Range stat.

*(Revised 2026-09-08 with §7.3. This section previously recorded the opposite
problem. Under the threshold model it replaced, an attack inside
`longRangeThreshold` took no penalty at all, so a Range-5 fighter two hexes
away was exactly as accurate as a Range-1 fighter in contact while staying out
of reach — a free window that the engagement model closes, because two hexes is
simply not contact. That window was the only distance at which the two models
disagree; everywhere else they produce identical target numbers.)*

**Range is still priced primarily by the point budget** (§3.2). One step of
accuracy is a real cost but a flat one: Range 8 and Range 3 attack at the same
5+, so nothing in resolution distinguishes them and the 15 points are what stop
everyone buying the maximum. If long reach proves oppressive in play, the dials
to reach for are `engagementModifier` and the budget's `maxPerStat`, not a
distance-scaled penalty — the sign discipline in §7.3 is worth more than a
second variable.

---

## 8. Flanking / Surrounding

- **Flanked:** exactly one enemy fighter (other than the active attacker/target) is adjacent to the fighter in question.
- **Surrounded:** two or more such enemies are adjacent. Also counts as flanked.

**Adjacent here means distance 1, always.** This section is measured in literal
adjacency and never in §7.3's `engagementRange`, which an ability may raise. A
fighter whose reach has been extended attacks from further away; it does not
flank from further away. See §7.3's note on the two words.

The condition is symmetric — it is asked of the attacker and of the target
alike — but **what it is worth is not**, and the two must be read off §7.3's
two charts rather than assumed equal:

| Who is flanked | Which roll it modifies | Flanked | Surrounded |
| --- | --- | --- | --- |
| The **target** | attack | −1 | −2 |
| The **attacker** | save | −2 | −3 |

A flanked attacker hands its victim a bigger gift than a flanked target hands
the attacker. That asymmetry is deliberate: it makes stepping into a crowd to
land a hit a real cost, not just a slightly worse position.

The two are alternatives, not cumulative: a surrounded fighter is flanked as
well, but only the surrounded row applies.

Adjacency is the only input. Nothing here reads a stat, and neither condition
depends on which fighter is attacking beyond excluding the two fighters in the
attack from counting as each other's neighbours.

*(Wording revised 2026-09-08 with §7: these were previously described as
unlocking extra success symbol types on a symbol-faced die. The probabilities
are unchanged — one unlocked face out of six is the same as one step of target
number.)*

---

## 9. Damage, Status, and Defeat

> **Revised 2026-09-08.** A defeat previously awarded the defeated fighter's
> `pointValue`, a per-fighter stat. That stat is gone (§3.2) and a defeat now
> awards a flat 1 point.
>
> `pointValue` existed to price fighters against each other, which a roster of
> unequal fighters needs. This game has no such roster: every fighter is built
> from the same 15 points, draws its special ability from the same library and
> its cards from the same pool, and the two sides field equal numbers. A
> per-fighter cost that is the same for every fighter is not a cost, and
> carrying it as an authored number invited it to drift away from the budget
> that actually governs. §11's third tiebreaker was rewritten with it.

- Each fighter tracks a damage counter.
- **Damaged** = counter > 0. **Vulnerable** = one more point of damage would defeat them. **Undamaged** = counter is 0.
- **Defeated** when the counter reaches or exceeds Health: remove the fighter and its tokens from the board, discard its attachments, award **1 point** to the opponent.
- Most per-round status flags (moved, charged, guarded, hazard-triggered) clear at end of round.
- An "enhanced" state (better stats) can be defined to trigger on a fighter meeting a condition (e.g. successfully attacking from an enemy-held zone), and reverts on a separate condition if you want that nuance.

---

## 10. End of Round Sequence

1. **Score:** check each scoring card in hand; if its condition is met, reveal and score it, move it to a scored pile.
2. **Equip:** play any attachment cards (capped so total attached value never exceeds current points).
3. **Discard:** optionally discard any hand cards.
4. **Refill:** draw scoring/ability cards back up to hand-size caps.
5. Clear round-level status flags on the board.
6. Next round begins — or, on the final round, run only steps 1–2, then go to victory determination.

**Surge-type scoring cards** (optional variant): instead of waiting for end phase, these score immediately the instant their condition is met, if held in hand; draw a replacement right away.

---

## 11. Victory Determination

1. Highest total score wins outright.
2. Tiebreakers, in order: only-surviving-player wins → highest value of held objective tokens wins → **most surviving fighters** wins → draw.

*(Third tiebreaker revised 2026-09-08: it was "highest combined point-value of
surviving fighters," which `pointValue`'s removal in §3.2 left with nothing to
sum. A count is what that measure becomes once every fighter is built from the
same budget — it was already asking "who has more left," and with equal
fighters the sum and the count order the same way.)*

---

## 12. Implementation Notes

- The dice-pool + target-number combat resolution is the core loop worth getting right first; everything else (cards, tokens, phases) layers on top of it.
- **Make the dice an explicit input, not a hidden one.** Resolution should be a
  function of state and action only: same state + same action + same generator
  position → same result, every time, in a fresh process. Never read a global
  or ambient RNG from inside resolution. This single constraint is what makes
  replays, mid-match save/load, reproducible bug reports ("here is the seed"),
  hand-checkable unit tests against these rules, and — later — networked play
  all possible. It is very cheap to adopt up front and expensive to retrofit,
  because by then every combat code path assumes ambient randomness.
- **Route every action through one resolution entry point,** even in local
  hotseat where there is no network and it looks like pure ceremony. UI
  gathers intent; a single object validates and resolves it; the UI renders
  what comes back and never mutates state itself. That chokepoint is what
  later makes AI opponents, undo, and networking additive rather than
  rewrites.
- **Numbers are data; rules are code.** All six fighter stats, card effects, and
  every field of §3.1's `CombatProfile` and `ConstructionBudget` — the two
  baseline target numbers, the attack and save flanking modifiers *as separate
  dials*, the guard modifier, the engagement range and modifier, the clamp,
  the point total and the per-stat floor and ceiling — belong in data files the
  resolver reads. The numbers will be tuned, and tuning should never mean
  editing the combat resolver. §7.8 names the dial most likely to move first.
- **Distance and movement are different problems.** Section 2 distance counts
  blocked hexes, so it is a direct coordinate calculation with no pathfinding.
  Movement (Section 6) must actually route *around* blocked and occupied
  hexes, so it needs a real search. Do not implement one and assume it covers
  the other.
- **Test line of sight for symmetry.** A line running exactly along the
  boundary between two hexes needs a consistent tie-break rule, or you get
  cases where A can see B but B cannot see A — a confusing bug to meet in
  play and an easy one to prevent with a test.
- Ability tags on fighters and cards are best modeled as a simple string/enum set with a small rules engine checking "does fighter X have tag Y" rather than hardcoding interactions — that mirrors how the tabletop original scales its own complexity.
- Push/move distinction matters: pushes shouldn't set a "moved" flag, since some effects key off of it.
- Suggested build order: board + fighter placement → Move/Attack core actions → combat resolution math → status effects (flank/surround/guard) → card system → scoring/end phase → win conditions.
- Before that full build order, prove the smallest slice that can be checked
  against these rules by hand: a board with blocked hexes, two fighters, one
  Attack, a fixed seed, and tests asserting the result — including a flanked
  and a surrounded case (Section 8) — matches what the tabletop rules produce
  when worked out on paper. Everything above becomes additive once that
  passes.

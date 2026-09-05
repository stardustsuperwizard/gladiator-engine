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

```
Fighter {
  id, owner, position
  stats: { move, save, health, pointValue }
  weapons: [Weapon]
  statusFlags: [moved, charged, guarded, hazard, ...]
  damageCounter: int
  tags: [ ]            // used to gate which abilities/cards apply
  enhanced: bool        // "powered up" state, see Section 9
}

Weapon {
  name, range, diceCount, damageValue
  type: melee | ranged
  abilityTags: [ ]      // optional special rules usable during combat
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

The whole of `GameState` must be serializable. Combat is stochastic
(Section 7), so the generator's seed *and* its current position belong in the
state alongside everything else — a state snapshot that omits them cannot
reproduce the match that follows it.

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
- **Attack** — pick a weapon, pick a valid visible target in range, run the Combat Resolution algorithm (Section 7).
- **Charge** — combined Move + Attack on the same fighter in one action, only usable if the fighter has no "moved"/"charged" flag yet this round; produces a distinct "charged" flag instead of "moved."
- **Guard** — apply a defensive flag that improves save results and prevents being pushed, until cleared at end of round.
- **Focus/Mulligan** — discard any number of cards from hand, draw replacements of the same type, plus one bonus card.

**Lockout rule:** a fighter with a "charged" flag can't Move/Attack/Guard again until all friendly fighters share that flag (a soft round-level restriction, not a permanent one).

---

## 7. Combat Resolution

1. If the chosen weapon has ability tags, the attacker may pick one to apply for this attack.
2. Attacker rolls a number of attack dice equal to the weapon's dice stat. Dice faces produce a few symbol types (e.g. a universal "critical" symbol, plus 1–2 weapon-type-specific symbols).
3. Defender rolls save dice equal to their Save stat, with an analogous symbol set.
4. **Count successes:**
   - Attack roll: criticals always count, plus symbols matching the weapon's type, plus bonus symbol types unlocked if the target is flanked/surrounded (Section 8).
   - Save roll: criticals always count, plus symbols matching the defender's save type, plus bonus symbol types unlocked if the attacker is flanked/surrounded.
5. **Compare totals:**
   - Attacker's successes > defender's → **Hit**
   - Equal → **Drawn**
   - Defender's successes > attacker's → **Miss**
6. **On Hit:** apply the weapon's damage value (+ any modifiers) to the target's damage counter; check for defeat (Section 9); if not defeated, optionally push the target back one hex, away from the attacker.
7. **On Drawn:** no damage, but a push-back may still apply.
8. **On Miss:** nothing happens by default, though a large success margin on either side can unlock a small bonus (e.g. attacker steps into the vacated hex; defender negates part of the damage or the push).

---

## 8. Flanking / Surrounding

- **Flanked:** exactly one enemy fighter (other than the active attacker/target) is adjacent to the target → unlocks one extra success symbol type on the attack roll. The same check applies symmetrically to the defense roll if the *attacker* is flanked.
- **Surrounded:** two or more such enemies are adjacent → unlocks two extra symbol types, and also counts as flanked.

---

## 9. Damage, Status, and Defeat

- Each fighter tracks a damage counter.
- **Damaged** = counter > 0. **Vulnerable** = one more point of damage would defeat them. **Undamaged** = counter is 0.
- **Defeated** when the counter reaches or exceeds Health: remove the fighter and its tokens from the board, discard its attachments, award its point value to the opponent.
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
2. Tiebreakers, in order: only-surviving-player wins → highest value of held objective tokens wins → highest combined point-value of surviving fighters wins → draw.

---

## 12. Implementation Notes

- The dice-pool + symbol-matching combat resolution is the core loop worth getting right first; everything else (cards, tokens, phases) layers on top of it.
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
- **Numbers are data; rules are code.** Dice counts, damage values, health,
  saves, point values, ranges, and card effects belong in data files the
  resolver reads. These mechanics are inherited from a settled tabletop game,
  but the numbers will still be tuned — and tuning should never mean editing
  the combat resolver.
- **Distance and movement are different problems.** Section 2 distance counts
  blocked hexes, so it is a direct coordinate calculation with no pathfinding.
  Movement (Section 6) must actually route *around* blocked and occupied
  hexes, so it needs a real search. Do not implement one and assume it covers
  the other.
- **Test line of sight for symmetry.** A line running exactly along the
  boundary between two hexes needs a consistent tie-break rule, or you get
  cases where A can see B but B cannot see A — a confusing bug to meet in
  play and an easy one to prevent with a test.
- Ability tags on fighters/weapons/cards are best modeled as a simple string/enum set with a small rules engine checking "does fighter X have tag Y" rather than hardcoding interactions — that mirrors how the tabletop original scales its own complexity.
- Push/move distinction matters: pushes shouldn't set a "moved" flag, since some effects key off of it.
- Suggested build order: board + fighter placement → Move/Attack core actions → combat resolution math → status effects (flank/surround/guard) → card system → scoring/end phase → win conditions.
- Before that full build order, prove the smallest slice that can be checked
  against these rules by hand: a board with blocked hexes, two fighters, one
  Attack, a fixed seed, and tests asserting the result — including a flanked
  and a surrounded case (Section 8) — matches what the tabletop rules produce
  when worked out on paper. Everything above becomes additive once that
  passes.

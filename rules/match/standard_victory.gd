## Spec §11.3's **Standard Victory**, and nothing else.
##
## Answers §11.3's two questions about a state: has the match ended, and given
## that it has, who won. `MatchVictory` is what callers use; this class is the
## implementation that registry resolves `"standard"` to, and the §11.3 rules
## live here and nowhere else.
##
## **When the match ends.** The first of §11.3's two endings to hold, in its
## stated order:
##
## 1. **Elimination** -- a side in `state.turn_order()` has no fighter on the
##    board. Immediate, so a state mid-round reports it: §11.3 says a side's
##    last fighter being removed ends the match inside that Turn.
## 2. **The round limit** -- `state.is_final_round()` and
##    `state.combat_segment_complete()`. §11.1's limit is reached when that
##    round's Combat Segment is complete, so a final round still mid-Segment is
##    not an ending.
##
## Elimination is tested first, so a final round whose last Segment also
## eliminated a side reports elimination. §11.1's unbounded match is
## `rounds_per_match == 0`, which `GameState.is_final_round()` already answers
## `false` for at every `round_number` -- there is no sentinel here and no
## second length field, and an unbounded match ends only by elimination.
##
## **Who won.** The side with the most VP -- `PlayerState.score` -- wins
## outright. When the highest score is shared, §11.3's tiebreakers run over the
## sides holding it, in order: only-surviving-side, then most surviving
## fighters, then a draw. The outcome reports which of the four decided it, so
## a caller can tell a won match from a drawn one and either from a tiebreak.
##
## Both sides eliminated at once is not special-cased, exactly as §11.3 says:
## tiebreaker 1 finds no only-survivor, tiebreaker 2 compares 0 against 0, and
## the result is a draw unless VP had already separated them.
##
## **§11.4's objective-token tiebreaker is absent, not stubbed.** With the
## module off no token is ever placed or held, so the rule does not apply and
## there is no zero-valued stand-in for it. Its position is recorded in
## `_winner()` as a comment: between only-surviving-side and most-surviving
## fighters, which is where §11.4 puts it back when the module exists.
##
## **A side is a player id, and a survivor is a board occupant.** Membership
## comes off the fighter payload's `owner_id`; presence comes off
## `Board.occupant_at()` across `state.board.coords()` -- the same test spec §9's
## defeat is expressed by, and the one `EndSegment` and `ChargeLockout` already
## use. Counting survivors therefore needs no `FighterTemplate`: the payload is
## read for one key and never parsed into a `Fighter`.
##
## **Pure.** Nothing here writes to the state, and nothing draws from
## `state.rng` on any path. `state.digest()` is identical across a call.
##
## `RefCounted`, static methods only, never instantiated -- the shape
## `EndSegment`, `ChargeLockout`, `Flanking` and `DicePool` already use.
class_name StandardVictory
extends RefCounted

## The id `RoundProfile.victory_condition` carries to select this condition,
## and the key `MatchVictory`'s registry files it under.
const CONDITION_ID := "standard"


## Spec §11.3 evaluated against `state`.
##
## `_profile` is unread, and the underscore says so rather than hiding it.
## Standard Victory takes both of its inputs off the state -- §11.1's length
## through `GameState.is_final_round()`, VP through `PlayerState.score` -- so
## the parameter is here because every implementation in `MatchVictory`'s
## registry shares one signature. §11.4's objective-token module is what would
## first read it, and that module is off.
static func evaluate(state: GameState, _profile: RoundProfile) -> MatchOutcome:
	if state == null:
		return MatchOutcome.unended()

	var survivors := _survivors_by_side(state)
	var ending := _ending(state, survivors)
	if ending == &"":
		return MatchOutcome.unended()

	return _winner(state, survivors, ending)


## Which of §11.3's endings holds, or `&""` when the match is still running.
##
## Elimination first, then the round limit -- §11.3's own order, and what makes
## a side's removal end a match that had rounds left.
static func _ending(state: GameState, survivors: Dictionary) -> StringName:
	for player_id in survivors:
		if int(survivors[player_id]) == 0:
			return MatchOutcome.ENDING_ELIMINATION

	if state.is_final_round() and state.combat_segment_complete():
		return MatchOutcome.ENDING_ROUND_LIMIT

	return &""


## §11.3's winner for a match that has ended by `ending`.
static func _winner(state: GameState, survivors: Dictionary, ending: StringName) -> MatchOutcome:
	var sides := state.turn_order()
	var leaders := _leaders(_scores(state), sides)
	if leaders.size() == 1:
		return MatchOutcome.ended(ending, leaders[0], MatchOutcome.RULE_VICTORY_POINTS)

	# Tiebreaker 1: only-surviving-side. Checked before the count below, which
	# would otherwise name the same winner under the wrong rule.
	var standing: Array[String] = []
	for player_id in leaders:
		if int(survivors[player_id]) > 0:
			standing.append(player_id)
	if standing.size() == 1:
		return MatchOutcome.ended(ending, standing[0], MatchOutcome.RULE_ONLY_SURVIVING_SIDE)

	# §11.4's objective-token tiebreaker -- highest value of held tokens --
	# belongs here, between the two below, and only while that module is on.
	# The module is off, so no rule stands in for it.

	# Tiebreaker 2: most surviving fighters.
	var most := _leaders(survivors, leaders)
	if most.size() == 1:
		return MatchOutcome.ended(ending, most[0], MatchOutcome.RULE_MOST_SURVIVING_FIGHTERS)

	# Tiebreaker 3: nothing separated them.
	return MatchOutcome.ended(ending, "", MatchOutcome.RULE_DRAW)


## Every player id in `among` holding the highest value `values` records for
## them, in `among`'s order. One entry means an outright winner of that
## measure; two or more means the measure did not separate them.
static func _leaders(values: Dictionary, among: Array[String]) -> Array[String]:
	var best: int = 0
	var leaders: Array[String] = []

	for player_id in among:
		var value: int = values.get(player_id, 0)
		if leaders.is_empty() or value > best:
			best = value
			leaders = [player_id] as Array[String]
		elif value == best:
			leaders.append(player_id)

	return leaders


## player id -> VP, for every player in `state.turn_order()`. §11.2 is what
## puts a number here; this reads it.
static func _scores(state: GameState) -> Dictionary:
	var scores: Dictionary = {}

	for player_id in state.turn_order():
		var player := state.player(player_id)
		scores[player_id] = 0 if player == null else player.score

	return scores


## player id -> fighters still on the board, for every player in
## `state.turn_order()`. A side with none is §11.3's eliminated side.
##
## The walk is the board's, not the state's fighter order: presence is what is
## being counted, and the count is order-independent because nothing is written.
## An occupant whose payload names no player in the turn order is skipped rather
## than counted for nobody.
static func _survivors_by_side(state: GameState) -> Dictionary:
	var counts: Dictionary = {}
	for player_id in state.turn_order():
		counts[player_id] = 0

	for coord in state.board.coords():
		var occupant := state.board.occupant_at(coord)
		if occupant == Board.EMPTY_OCCUPANT:
			continue

		var owner_id := _owner_id(state.fighter(String(occupant)))
		if not counts.has(owner_id):
			continue

		counts[owner_id] = int(counts[owner_id]) + 1

	return counts


## The payload's `"owner_id"`, or `""` when it is missing or not a `String`.
##
## One key read off an otherwise opaque payload, the way `Fighter.from_dict()`
## reads it -- and deliberately not through `Fighter.from_dict()` itself, which
## would demand a `FighterTemplate` this class has no business holding.
static func _owner_id(payload: Dictionary) -> String:
	var value: Variant = payload.get("owner_id")
	if typeof(value) != TYPE_STRING:
		return ""

	var owner_id: String = value
	return owner_id

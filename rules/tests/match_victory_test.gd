## Tests spec §11.3 as `MatchVictory` and `StandardVictory` implement it:
## called directly, with no gate involved and no game-side type named anywhere
## in this file.
##
## That omission is deliberate and is the same one `end_segment_test.gd`
## documents: this suite lives under `rules/`, which names no game-side class at
## all -- not by `res://` path and not by global `class_name`. Every fixture is
## built in memory through `AttackActionTest`'s own public statics, because
## `extraction_contract_test.gd` forbids naming a `res://resources/` path here
## and a second, drifting copy of those builders would be the alternative. The
## `RoundProfile` is constructed rather than loaded for the same reason.
##
## **Every assertion is about a rule, not about a seed.** Nothing here rolls a
## die: a defeated fighter is one `Board.remove_occupant()` has taken off, which
## is exactly what spec §9's defeat is in this engine, and VP are written
## straight onto `PlayerState.score` rather than earned through an Attack. What
## awards a VP is §11.2's business and a different task's; what this suite
## asserts is what §11.3 does with the VP once they are there.
##
## **The profile and the state are configured together.** §11.1's length reaches
## the rules as `GameState.rounds_per_match`, seeded game-side from the authored
## `RoundProfile`, so `_state()` copies the profile's dials onto the state it
## builds. A fixture that set one and not the other would be testing a
## configuration no match can be in.
class_name MatchVictoryTest

## Hexes inside `AttackActionTest`'s radius-5 board, two per side.
const P1_HEX := Vector3i(0, 0, 0)
const P1_SECOND_HEX := Vector3i(0, 1, -1)
const P2_HEX := Vector3i(1, -1, 0)
const P2_SECOND_HEX := Vector3i(2, -2, 0)

## The `turns_taken` value `_finish_final_round()` advances to, and §11.1's
## round limit, chosen for this suite. Two players, so `TURNS_PER_PLAYER` worth
## of Turns each puts `turns_taken` at four for readability; nothing reads it.
## 3 is the MVP's authored round count.
const TURNS_PER_PLAYER := 2
const ROUNDS_PER_MATCH := 3

## §11.1's sanctioned unbounded encoding, and a round number far past the MVP's
## 3 to ask an unbounded match about.
const UNBOUNDED := 0
const FAR_ROUND := 99

## A `victory_condition` no registry row names.
const UNREGISTERED_CONDITION := "treasure"

const SEED := 4242


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_running_match_reports_no_winner())
	violations.append_array(_test_elimination_ends_the_match_mid_round())
	violations.append_array(_test_the_round_limit_ends_the_match())
	violations.append_array(_test_a_final_round_mid_segment_is_not_over())
	violations.append_array(_test_elimination_is_tested_before_the_round_limit())
	violations.append_array(_test_an_unbounded_match_never_reaches_a_round_limit())
	violations.append_array(_test_an_unbounded_match_still_ends_on_elimination())
	violations.append_array(_test_most_vp_wins_outright())
	violations.append_array(_test_only_surviving_side_breaks_a_level_score())
	violations.append_array(_test_most_surviving_fighters_breaks_a_level_score())
	violations.append_array(_test_level_on_every_measure_is_a_draw())
	violations.append_array(_test_simultaneous_elimination_with_level_vp_is_a_draw())
	violations.append_array(_test_simultaneous_elimination_with_unequal_vp_has_a_winner())
	violations.append_array(_test_an_unregistered_condition_never_ends_the_match())
	violations.append_array(_test_an_empty_condition_never_ends_the_match())
	violations.append_array(_test_evaluate_leaves_an_ended_state_untouched())
	violations.append_array(_test_evaluate_leaves_a_running_state_untouched())
	violations.append_array(_test_has_ended_agrees_with_evaluate())

	if violations.is_empty():
		return true

	printerr("\n=== Match Victory Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## The authored §11 dials, restated in memory: the MVP configuration, with the
## victory condition and the round limit left open for the callers that vary
## them.
static func _profile(
	victory_condition: String = StandardVictory.CONDITION_ID,
	rounds_per_match: int = ROUNDS_PER_MATCH
) -> RoundProfile:
	var profile := RoundProfile.new()
	profile.profile_id = "fixture-match"
	profile.rounds_per_match = rounds_per_match
	profile.game_mode = "deathmatch"
	profile.victory_condition = victory_condition
	return profile


## A two-player state carrying `profile`'s round structure, on round 1 with no
## Turn yet taken and no fighter placed.
static func _state(profile: RoundProfile) -> GameState:
	var state := AttackActionTest._build_state(SEED)
	state.rounds_per_match = profile.rounds_per_match
	return state


## One fighter per side, both on the board: the shape a match runs in.
static func _engaged_state(profile: RoundProfile) -> GameState:
	var state := _state(profile)
	var template := AttackActionTest.fighter_template(5, 5)
	AttackActionTest._place(state, "a1", "p1", P1_HEX, template)
	AttackActionTest._place(state, "b1", "p2", P2_HEX, template)
	return state


## Places a second fighter for `owner_id`, so the two sides can differ in how
## many they still have on the board.
static func _reinforce(state: GameState, fighter_id: String, owner_id: String) -> void:
	var template := AttackActionTest.fighter_template(5, 5)
	var coord := P1_SECOND_HEX if owner_id == "p1" else P2_SECOND_HEX
	AttackActionTest._place(state, fighter_id, owner_id, coord, template)


## Spec §9's defeat as this engine expresses it: the board no longer reports the
## fighter, and its stored payload is left exactly where it was.
static func _defeat(state: GameState, coord: Vector3i) -> void:
	state.board.remove_occupant(coord)


## Writes §11.2's VP straight onto the two players. What awards them is a
## different task; §11.3 only reads them.
static func _score(state: GameState, p1_score: int, p2_score: int) -> void:
	state.player("p1").score = p1_score
	state.player("p2").score = p2_score


## Advances the state to the point §11.1's round limit is reached: the final
## round, with every Turn of its Combat Segment taken -- which spec §5.2 now
## expresses as every champion on the board having spent its activation.
## `turns_taken` is moved alongside it for readability; nothing reads it.
static func _finish_final_round(state: GameState) -> void:
	state.round_number = ROUNDS_PER_MATCH
	state.turns_taken = TURNS_PER_PLAYER * state.turn_order().size()
	_spend_every_activation(state)


## Spec §5.2's Combat Segment played out: every champion the board still
## reports spends its activation. Its inverse -- leaving one unspent -- is what
## the "mid-Segment" cases below need, and they say so by naming a champion.
static func _spend_every_activation(state: GameState) -> void:
	for coord in state.board.coords():
		var occupant := state.board.occupant_at(coord)
		if occupant == Board.EMPTY_OCCUPANT:
			continue

		Activation.record(state, String(occupant))


## The inverse of the above for one champion: its activation is cleared the way
## §10 step 5 clears it, so spec §5.2 still owes its owner a Turn and the
## Combat Segment is incomplete.
static func _leave_a_turn_unspent(state: GameState, fighter_id: String) -> void:
	var cleared := Fighter.without_flags(
		state.fighter(fighter_id), [Activation.FLAG_ACTIVATED] as Array[String]
	)
	state.update_fighter(fighter_id, cleared)


## One row of assertions covering a whole outcome, so each scenario below states
## all four fields rather than the one it is about.
static func _expect_outcome(
	outcome: MatchOutcome,
	over: bool,
	ended_by: StringName,
	winner_id: String,
	deciding_rule: StringName,
	scenario: String
) -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			outcome.over == over, "%s: over must be %s, got %s" % [scenario, over, outcome.over]
		)
	)
	violations.append_array(
		_expect(
			outcome.ended_by == ended_by,
			'%s: ended_by must be "%s", got "%s"' % [scenario, ended_by, outcome.ended_by]
		)
	)
	violations.append_array(
		_expect(
			outcome.winner_id == winner_id,
			'%s: winner_id must be "%s", got "%s"' % [scenario, winner_id, outcome.winner_id]
		)
	)
	violations.append_array(
		_expect(
			outcome.deciding_rule == deciding_rule,
			(
				'%s: deciding_rule must be "%s", got "%s"'
				% [scenario, deciding_rule, outcome.deciding_rule]
			)
		)
	)

	return violations


# --- When the match ends ----------------------------------------------------


## Round 1, no Turn taken, both sides on the board: nothing has ended, and the
## outcome says so with no ending, no winner and no deciding rule.
static func _test_a_running_match_reports_no_winner() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 2, 1)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(outcome, false, &"", "", &"", "a match still on round 1")


## §11.3's elimination is immediate: the last fighter of a side being removed
## ends the match inside that Turn, rounds still remaining and the Combat
## Segment half-taken.
static func _test_elimination_ends_the_match_mid_round() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile()
	var state := _engaged_state(profile)
	state.turns_taken = 1
	_defeat(state, P2_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	violations.append_array(
		_expect(
			not TurnSequence.combat_segment_complete(state) and not state.is_final_round(),
			"this scenario must be mid-round and short of the final round to test anything"
		)
	)
	violations.append_array(
		_expect_outcome(
			outcome,
			true,
			MatchOutcome.ENDING_ELIMINATION,
			"p1",
			MatchOutcome.RULE_ONLY_SURVIVING_SIDE,
			"a side eliminated mid-round"
		)
	)

	return violations


## §11.1's limit is reached when the final round's Combat Segment is complete.
static func _test_the_round_limit_ends_the_match() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 2, 1)
	_finish_final_round(state)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ROUND_LIMIT,
		"p1",
		MatchOutcome.RULE_VICTORY_POINTS,
		"the final round's Combat Segment complete"
	)


## The other half of that rule: a final round with a Turn still to take has not
## reached the limit, so the match is not over.
static func _test_a_final_round_mid_segment_is_not_over() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 2, 1)
	_finish_final_round(state)
	# One champion's Turn left unspent: spec §5.2's Segment is incomplete while
	# any champion on the board still has one, which is the state this case is
	# about.
	_leave_a_turn_unspent(state, "a1")

	var outcome := MatchVictory.evaluate(state, profile)

	violations.append_array(
		_expect(
			state.is_final_round() and not TurnSequence.combat_segment_complete(state),
			"this scenario must be on the final round with the Segment incomplete"
		)
	)
	violations.append_array(
		_expect_outcome(outcome, false, &"", "", &"", "the final round mid-Segment")
	)

	return violations


## When both endings hold at once, §11.3's order decides which is reported:
## elimination is first, so the outcome names it rather than the round limit.
static func _test_elimination_is_tested_before_the_round_limit() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 1, 2)
	_finish_final_round(state)
	_defeat(state, P1_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ELIMINATION,
		"p2",
		MatchOutcome.RULE_VICTORY_POINTS,
		"a side eliminated on the final round's last Turn"
	)


## §11.1's unbounded match has no final round at any `round_number`, including
## one far past the MVP's 3, so the round limit never ends it.
static func _test_an_unbounded_match_never_reaches_a_round_limit() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile(StandardVictory.CONDITION_ID, UNBOUNDED)
	var state := _engaged_state(profile)
	_score(state, 5, 1)
	state.round_number = FAR_ROUND
	state.turns_taken = TURNS_PER_PLAYER * state.turn_order().size()
	_spend_every_activation(state)

	var outcome := MatchVictory.evaluate(state, profile)

	violations.append_array(
		_expect(
			TurnSequence.combat_segment_complete(state),
			"this scenario must have a complete Segment, leaving only the limit in question"
		)
	)
	violations.append_array(
		_expect_outcome(outcome, false, &"", "", &"", "an unbounded match on round %d" % FAR_ROUND)
	)

	return violations


## Elimination is the unbounded match's only ending, and it still works.
static func _test_an_unbounded_match_still_ends_on_elimination() -> Array[String]:
	var profile := _profile(StandardVictory.CONDITION_ID, UNBOUNDED)
	var state := _engaged_state(profile)
	_score(state, 5, 1)
	state.round_number = FAR_ROUND
	_defeat(state, P2_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ELIMINATION,
		"p1",
		MatchOutcome.RULE_VICTORY_POINTS,
		"an unbounded match whose opponent was eliminated"
	)


# --- Who won ----------------------------------------------------------------


## Most VP wins outright, with both sides still on the board and no tiebreaker
## consulted. Run both ways round, so the answer is the score's and not the turn
## order's.
static func _test_most_vp_wins_outright() -> Array[String]:
	var violations: Array[String] = []
	var sides: Array[String] = ["p1", "p2"]

	for winner in sides:
		var profile := _profile()
		var state := _engaged_state(profile)
		_score(state, 3 if winner == "p1" else 1, 1 if winner == "p1" else 3)
		_finish_final_round(state)

		violations.append_array(
			_expect_outcome(
				MatchVictory.evaluate(state, profile),
				true,
				MatchOutcome.ENDING_ROUND_LIMIT,
				winner,
				MatchOutcome.RULE_VICTORY_POINTS,
				"%s ahead on VP with both sides on the board" % winner
			)
		)

	return violations


## Tiebreaker 1 against a level score: one side has fighters on the board and
## the other does not. The eliminated side holds two fighters' worth of payload
## and neither is on the board, so this is a board test and not a roster count.
static func _test_only_surviving_side_breaks_a_level_score() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_reinforce(state, "b2", "p2")
	_score(state, 2, 2)
	_defeat(state, P2_HEX)
	_defeat(state, P2_SECOND_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ELIMINATION,
		"p1",
		MatchOutcome.RULE_ONLY_SURVIVING_SIDE,
		"a level score with only one side left on the board"
	)


## Tiebreaker 2 against a level score: both sides are still on the board, so
## tiebreaker 1 does not apply, and the side with more fighters standing wins.
static func _test_most_surviving_fighters_breaks_a_level_score() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile()
	var state := _engaged_state(profile)
	_reinforce(state, "a2", "p1")
	_reinforce(state, "b2", "p2")
	_score(state, 2, 2)
	_defeat(state, P2_SECOND_HEX)
	_finish_final_round(state)

	var outcome := MatchVictory.evaluate(state, profile)

	violations.append_array(
		_expect(
			(
				state.board.occupant_at(P1_HEX) != Board.EMPTY_OCCUPANT
				and state.board.occupant_at(P2_HEX) != Board.EMPTY_OCCUPANT
			),
			"both sides must still be on the board, or tiebreaker 1 would decide this instead"
		)
	)
	violations.append_array(
		_expect_outcome(
			outcome,
			true,
			MatchOutcome.ENDING_ROUND_LIMIT,
			"p1",
			MatchOutcome.RULE_MOST_SURVIVING_FIGHTERS,
			"a level score with 2 fighters standing against 1"
		)
	)

	return violations


## Tiebreaker 3: level on VP and level on fighters standing is a draw, and the
## draw names no winner.
static func _test_level_on_every_measure_is_a_draw() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 2, 2)
	_finish_final_round(state)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ROUND_LIMIT,
		"",
		MatchOutcome.RULE_DRAW,
		"a level score with one fighter standing each"
	)


## Spec §11.3: both sides eliminated at once is legal and is not special-cased.
## Tiebreaker 1 finds no only-survivor, tiebreaker 2 compares 0 against 0, and
## the ending reported is still elimination.
static func _test_simultaneous_elimination_with_level_vp_is_a_draw() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 3, 3)
	_defeat(state, P1_HEX)
	_defeat(state, P2_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ELIMINATION,
		"",
		MatchOutcome.RULE_DRAW,
		"both sides eliminated at once on a level score"
	)


## The other half of that rule: with VP already separating them, the higher side
## wins the simultaneous elimination outright.
static func _test_simultaneous_elimination_with_unequal_vp_has_a_winner() -> Array[String]:
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 1, 4)
	_defeat(state, P1_HEX)
	_defeat(state, P2_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(
		outcome,
		true,
		MatchOutcome.ENDING_ELIMINATION,
		"p2",
		MatchOutcome.RULE_VICTORY_POINTS,
		"both sides eliminated at once with VP apart"
	)


# --- The registry -----------------------------------------------------------


## A condition no registry row names resolves to no implementation, and a match
## with no configured condition never ends -- not even one whose board would end
## it under Standard Victory.
static func _test_an_unregistered_condition_never_ends_the_match() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile(UNREGISTERED_CONDITION)
	var state := _engaged_state(profile)
	_score(state, 3, 1)
	_finish_final_round(state)
	_defeat(state, P2_HEX)

	var outcome := MatchVictory.evaluate(state, profile)
	var under_standard := StandardVictory.evaluate(state, _profile())

	violations.append_array(
		_expect_outcome(outcome, false, &"", "", &"", "a profile naming an unregistered condition")
	)
	violations.append_array(
		_expect(
			under_standard.ended_by == MatchOutcome.ENDING_ELIMINATION,
			"Standard Victory must end this very state, or the refusal above proves nothing"
		)
	)
	violations.append_array(
		_expect(
			not MatchVictory.has_ended(state, profile),
			"has_ended() must agree that an unregistered condition ends nothing"
		)
	)

	return violations


## An empty `victory_condition` is the unconfigured case and behaves the same
## way: no implementation, no ending, and no silent fallback to Standard
## Victory.
static func _test_an_empty_condition_never_ends_the_match() -> Array[String]:
	var profile := _profile("")
	var state := _engaged_state(profile)
	_finish_final_round(state)
	_defeat(state, P2_HEX)

	var outcome := MatchVictory.evaluate(state, profile)

	return _expect_outcome(outcome, false, &"", "", &"", "a profile with no victory condition")


# --- Pure derivation --------------------------------------------------------


## The whole point of a derived check: asking the question does not change the
## answer. The state's digest is byte-identical across the call and the
## generator has not moved -- seed or position.
static func _test_evaluate_leaves_an_ended_state_untouched() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 2, 1)
	_finish_final_round(state)
	var digest := state.digest()
	var rng_state := state.rng.get_state()
	var rng_seed := state.rng.get_seed()

	var outcome := MatchVictory.evaluate(state, profile)
	MatchVictory.has_ended(state, profile)

	violations.append_array(
		_expect(outcome.over, "this scenario must report an ended match to test anything")
	)
	violations.append_array(
		_expect(state.digest() == digest, "evaluate() must leave an ended state's digest identical")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"evaluate() must not advance the generator's state on an ended match"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == rng_seed,
			"evaluate() must not change the generator's seed on an ended match"
		)
	)

	return violations


## The same, for a match still running -- the path that returns early and could
## most easily have been written to touch something on the way.
static func _test_evaluate_leaves_a_running_state_untouched() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile()
	var state := _engaged_state(profile)
	_score(state, 1, 1)
	var digest := state.digest()
	var rng_state := state.rng.get_state()
	var rng_seed := state.rng.get_seed()

	var outcome := MatchVictory.evaluate(state, profile)
	MatchVictory.has_ended(state, profile)

	violations.append_array(
		_expect(not outcome.over, "this scenario must report a running match to test anything")
	)
	violations.append_array(
		_expect(
			state.digest() == digest, "evaluate() must leave a running state's digest identical"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"evaluate() must not advance the generator's state on a running match"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == rng_seed,
			"evaluate() must not change the generator's seed on a running match"
		)
	)

	return violations


## `has_ended()` is `evaluate().over` and must never say otherwise, across a
## running match, an elimination and a round limit.
static func _test_has_ended_agrees_with_evaluate() -> Array[String]:
	var violations: Array[String] = []
	var profile := _profile()

	var running := _engaged_state(profile)

	var eliminated := _engaged_state(profile)
	_defeat(eliminated, P2_HEX)

	var limited := _engaged_state(profile)
	_finish_final_round(limited)

	var states: Array[GameState] = [running, eliminated, limited]
	for state in states:
		violations.append_array(
			_expect(
				(
					MatchVictory.has_ended(state, profile)
					== MatchVictory.evaluate(state, profile).over
				),
				"has_ended() must report exactly what evaluate().over reports"
			)
		)

	violations.append_array(
		_expect(
			(
				not MatchVictory.has_ended(running, profile)
				and MatchVictory.has_ended(eliminated, profile)
				and MatchVictory.has_ended(limited, profile)
			),
			"the three fixtures must be running, ended by elimination and ended by the round limit"
		)
	)

	return violations

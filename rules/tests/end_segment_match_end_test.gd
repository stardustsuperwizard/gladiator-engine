## The `EndSegment` cases that exercise spec §10's **match-end form** -- the
## branch `MatchVictory.has_ended()` selects, which runs steps 1-2 as comments,
## mutates nothing and returns success: §11.1's round limit reached on a final
## round, §11.3's elimination reached mid-round, and §11.1's unbounded match
## where the limit never arrives and only the elimination ends anything.
##
## **Why a second file.** Keeping these three cases in
## `rules/tests/end_segment_test.gd` puts that file past `.gdlintrc`'s
## `max-file-lines`. That file's own comment prescribes exactly this response:
## "when a file approaches the limit, split it" -- rather than raising the
## ceiling or thinning the coverage to fit. The line the split falls on is
## which branch a case asserts: the sibling file asserts the ordinary path --
## the refusal, the flag clearing, the counters, the round-scoped rules
## re-proved through resolved actions -- and this one asserts the path that
## takes none of it.
##
## Like `charge_action_equivalence_test.gd` and unlike
## `attack_action_push_test.gd`, this file is registered in
## `tests/test_bootstrap.gd`'s `_suites` in its own right: the file it was
## split from is nowhere near needing a nested call, and a suite of record
## keeps this name in the headless run's output.
##
## **No fixture is redefined.** Every helper below is a one-line forward onto
## `EndSegmentTest`'s own, so this file carries no second copy of a fixture the
## sibling suite already defines and whose tests already exercise it. The two
## exceptions are `_unbounded_round_profile()` and `_spend_every_activation()`,
## both defined here because nothing outside this file has a use for a match
## with no round limit or for playing several of its rounds out in a loop.
##
## **Spec §5.2's Segment is complete when no champion on the board has an
## unspent activation**, so a case here that puts a champion on the board and
## never acts with it spends its activation itself -- `_place_spent()`, or
## `_spend_every_activation()` between the rounds of the unbounded case.
## `turns_taken` settles nothing any more.
##
## **Every state fixture still puts a fighter on the board for each side**, for
## the reason the sibling file's docstring gives at length: `StandardVictory`
## ends a match the moment a side in `state.turn_order()` has nobody left, so an
## unpeopled side would end the match for a reason the case never chose. A case
## here that wants the match ended by an elimination removes a garrison fighter
## itself, in the open, and says which ending it expects before running anything.
class_name EndSegmentMatchEndTest

const ORIGIN := EndSegmentTest.ORIGIN
const H1 := EndSegmentTest.H1
const GARRISON_P2_HOME := EndSegmentTest.GARRISON_P2_HOME

const TURNS_PER_PLAYER := EndSegmentTest.TURNS_PER_PLAYER
const ROUNDS_PER_MATCH := EndSegmentTest.ROUNDS_PER_MATCH


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_final_round_segment_succeeds_without_mutations())
	violations.append_array(_test_a_mid_round_elimination_ends_the_match())
	violations.append_array(_test_an_unbounded_match_advances_past_the_mvp_round_limit())

	if violations.is_empty():
		return true

	printerr("\n=== End Segment Match End Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures, forwarded onto EndSegmentTest's own --------------------------


static func _template(move: int = 1, save: int = 2, health: int = 5) -> FighterTemplate:
	return EndSegmentTest._template(move, save, health)


static func _incomplete_state(seed_value: int = 11) -> GameState:
	return EndSegmentTest._incomplete_state(seed_value)


static func _complete_state(seed_value: int = 11) -> GameState:
	return EndSegmentTest._complete_state(seed_value)


static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate
) -> void:
	EndSegmentTest._place(state, fighter_id, owner_id, coord, template)


static func _place_spent(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate
) -> void:
	EndSegmentTest._place_spent(state, fighter_id, owner_id, coord, template)


## Spec §5.2's Combat Segment played out, for a case that needs several rounds
## in a loop: every champion the board still reports spends its activation.
##
## Defined here rather than forwarded because only the unbounded case below
## advances more than one round.
static func _spend_every_activation(state: GameState) -> void:
	for coord in state.board.coords():
		var occupant := state.board.occupant_at(coord)
		if occupant == Board.EMPTY_OCCUPANT:
			continue

		Activation.record(state, String(occupant))


static func _stored(state: GameState, fighter_id: String, template: FighterTemplate) -> Fighter:
	return EndSegmentTest._stored(state, fighter_id, template)


static func _flag(
	state: GameState, fighter_id: String, template: FighterTemplate, flags: Array[String]
) -> void:
	EndSegmentTest._flag(state, fighter_id, template, flags)


static func _basic_round_profile() -> RoundProfile:
	return EndSegmentTest._basic_round_profile()


## A RoundProfile with Standard Victory and no round limit (`rounds_per_match == 0`),
## so the Segment keeps advancing rounds indefinitely and `is_final_round()` stays false.
## Used to test that unbounded matches still end on elimination.
static func _unbounded_round_profile() -> RoundProfile:
	var profile := RoundProfile.new()
	profile.turns_per_player = TURNS_PER_PLAYER
	profile.rounds_per_match = 0
	profile.victory_condition = "standard"
	return profile


# --- The match-end form -----------------------------------------------------


## Spec §10's match-end form, reached by §11.1's **round limit** and not by an
## elimination: the final round's complete Combat Segment, both sides still on
## the board, succeeds and changes nothing whatsoever.
##
## The digest is captured immediately before `run()` and compared immediately
## after -- "no mutations" is the one assertion, and the counters and flags
## checked alongside it name *which* mutations the ordinary branch would have
## made. Every round-level flag is still set afterwards, because §10 step 5 does
## not run on this path.
static func _test_a_final_round_segment_succeeds_without_mutations() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	var profile := _basic_round_profile()
	state.round_number = ROUNDS_PER_MATCH
	_place(state, "a1", "p1", ORIGIN, template)
	_place_spent(state, "b1", "p2", H1, template)
	_flag(state, "a1", template, StatusFlags.round_level())

	violations.append_array(
		_expect(
			state.is_final_round() and TurnSequence.combat_segment_complete(state),
			"this scenario must be a complete Segment on the final round to test anything"
		)
	)
	violations.append_array(
		_expect(
			MatchVictory.evaluate(state, profile).ended_by == MatchOutcome.ENDING_ROUND_LIMIT,
			"the ending under test must be §11.1's round limit, not an elimination"
		)
	)
	violations.append_array(
		_expect(
			EndSegment.can_run(state, profile),
			"a match that has ended is runnable: run() answers it with the match-end form"
		)
	)

	var before_round := state.round_number
	var before_turns := state.turns_taken
	var digest := state.digest()
	var rng_state := state.rng.get_state()

	var result := EndSegment.run(state, profile)

	violations.append_array(
		_expect(result.success, "a final-round complete Segment must succeed, not refuse")
	)
	violations.append_array(_expect(result.reason == &"", 'the result must have reason == &""'))
	violations.append_array(
		_expect(
			state.digest() == digest,
			"the match-end form must leave the state digest byte-identical"
		)
	)
	violations.append_array(
		_expect(
			state.round_number == before_round,
			"the match-end form must leave round_number at %d, not advance it" % before_round
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == before_turns,
			"the match-end form must leave turns_taken at %d unchanged" % before_turns
		)
	)
	for flag in StatusFlags.round_level():
		violations.append_array(
			_expect(
				_stored(state, "a1", template).has_status_flag(flag),
				'the match-end form must leave the "%s" flag set -- step 5 does not run' % flag
			)
		)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"the final-round match-end form must not advance the generator's state"
		)
	)

	return violations


## An elimination ends the match **mid-round**, and the Segment reports that
## instead of refusing the incomplete Combat Segment underneath it.
##
## This is the `can_run()`/`run()` agreement at its sharpest: a Turn of the round
## is still unspent, so the refusal would otherwise fire, and §11.3 has already
## ended the match, so it must not. Both entry points have to answer the same
## way, which is what `_refusal()` being the single implementation buys.
static func _test_a_mid_round_elimination_ends_the_match() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _incomplete_state()
	var profile := _basic_round_profile()
	_place(state, "a1", "p1", ORIGIN, template)
	_flag(state, "a1", template, StatusFlags.round_level())
	state.board.remove_occupant(GARRISON_P2_HOME)

	violations.append_array(
		_expect(
			not TurnSequence.combat_segment_complete(state),
			"this scenario must have a Turn of the round left to test anything"
		)
	)
	violations.append_array(
		_expect(
			MatchVictory.evaluate(state, profile).ended_by == MatchOutcome.ENDING_ELIMINATION,
			"removing p2's last fighter from the board must end the match by elimination"
		)
	)

	var before_round := state.round_number
	var digest := state.digest()
	var rng_state := state.rng.get_state()

	violations.append_array(
		_expect(
			EndSegment.can_run(state, profile),
			"can_run() must agree with run(): a match that has ended is runnable, not refused"
		)
	)

	var result := EndSegment.run(state, profile)

	violations.append_array(
		_expect(
			result.success and result.reason == &"",
			"a match ended mid-round must take the match-end form, got %s" % result.reason
		)
	)
	violations.append_array(
		_expect(state.digest() == digest, "the match-end form must change nothing mid-round")
	)
	violations.append_array(
		_expect(
			state.round_number == before_round,
			"a match ended mid-round must not advance round_number"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"the match-end form must not advance the generator's state"
		)
	)

	return violations


## §11.1's unbounded match: `rounds_per_match == 0` leaves `is_final_round()`
## false at every round, so the Segment keeps advancing past the MVP's three --
## and an elimination still ends it, because that is §11.3's other ending and it
## has nothing to do with the length.
static func _test_an_unbounded_match_advances_past_the_mvp_round_limit() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	var profile := _unbounded_round_profile()
	state.rounds_per_match = 0
	_place_spent(state, "a1", "p1", ORIGIN, template)

	# One Segment more than the MVP's three rounds, so a pass here cannot mean
	# the limit was simply never reached.
	for _segment in ROUNDS_PER_MATCH + 1:
		violations.append_array(
			_expect(
				not state.is_final_round(),
				"an unbounded match reported a final round at round %d" % state.round_number
			)
		)
		var advanced := EndSegment.run(state, profile)
		violations.append_array(
			_expect(
				advanced.success, "an unbounded match's Segment must run, got %s" % advanced.reason
			)
		)
		# Play out the round the Segment just opened, so the next one is
		# complete: the Segment it just ran cleared every activation.
		_spend_every_activation(state)

	violations.append_array(
		_expect(
			state.round_number == ROUNDS_PER_MATCH + 2,
			(
				"%d Segments of an unbounded match must reach round %d, got %d"
				% [ROUNDS_PER_MATCH + 1, ROUNDS_PER_MATCH + 2, state.round_number]
			)
		)
	)

	# §11.3's other ending is untouched by the length: p2's last fighter goes,
	# and the next Segment stops advancing.
	state.board.remove_occupant(GARRISON_P2_HOME)
	var before_round := state.round_number
	var digest := state.digest()

	var ended := EndSegment.run(state, profile)

	violations.append_array(
		_expect(ended.success, "the Segment after an elimination must succeed, not refuse")
	)
	violations.append_array(
		_expect(
			state.round_number == before_round,
			"an elimination must end an unbounded match rather than advance it again"
		)
	)
	violations.append_array(
		_expect(
			state.digest() == digest,
			"the match-end form must leave an unbounded match's digest identical"
		)
	)

	return violations

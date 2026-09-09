## Tests `EndSegment.run()` and `EndSegment.can_run()` in isolation: called
## directly, with no gate involved and no game-side type named anywhere in this
## file.
##
## That omission is deliberate, and it is the same one `guard_action_test.gd`
## and `attack_action_test.gd` document: this suite lives under `rules/`, which
## names no game-side class at all -- not by `res://` path and not by global
## `class_name`. The full-round case that plays a round through `ActionRunner`
## and then ends it lives in `tests/end_segment_round_test.gd`, which is
## game-side.
##
## **Nothing here is a `TurnAction` call.** `EndSegment` is not one, and its
## entry point is `run()`; see its own docstring for why a Segment boundary is
## not a player command and does not route through the gate.
##
## Every fixture is built in memory through `AttackActionTest`'s own public
## statics -- `extraction_contract_test.gd` forbids naming a `res://resources/`
## path under `rules/`, and reusing those builders avoids a second, drifting
## copy. Flags are set through `Fighter.set_status_flag()` and committed with
## `GameState.update_fighter()`, the seam `charge_lockout_test.gd` already uses,
## never by editing a payload's `"status_flags"` array by hand.
##
## **The round-scoped rules are asserted through resolved actions**, not off the
## flags alone: a fighter that Charged resolves a Charge next round, one that
## Guarded is attacked and its save target read off the resolver, and the
## lockout is proved released by resolving the three actions it barred. A flag
## nobody reads would be a cleared flag that changed nothing.
class_name EndSegmentTest

## The line running away from `ORIGIN`, all within `AttackActionTest`'s
## radius-5 board.
const ORIGIN := Vector3i(0, 0, 0)
const H1 := Vector3i(1, -1, 0)
const H2 := Vector3i(2, -2, 0)
const H3 := Vector3i(3, -3, 0)
const H4 := Vector3i(4, -4, 0)

## Adjacent to `H4` and to `H3`, so a charger standing on either can reach it.
const NEAR_H4 := Vector3i(3, -4, 1)

## Adjacent to `ORIGIN`, free in every scenario below.
const NEAR_ORIGIN := Vector3i(0, 1, -1)

## The other free neighbour of `ORIGIN`, for a Move that is not into an
## occupied hex.
const AWAY_FROM_ORIGIN := Vector3i(-1, 0, 1)

## Spec §5.2's Turns per player and §5.1's rounds per match, chosen for this
## suite. Two players, so a complete Combat Segment is four Turns taken.
const TURNS_PER_PLAYER := 2
const ROUNDS_PER_MATCH := 3

## A status flag outside `StatusFlags.round_level()`, which the Segment must
## leave alone. Named for the fixture rather than for spec §9's `enhanced`: no
## rule in this tree sets or reads either one, and naming this one `enhanced`
## would read as an assertion about a state that has no rule yet.
const PERSISTENT_FLAG := "fixture-persistent"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_an_incomplete_combat_segment_is_refused())
	violations.append_array(_test_a_final_round_is_refused())
	violations.append_array(_test_a_runnable_state_runs())
	violations.append_array(_test_round_level_flags_clear_on_the_board())
	violations.append_array(_test_the_counters_advance())
	violations.append_array(_test_a_defeated_fighter_is_left_exactly_as_it_is())
	violations.append_array(_test_a_moved_fighter_moves_again_next_round())
	violations.append_array(_test_a_charged_fighter_charges_again_next_round())
	violations.append_array(_test_the_charge_lockout_releases())
	violations.append_array(_test_a_guarded_fighter_saves_at_its_unmodified_target())
	violations.append_array(_test_the_generator_is_untouched_by_a_successful_run())
	violations.append_array(_test_the_result_survives_serialization())
	violations.append_array(_test_without_flags_does_not_mutate_its_argument())
	violations.append_array(_test_without_flags_preserves_key_order_and_every_other_key())
	violations.append_array(_test_without_flags_leaves_a_payload_it_cannot_read_alone())
	violations.append_array(_test_without_flags_leaves_a_non_string_entry_alone())
	violations.append_array(_test_without_flags_removes_nothing_for_an_empty_flag_list())

	if violations.is_empty():
		return true

	printerr("\n=== End Segment Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## A fighter template with the stats this suite chooses, built through
## `AttackActionTest.fighter_template()` and then given the `move` allowance
## that builder hardcodes to 1.
static func _template(move: int = 1, save: int = 2, health: int = 5) -> FighterTemplate:
	var template := AttackActionTest.fighter_template(save, health)
	template.move = move
	return template


## A state whose Combat Segment is **not** complete: the round structure is
## configured, and one Turn of it remains.
static func _incomplete_state(seed_value: int = 11) -> GameState:
	var state := AttackActionTest._build_state(seed_value)
	state.turns_per_player = TURNS_PER_PLAYER
	state.rounds_per_match = ROUNDS_PER_MATCH
	state.turns_taken = TURNS_PER_PLAYER * state.turn_order().size() - 1
	return state


## A state whose Combat Segment is complete and which is not on its final
## round: the shape `run()` does its work against.
static func _complete_state(seed_value: int = 11) -> GameState:
	var state := _incomplete_state(seed_value)
	state.turns_taken += 1
	return state


static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate
) -> void:
	AttackActionTest._place(state, fighter_id, owner_id, coord, template)


static func _stored(state: GameState, fighter_id: String, template: FighterTemplate) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


## Sets every flag in `flags` on the stored fighter through
## `Fighter.set_status_flag()` and commits with `GameState.update_fighter()`.
static func _flag(
	state: GameState, fighter_id: String, template: FighterTemplate, flags: Array[String]
) -> void:
	var fighter := _stored(state, fighter_id, template)
	for flag in flags:
		fighter.set_status_flag(flag)
	state.update_fighter(fighter_id, fighter.to_dict())


## True when the stored fighter holds none of `StatusFlags.round_level()`.
static func _is_clear(state: GameState, fighter_id: String, template: FighterTemplate) -> bool:
	var fighter := _stored(state, fighter_id, template)
	if fighter == null:
		return false

	for flag in StatusFlags.round_level():
		if fighter.has_status_flag(flag):
			return false

	return true


## An attack whose outcome is dictated by the die rather than by the seed: no
## face meets the attack target and every face meets the save target, so the
## attack always Misses and no fixture target is ever defeated mid-test.
static func _harmless_profile() -> CombatProfile:
	return AttackActionTest.forced_profile(
		AttackActionTest.NEVER_TARGET, AttackActionTest.ALWAYS_TARGET
	)


# --- Refusals ---------------------------------------------------------------


## One Turn short of a complete Combat Segment, the Segment refuses and changes
## nothing at all: the digest is byte-identical, the generator has not moved,
## and `can_run()` says the same thing `run()` does.
static func _test_an_incomplete_combat_segment_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _incomplete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_flag(state, "a1", template, StatusFlags.round_level())
	var digest := state.digest()
	var rng_state := state.rng.get_state()

	violations.append_array(
		_expect(
			not EndSegment.can_run(state),
			"can_run() must be false while at least one Turn of the round remains"
		)
	)

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(
			result.reason == EndSegment.FAILURE_COMBAT_SEGMENT_INCOMPLETE,
			"an incomplete Combat Segment must be refused with FAILURE_COMBAT_SEGMENT_INCOMPLETE"
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not report success"))
	violations.append_array(
		_expect(
			state.digest() == digest, "a refused End Segment must leave the state digest identical"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"a refused End Segment must not advance the generator's state"
		)
	)

	return violations


## On the final round there is no next round to begin, so a complete Combat
## Segment is refused all the same -- and nothing is cleared on the way out.
static func _test_a_final_round_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	state.round_number = ROUNDS_PER_MATCH
	_place(state, "a1", "p1", ORIGIN, template)
	_flag(state, "a1", template, StatusFlags.round_level())
	var digest := state.digest()
	var rng_state := state.rng.get_state()

	violations.append_array(
		_expect(not EndSegment.can_run(state), "can_run() must be false on the match's final round")
	)

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(
			result.reason == EndSegment.FAILURE_FINAL_ROUND,
			"a complete Segment on the final round must be refused with FAILURE_FINAL_ROUND"
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not report success"))
	violations.append_array(
		_expect(
			state.digest() == digest,
			"a final-round refusal must leave the state digest identical -- no flag cleared"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"a final-round refusal must not advance the generator's state"
		)
	)

	return violations


## The other half of the `can_run()`/`run()` agreement: a state the predicate
## calls runnable is one `run()` resolves against.
static func _test_a_runnable_state_runs() -> Array[String]:
	var violations: Array[String] = []
	var state := _complete_state()

	violations.append_array(
		_expect(
			EndSegment.can_run(state),
			"can_run() must be true for a complete Segment short of the final round"
		)
	)

	var result := EndSegment.run(state)

	violations.append_array(_expect(result.success, "run() must resolve when can_run() is true"))
	violations.append_array(
		_expect(result.reason == &"", 'a successful End Segment result must have reason == &""')
	)

	return violations


# --- Clearing ---------------------------------------------------------------


## Every fighter on the board loses every flag in `StatusFlags.round_level()`,
## and a flag outside that set survives untouched.
static func _test_round_level_flags_clear_on_the_board() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_place(state, "a2", "p1", NEAR_ORIGIN, template)
	_place(state, "b1", "p2", H1, template)
	_flag(state, "a1", template, [StatusFlags.MOVED, PERSISTENT_FLAG] as Array[String])
	_flag(state, "a2", template, [StatusFlags.GUARDED] as Array[String])
	_flag(state, "b1", template, StatusFlags.round_level())

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(result.success, "this scenario must run for it to test anything")
	)
	for fighter_id in ["a1", "a2", "b1"]:
		(
			violations
			. append_array(
				_expect(
					_is_clear(state, fighter_id, template),
					(
						'"moved", "guarded" and "charged" must all be cleared from %s, which is on the board'
						% fighter_id
					)
				)
			)
		)

	var cleared := _stored(state, "a1", template)
	violations.append_array(
		_expect(
			cleared != null and cleared.has_status_flag(PERSISTENT_FLAG),
			"a flag outside StatusFlags.round_level() must survive the End Segment"
		)
	)
	violations.append_array(
		_expect(
			cleared != null and cleared.damage_counter() == 0 and cleared.position() == ORIGIN,
			"clearing a flag must not move a fighter or change its damage counter"
		)
	)

	return violations


## `turns_taken` is reset and `round_number` rises by exactly one.
static func _test_the_counters_advance() -> Array[String]:
	var violations: Array[String] = []
	var state := _complete_state()
	var before_round := state.round_number

	EndSegment.run(state)

	violations.append_array(
		_expect(
			state.round_number == before_round + 1,
			"the End Segment must advance round_number by exactly 1"
		)
	)
	violations.append_array(
		_expect(state.turns_taken == 0, "the End Segment must reset turns_taken to 0")
	)
	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"the new round's Combat Segment must not already be complete"
		)
	)

	return violations


## Spec §10 step 5 says "on the board." A defeated fighter -- one
## `Board.remove_occupant()` has taken off, its payload left in the state
## exactly as `AttackAction` leaves a defeat -- keeps its flags, its payload is
## byte-identical afterwards, and it is not re-placed.
static func _test_a_defeated_fighter_is_left_exactly_as_it_is() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_place(state, "d1", "p2", H1, template)
	_flag(state, "d1", template, StatusFlags.round_level())
	state.board.remove_occupant(H1)
	var payload := JSON.stringify(state.fighter("d1"))

	EndSegment.run(state)

	violations.append_array(
		_expect(
			JSON.stringify(state.fighter("d1")) == payload,
			"a fighter off the board must come through the End Segment byte-identical"
		)
	)
	var defeated := _stored(state, "d1", template)
	for flag in StatusFlags.round_level():
		violations.append_array(
			_expect(
				defeated != null and defeated.has_status_flag(flag),
				'a fighter off the board must keep its "%s" flag' % flag
			)
		)
	violations.append_array(
		_expect(
			state.board.occupant_at(H1) == Board.EMPTY_OCCUPANT,
			"the End Segment must not re-place a defeated fighter on the board"
		)
	)
	violations.append_array(
		_expect(
			_is_clear(state, "a1", template),
			"a fighter still on the board must still be cleared alongside one that is not"
		)
	)

	return violations


# --- The round-scoped rules actually reset ----------------------------------


## A fighter that Moved in round 1 holds no `"moved"` flag in round 2, and
## resolves a Move there.
static func _test_a_moved_fighter_moves_again_next_round() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)

	var first := MoveAction.new("a1", H1, template).resolve(state)
	violations.append_array(_expect(first.success, "the round 1 Move must resolve"))
	violations.append_array(
		_expect(
			_stored(state, "a1", template).has_status_flag(StatusFlags.MOVED),
			'a resolved Move must leave the "moved" flag for the Segment to clear'
		)
	)

	EndSegment.run(state)

	violations.append_array(
		_expect(_is_clear(state, "a1", template), 'the End Segment must clear the "moved" flag')
	)

	var second := MoveAction.new("a1", H2, template).resolve(state)

	violations.append_array(
		_expect(second.success, "a fighter that Moved in round 1 must resolve a Move in round 2")
	)
	violations.append_array(
		_expect(
			_stored(state, "a1", template).position() == H2,
			"the round 2 Move must actually have moved the fighter"
		)
	)

	return violations


## A fighter that Charged in round 1 is refused a second Charge that round --
## spec §6's own precondition -- and resolves one in round 2.
static func _test_a_charged_fighter_charges_again_next_round() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var profile := _harmless_profile()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_place(state, "b1", "p2", H4, template)

	var first := ChargeAction.new("a1", H3, "b1", template, template, profile).resolve(state)
	violations.append_array(_expect(first.success, "the round 1 Charge must resolve"))

	var repeat := ChargeAction.new("a1", NEAR_H4, "b1", template, template, profile).resolve(state)
	violations.append_array(
		_expect(
			repeat.reason == ChargeAction.FAILURE_ALREADY_ACTED,
			"a second Charge in the same round must be refused -- the control for the case below"
		)
	)

	EndSegment.run(state)

	violations.append_array(
		_expect(_is_clear(state, "a1", template), 'the End Segment must clear the "charged" flag')
	)

	var second := ChargeAction.new("a1", NEAR_H4, "b1", template, template, profile).resolve(state)

	violations.append_array(
		_expect(
			second.success,
			(
				"a fighter that Charged in round 1 must resolve a Charge in round 2, got %s"
				% second.reason
			)
		)
	)

	return violations


## Spec §6's lockout, which held a charged fighter out of Move, Attack and
## Guard while a friendly still lacked the flag, releases: `locks_out()` is
## false for every fighter afterwards and all three actions resolve.
##
## This is the behaviour deferred finding #152 reports -- a fighter barred for
## the rest of the match, a lockout that released permanently -- and it is what
## no longer holds once a round can end.
static func _test_the_charge_lockout_releases() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var profile := _harmless_profile()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_place(state, "a2", "p1", NEAR_ORIGIN, template)
	_place(state, "b1", "p2", H1, template)
	_flag(state, "a1", template, [StatusFlags.CHARGED] as Array[String])

	violations.append_array(
		_expect(
			ChargeLockout.locks_out(state, _stored(state, "a1", template)),
			"this scenario must actually lock a1 out for the release to mean anything"
		)
	)
	violations.append_array(
		_expect(
			(
				MoveAction.new("a1", AWAY_FROM_ORIGIN, template).resolve(state).reason
				== MoveAction.FAILURE_CHARGE_LOCKOUT
			),
			"the locked-out fighter's Move must be refused before the End Segment"
		)
	)
	violations.append_array(
		_expect(
			(
				AttackAction.new("a1", "b1", template, template, profile).resolve(state).reason
				== AttackAction.FAILURE_CHARGE_LOCKOUT
			),
			"the locked-out fighter's Attack must be refused before the End Segment"
		)
	)
	violations.append_array(
		_expect(
			(
				GuardAction.new("a1", template).resolve(state).reason
				== GuardAction.FAILURE_CHARGE_LOCKOUT
			),
			"the locked-out fighter's Guard must be refused before the End Segment"
		)
	)

	EndSegment.run(state)

	for fighter_id in state.fighter_ids():
		violations.append_array(
			_expect(
				not ChargeLockout.locks_out(state, _stored(state, fighter_id, template)),
				"ChargeLockout.locks_out() must be false for %s after the End Segment" % fighter_id
			)
		)

	violations.append_array(
		_expect(
			GuardAction.new("a1", template).resolve(state).success,
			"the released fighter must resolve a Guard in round 2"
		)
	)
	violations.append_array(
		_expect(
			AttackAction.new("a1", "b1", template, template, profile).resolve(state).success,
			"the released fighter must resolve an Attack in round 2"
		)
	)
	violations.append_array(
		_expect(
			MoveAction.new("a1", AWAY_FROM_ORIGIN, template).resolve(state).success,
			"the released fighter must resolve a Move in round 2"
		)
	)

	return violations


## Guard's effect is read off a resolved Attack, not off the flag: against
## `standard_profile()` a guarded defender reports `save_target() == 4`, and the
## same defender after the End Segment reports its unmodified 5.
static func _test_a_guarded_fighter_saves_at_its_unmodified_target() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_place(state, "b1", "p2", H1, template)

	violations.append_array(
		_expect(
			GuardAction.new("b1", template).resolve(state).success, "the round 1 Guard must resolve"
		)
	)

	var guarded := AttackAction.new(
		"a1", "b1", template, template, AttackActionTest.standard_profile()
	)
	guarded.resolve(state)
	violations.append_array(
		_expect(
			guarded.save_target() == 4,
			(
				"a guarded defender must report save_target() == 4 in round 1, got %d"
				% guarded.save_target()
			)
		)
	)

	EndSegment.run(state)

	var cleared := AttackAction.new(
		"a1", "b1", template, template, AttackActionTest.standard_profile()
	)
	cleared.resolve(state)

	violations.append_array(
		_expect(
			cleared.save_target() == 5,
			(
				"a fighter that Guarded in round 1 must save at its unmodified 5 in round 2, got %d"
				% cleared.save_target()
			)
		)
	)

	return violations


# --- The generator and serialization ----------------------------------------


## Nothing in the Segment draws from `state.rng`.
static func _test_the_generator_is_untouched_by_a_successful_run() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_flag(state, "a1", template, StatusFlags.round_level())
	var rng_state := state.rng.get_state()
	var rng_seed := state.rng.get_seed()

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(result.success, "this scenario must run for it to test anything")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state,
			"a successful End Segment must not advance the generator's state"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == rng_seed,
			"a successful End Segment must not change the generator's seed"
		)
	)

	return violations


## The cleared flags and both counters survive a `to_dict()`/`from_dict()`
## round trip, and the Segment changes the state's identity.
static func _test_the_result_survives_serialization() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var state := _complete_state()
	_place(state, "a1", "p1", ORIGIN, template)
	_flag(state, "a1", template, StatusFlags.round_level())
	var before := state.digest()

	EndSegment.run(state)

	violations.append_array(
		_expect(state.digest() != before, "the End Segment must change the state's digest")
	)

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(
			restored != null, "the state after an End Segment must round-trip through GameState"
		)
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			_is_clear(restored, "a1", template), "the cleared flags must survive the round trip"
		)
	)
	violations.append_array(
		_expect(
			restored.round_number == state.round_number and restored.turns_taken == 0,
			"the advanced round_number and the reset turns_taken must survive the round trip"
		)
	)
	violations.append_array(
		_expect(
			restored.digest() == state.digest(), "the round trip must preserve the state's digest"
		)
	)

	return violations


# --- Fighter.without_flags() ------------------------------------------------


static func _payload() -> Dictionary:
	var fighter := Fighter.new("a1", _template(), "p1", ORIGIN)
	fighter.apply_damage(2)
	fighter.set_status_flag(StatusFlags.MOVED)
	fighter.set_status_flag(PERSISTENT_FLAG)
	fighter.set_status_flag(StatusFlags.GUARDED)
	return fighter.to_dict()


static func _test_without_flags_does_not_mutate_its_argument() -> Array[String]:
	var violations: Array[String] = []
	var payload := _payload()
	var before := JSON.stringify(payload)

	var result := Fighter.without_flags(payload, StatusFlags.round_level())

	violations.append_array(
		_expect(
			JSON.stringify(payload) == before,
			"without_flags() must not mutate the payload it is given"
		)
	)
	violations.append_array(
		_expect(
			result["status_flags"] == [PERSISTENT_FLAG],
			"without_flags() must remove every listed flag and keep every other one, in order"
		)
	)

	return violations


static func _test_without_flags_preserves_key_order_and_every_other_key() -> Array[String]:
	var violations: Array[String] = []
	var payload := _payload()

	var result := Fighter.without_flags(payload, StatusFlags.round_level())

	(
		violations
		. append_array(
			_expect(
				result.keys() == payload.keys(),
				"without_flags() must return the payload's keys in the identical order -- digest() hashes it"
			)
		)
	)
	for key in payload:
		if key == "status_flags":
			continue
		violations.append_array(
			_expect(result[key] == payload[key], 'without_flags() must leave "%s" untouched' % key)
		)

	return violations


## A payload with no `"status_flags"`, and one whose `"status_flags"` is not an
## `Array`, both come back unchanged. Nothing is repaired and no key is added.
static func _test_without_flags_leaves_a_payload_it_cannot_read_alone() -> Array[String]:
	var violations: Array[String] = []
	var missing := {"id": "a1", "owner_id": "p1"}
	var malformed := {"id": "a1", "status_flags": "moved", "owner_id": "p1"}

	var from_missing := Fighter.without_flags(missing, StatusFlags.round_level())
	var from_malformed := Fighter.without_flags(malformed, StatusFlags.round_level())

	violations.append_array(
		_expect(
			JSON.stringify(from_missing) == JSON.stringify(missing),
			'a payload with no "status_flags" must come back unchanged, gaining no key'
		)
	)
	violations.append_array(
		_expect(
			JSON.stringify(from_malformed) == JSON.stringify(malformed),
			'a payload whose "status_flags" is not an Array must come back unchanged'
		)
	)

	return violations


## A non-`String` entry is left alone rather than dropped, so this helper never
## quietly changes whether a payload would survive `Fighter.from_dict()`.
static func _test_without_flags_leaves_a_non_string_entry_alone() -> Array[String]:
	var payload := {"id": "a1", "status_flags": [StatusFlags.MOVED, 7, StatusFlags.GUARDED]}

	var result := Fighter.without_flags(payload, StatusFlags.round_level())

	return _expect(
		result["status_flags"] == [7],
		"without_flags() must leave a non-String entry in place while removing the listed flags"
	)


static func _test_without_flags_removes_nothing_for_an_empty_flag_list() -> Array[String]:
	var payload := _payload()

	var result := Fighter.without_flags(payload, [] as Array[String])

	return _expect(
		JSON.stringify(result) == JSON.stringify(payload),
		"without_flags() with an empty flag list must return the payload unchanged"
	)

## Tests `EndSegment.run()` and `EndSegment.can_run()` in isolation: called
## directly, with no gate involved and no game-side type named anywhere in this
## file.
##
## That omission is deliberate, matching `guard_action_test.gd`'s own docstring:
## this suite lives under `rules/`, which names no game-side class at all -- not
## by `res://` path and not by global `class_name`. The full-round case, which
## plays a whole Combat Segment through `ActionRunner` and then runs the
## Segment, is `tests/end_segment_round_test.gd`.
##
## **The round-scoped rules are asserted through resolved actions, not through
## the flags alone.** A cleared `"charged"` is only interesting because it lets
## the fighter Charge again, and a cleared `"guarded"` because the defender's
## save target goes back up -- so each of those is asserted by resolving the
## real action and reading the real number, with the un-cleared state as the
## control.
##
## **No fixture is redefined where one already exists.** `fighter_template()`,
## `standard_profile()`, `forced_profile()` and the hex constants are
## `AttackActionTest`'s own public fixtures, forwarded onto here the way
## `attack_action_guard_test.gd` forwards them, so this file carries no second,
## drifting copy.
##
## Flags are set through `Fighter.set_status_flag()` and committed as a payload;
## nothing here appends to a `"status_flags"` array by hand.
class_name EndSegmentTest

const ATTACKER_HEX := AttackActionTest.ATTACKER_HEX
const TARGET_HEX := AttackActionTest.TARGET_HEX
const FRIEND_HEX := AttackActionTest.TARGET_FLANK_A
const FREE_HEX := AttackActionTest.ATTACKER_FLANK

## Turns each player takes per round, and rounds in the match, for every
## fixture here. Both small: what is under test is the Segment, not the sizes.
const TURNS_PER_PLAYER := 2
const ROUNDS_PER_MATCH := 3

## A flag outside `StatusFlags.round_level()`. Spec §9's `enhanced` names no
## rule that exists, which is exactly why it is the right fixture for "a flag
## the Segment must not touch" -- no rule can be depended on here by accident.
const PERSISTENT_FLAG := "enhanced"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_an_incomplete_combat_segment_is_refused())
	violations.append_array(_test_a_final_round_is_refused())
	violations.append_array(_test_clearing_removes_round_level_flags_and_leaves_others())
	violations.append_array(_test_the_counters_advance())
	violations.append_array(_test_a_defeated_fighter_is_left_exactly_as_it_was())
	violations.append_array(_test_a_fighter_that_moved_moves_again_next_round())
	violations.append_array(_test_a_fighter_that_charged_charges_again_next_round())
	violations.append_array(_test_a_guarded_fighter_saves_at_its_unmodified_target_next_round())
	violations.append_array(_test_the_charge_lockout_releases())
	violations.append_array(_test_the_generator_is_untouched())
	violations.append_array(_test_the_new_round_survives_serialization())
	violations.append_array(_test_without_flags_directly())

	if violations.is_empty():
		return true

	printerr("\n=== End Segment Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures, forwarded onto AttackActionTest's own ----------------------


static func _fighter_template(save: int = 2, health: int = 5) -> FighterTemplate:
	return AttackActionTest.fighter_template(save, health)


static func _standard_profile() -> CombatProfile:
	return AttackActionTest.standard_profile()


## A profile whose outcome is fixed by the die rather than by the seed: no
## attack die counts and no save die counts, so nothing is ever damaged and no
## fixture below can lose a fighter it still needs.
static func _harmless_profile() -> CombatProfile:
	return AttackActionTest.forced_profile(
		AttackActionTest.NEVER_TARGET, AttackActionTest.NEVER_TARGET
	)


## A sized state on the shared radius-5 board, with `p1` and `p2` added and its
## Combat Segment one Turn short of complete.
static func _build_state(seed_value: int = 11) -> GameState:
	var state := AttackActionTest._build_state(seed_value)
	state.turns_per_player = TURNS_PER_PLAYER
	state.rounds_per_match = ROUNDS_PER_MATCH
	state.turns_taken = TURNS_PER_PLAYER * state.turn_order().size() - 1
	return state


## Marks `state`'s Combat Segment complete, by the definition
## `GameState.combat_segment_complete()` already owns.
static func _complete(state: GameState) -> void:
	state.turns_taken = TURNS_PER_PLAYER * state.turn_order().size()


## Records a fighter both ways the engine tracks one -- an opaque payload in
## `GameState` and an occupant on the board -- carrying `flags`, each set
## through `Fighter.set_status_flag()`.
static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate,
	flags: Array[String] = []
) -> void:
	var fighter := Fighter.new(fighter_id, template, owner_id, coord)
	for flag in flags:
		fighter.set_status_flag(flag)
	state.add_fighter(fighter_id, fighter.to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


static func _stored(state: GameState, fighter_id: String, template: FighterTemplate) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


## The stored payload for `fighter_id` as its canonical string, for the
## byte-identical claims below. `JSON.stringify()` is what `digest()` hashes, so
## it is what "byte-identical payload" is measured with here too.
static func _payload_text(state: GameState, fighter_id: String) -> String:
	return JSON.stringify(state.fighter(fighter_id))


# --- Refusals -------------------------------------------------------------


## One Turn short of a complete Combat Segment: refused, and nothing moves.
static func _test_an_incomplete_combat_segment_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.MOVED] as Array[String])
	var before := state.digest()
	var before_rng := state.rng.get_state()

	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"this fixture must have an incomplete Combat Segment for the case to test anything"
		)
	)
	violations.append_array(
		_expect(
			not EndSegment.can_run(state),
			"can_run() must be false while the Combat Segment is incomplete"
		)
	)

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(not result.success, "an incomplete Combat Segment must refuse the End Segment")
	)
	violations.append_array(
		_expect(
			result.reason == EndSegment.FAILURE_COMBAT_SEGMENT_INCOMPLETE,
			'the refusal must be &"end_segment_combat_incomplete", got "%s"' % result.reason
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before,
			"a refused End Segment must leave the state digest byte-identical"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_rng,
			"a refused End Segment must not advance the generator"
		)
	)

	return violations


## A complete Combat Segment on the last round of the match: refused, because
## there is no next round to begin.
static func _test_a_final_round_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.GUARDED] as Array[String])
	_complete(state)
	state.round_number = ROUNDS_PER_MATCH
	var before := state.digest()
	var before_rng := state.rng.get_state()

	violations.append_array(
		_expect(
			state.combat_segment_complete() and state.is_final_round(),
			"this fixture must be a complete Combat Segment on the final round"
		)
	)
	violations.append_array(
		_expect(not EndSegment.can_run(state), "can_run() must be false on the final round")
	)

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(not result.success, "the final round must refuse the End Segment")
	)
	violations.append_array(
		_expect(
			result.reason == EndSegment.FAILURE_FINAL_ROUND,
			'the refusal must be &"end_segment_final_round", got "%s"' % result.reason
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before,
			"a final-round refusal must leave the state digest byte-identical"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_rng,
			"a final-round refusal must not advance the generator"
		)
	)

	return violations


# --- Clearing ---------------------------------------------------------------


## Every flag in `StatusFlags.round_level()` goes; a flag outside that set,
## held by the same fighter, stays.
static func _test_clearing_removes_round_level_flags_and_leaves_others() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	var flags: Array[String] = [
		StatusFlags.MOVED, PERSISTENT_FLAG, StatusFlags.GUARDED, StatusFlags.CHARGED
	]
	_place(state, "a1", "p1", ATTACKER_HEX, template, flags)
	_place(state, "b1", "p2", TARGET_HEX, template, [StatusFlags.GUARDED] as Array[String])
	_complete(state)

	violations.append_array(
		_expect(EndSegment.can_run(state), "can_run() must be true for a runnable state")
	)
	var result := EndSegment.run(state)
	violations.append_array(_expect(result.success, "a runnable End Segment must return ok()"))
	violations.append_array(
		_expect(result.reason == &"", 'a successful End Segment result must have reason == &""')
	)

	var a1 := _stored(state, "a1", template)
	violations.append_array(_expect(a1 != null, "the cleared fighter must still parse"))
	if a1 == null:
		return violations

	for flag in StatusFlags.round_level():
		violations.append_array(
			_expect(not a1.has_status_flag(flag), 'the Segment must clear the "%s" flag' % flag)
		)

	violations.append_array(
		_expect(
			a1.has_status_flag(PERSISTENT_FLAG),
			"a flag outside StatusFlags.round_level() must survive the Segment untouched"
		)
	)
	violations.append_array(
		_expect(
			a1.status_flags() == [PERSISTENT_FLAG],
			"the surviving flag must be the only one left, in its original position"
		)
	)

	var b1 := _stored(state, "b1", template)
	violations.append_array(
		_expect(
			b1 != null and not b1.has_status_flag(StatusFlags.GUARDED),
			"the Segment must clear every fighter on the board, not just the first"
		)
	)

	return violations


## `round_number` rises by exactly one, `turns_taken` goes to zero, and the
## Combat Segment is incomplete again.
static func _test_the_counters_advance() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	_complete(state)
	var before_round := state.round_number

	EndSegment.run(state)

	violations.append_array(
		_expect(
			state.round_number == before_round + 1,
			"the End Segment must advance round_number by exactly 1, got %d" % state.round_number
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == 0,
			"the End Segment must reset turns_taken to 0, got %d" % state.turns_taken
		)
	)
	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"the new round's Combat Segment must be incomplete again"
		)
	)
	violations.append_array(
		_expect(
			not EndSegment.can_run(state),
			"can_run() must be false immediately after a run, for the same reason"
		)
	)

	return violations


## Spec §10 step 5 says "on the board." A defeated fighter -- in the state, off
## the board, exactly as `AttackAction` leaves one -- keeps its flags, keeps its
## payload byte for byte, and is not re-placed.
static func _test_a_defeated_fighter_is_left_exactly_as_it_was() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	var flags: Array[String] = [StatusFlags.MOVED, StatusFlags.GUARDED]
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.MOVED] as Array[String])
	_place(state, "b1", "p2", TARGET_HEX, template, flags)
	state.board.remove_occupant(TARGET_HEX)
	_complete(state)
	var before_payload := _payload_text(state, "b1")

	EndSegment.run(state)

	violations.append_array(
		_expect(
			_payload_text(state, "b1") == before_payload,
			"a defeated fighter's stored payload must be byte-identical after the Segment"
		)
	)

	var b1 := _stored(state, "b1", template)
	violations.append_array(_expect(b1 != null, "the defeated fighter must still parse"))
	if b1 == null:
		return violations

	violations.append_array(
		_expect(
			b1.has_status_flag(StatusFlags.MOVED) and b1.has_status_flag(StatusFlags.GUARDED),
			"a defeated fighter must keep every flag it held"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == Board.EMPTY_OCCUPANT,
			"the Segment must not re-place a defeated fighter on the board"
		)
	)

	var a1 := _stored(state, "a1", template)
	violations.append_array(
		_expect(
			a1 != null and not a1.has_status_flag(StatusFlags.MOVED),
			"the fighter still on the board must be cleared in the same run"
		)
	)

	return violations


# --- The round-scoped rules, through resolved actions -----------------------


## A fighter that Moved in round 1 starts round 2 unflagged and Moves again,
## gaining a fresh `"moved"`.
static func _test_a_fighter_that_moved_moves_again_next_round() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.MOVED] as Array[String])
	_complete(state)

	EndSegment.run(state)

	var cleared := _stored(state, "a1", template)
	violations.append_array(
		_expect(
			cleared != null and not cleared.has_status_flag(MoveAction.FLAG_MOVED),
			"round 2 must begin with the round-1 Move flag gone"
		)
	)

	var result := MoveAction.new("a1", FREE_HEX, template).resolve(state)
	violations.append_array(
		_expect(result.success, "a fighter that Moved in round 1 must resolve a Move in round 2")
	)

	var moved := _stored(state, "a1", template)
	violations.append_array(
		_expect(
			moved != null and moved.position() == FREE_HEX,
			"the round-2 Move must actually relocate the fighter"
		)
	)
	violations.append_array(
		_expect(
			moved != null and moved.has_status_flag(MoveAction.FLAG_MOVED),
			"the round-2 Move must set a fresh moved flag"
		)
	)

	return violations


## A fighter that Charged in round 1 Charges again in round 2. The control is
## the same fixture before the Segment, where spec §6's own precondition
## refuses it `FAILURE_ALREADY_ACTED`.
static func _test_a_fighter_that_charged_charges_again_next_round() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var profile := _harmless_profile()

	var control := _build_state()
	_place(control, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.CHARGED] as Array[String])
	_place(control, "b1", "p2", TARGET_HEX, template)
	var refused := ChargeAction.new("a1", FRIEND_HEX, "b1", template, template, profile).resolve(
		control
	)
	violations.append_array(
		_expect(
			refused.reason == ChargeAction.FAILURE_ALREADY_ACTED,
			"the control must show a charged fighter refused a second Charge in the same round"
		)
	)

	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.CHARGED] as Array[String])
	_place(state, "b1", "p2", TARGET_HEX, template)
	_complete(state)

	EndSegment.run(state)

	var result := ChargeAction.new("a1", FRIEND_HEX, "b1", template, template, profile).resolve(
		state
	)
	violations.append_array(
		_expect(
			result.success,
			(
				'a fighter that Charged in round 1 must resolve a Charge in round 2, got "%s"'
				% result.reason
			)
		)
	)

	var charged := _stored(state, "a1", template)
	violations.append_array(
		_expect(
			charged != null and charged.position() == FRIEND_HEX,
			"the round-2 Charge must actually relocate the fighter"
		)
	)
	violations.append_array(
		_expect(
			charged != null and charged.has_status_flag(ChargeLockout.FLAG_CHARGED),
			"the round-2 Charge must set a fresh charged flag"
		)
	)

	return violations


## A fighter that Guarded in round 1 saves at its unmodified `save_target` in
## round 2 -- asserted through a resolved Attack against it, with the same
## fixture before the Segment as the control.
static func _test_a_guarded_fighter_saves_at_its_unmodified_target_next_round() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var guarded: Array[String] = [StatusFlags.GUARDED]

	var control := _build_state()
	_place(control, "a1", "p1", ATTACKER_HEX, template)
	_place(control, "b1", "p2", TARGET_HEX, template, guarded)
	var control_attack := AttackAction.new("a1", "b1", template, template, _standard_profile())
	control_attack.resolve(control)
	violations.append_array(
		_expect(
			control_attack.save_target() == 4,
			(
				"the control -- still guarded -- must report save_target() == 4, got %d"
				% control_attack.save_target()
			)
		)
	)

	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template, guarded)
	_complete(state)

	EndSegment.run(state)

	var attack := AttackAction.new("a1", "b1", template, template, _standard_profile())
	attack.resolve(state)

	var message := (
		"a fighter that Guarded in round 1 must save at its unmodified target of 5 in round 2, got %d"
		% attack.save_target()
	)
	violations.append_array(_expect(attack.save_target() == 5, message))

	return violations


## Spec §6's lockout releases with the flag that caused it: a fighter locked
## out of Move, Attack and Guard before the Segment resolves all three after it.
static func _test_the_charge_lockout_releases() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.CHARGED] as Array[String])
	_place(state, "a2", "p1", FRIEND_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_complete(state)

	var locked := _stored(state, "a1", template)
	violations.append_array(
		_expect(
			ChargeLockout.locks_out(state, locked),
			"the fixture must actually lock the charged fighter out before the Segment"
		)
	)
	violations.append_array(
		_expect(
			(
				MoveAction.new("a1", FREE_HEX, template).resolve(state).reason
				== MoveAction.FAILURE_CHARGE_LOCKOUT
			),
			"the locked-out fighter's Move must be refused before the Segment"
		)
	)
	violations.append_array(
		_expect(
			(
				GuardAction.new("a1", template).resolve(state).reason
				== GuardAction.FAILURE_CHARGE_LOCKOUT
			),
			"the locked-out fighter's Guard must be refused before the Segment"
		)
	)
	violations.append_array(
		_expect(
			(
				(
					AttackAction
					. new("a1", "b1", template, template, _harmless_profile())
					. resolve(state)
					. reason
				)
				== AttackAction.FAILURE_CHARGE_LOCKOUT
			),
			"the locked-out fighter's Attack must be refused before the Segment"
		)
	)

	EndSegment.run(state)

	for fighter_id in state.fighter_ids():
		var fighter := _stored(state, fighter_id, template)
		violations.append_array(
			_expect(
				fighter != null and not ChargeLockout.locks_out(state, fighter),
				"ChargeLockout.locks_out() must be false for %s after the Segment" % fighter_id
			)
		)

	violations.append_array(
		_expect(
			GuardAction.new("a1", template).resolve(state).success,
			"the released fighter must resolve a Guard after the Segment"
		)
	)
	violations.append_array(
		_expect(
			(
				AttackAction
				. new("a1", "b1", template, template, _harmless_profile())
				. resolve(state)
				. success
			),
			"the released fighter must resolve an Attack after the Segment"
		)
	)
	violations.append_array(
		_expect(
			MoveAction.new("a1", FREE_HEX, template).resolve(state).success,
			"the released fighter must resolve a Move after the Segment"
		)
	)

	return violations


# --- Determinism and serialization ------------------------------------------


## The Segment is fully determined by the state it is handed: a successful run
## draws nothing, exactly as each refusal above draws nothing.
static func _test_the_generator_is_untouched() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", ATTACKER_HEX, template, [StatusFlags.CHARGED] as Array[String])
	_complete(state)
	var before_state := state.rng.get_state()
	var before_seed := state.rng.get_seed()

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(result.success, "this scenario must run for the generator claim to mean anything")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_state,
			"a successful End Segment must not advance the generator's state"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == before_seed,
			"a successful End Segment must not change the generator's seed"
		)
	)

	return violations


## The cleared flags and both counters survive `to_dict()`/`from_dict()`, and
## the Segment moves the state's identity.
static func _test_the_new_round_survives_serialization() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	var flags: Array[String] = [StatusFlags.MOVED, PERSISTENT_FLAG]
	_place(state, "a1", "p1", ATTACKER_HEX, template, flags)
	_complete(state)
	var before := state.digest()

	EndSegment.run(state)

	violations.append_array(
		_expect(state.digest() != before, "the End Segment must change the state's digest")
	)

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(
			restored != null, "the state after the End Segment must round-trip through GameState"
		)
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.digest() == state.digest(),
			"the round-tripped state must have the identical digest"
		)
	)
	violations.append_array(
		_expect(
			restored.round_number == state.round_number and restored.turns_taken == 0,
			"the advanced round_number and the reset turns_taken must survive the round trip"
		)
	)

	var fighter := _stored(restored, "a1", template)
	violations.append_array(_expect(fighter != null, "the round-tripped fighter must parse"))
	if fighter == null:
		return violations

	violations.append_array(
		_expect(
			not fighter.has_status_flag(StatusFlags.MOVED),
			"the cleared flag must still be gone after the round trip"
		)
	)
	violations.append_array(
		_expect(
			fighter.has_status_flag(PERSISTENT_FLAG),
			"the flag outside round_level() must still be present after the round trip"
		)
	)

	return violations


# --- Fighter.without_flags() ------------------------------------------------


## The payload-shaped helper on its own terms: it copies, it preserves order, it
## refuses to repair, and it leaves what it does not recognise alone.
static func _test_without_flags_directly() -> Array[String]:
	var violations: Array[String] = []
	var round_level := StatusFlags.round_level()

	var payload := {
		"id": "a1",
		"template_id": "t",
		"owner_id": "p1",
		"position": [0, 0, 0],
		"damage_counter": 2,
		"status_flags": [StatusFlags.MOVED, PERSISTENT_FLAG, StatusFlags.GUARDED],
	}
	var before := JSON.stringify(payload)

	var out := Fighter.without_flags(payload, round_level)

	violations.append_array(
		_expect(JSON.stringify(payload) == before, "without_flags() must not mutate its argument")
	)
	violations.append_array(
		_expect(
			out["status_flags"] == [PERSISTENT_FLAG],
			"without_flags() must remove exactly the named flags"
		)
	)
	violations.append_array(
		_expect(
			out.keys() == payload.keys(),
			"without_flags() must preserve the payload's key order exactly"
		)
	)
	violations.append_array(
		_expect(
			out["damage_counter"] == 2 and out["position"] == [0, 0, 0] and out["id"] == "a1",
			"without_flags() must leave every other key's value untouched"
		)
	)

	var empty_removal := Fighter.without_flags(payload, [] as Array[String])
	violations.append_array(
		_expect(
			JSON.stringify(empty_removal) == before,
			"without_flags() with an empty flag list must remove nothing"
		)
	)

	var no_key := {"id": "a1", "damage_counter": 0}
	var no_key_out := Fighter.without_flags(no_key, round_level)
	violations.append_array(
		_expect(
			JSON.stringify(no_key_out) == JSON.stringify(no_key),
			'a payload with no "status_flags" key must come back unchanged'
		)
	)
	violations.append_array(
		_expect(
			not no_key_out.has("status_flags"),
			'without_flags() must not add a "status_flags" key it did not find'
		)
	)

	var not_array := {"id": "a1", "status_flags": "moved", "damage_counter": 0}
	violations.append_array(
		_expect(
			(
				JSON.stringify(Fighter.without_flags(not_array, round_level))
				== JSON.stringify(not_array)
			),
			'a payload whose "status_flags" is not an Array must come back unchanged'
		)
	)

	var mixed := {"id": "a1", "status_flags": [StatusFlags.MOVED, 7, PERSISTENT_FLAG]}
	var mixed_out := Fighter.without_flags(mixed, round_level)
	violations.append_array(
		_expect(
			mixed_out["status_flags"] == [7, PERSISTENT_FLAG],
			"without_flags() must leave a non-String entry alone rather than dropping it"
		)
	)

	return violations

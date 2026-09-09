## Tests spec §5.3's Power Step from the rules side: `PowerStep`,
## `PowerStepPassAction`, and the `GameState` slot the two of them write.
##
## No gate is involved and no game-side type is named anywhere in this file.
## That omission is deliberate rather than an oversight, exactly as
## `rules/tests/pass_action_test.gd`'s docstring explains: this suite lives
## under `rules/`, which names no `res://scripts/` type at all, so every
## assertion about *who may submit a pass* lives in
## `tests/power_step_gate_test.gd` instead. What is here is what a pass does
## once it has reached `resolve()`.
##
## **The `turns_taken` assertions are the point of the suite.** Spec §5.3 says
## a Turn is not over until its Power Step has ended, so a resolved core action
## must leave the counter alone and the second pass in a row must raise it by
## exactly one. Both directions are asserted below.
##
## New assertions about the Power Step land here rather than in
## `rules/tests/game_state_test.gd`, which sits at `.gdlintrc`'s 1000-line cap.
class_name PowerStepTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_fresh_state_has_no_open_step())
	violations.append_array(_test_note_action_opens_and_is_idempotent())
	violations.append_array(_test_two_passes_end_the_step_and_count_the_turn())
	violations.append_array(_test_each_refusal_in_order_changes_nothing())
	violations.append_array(_test_an_action_between_two_passes_resets_the_count())
	violations.append_array(_test_nothing_here_touches_the_generator())
	violations.append_array(_test_the_power_step_survives_a_round_trip())
	violations.append_array(_test_from_dict_refuses_every_malformed_shape())
	violations.append_array(_test_power_step_passes_returns_a_copy())

	if violations.is_empty():
		return true

	printerr("\n=== Power Step Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## `ids` as an `Array[String]`, for comparing against `power_step_passes()`.
## A helper rather than an inline cast: `==` binds tighter than `as`, so
## `passes() == ["p1"] as Array[String]` casts the comparison rather than the
## literal and does not compile.
static func _record(ids: Array) -> Array[String]:
	var out: Array[String] = []
	out.append_array(ids)
	return out


## Two players and one fighter each. The fighters exist only so `PassAction`
## has an actor to resolve against; nothing about a Power Step names one.
static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(7))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	state.add_fighter("f2", {"id": "f2", "owner_id": "p2"})
	return state


static func _test_fresh_state_has_no_open_step() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	violations.append_array(
		_expect(not state.power_step_open, "a fresh state must have no open Power Step")
	)
	violations.append_array(
		_expect(
			state.power_step_passes().is_empty(),
			"a fresh state must have an empty consecutive-pass record"
		)
	)

	return violations


## `note_action()` opens the Step and clears the record, and calling it a
## second time changes nothing -- the idempotence `ChargeAction` relies on when
## it reaches the call both directly and through its Attack half.
static func _test_note_action_opens_and_is_idempotent() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	state.record_power_step_pass("p1")

	PowerStep.note_action(state)

	violations.append_array(
		_expect(state.power_step_open, "note_action() must open the Power Step")
	)
	violations.append_array(
		_expect(
			state.power_step_passes().is_empty(),
			"note_action() must clear the consecutive-pass record"
		)
	)

	var after_first := state.digest()
	PowerStep.note_action(state)

	violations.append_array(
		_expect(
			state.digest() == after_first,
			"a second note_action() in a row must leave the state byte-identical"
		)
	)

	return violations


## One pass leaves the Step open and the counter alone. The second, by the
## other player, closes the Step, clears the record and raises `turns_taken` by
## exactly one.
static func _test_two_passes_end_the_step_and_count_the_turn() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	PowerStep.note_action(state)
	var before_turns := state.turns_taken

	var first := PowerStepPassAction.new("p1").resolve(state)

	violations.append_array(_expect(first.success, "a first pass must resolve successfully"))
	violations.append_array(
		_expect(state.power_step_open, "one pass must leave the Power Step open")
	)
	violations.append_array(
		_expect(
			state.power_step_passes() == _record(["p1"]),
			"one pass must leave exactly that player in the consecutive-pass record"
		)
	)
	violations.append_array(
		_expect(state.turns_taken == before_turns, "one pass must not advance turns_taken")
	)

	var second := PowerStepPassAction.new("p2").resolve(state)

	violations.append_array(_expect(second.success, "a second pass must resolve successfully"))
	violations.append_array(
		_expect(not state.power_step_open, "two passes in a row must close the Power Step")
	)
	violations.append_array(
		_expect(
			state.power_step_passes().is_empty(),
			"ending the Power Step must clear the consecutive-pass record"
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == before_turns + 1,
			"ending the Power Step must raise turns_taken by exactly one"
		)
	)

	return violations


## The three failure constants, each reached in the documented order, each
## leaving `state.digest()` byte-identical.
static func _test_each_refusal_in_order_changes_nothing() -> Array[String]:
	var violations: Array[String] = []

	# No such player, and the Step is closed too: the identity check comes
	# first, so this reports FAILURE_NO_SUCH_PLAYER rather than the other.
	var unknown_state := _build_state()
	var unknown_digest := unknown_state.digest()
	var unknown := PowerStepPassAction.new("nobody").resolve(unknown_state)
	violations.append_array(
		_expect(
			unknown.reason == PowerStepPassAction.FAILURE_NO_SUCH_PLAYER,
			"a pass by a player not in turn_order() must fail with FAILURE_NO_SUCH_PLAYER"
		)
	)
	violations.append_array(
		_expect(
			unknown_state.digest() == unknown_digest,
			"a FAILURE_NO_SUCH_PLAYER pass must leave the state digest byte-identical"
		)
	)

	var closed_state := _build_state()
	var closed_digest := closed_state.digest()
	var closed := PowerStepPassAction.new("p1").resolve(closed_state)
	violations.append_array(
		_expect(
			closed.reason == PowerStepPassAction.FAILURE_STEP_NOT_OPEN,
			"a pass with no open Power Step must fail with FAILURE_STEP_NOT_OPEN"
		)
	)
	violations.append_array(
		_expect(
			closed_state.digest() == closed_digest,
			"a FAILURE_STEP_NOT_OPEN pass must leave the state digest byte-identical"
		)
	)

	var repeat_state := _build_state()
	PowerStep.note_action(repeat_state)
	PowerStepPassAction.new("p1").resolve(repeat_state)
	var repeat_digest := repeat_state.digest()
	var repeat := PowerStepPassAction.new("p1").resolve(repeat_state)
	violations.append_array(
		_expect(
			repeat.reason == PowerStepPassAction.FAILURE_ALREADY_PASSED,
			"a second consecutive pass by the same player must fail with FAILURE_ALREADY_PASSED"
		)
	)
	violations.append_array(
		_expect(
			repeat_state.digest() == repeat_digest,
			"a FAILURE_ALREADY_PASSED pass must leave the state digest byte-identical"
		)
	)

	return violations


## Pass, action, pass: the Step is still open and no Turn has been counted,
## because the resolved command between the two passes made them no longer
## consecutive. The contrast case -- pass, pass, nothing between -- does end
## the Step, and is asserted here beside it so the two cannot drift apart.
static func _test_an_action_between_two_passes_resets_the_count() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	PowerStep.note_action(state)
	var before_turns := state.turns_taken

	PowerStepPassAction.new("p2").resolve(state)
	PassAction.new("f1").resolve(state)
	var third := PowerStepPassAction.new("p2").resolve(state)

	violations.append_array(
		_expect(third.success, "a pass after the opponent acted must resolve successfully")
	)
	violations.append_array(
		_expect(
			state.power_step_open,
			"pass, action, pass must leave the Power Step open -- the passes are not consecutive"
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == before_turns, "pass, action, pass must not advance turns_taken"
		)
	)

	var contrast := _build_state()
	PowerStep.note_action(contrast)
	var contrast_turns := contrast.turns_taken
	PowerStepPassAction.new("p2").resolve(contrast)
	PowerStepPassAction.new("p1").resolve(contrast)

	violations.append_array(
		_expect(
			not contrast.power_step_open,
			"two passes with nothing between them must end the Power Step"
		)
	)
	violations.append_array(
		_expect(
			contrast.turns_taken == contrast_turns + 1,
			"two passes with nothing between them must raise turns_taken by exactly one"
		)
	)

	return violations


## The generator position is untouched by a resolved pass, by a refused pass,
## and by the pass that ends the Step. `DeterministicRng.get_state()` is the
## position, not the seed, so a single hidden draw would move it.
static func _test_nothing_here_touches_the_generator() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	PowerStep.note_action(state)
	var before := state.rng.get_state()

	PowerStepPassAction.new("p1").resolve(state)
	violations.append_array(
		_expect(state.rng.get_state() == before, "a resolved pass must not draw from state.rng")
	)

	PowerStepPassAction.new("p1").resolve(state)
	violations.append_array(
		_expect(state.rng.get_state() == before, "a refused pass must not draw from state.rng")
	)

	PowerStepPassAction.new("p2").resolve(state)
	violations.append_array(
		_expect(
			state.rng.get_state() == before and not state.power_step_open,
			"the pass that ends the Power Step must not draw from state.rng"
		)
	)

	PowerStep.note_action(state)
	violations.append_array(
		_expect(
			state.rng.get_state() == before, "note_action() must not draw from state.rng either"
		)
	)

	return violations


## Both fields survive `to_dict()`/`from_dict()`, in the open-with-one-pass and
## the closed-with-none states alike, and a state whose Power Step differs has
## a different `digest()`.
static func _test_the_power_step_survives_a_round_trip() -> Array[String]:
	var violations: Array[String] = []

	var closed := _build_state()
	var closed_back := GameState.from_dict(closed.to_dict())
	violations.append_array(
		_expect(closed_back != null, "a closed-Power-Step state must round trip")
	)
	violations.append_array(
		_expect(
			closed_back != null and closed_back.digest() == closed.digest(),
			"a closed-Power-Step round trip must reproduce the digest"
		)
	)

	var open_state := _build_state()
	PowerStep.note_action(open_state)
	PowerStepPassAction.new("p2").resolve(open_state)
	var open_back := GameState.from_dict(open_state.to_dict())
	violations.append_array(
		_expect(open_back != null, "an open-Power-Step state with one pass must round trip")
	)
	violations.append_array(
		_expect(
			open_back != null and open_back.power_step_open,
			"the round trip must restore power_step_open"
		)
	)
	violations.append_array(
		_expect(
			open_back != null and open_back.power_step_passes() == _record(["p2"]),
			"the round trip must restore the consecutive-pass record, in order"
		)
	)
	violations.append_array(
		_expect(
			open_back != null and open_back.digest() == open_state.digest(),
			"an open-Power-Step round trip must reproduce the digest"
		)
	)

	violations.append_array(
		_expect(
			open_state.digest() != closed.digest(),
			"two states differing only in their Power Step must have different digests"
		)
	)

	# The record alone is enough to move the digest, with the flag held equal.
	var one_pass := _build_state()
	PowerStep.note_action(one_pass)
	var no_pass_digest := one_pass.digest()
	one_pass.record_power_step_pass("p1")
	violations.append_array(
		_expect(
			one_pass.digest() != no_pass_digest,
			"recording a pass must change the digest even with power_step_open unchanged"
		)
	)

	# The shape a JSON round trip produces must be the shape from_dict() takes.
	var parsed: Variant = JSON.parse_string(JSON.stringify(open_state.to_dict()))
	var reparsed := GameState.from_dict(parsed)
	violations.append_array(
		_expect(
			reparsed != null and reparsed.digest() == open_state.digest(),
			"a round trip through JSON.parse_string() must reproduce the digest"
		)
	)

	return violations


## Every malformed shape `from_dict()`'s refusal list names, each required to
## produce `null` rather than a repaired state.
static func _test_from_dict_refuses_every_malformed_shape() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	PowerStep.note_action(state)
	state.record_power_step_pass("p1")

	var cases := {
		"a missing power_step_open": _without(state, "power_step_open"),
		"a non-bool power_step_open": _with(state, "power_step_open", "true"),
		"a missing power_step_passes": _without(state, "power_step_passes"),
		"a non-array power_step_passes": _with(state, "power_step_passes", "p1"),
		"a non-String entry": _with(state, "power_step_passes", [7]),
		"an entry naming no player": _with(state, "power_step_passes", ["p3"]),
		"an empty entry": _with(state, "power_step_passes", [""]),
		"a repeated entry": _with(state, "power_step_passes", ["p1", "p1"]),
	}

	for description in cases:
		violations.append_array(
			_expect(
				GameState.from_dict(cases[description]) == null,
				"from_dict() must return null for %s" % description
			)
		)

	# The negative control: the same dictionary, unmodified, must restore.
	# Without it every case above could pass vacuously.
	violations.append_array(
		_expect(
			GameState.from_dict(state.to_dict()) != null,
			"the unmodified dictionary must still restore"
		)
	)

	return violations


## `state.to_dict()` with `key` replaced by `value`.
static func _with(state: GameState, key: String, value: Variant) -> Dictionary:
	var data := state.to_dict()
	data[key] = value
	return data


## `state.to_dict()` with `key` removed entirely.
static func _without(state: GameState, key: String) -> Dictionary:
	var data := state.to_dict()
	data.erase(key)
	return data


## The record is handed back as a copy, so editing the returned array cannot
## reach the state -- the guarantee `turn_order()` and `fighter_ids()` give.
static func _test_power_step_passes_returns_a_copy() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	state.record_power_step_pass("p1")

	var handed_back := state.power_step_passes()
	handed_back.append("p2")
	handed_back.append("p2")

	violations.append_array(
		_expect(
			state.power_step_passes() == _record(["p1"]),
			"mutating the array power_step_passes() returned must not change the state"
		)
	)

	violations.append_array(
		_expect(
			not state.record_power_step_pass("nobody"),
			"record_power_step_pass() must refuse a player not in turn_order()"
		)
	)
	violations.append_array(
		_expect(
			not state.record_power_step_pass(""), "record_power_step_pass() must refuse an empty id"
		)
	)
	violations.append_array(
		_expect(
			state.power_step_passes() == _record(["p1"]),
			"a refused record_power_step_pass() must change nothing"
		)
	)

	state.clear_power_step_passes()
	violations.append_array(
		_expect(
			state.power_step_passes().is_empty(), "clear_power_step_passes() must empty the record"
		)
	)

	return violations

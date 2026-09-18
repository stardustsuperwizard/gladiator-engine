## Tests `Activation`: `record()`'s once-per-round write, its refusal of an
## unknown fighter id, its idempotence, and `has_activated()`'s read side.
##
## No gate is involved and no game-side type is named anywhere in this file --
## this suite lives under `rules/`, matching `power_step_test.gd`'s own
## reasoning: `Activation` names no requester and answers no permission
## question, so there is nothing here for a gate test to add.
##
## Fixtures are minimal fighter payloads built by hand, the same shape
## `power_step_test.gd`'s `_build_state()` uses -- `Activation` reads and
## writes only `"status_flags"`, so a payload need carry nothing else to
## exercise it.
class_name ActivationTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_record_sets_the_flag_on_a_known_fighter())
	violations.append_array(_test_record_flags_only_the_named_fighter())
	violations.append_array(_test_record_preserves_every_other_payload_field())
	violations.append_array(_test_record_refuses_an_unknown_fighter_id())
	violations.append_array(_test_record_is_idempotent())
	violations.append_array(_test_has_activated_reports_presence_and_absence())
	violations.append_array(_test_has_activated_is_false_for_an_unknown_fighter_id())
	violations.append_array(_test_has_activated_never_changes_the_digest())

	if violations.is_empty():
		return true

	printerr("\n=== Activation Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Two players, one fighter each, neither carrying any status flag yet.
static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(7))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1", "damage_counter": 0, "status_flags": []})
	state.add_fighter("f2", {"id": "f2", "owner_id": "p2", "damage_counter": 0, "status_flags": []})
	return state


static func _test_record_sets_the_flag_on_a_known_fighter() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	violations.append_array(
		_expect(Activation.record(state, "f1"), "record() must return true for a known fighter")
	)
	violations.append_array(
		_expect(
			Fighter.has_flag(state.fighter("f1"), Activation.FLAG_ACTIVATED),
			'record() must leave "activated" on the named fighter\'s stored payload'
		)
	)

	return violations


static func _test_record_flags_only_the_named_fighter() -> Array[String]:
	var state := _build_state()
	Activation.record(state, "f1")

	return _expect(
		not Fighter.has_flag(state.fighter("f2"), Activation.FLAG_ACTIVATED),
		"record() must not flag any fighter other than the one named"
	)


static func _test_record_preserves_every_other_payload_field() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var before := state.fighter("f1")

	Activation.record(state, "f1")
	var after := state.fighter("f1")

	for key in before.keys():
		if key == "status_flags":
			continue
		violations.append_array(
			_expect(after[key] == before[key], 'record() must leave "%s" untouched' % key)
		)

	return violations


static func _test_record_refuses_an_unknown_fighter_id() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var digest_before := state.digest()

	violations.append_array(
		_expect(
			not Activation.record(state, "no-such-fighter"),
			"record() must return false for a fighter id the state does not hold"
		)
	)
	violations.append_array(
		_expect(
			state.digest() == digest_before,
			"a refused record() must leave the state digest byte-identical"
		)
	)

	return violations


## `ChargeAction` composes `AttackAction`, so the same fighter id reaches
## `record()` twice in one resolved Charge. The second call must add no second
## entry and must leave the digest exactly where the first call left it.
static func _test_record_is_idempotent() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	violations.append_array(
		_expect(Activation.record(state, "f1"), "the first record() must succeed")
	)
	var digest_after_first := state.digest()

	violations.append_array(
		_expect(Activation.record(state, "f1"), "a second record() must also return true")
	)
	violations.append_array(
		_expect(
			state.digest() == digest_after_first,
			"a second record() for the same fighter must leave the digest unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.fighter("f1")["status_flags"] == [Activation.FLAG_ACTIVATED],
			"a second record() must not add a duplicate activated entry"
		)
	)

	return violations


static func _test_has_activated_reports_presence_and_absence() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	violations.append_array(
		_expect(
			not Activation.has_activated(state, "f1"),
			"has_activated() must report false before record() has run"
		)
	)

	Activation.record(state, "f1")

	violations.append_array(
		_expect(
			Activation.has_activated(state, "f1"),
			"has_activated() must report true for a fighter record() has flagged"
		)
	)
	violations.append_array(
		_expect(
			not Activation.has_activated(state, "f2"),
			"has_activated() must report false for a fighter that was never recorded"
		)
	)

	return violations


static func _test_has_activated_is_false_for_an_unknown_fighter_id() -> Array[String]:
	var state := _build_state()

	return _expect(
		not Activation.has_activated(state, "no-such-fighter"),
		"has_activated() must report false for a fighter id the state does not hold"
	)


static func _test_has_activated_never_changes_the_digest() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	Activation.record(state, "f1")
	var digest_before := state.digest()

	Activation.has_activated(state, "f1")
	violations.append_array(
		_expect(
			state.digest() == digest_before,
			"has_activated() on a recorded fighter must not change the digest"
		)
	)

	Activation.has_activated(state, "f2")
	violations.append_array(
		_expect(
			state.digest() == digest_before,
			"has_activated() on an unrecorded fighter must not change the digest"
		)
	)

	Activation.has_activated(state, "no-such-fighter")
	violations.append_array(
		_expect(
			state.digest() == digest_before,
			"has_activated() on an unknown fighter id must not change the digest"
		)
	)

	return violations

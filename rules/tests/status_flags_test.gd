## Tests `StatusFlags`: the three constants' literal values, that the three
## re-exports on `MoveAction`, `GuardAction` and `ChargeLockout` still equal
## them, that `round_level()` publishes exactly the three and nothing else as
## a fresh copy every call, and that a `Fighter` round-trips a flag set by name
## from this class through serialization.
##
## Every fixture `FighterTemplate` here is built in memory with `.new()` --
## this suite lives under `rules/` and `extraction_contract_test.gd` forbids
## naming an authored content path.
class_name StatusFlagsTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_constants_hold_expected_literals())
	violations.append_array(_test_reexports_equal_canonical_constants())
	violations.append_array(_test_round_level_holds_exactly_the_three())
	violations.append_array(_test_round_level_returns_fresh_array_each_call())
	violations.append_array(_test_round_level_entries_are_plain_strings())
	violations.append_array(_test_fighter_round_trips_a_status_flags_flag())

	if violations.is_empty():
		return true

	printerr("\n=== Status Flags Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "fixture-fighter"
	template.move = 1
	template.save = 5
	template.health = 5
	template.range_hexes = 1
	template.attack = 3
	template.damage = 1
	return template


static func _test_constants_hold_expected_literals() -> Array[String]:
	var violations: Array[String] = []
	violations.append_array(
		_expect(StatusFlags.MOVED == "moved", 'StatusFlags.MOVED must equal "moved"')
	)
	violations.append_array(
		_expect(StatusFlags.GUARDED == "guarded", 'StatusFlags.GUARDED must equal "guarded"')
	)
	violations.append_array(
		_expect(StatusFlags.CHARGED == "charged", 'StatusFlags.CHARGED must equal "charged"')
	)
	return violations


static func _test_reexports_equal_canonical_constants() -> Array[String]:
	var violations: Array[String] = []
	violations.append_array(
		_expect(
			MoveAction.FLAG_MOVED == StatusFlags.MOVED,
			"MoveAction.FLAG_MOVED must equal StatusFlags.MOVED"
		)
	)
	violations.append_array(
		_expect(
			GuardAction.FLAG_GUARDED == StatusFlags.GUARDED,
			"GuardAction.FLAG_GUARDED must equal StatusFlags.GUARDED"
		)
	)
	violations.append_array(
		_expect(
			ChargeLockout.FLAG_CHARGED == StatusFlags.CHARGED,
			"ChargeLockout.FLAG_CHARGED must equal StatusFlags.CHARGED"
		)
	)
	return violations


static func _test_round_level_holds_exactly_the_three() -> Array[String]:
	var violations: Array[String] = []
	var flags := StatusFlags.round_level()

	violations.append_array(
		_expect(
			flags.size() == 3,
			"round_level() must hold exactly three entries, got %d" % flags.size()
		)
	)
	violations.append_array(
		_expect(StatusFlags.MOVED in flags, "round_level() must include StatusFlags.MOVED")
	)
	violations.append_array(
		_expect(StatusFlags.GUARDED in flags, "round_level() must include StatusFlags.GUARDED")
	)
	violations.append_array(
		_expect(StatusFlags.CHARGED in flags, "round_level() must include StatusFlags.CHARGED")
	)

	return violations


static func _test_round_level_returns_fresh_array_each_call() -> Array[String]:
	var first := StatusFlags.round_level()
	first.append("intruder")
	first.clear()

	var second := StatusFlags.round_level()
	return _expect(
		second.size() == 3,
		(
			"round_level() must return a fresh array each call -- mutating a previous result must "
			+ "not affect the next call, got size %d" % second.size()
		)
	)


static func _test_round_level_entries_are_plain_strings() -> Array[String]:
	var violations: Array[String] = []
	for flag in StatusFlags.round_level():
		(
			violations
			. append_array(
				_expect(
					typeof(flag) == TYPE_STRING,
					(
						"every round_level() entry must be TYPE_STRING, not StringName -- got typeof() %d for %s"
						% [typeof(flag), flag]
					)
				)
			)
		)
	return violations


static func _test_fighter_round_trips_a_status_flags_flag() -> Array[String]:
	var template := _template()
	var fighter := Fighter.new("fixture", template, "p1", Vector3i(0, 0, 0))
	fighter.set_status_flag(StatusFlags.GUARDED)

	var round_tripped := Fighter.from_dict(fighter.to_dict(), template)

	return _expect(
		round_tripped != null and round_tripped.has_status_flag(StatusFlags.GUARDED),
		"a Fighter must round-trip a flag set by name from StatusFlags through to_dict()/from_dict()"
	)

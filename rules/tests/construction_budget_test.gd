## Tests ConstructionBudget: the 15-point construction budget for fighter authoring.
##
## Tests `is_satisfied_by()` with templates that pass the budget, ones that fail
## on total points (too low or too high), ones that fail on individual stat
## bounds, and a null template. Tests `violations()` for empty results when a
## template passes, and for human-readable violation messages when it fails.
class_name ConstructionBudgetTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_is_satisfied_by_null_returns_false())
	violations.append_array(_test_is_satisfied_by_passing_template_returns_true())
	violations.append_array(_test_is_satisfied_by_total_too_low_returns_false())
	violations.append_array(_test_is_satisfied_by_total_too_high_returns_false())
	violations.append_array(_test_is_satisfied_by_stat_below_minimum_returns_false())
	violations.append_array(_test_is_satisfied_by_stat_above_maximum_returns_false())
	violations.append_array(_test_violations_empty_when_template_passes())
	violations.append_array(_test_violations_contains_message_for_each_failing_stat())
	violations.append_array(_test_violations_contains_message_for_wrong_total())
	violations.append_array(_test_violations_null_returns_single_message())

	if violations.is_empty():
		return true

	printerr("\n=== Construction Budget Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_is_satisfied_by_null_returns_false() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	return _expect(
		not budget.is_satisfied_by(null),
		"is_satisfied_by(null) must return false"
	)


static func _test_is_satisfied_by_passing_template_returns_true() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 1, 3, 2)  # 4+2+3+1+3+2 = 15
	return _expect(
		budget.is_satisfied_by(template),
		"is_satisfied_by() must return true for a template with stats totalling exactly 15 within [1, 5]"
	)


static func _test_is_satisfied_by_total_too_low_returns_false() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 1, 2, 2)  # 4+2+3+1+2+2 = 14
	return _expect(
		not budget.is_satisfied_by(template),
		"is_satisfied_by() must return false for a template totalling 14 (below 15)"
	)


static func _test_is_satisfied_by_total_too_high_returns_false() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 1, 3, 3)  # 4+2+3+1+3+3 = 16
	return _expect(
		not budget.is_satisfied_by(template),
		"is_satisfied_by() must return false for a template totalling 16 (above 15)"
	)


static func _test_is_satisfied_by_stat_below_minimum_returns_false() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 0, 3, 3)  # range_hexes = 0, below minimum 1
	return _expect(
		not budget.is_satisfied_by(template),
		"is_satisfied_by() must return false for a template with a stat below the minimum"
	)


static func _test_is_satisfied_by_stat_above_maximum_returns_false() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 1, 3, 6)  # damage = 6, above maximum 5
	return _expect(
		not budget.is_satisfied_by(template),
		"is_satisfied_by() must return false for a template with a stat above the maximum"
	)


static func _test_violations_empty_when_template_passes() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 1, 3, 2)  # 4+2+3+1+3+2 = 15
	return _expect(
		budget.violations(template).is_empty(),
		"violations() must return an empty array for a template that passes the budget"
	)


static func _test_violations_contains_message_for_each_failing_stat() -> Array[String]:
	var violations_array: Array[String] = []
	var budget := _make_budget(15, 1, 5)

	# Stat below minimum: range_hexes = 0
	var template_below := _make_template(4, 2, 3, 0, 3, 3)
	var msgs_below := budget.violations(template_below)
	violations_array.append_array(
		_expect(msgs_below.size() >= 1, "violations() must report stat below minimum")
	)
	violations_array.append_array(
		_expect(
			_contains_substring(msgs_below, "range_hexes"),
			"violations() must name the stat that is below minimum"
		)
	)

	# Stat above maximum: damage = 6
	var template_above := _make_template(4, 2, 3, 1, 3, 6)
	var msgs_above := budget.violations(template_above)
	violations_array.append_array(
		_expect(msgs_above.size() >= 1, "violations() must report stat above maximum")
	)
	violations_array.append_array(
		_expect(
			_contains_substring(msgs_above, "damage"),
			"violations() must name the stat that is above maximum"
		)
	)

	return violations_array as Array[String]


static func _test_violations_contains_message_for_wrong_total() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var template := _make_template(4, 2, 3, 1, 2, 2)  # 4+2+3+1+2+2 = 14
	var msgs := budget.violations(template)
	return _expect(
		_contains_substring(msgs, "total"),
		"violations() must report when the total does not equal the budget"
	)


static func _test_violations_null_returns_single_message() -> Array[String]:
	var budget := _make_budget(15, 1, 5)
	var msgs := budget.violations(null)
	return _expect(
		msgs.size() == 1 and msgs[0] == "template is null",
		"violations(null) must return a single message saying the template is null"
	)


## Helper: creates a FighterTemplate with the given stats.
static func _make_template(
	move: int,
	save: int,
	health: int,
	range_hexes: int,
	attack: int,
	damage: int
) -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "test"
	template.display_name = "Test Fighter"
	template.move = move
	template.save = save
	template.health = health
	template.range_hexes = range_hexes
	template.attack = attack
	template.damage = damage
	return template


## Helper: creates a ConstructionBudget with the given values.
static func _make_budget(total_points: int, min_per_stat: int, max_per_stat: int) -> ConstructionBudget:
	var budget := ConstructionBudget.new()
	budget.budget_id = "test"
	budget.total_points = total_points
	budget.min_per_stat = min_per_stat
	budget.max_per_stat = max_per_stat
	return budget


## Helper: returns true if any string in the array contains the substring.
static func _contains_substring(array: PackedStringArray, substring: String) -> bool:
	for s in array:
		if substring in s:
			return true
	return false

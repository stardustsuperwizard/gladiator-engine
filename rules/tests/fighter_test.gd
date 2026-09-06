## Tests the runtime Fighter's behaviour: mutable state over a shared
## FighterTemplate, the spec §9 damage predicates at every boundary, and the
## opaque status-flag set. Serialization is FighterSerializationTest, split off
## for the same reason Board's is -- one file was approaching .gdlintrc's
## 1000-line ceiling, which is deliberately not raisable.
##
## The shared-template test is the one this type exists for. Godot caches and
## shares Resource instances, so the bug worth catching is a fighter writing
## through to its template -- and an isolation test alone cannot catch it,
## because a design that quietly duplicated the template per fighter would pass
## isolation while discarding everything the sharing is for. So the sharing is
## asserted first, by object identity, and the isolation second.
##
## Every template here is built in memory with .new(). This suite lives under
## rules/ and extraction_contract_test.gd forbids naming an authored content
## path, so it may not load a .tres; authored content is sibling task #32.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail once
## during development before the implementation made it pass.
class_name FighterTest

## The values make_template() authors, named so the "the template did not
## change" assertions compare against something other than a re-read of the
## template itself. Public alongside make_template(), for the same reason.
const TEMPLATE_ID := "test-fighter"
const DISPLAY_NAME := "Test Fighter"
const MOVE := 3
const SAVE := 4
const POINT_VALUE := 6
const TAG := "elite"
const MELEE_WEAPON_ID := "test-blade"
const MELEE_DAMAGE := 2
const RANGED_WEAPON_ID := "test-bow"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_accessors_report_construction_and_template())
	violations.append_array(_test_two_fighters_share_one_template())
	violations.append_array(_test_mutation_leaves_every_template_field_unchanged())
	violations.append_array(_test_weapons_returns_a_shallow_copy())
	violations.append_array(_test_status_flags_returns_a_copy())
	violations.append_array(_test_damage_truth_table_at_every_boundary())
	violations.append_array(_test_damage_truth_table_for_one_health())
	violations.append_array(_test_defeated_fighter_is_also_vulnerable())
	violations.append_array(_test_apply_damage_refuses_non_positive_and_accumulates())
	violations.append_array(_test_move_to_validates_the_coordinate())
	violations.append_array(_test_status_flags_are_an_insertion_ordered_set())

	if violations.is_empty():
		return true

	printerr("\n=== Fighter Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A fully populated FighterTemplate with `health` health, built in memory.
##
## Public because FighterSerializationTest builds its fighters over the same
## template rather than keeping a second, drifting copy of these values -- the
## same reason ExtractionContractTest.files_recursive() is public.
static func make_template(health: int) -> FighterTemplate:
	var blade := WeaponTemplate.new()
	blade.template_id = MELEE_WEAPON_ID
	blade.range_hexes = 1
	blade.dice_count = 3
	blade.damage_value = MELEE_DAMAGE
	blade.weapon_type = WeaponTemplate.MELEE
	blade.ability_tags = PackedStringArray(["reach"])

	var bow := WeaponTemplate.new()
	bow.template_id = RANGED_WEAPON_ID
	bow.range_hexes = 4
	bow.dice_count = 2
	bow.damage_value = 1
	bow.weapon_type = WeaponTemplate.RANGED

	var template := FighterTemplate.new()
	template.template_id = TEMPLATE_ID
	template.display_name = DISPLAY_NAME
	template.move = MOVE
	template.save = SAVE
	template.health = health
	template.point_value = POINT_VALUE
	template.weapons = [blade, bow] as Array[WeaponTemplate]
	template.tags = PackedStringArray([TAG])
	return template


## Every field of a make_template() result, still as authored. Field by field
## rather than as one snapshot comparison, so a failure names what moved.
## Public for the same reason make_template() is.
static func expect_template_unchanged(
	template: FighterTemplate, expected_health: int, context: String
) -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(template.template_id == TEMPLATE_ID, "%s must leave template.template_id" % context)
	)
	violations.append_array(
		_expect(
			template.display_name == DISPLAY_NAME, "%s must leave template.display_name" % context
		)
	)
	violations.append_array(_expect(template.move == MOVE, "%s must leave template.move" % context))
	violations.append_array(_expect(template.save == SAVE, "%s must leave template.save" % context))
	violations.append_array(
		_expect(template.health == expected_health, "%s must leave template.health" % context)
	)
	violations.append_array(
		_expect(template.point_value == POINT_VALUE, "%s must leave template.point_value" % context)
	)
	violations.append_array(
		_expect(template.tags == PackedStringArray([TAG]), "%s must leave template.tags" % context)
	)
	violations.append_array(
		_expect(template.weapons.size() == 2, "%s must leave template.weapons' size" % context)
	)
	if template.weapons.size() != 2:
		return violations

	violations.append_array(
		_expect(
			template.weapons[0].template_id == MELEE_WEAPON_ID,
			"%s must leave template.weapons[0]" % context
		)
	)
	violations.append_array(
		_expect(
			template.weapons[1].template_id == RANGED_WEAPON_ID,
			"%s must leave template.weapons[1]" % context
		)
	)
	violations.append_array(
		_expect(
			template.weapons[0].damage_value == MELEE_DAMAGE,
			"%s must leave template.weapons[0].damage_value" % context
		)
	)

	return violations


static func _test_accessors_report_construction_and_template() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var start := Vector3i(1, -1, 0)
	var fighter := Fighter.new("fighter-1", template, "player-1", start)

	violations.append_array(_expect(fighter.id() == "fighter-1", "id() must report the id given"))
	violations.append_array(
		_expect(fighter.owner_id() == "player-1", "owner_id() must report the owner given")
	)
	violations.append_array(
		_expect(fighter.template() == template, "template() must report the template given")
	)
	violations.append_array(
		_expect(fighter.position() == start, "position() must report the start position given")
	)
	violations.append_array(_expect(fighter.move() == MOVE, "move() must read through to template"))
	violations.append_array(_expect(fighter.save() == SAVE, "save() must read through to template"))
	violations.append_array(
		_expect(fighter.health() == 3, "health() must read through to the template")
	)
	violations.append_array(
		_expect(fighter.point_value() == POINT_VALUE, "point_value() must read through")
	)
	violations.append_array(
		_expect(fighter.weapons().size() == 2, "weapons() must report the template's weapons")
	)
	violations.append_array(
		_expect(fighter.damage_counter() == 0, "a new fighter must start on damage counter 0")
	)
	violations.append_array(
		_expect(fighter.status_flags().is_empty(), "a new fighter must start with no status flags")
	)

	return violations


## The shared-template trap, both halves.
##
## The identity assertion comes first and is not optional: without it this test
## would pass just as happily against a Fighter that duplicated its template per
## instance, and would therefore not be testing the trap at all.
static func _test_two_fighters_share_one_template() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var a := Fighter.new("fighter-a", template, "player-1", Vector3i.ZERO)
	var b := Fighter.new("fighter-b", template, "player-2", Vector3i(1, -1, 0))

	violations.append_array(
		_expect(
			a.template() == b.template(),
			(
				"two fighters built from one FighterTemplate must hold the identical object -- "
				+ "a per-fighter duplicate would make the isolation assertions below vacuous"
			)
		)
	)
	violations.append_array(
		_expect(a.template() == template, "template() must be the template passed to _init()")
	)

	a.apply_damage(2)

	violations.append_array(
		_expect(a.damage_counter() == 2, "the damaged fighter's counter must be 2")
	)
	violations.append_array(
		_expect(
			b.damage_counter() == 0,
			(
				"damaging one fighter must leave the other on counter 0 -- a counter written "
				+ "through to the shared template would damage every fighter sharing it"
			)
		)
	)
	violations.append_array(
		expect_template_unchanged(template, 3, "damaging a fighter built from a template")
	)

	violations.append_array(
		_expect(a.health() == b.health(), "both fighters must still agree on health()")
	)
	violations.append_array(
		_expect(a.move() == b.move(), "both fighters must still agree on move()")
	)
	violations.append_array(
		_expect(a.save() == b.save(), "both fighters must still agree on save()")
	)
	violations.append_array(
		_expect(
			a.point_value() == b.point_value(), "both fighters must still agree on point_value()"
		)
	)
	violations.append_array(
		_expect(
			a.weapons() == b.weapons(), "both fighters must still agree on the weapons they carry"
		)
	)

	return violations


static func _test_mutation_leaves_every_template_field_unchanged() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(2)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)

	fighter.move_to(Vector3i(3, -2, -1))
	fighter.set_status_flag("moved")
	fighter.set_status_flag("guarded")
	fighter.clear_status_flag("moved")
	fighter.apply_damage(5)

	violations.append_array(
		expect_template_unchanged(
			template, 2, "moving, flagging and damaging a fighter (all of it together)"
		)
	)

	return violations


static func _test_weapons_returns_a_shallow_copy() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)

	var returned := fighter.weapons()
	returned.append(WeaponTemplate.new())

	violations.append_array(
		_expect(
			fighter.template().weapons.size() == 2,
			"appending to the array weapons() returned must not reach the template's array"
		)
	)
	violations.append_array(
		_expect(fighter.weapons().size() == 2, "a second weapons() call must not see the append")
	)

	# Shallow, and deliberately: the elements are the template's own immutable
	# WeaponTemplates, shared rather than copied.
	var fresh := fighter.weapons()
	violations.append_array(
		_expect(
			fresh[0] == template.weapons[0],
			"weapons()[0] must be the identical WeaponTemplate object the template holds"
		)
	)
	violations.append_array(
		_expect(
			fresh[1] == template.weapons[1],
			"weapons()[1] must be the identical WeaponTemplate object the template holds"
		)
	)

	return violations


static func _test_status_flags_returns_a_copy() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)
	fighter.set_status_flag("moved")

	var returned := fighter.status_flags()
	returned.append("charged")
	returned.remove_at(0)

	violations.append_array(
		_expect(
			fighter.status_flags() == (["moved"] as Array[String]),
			"mutating the array status_flags() returned must not change what a second call returns"
		)
	)
	violations.append_array(
		_expect(
			not fighter.has_status_flag("charged"),
			"appending to the array status_flags() returned must not set a flag"
		)
	)

	return violations


## Spec §9's four predicates at every boundary of a health-3 template: counters
## 0, 1, 2, 3 and 4, all four predicates at each, twenty assertions.
static func _test_damage_truth_table_at_every_boundary() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)

	# counter -> [undamaged, damaged, vulnerable, defeated], worked out by hand
	# against spec §9 rather than recomputed from the implementation's own
	# formulas. Counter 3 is health exactly; counter 4 is past it, which
	# apply_damage() deliberately does not clamp.
	var expected := {
		0: [true, false, false, false],
		1: [false, true, false, false],
		2: [false, true, true, false],
		3: [false, true, true, true],
		4: [false, true, true, true],
	}

	for counter: int in [0, 1, 2, 3, 4]:
		var fighter := Fighter.new("fighter-%d" % counter, template, "player-1", Vector3i.ZERO)
		if counter > 0:
			fighter.apply_damage(counter)

		var row: Array = expected[counter]

		violations.append_array(
			_expect(
				fighter.is_undamaged() == row[0],
				"health 3, counter %d: is_undamaged() must be %s" % [counter, row[0]]
			)
		)
		violations.append_array(
			_expect(
				fighter.is_damaged() == row[1],
				"health 3, counter %d: is_damaged() must be %s" % [counter, row[1]]
			)
		)
		violations.append_array(
			_expect(
				fighter.is_vulnerable() == row[2],
				"health 3, counter %d: is_vulnerable() must be %s" % [counter, row[2]]
			)
		)
		violations.append_array(
			_expect(
				fighter.is_defeated() == row[3],
				"health 3, counter %d: is_defeated() must be %s" % [counter, row[3]]
			)
		)

	return violations


## The health-1 case, pinned separately because it is where "undamaged" and
## "vulnerable" overlap.
static func _test_damage_truth_table_for_one_health() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(1)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)

	var overlap := (
		"health 1, counter 0: a one-health fighter is BOTH undamaged AND vulnerable, and that "
		+ "overlap is intended, not a bug -- it is untouched, and one point would defeat it. "
		+ "Do not 'correct' is_vulnerable() to exclude it"
	)

	violations.append_array(_expect(fighter.is_undamaged(), overlap))
	violations.append_array(_expect(fighter.is_vulnerable(), overlap))
	violations.append_array(
		_expect(not fighter.is_damaged(), "health 1, counter 0: is_damaged() must be false")
	)
	violations.append_array(
		_expect(not fighter.is_defeated(), "health 1, counter 0: is_defeated() must be false")
	)

	fighter.apply_damage(1)

	violations.append_array(
		_expect(not fighter.is_undamaged(), "health 1, counter 1: is_undamaged() must be false")
	)
	violations.append_array(
		_expect(fighter.is_damaged(), "health 1, counter 1: is_damaged() must be true")
	)
	violations.append_array(
		_expect(fighter.is_vulnerable(), "health 1, counter 1: is_vulnerable() must be true")
	)
	violations.append_array(
		_expect(fighter.is_defeated(), "health 1, counter 1: is_defeated() must be true")
	)

	return violations


static func _test_defeated_fighter_is_also_vulnerable() -> Array[String]:
	var template := make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)
	fighter.apply_damage(4)

	if not fighter.is_defeated():
		return ["a fighter on counter 4 of health 3 must be defeated"]

	return _expect(
		fighter.is_vulnerable(),
		(
			"a defeated fighter must also report is_vulnerable() -- c >= H implies c + 1 >= H, "
			+ "and that overlap is intended. The four predicates are independent descriptions, "
			+ "not a partition, so do not add a precedence rule to separate them"
		)
	)


static func _test_apply_damage_refuses_non_positive_and_accumulates() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)

	fighter.apply_damage(1)

	violations.append_array(
		_expect(not fighter.apply_damage(0), "apply_damage(0) must return false")
	)
	violations.append_array(
		_expect(fighter.damage_counter() == 1, "apply_damage(0) must leave the counter alone")
	)
	violations.append_array(
		_expect(not fighter.apply_damage(-1), "apply_damage(-1) must return false")
	)
	violations.append_array(
		_expect(
			fighter.damage_counter() == 1,
			"apply_damage(-1) must leave the counter alone -- this is not a healing API"
		)
	)

	violations.append_array(_expect(fighter.apply_damage(2), "apply_damage(2) must return true"))
	violations.append_array(_expect(fighter.apply_damage(3), "apply_damage(3) must return true"))
	violations.append_array(
		_expect(
			fighter.damage_counter() == 6,
			(
				"apply_damage() must accumulate across calls, and must not clamp at health -- "
				+ "6 on a health-3 template is legitimate state"
			)
		)
	)

	return violations


static func _test_move_to_validates_the_coordinate() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var start := Vector3i(1, -1, 0)
	var fighter := Fighter.new("fighter-1", template, "player-1", start)

	var invalid := Vector3i(1, 1, 1)

	violations.append_array(
		_expect(not HexCoord.is_valid(invalid), "the test's invalid coord must actually be invalid")
	)
	violations.append_array(
		_expect(not fighter.move_to(invalid), "move_to() must return false for an invalid coord")
	)
	violations.append_array(
		_expect(fighter.position() == start, "a refused move_to() must leave the position alone")
	)

	var destination := Vector3i(2, -3, 1)
	violations.append_array(
		_expect(fighter.move_to(destination), "move_to() must return true for a valid cube coord")
	)
	violations.append_array(
		_expect(fighter.position() == destination, "an accepted move_to() must move the fighter")
	)

	return violations


static func _test_status_flags_are_an_insertion_ordered_set() -> Array[String]:
	var violations: Array[String] = []
	var template := make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)

	violations.append_array(
		_expect(not fighter.set_status_flag(""), 'set_status_flag("") must return false')
	)
	violations.append_array(
		_expect(fighter.status_flags().is_empty(), 'a refused set_status_flag("") must set nothing')
	)
	violations.append_array(
		_expect(
			not fighter.clear_status_flag("absent"),
			"clear_status_flag() must return false for a flag that is not set"
		)
	)

	violations.append_array(
		_expect(fighter.set_status_flag("moved"), "a new flag must be accepted")
	)
	violations.append_array(
		_expect(fighter.has_status_flag("moved"), "has_status_flag() must see a flag just set")
	)
	violations.append_array(
		_expect(
			not fighter.set_status_flag("moved"), "set_status_flag() must refuse a duplicate flag"
		)
	)

	fighter.set_status_flag("guarded")
	fighter.set_status_flag("charged")

	violations.append_array(
		_expect(
			fighter.status_flags() == (["moved", "guarded", "charged"] as Array[String]),
			"status_flags() must preserve the order the flags were set in"
		)
	)

	violations.append_array(
		_expect(fighter.clear_status_flag("guarded"), "clearing a set flag must return true")
	)
	violations.append_array(
		_expect(
			not fighter.has_status_flag("guarded"),
			"has_status_flag() must not see a flag that was cleared"
		)
	)
	violations.append_array(
		_expect(
			fighter.status_flags() == (["moved", "charged"] as Array[String]),
			"clearing a flag must leave the remaining flags in their original order"
		)
	)

	return violations

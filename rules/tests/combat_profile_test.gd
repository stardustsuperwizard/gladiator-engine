## CombatProfile tests: verify clamped_target() behavior without loading resources.
## Resource loading and field verification happens in tests/resource_data_test.gd.
class_name CombatProfileTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_attack_ladder())
	violations.append_array(_test_save_ladder())
	violations.append_array(_test_clamped_target_floor_and_ceiling())

	if violations.is_empty():
		return true

	printerr("\n=== Combat Profile Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Create a test profile with standard values and verify attack ladder.
static func _test_attack_ladder() -> Array[String]:
	var violations: Array[String] = []
	var profile = CombatProfile.new()
	profile.profile_id = "test"
	profile.die_sides = 6
	profile.attack_target = 5
	profile.save_target = 5
	profile.engagement_range = 1
	profile.engagement_modifier = 1
	profile.attack_flank_modifier = 1
	profile.attack_surround_modifier = 2
	profile.save_flank_modifier = 2
	profile.save_surround_modifier = 3
	profile.guard_modifier = 1
	profile.min_target = 2
	profile.max_target = 6

	violations.append_array(
		_expect(profile.clamped_target(5, 0) == 5, "clamped_target(5, 0) must be 5")
	)

	violations.append_array(
		_expect(profile.clamped_target(5, -1) == 4, "clamped_target(5, -1) must be 4 (engaged)")
	)

	violations.append_array(
		_expect(
			profile.clamped_target(5, -2) == 3,
			"clamped_target(5, -2) must be 3 (engaged, target flanked)"
		)
	)

	violations.append_array(
		_expect(
			profile.clamped_target(5, -3) == 2,
			"clamped_target(5, -3) must be 2 (engaged, target surrounded)"
		)
	)

	return violations


## Save ladder: guarded, attacker flanked, attacker surrounded, guarded+surrounded.
static func _test_save_ladder() -> Array[String]:
	var violations: Array[String] = []
	var profile = CombatProfile.new()
	profile.profile_id = "test"
	profile.die_sides = 6
	profile.attack_target = 5
	profile.save_target = 5
	profile.engagement_range = 1
	profile.engagement_modifier = 1
	profile.attack_flank_modifier = 1
	profile.attack_surround_modifier = 2
	profile.save_flank_modifier = 2
	profile.save_surround_modifier = 3
	profile.guard_modifier = 1
	profile.min_target = 2
	profile.max_target = 6

	violations.append_array(
		_expect(profile.clamped_target(5, -1) == 4, "clamped_target(5, -1) must be 4 (guarded)")
	)

	violations.append_array(
		_expect(
			profile.clamped_target(5, -2) == 3, "clamped_target(5, -2) must be 3 (attacker flanked)"
		)
	)

	violations.append_array(
		_expect(
			profile.clamped_target(5, -3) == 2,
			"clamped_target(5, -3) must be 2 (attacker surrounded)"
		)
	)

	violations.append_array(
		_expect(
			profile.clamped_target(5, -4) == 2,
			"clamped_target(5, -4) must be 2 (guarded + attacker surrounded, clamped to floor)"
		)
	)

	return violations


## The ceiling and floor clamps work correctly.
static func _test_clamped_target_floor_and_ceiling() -> Array[String]:
	var violations: Array[String] = []
	var profile = CombatProfile.new()
	profile.profile_id = "test"
	profile.die_sides = 6
	profile.attack_target = 5
	profile.save_target = 5
	profile.engagement_range = 1
	profile.engagement_modifier = 1
	profile.attack_flank_modifier = 1
	profile.attack_surround_modifier = 2
	profile.save_flank_modifier = 2
	profile.save_surround_modifier = 3
	profile.guard_modifier = 1
	profile.min_target = 2
	profile.max_target = 6

	violations.append_array(
		_expect(profile.clamped_target(5, 1) == 6, "clamped_target(5, 1) must be 6 (ceiling)")
	)

	violations.append_array(
		_expect(
			profile.clamped_target(5, 99) == 6,
			"clamped_target(5, 99) must be 6 (ceiling holds on large positive)"
		)
	)

	return violations

## Game-side data suite for the four authored `.tres` files under `resources/`:
## `resources/fighters/warrior.tres`, `resources/fighters/archer.tres`,
## `resources/fighters/construction_budget.tres`, and `resources/combat/combat_profile.tres`.
##
## **There were seven.** `resources/weapons/` and `resources/dice/` are gone,
## deleted along with the two resource classes they were authored against:
## spec §3 and §7 as revised 2026-09-08 collapsed the fighter/weapon split into
## the fighter's own six combat stats and replaced symbol-faced dice with d6s
## against a target number. Do not restore either directory by appeal to the
## tabletop original -- see the spec's revision notes.
##
## This suite lives under `tests/`, not `rules/tests/`, because
## `rules/tests/extraction_contract_test.gd` fails the build on any file under
## `rules/` naming `res://resources/`, and it scans test files exactly as it
## scans rules code. Loading the authored roster is therefore ordinary
## game-side code that cannot live under `rules/`.
##
## Every number pinned here is authored content, not a balance decision:
## `AGENTS.md` says outright that dice counts, damage values, and point costs
## are expected to be tuned. Only `_test_field_values_match_authored_content()`
## and `_test_combat_profile_loads_correctly()` name those numbers as
## literals -- they exist to pin what the files contain. Every other test below
## reads its expected values back off a loaded resource and compares runtime
## behaviour against them, never against a second literal, so retuning a
## `.tres` cannot silently break a test that was supposed to be reading the
## file rather than restating it.
class_name ResourceDataTest

const WARRIOR_PATH := "res://resources/fighters/warrior.tres"
const ARCHER_PATH := "res://resources/fighters/archer.tres"
const COMBAT_PROFILE_PATH := "res://resources/combat/combat_profile.tres"
const CONSTRUCTION_BUDGET_PATH := "res://resources/fighters/construction_budget.tres"

## Where the "retuning is a file edit" test saves its duplicated, retuned
## warrior. Never a path under `res://resources/` -- no test may write there.
const RETUNED_WARRIOR_PATH := "user://resource_data_test_retuned_warrior.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_files_load_as_expected_class())
	violations.append_array(_test_field_values_match_authored_content())
	violations.append_array(_test_load_caching_returns_same_object())
	violations.append_array(_test_parent_feature_scenario_end_to_end())
	violations.append_array(_test_fighter_from_warrior_reports_template_stats())
	violations.append_array(_test_fighter_from_archer_reports_template_stats())
	violations.append_array(_test_retuning_is_a_file_edit())
	violations.append_array(_test_combat_profile_loads_correctly())
	violations.append_array(_test_all_fighters_satisfy_construction_budget())

	if violations.is_empty():
		return true

	printerr("\n=== Resource Data Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Each of the three authored paths loads and is an instance of the expected
## class. Asserted with `is`, not merely `!= null`: a `.tres` that lost its
## script reference loads as a bare `Resource`, and `!= null` alone would not
## catch that.
static func _test_files_load_as_expected_class() -> Array[String]:
	var violations: Array[String] = []

	var warrior: Variant = load(WARRIOR_PATH)
	violations.append_array(
		_expect(warrior is FighterTemplate, "warrior.tres must load as a FighterTemplate")
	)

	var archer: Variant = load(ARCHER_PATH)
	violations.append_array(
		_expect(archer is FighterTemplate, "archer.tres must load as a FighterTemplate")
	)

	var profile: Variant = load(COMBAT_PROFILE_PATH)
	violations.append_array(
		_expect(profile is CombatProfile, "combat_profile.tres must load as a CombatProfile")
	)

	return violations


## Field-by-field pin of what the two authored rosters contain. One of the two
## places in this suite where a value from the roster tables appears as a
## literal -- see the class docstring for why that is the deliberate exception.
static func _test_field_values_match_authored_content() -> Array[String]:
	var violations: Array[String] = []

	var warrior := load(WARRIOR_PATH) as FighterTemplate
	violations.append_array(
		_expect(warrior.template_id == "warrior", 'warrior.tres template_id must be "warrior"')
	)
	violations.append_array(
		_expect(warrior.display_name == "Warrior", 'warrior.tres display_name must be "Warrior"')
	)
	violations.append_array(_expect(warrior.move == 4, "warrior.tres move must be 4"))
	violations.append_array(_expect(warrior.save == 2, "warrior.tres save must be 2"))
	violations.append_array(_expect(warrior.health == 3, "warrior.tres health must be 3"))
	violations.append_array(_expect(warrior.range_hexes == 1, "warrior.tres range_hexes must be 1"))
	violations.append_array(_expect(warrior.attack == 3, "warrior.tres attack must be 3"))
	violations.append_array(_expect(warrior.damage == 2, "warrior.tres damage must be 2"))
	violations.append_array(
		_expect(
			warrior.tags == PackedStringArray(["infantry"]),
			'warrior.tres tags must be ["infantry"]'
		)
	)
	violations.append_array(
		_expect(
			warrior.ability_tags == PackedStringArray(["cleave"]),
			'warrior.tres ability_tags must be ["cleave"]'
		)
	)

	var archer := load(ARCHER_PATH) as FighterTemplate
	violations.append_array(
		_expect(archer.template_id == "archer", 'archer.tres template_id must be "archer"')
	)
	violations.append_array(
		_expect(archer.display_name == "Archer", 'archer.tres display_name must be "Archer"')
	)
	violations.append_array(_expect(archer.move == 5, "archer.tres move must be 5"))
	violations.append_array(_expect(archer.save == 1, "archer.tres save must be 1"))
	violations.append_array(_expect(archer.health == 2, "archer.tres health must be 2"))
	violations.append_array(_expect(archer.range_hexes == 4, "archer.tres range_hexes must be 4"))
	violations.append_array(_expect(archer.attack == 2, "archer.tres attack must be 2"))
	violations.append_array(_expect(archer.damage == 1, "archer.tres damage must be 1"))
	violations.append_array(
		_expect(
			archer.tags == PackedStringArray(["missile"]), 'archer.tres tags must be ["missile"]'
		)
	)
	violations.append_array(
		_expect(archer.ability_tags == PackedStringArray(), "archer.tres ability_tags must be []")
	)

	# The pair is what the target-number chart is worked against, so the two
	# must actually differ in the stats that chart turns on.
	violations.append_array(
		_expect(
			warrior.range_hexes != archer.range_hexes,
			"the authored roster must give the warrior and the archer different reach"
		)
	)
	violations.append_array(
		_expect(
			warrior.damage != archer.damage,
			"the authored roster must give the warrior and the archer different damage"
		)
	)

	return violations


## `load()` of the same path twice returns the same object -- Godot caches and
## shares `Resource` instances. This is not a bug to work around; it is the
## exact behaviour the runtime `Fighter` type exists to survive by never
## writing through its template reference.
static func _test_load_caching_returns_same_object() -> Array[String]:
	var first := load(WARRIOR_PATH)
	var second := load(WARRIOR_PATH)

	return _expect(
		is_same(first, second),
		(
			"load() of the same .tres path twice must return the same object -- Godot's Resource "
			+ "cache, which is exactly the behaviour the runtime Fighter design exists to survive "
			+ "by never writing through its shared template"
		)
	)


## The parent Feature's worked scenario, end to end: two Fighters built from
## the one loaded warrior.tres, damage applied to one, and the shared template
## left untouched -- in memory, and on a fresh load() from disk.
static func _test_parent_feature_scenario_end_to_end() -> Array[String]:
	var violations: Array[String] = []
	var template := load(WARRIOR_PATH) as FighterTemplate

	var original_template_id := template.template_id
	var original_display_name := template.display_name
	var original_move := template.move
	var original_save := template.save
	var original_health := template.health
	var original_range_hexes := template.range_hexes
	var original_attack := template.attack
	var original_damage := template.damage
	var original_tags := template.tags.duplicate()
	var original_ability_tags := template.ability_tags.duplicate()

	var damaged_fighter := Fighter.new("scenario-damaged", template, "player-1", Vector3i(0, 0, 0))
	var untouched_fighter := Fighter.new(
		"scenario-untouched", template, "player-2", Vector3i(0, 0, 0)
	)

	violations.append_array(
		_expect(damaged_fighter.apply_damage(2), "apply_damage(2) must succeed")
	)
	(
		violations
		. append_array(
			_expect(
				untouched_fighter.damage_counter() == 0,
				(
					"damaging one Fighter must leave a second Fighter built from the same template at a "
					+ "damage_counter() of 0"
				)
			)
		)
	)

	violations.append_array(
		_expect(
			template.health == original_health,
			"applying damage to a Fighter must not mutate the shared template's health"
		)
	)

	var reloaded := load(WARRIOR_PATH) as FighterTemplate
	violations.append_array(
		_expect(
			reloaded.health == original_health,
			(
				"a fresh load() of warrior.tres after damage was applied must still report the "
				+ "original health"
			)
		)
	)
	violations.append_array(
		_expect(
			reloaded.template_id == original_template_id,
			"a fresh load() of warrior.tres must still report the original template_id"
		)
	)
	violations.append_array(
		_expect(
			reloaded.display_name == original_display_name,
			"a fresh load() of warrior.tres must still report the original display_name"
		)
	)
	violations.append_array(
		_expect(
			reloaded.move == original_move,
			"a fresh load() of warrior.tres must still report the original move"
		)
	)
	violations.append_array(
		_expect(
			reloaded.save == original_save,
			"a fresh load() of warrior.tres must still report the original save"
		)
	)
	violations.append_array(
		_expect(
			reloaded.range_hexes == original_range_hexes,
			"a fresh load() of warrior.tres must still report the original range_hexes"
		)
	)
	violations.append_array(
		_expect(
			reloaded.attack == original_attack,
			"a fresh load() of warrior.tres must still report the original attack"
		)
	)
	violations.append_array(
		_expect(
			reloaded.damage == original_damage,
			"a fresh load() of warrior.tres must still report the original damage"
		)
	)
	violations.append_array(
		_expect(
			reloaded.tags == original_tags,
			"a fresh load() of warrior.tres must still report the original tags"
		)
	)
	violations.append_array(
		_expect(
			reloaded.ability_tags == original_ability_tags,
			"a fresh load() of warrior.tres must still report the original ability_tags"
		)
	)

	return violations


## A Fighter built from warrior.tres reads its stats through to the loaded
## template rather than from any script -- compared against the template's own
## fields, never against a second literal.
static func _test_fighter_from_warrior_reports_template_stats() -> Array[String]:
	return _expect_fighter_reads_through(WARRIOR_PATH, "warrior.tres")


## The same, for archer.tres. Two rosters rather than one, because the
## authored pair differ in exactly the stats attack resolution reads.
static func _test_fighter_from_archer_reports_template_stats() -> Array[String]:
	return _expect_fighter_reads_through(ARCHER_PATH, "archer.tres")


## Every stat accessor on a `Fighter` built from `path`, compared against the
## loaded template's own field.
static func _expect_fighter_reads_through(path: String, label: String) -> Array[String]:
	var violations: Array[String] = []
	var template := load(path) as FighterTemplate
	var fighter := Fighter.new("stats-fixture", template, "player-1", Vector3i(0, 0, 0))

	violations.append_array(
		_expect(
			fighter.health() == template.health,
			"a Fighter built from %s must report health() equal to the template's health" % label
		)
	)
	violations.append_array(
		_expect(
			fighter.move() == template.move,
			"a Fighter built from %s must report move() equal to the template's move" % label
		)
	)
	violations.append_array(
		_expect(
			fighter.save() == template.save,
			"a Fighter built from %s must report save() equal to the template's save" % label
		)
	)
	violations.append_array(
		_expect(
			fighter.range_hexes() == template.range_hexes,
			(
				"a Fighter built from %s must report range_hexes() equal to the template's " % label
				+ "range_hexes"
			)
		)
	)
	violations.append_array(
		_expect(
			fighter.attack() == template.attack,
			"a Fighter built from %s must report attack() equal to the template's attack" % label
		)
	)
	violations.append_array(
		_expect(
			fighter.damage() == template.damage,
			"a Fighter built from %s must report damage() equal to the template's damage" % label
		)
	)
	violations.append_array(
		_expect(
			fighter.ability_tags() == template.ability_tags,
			(
				(
					"a Fighter built from %s must report ability_tags() equal to the template's "
					% label
				)
				+ "ability_tags"
			)
		)
	)

	return violations


## "Retuning is a file edit" tested rather than merely asserted: duplicate the
## loaded warrior.tres, change its attack, save the copy to user:// (never
## under resources/), load it back, and confirm a Fighter built over it reports
## the new value -- with no script modified anywhere.
static func _test_retuning_is_a_file_edit() -> Array[String]:
	var violations: Array[String] = []

	var original := load(WARRIOR_PATH) as FighterTemplate
	var original_attack := original.attack

	var retuned := original.duplicate() as FighterTemplate
	var new_attack := original_attack + 1
	retuned.attack = new_attack

	var save_result := ResourceSaver.save(retuned, RETUNED_WARRIOR_PATH)
	violations.append_array(
		_expect(save_result == OK, "ResourceSaver.save() must succeed for the retuned duplicate")
	)
	if save_result != OK:
		return violations

	var reloaded_variant: Variant = ResourceLoader.load(
		RETUNED_WARRIOR_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	violations.append_array(
		_expect(reloaded_variant != null, "the retuned .tres must load back from user://")
	)
	if reloaded_variant == null:
		_cleanup_retuned_warrior()
		return violations

	violations.append_array(
		_expect(
			reloaded_variant is FighterTemplate,
			"the reloaded retuned resource must still be a FighterTemplate"
		)
	)
	if not (reloaded_variant is FighterTemplate):
		_cleanup_retuned_warrior()
		return violations

	var reloaded: FighterTemplate = reloaded_variant
	var fighter := Fighter.new("retuned-fixture", reloaded, "player-1", Vector3i(0, 0, 0))

	violations.append_array(
		_expect(
			fighter.attack() == new_attack,
			(
				"a Fighter built over the retuned template must report the new attack -- retuning "
				+ "is a file edit, not a script edit"
			)
		)
	)
	violations.append_array(
		_expect(
			original.attack == original_attack,
			"duplicating and retuning a copy must not mutate the originally loaded warrior.tres"
		)
	)

	_cleanup_retuned_warrior()
	return violations


## The combat profile loads as a CombatProfile with correct authored values.
static func _test_combat_profile_loads_correctly() -> Array[String]:
	var violations: Array[String] = []

	var profile: Variant = load(COMBAT_PROFILE_PATH)
	violations.append_array(
		_expect(profile is CombatProfile, "combat_profile.tres must load as a CombatProfile")
	)

	if profile is CombatProfile:
		violations.append_array(
			_expect(profile.profile_id == "standard", "profile_id must be 'standard'")
		)
		violations.append_array(_expect(profile.die_sides == 6, "die_sides must be 6"))
		violations.append_array(_expect(profile.attack_target == 5, "attack_target must be 5"))
		violations.append_array(_expect(profile.save_target == 5, "save_target must be 5"))
		violations.append_array(
			_expect(profile.engagement_range == 1, "engagement_range must be 1")
		)
		violations.append_array(
			_expect(profile.engagement_modifier == 1, "engagement_modifier must be 1")
		)
		violations.append_array(
			_expect(profile.attack_flank_modifier == 1, "attack_flank_modifier must be 1")
		)
		violations.append_array(
			_expect(profile.attack_surround_modifier == 2, "attack_surround_modifier must be 2")
		)
		violations.append_array(
			_expect(profile.save_flank_modifier == 2, "save_flank_modifier must be 2")
		)
		violations.append_array(
			_expect(profile.save_surround_modifier == 3, "save_surround_modifier must be 3")
		)
		violations.append_array(_expect(profile.guard_modifier == 1, "guard_modifier must be 1"))
		violations.append_array(_expect(profile.min_target == 2, "min_target must be 2"))
		violations.append_array(_expect(profile.max_target == 6, "max_target must be 6"))
		violations.append_array(_expect(profile.defeat_award == 1, "defeat_award must be 1"))
		violations.append_array(
			_expect(
				profile.attack_flank_modifier != profile.save_flank_modifier,
				"attack_flank_modifier (1) must differ from save_flank_modifier (2)"
			)
		)
		violations.append_array(
			_expect(
				profile.attack_surround_modifier != profile.save_surround_modifier,
				"attack_surround_modifier (2) must differ from save_surround_modifier (3)"
			)
		)

	return violations


## Every authored fighter satisfies the construction budget, so a future
## fighter cannot be added illegally without a red test.
static func _test_all_fighters_satisfy_construction_budget() -> Array[String]:
	var violations: Array[String] = []

	var budget: Variant = load(CONSTRUCTION_BUDGET_PATH)
	violations.append_array(
		_expect(
			budget is ConstructionBudget,
			"construction_budget.tres must load as a ConstructionBudget"
		)
	)
	if not (budget is ConstructionBudget):
		return violations

	var budget_resource: ConstructionBudget = budget
	var fighters_dir := "res://resources/fighters/"
	var fighter_count := 0

	# Enumerate all files under res://resources/fighters/, filtering to FighterTemplate instances.
	# This naturally skips construction_budget.tres, which lives in the same directory.
	for file_path in ExtractionContractTest.files_recursive(fighters_dir):
		if not file_path.ends_with(".tres"):
			continue

		var resource: Variant = load(file_path)
		if not (resource is FighterTemplate):
			continue

		fighter_count += 1
		var template: FighterTemplate = resource
		violations.append_array(
			_expect(
				budget_resource.is_satisfied_by(template),
				"the authored fighter at %s must satisfy the construction budget" % file_path
			)
		)

	violations.append_array(
		_expect(
			fighter_count > 0,
			"at least one FighterTemplate must be found under res://resources/fighters/"
		)
	)

	return violations


## Removes the user:// .tres this suite writes, so repeated runs do not depend
## on state a previous run left behind. Never touches anything under
## res://resources/.
static func _cleanup_retuned_warrior() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(RETUNED_WARRIOR_PATH.trim_prefix("user://")):
		dir.remove(RETUNED_WARRIOR_PATH.trim_prefix("user://"))

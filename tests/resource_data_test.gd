## Game-side data suite for the four authored `.tres` files under
## `resources/`: `resources/weapons/sword.tres`, `resources/weapons/bow.tres`,
## `resources/fighters/warrior.tres`, and `resources/fighters/archer.tres`.
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
## names those numbers as literals -- it exists to pin what the four files
## contain. Every other test below reads its expected values back off a
## loaded resource and compares runtime behaviour against them, never against
## a second literal, so retuning a `.tres` cannot silently break a test that
## was supposed to be reading the file rather than restating it.
class_name ResourceDataTest

const SWORD_PATH := "res://resources/weapons/sword.tres"
const BOW_PATH := "res://resources/weapons/bow.tres"
const WARRIOR_PATH := "res://resources/fighters/warrior.tres"
const ARCHER_PATH := "res://resources/fighters/archer.tres"

## Where the "retuning is a file edit" test saves its duplicated, retuned
## sword. Never a path under `res://resources/` -- no test may write there.
const RETUNED_SWORD_PATH := "user://resource_data_test_retuned_sword.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_files_load_as_expected_class())
	violations.append_array(_test_field_values_match_authored_content())
	violations.append_array(_test_nested_weapon_references_are_object_identical())
	violations.append_array(_test_load_caching_returns_same_object())
	violations.append_array(_test_parent_feature_scenario_end_to_end())
	violations.append_array(_test_fighter_from_warrior_reports_template_stats())
	violations.append_array(_test_fighter_from_archer_reports_ranged_weapon())
	violations.append_array(_test_retuning_is_a_file_edit())

	if violations.is_empty():
		return true

	printerr("\n=== Resource Data Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Each of the four authored paths loads and is an instance of the expected
## class. Asserted with `is`, not merely `!= null`: a `.tres` that lost its
## script reference loads as a bare `Resource`, and `!= null` alone would not
## catch that.
static func _test_files_load_as_expected_class() -> Array[String]:
	var violations: Array[String] = []

	var sword: Variant = load(SWORD_PATH)
	violations.append_array(
		_expect(sword is WeaponTemplate, "sword.tres must load as a WeaponTemplate")
	)

	var bow: Variant = load(BOW_PATH)
	violations.append_array(
		_expect(bow is WeaponTemplate, "bow.tres must load as a WeaponTemplate")
	)

	var warrior: Variant = load(WARRIOR_PATH)
	violations.append_array(
		_expect(warrior is FighterTemplate, "warrior.tres must load as a FighterTemplate")
	)

	var archer: Variant = load(ARCHER_PATH)
	violations.append_array(
		_expect(archer is FighterTemplate, "archer.tres must load as a FighterTemplate")
	)

	return violations


## Field-by-field pin of what the four authored files contain. The only place
## in this suite where a value from the roster tables appears as a literal --
## see the class docstring for why that is the deliberate exception.
static func _test_field_values_match_authored_content() -> Array[String]:
	var violations: Array[String] = []

	var sword := load(SWORD_PATH) as WeaponTemplate
	violations.append_array(
		_expect(sword.template_id == "sword", 'sword.tres template_id must be "sword"')
	)
	violations.append_array(
		_expect(sword.display_name == "Sword", 'sword.tres display_name must be "Sword"')
	)
	violations.append_array(_expect(sword.range_hexes == 1, "sword.tres range_hexes must be 1"))
	violations.append_array(_expect(sword.dice_count == 3, "sword.tres dice_count must be 3"))
	violations.append_array(_expect(sword.damage_value == 2, "sword.tres damage_value must be 2"))
	violations.append_array(
		_expect(sword.weapon_type == WeaponTemplate.MELEE, "sword.tres weapon_type must be MELEE")
	)
	violations.append_array(
		_expect(
			sword.ability_tags == PackedStringArray(["cleave"]),
			'sword.tres ability_tags must be ["cleave"]'
		)
	)

	var bow := load(BOW_PATH) as WeaponTemplate
	violations.append_array(_expect(bow.template_id == "bow", 'bow.tres template_id must be "bow"'))
	violations.append_array(
		_expect(bow.display_name == "Bow", 'bow.tres display_name must be "Bow"')
	)
	violations.append_array(_expect(bow.range_hexes == 4, "bow.tres range_hexes must be 4"))
	violations.append_array(_expect(bow.dice_count == 2, "bow.tres dice_count must be 2"))
	violations.append_array(_expect(bow.damage_value == 1, "bow.tres damage_value must be 1"))
	violations.append_array(
		_expect(bow.weapon_type == WeaponTemplate.RANGED, "bow.tres weapon_type must be RANGED")
	)
	violations.append_array(
		_expect(bow.ability_tags.is_empty(), "bow.tres ability_tags must be deliberately empty")
	)

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
	violations.append_array(_expect(warrior.point_value == 5, "warrior.tres point_value must be 5"))
	violations.append_array(
		_expect(
			warrior.tags == PackedStringArray(["infantry"]),
			'warrior.tres tags must be ["infantry"]'
		)
	)
	violations.append_array(
		_expect(warrior.weapons.size() == 1, "warrior.tres weapons must hold exactly one entry")
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
	violations.append_array(_expect(archer.point_value == 4, "archer.tres point_value must be 4"))
	violations.append_array(
		_expect(
			archer.tags == PackedStringArray(["missile"]), 'archer.tres tags must be ["missile"]'
		)
	)
	violations.append_array(
		_expect(archer.weapons.size() == 1, "archer.tres weapons must hold exactly one entry")
	)

	return violations


## `warrior.tres`'s `weapons[0]` and a direct `load()` of `sword.tres` must be
## the identical object, and likewise `archer.tres` to `bow.tres` -- proving
## the nested `ext_resource` reference resolved rather than silently producing
## `null` or, worse, a private embedded copy.
static func _test_nested_weapon_references_are_object_identical() -> Array[String]:
	var violations: Array[String] = []

	var sword := load(SWORD_PATH) as WeaponTemplate
	var warrior := load(WARRIOR_PATH) as FighterTemplate
	violations.append_array(
		_expect(
			warrior.weapons.size() == 1 and is_same(warrior.weapons[0], sword),
			"warrior.tres weapons[0] must be the identical object as a direct load() of sword.tres"
		)
	)

	var bow := load(BOW_PATH) as WeaponTemplate
	var archer := load(ARCHER_PATH) as FighterTemplate
	violations.append_array(
		_expect(
			archer.weapons.size() == 1 and is_same(archer.weapons[0], bow),
			"archer.tres weapons[0] must be the identical object as a direct load() of bow.tres"
		)
	)

	return violations


## `load()` of the same path twice returns the same object -- Godot caches and
## shares `Resource` instances. This is not a bug to work around; it is the
## exact behaviour the runtime `Fighter` type (task #31) exists to survive by
## never writing through its template reference.
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
	var original_point_value := template.point_value
	var original_tags := template.tags.duplicate()
	var original_weapon_count := template.weapons.size()
	var original_weapon_dice_count := (
		template.weapons[0].dice_count if original_weapon_count > 0 else -1
	)
	var original_weapon_type := template.weapons[0].weapon_type if original_weapon_count > 0 else ""

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
			reloaded.point_value == original_point_value,
			"a fresh load() of warrior.tres must still report the original point_value"
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
			reloaded.weapons.size() == original_weapon_count,
			"a fresh load() of warrior.tres must still report the original weapon count"
		)
	)
	if reloaded.weapons.size() == original_weapon_count and original_weapon_count > 0:
		violations.append_array(
			_expect(
				reloaded.weapons[0].dice_count == original_weapon_dice_count,
				"a fresh load() of warrior.tres must still report the original weapon dice_count"
			)
		)
		violations.append_array(
			_expect(
				reloaded.weapons[0].weapon_type == original_weapon_type,
				"a fresh load() of warrior.tres must still report the original weapon weapon_type"
			)
		)

	return violations


## A Fighter built from warrior.tres reads its stats through to the loaded
## template rather than from any script -- compared against the template's own
## fields, never against a second literal.
static func _test_fighter_from_warrior_reports_template_stats() -> Array[String]:
	var violations: Array[String] = []
	var template := load(WARRIOR_PATH) as FighterTemplate
	var fighter := Fighter.new("warrior-stats", template, "player-1", Vector3i(0, 0, 0))

	violations.append_array(
		_expect(
			fighter.health() == template.health,
			"a Fighter built from warrior.tres must report health() equal to the template's health"
		)
	)
	violations.append_array(
		_expect(
			fighter.move() == template.move,
			"a Fighter built from warrior.tres must report move() equal to the template's move"
		)
	)
	violations.append_array(
		_expect(
			fighter.save() == template.save,
			"a Fighter built from warrior.tres must report save() equal to the template's save"
		)
	)
	violations.append_array(
		_expect(
			fighter.point_value() == template.point_value,
			(
				"a Fighter built from warrior.tres must report point_value() equal to the "
				+ "template's point_value"
			)
		)
	)

	var weapons := fighter.weapons()
	violations.append_array(
		_expect(
			weapons.size() == template.weapons.size(),
			"a Fighter built from warrior.tres must report the same weapon count as its template"
		)
	)
	if weapons.size() == template.weapons.size() and weapons.size() > 0:
		(
			violations
			. append_array(
				_expect(
					weapons[0].dice_count == template.weapons[0].dice_count,
					(
						"a Fighter built from warrior.tres must report a weapon dice_count equal to the "
						+ "template's"
					)
				)
			)
		)
		violations.append_array(
			_expect(
				weapons[0].weapon_type == WeaponTemplate.MELEE,
				(
					"a Fighter built from warrior.tres must report a weapon whose weapon_type is "
					+ "WeaponTemplate.MELEE"
				)
			)
		)

	return violations


## A Fighter built from archer.tres carries a ranged weapon: the melee/ranged
## discriminator survives authoring, not just in-memory construction.
static func _test_fighter_from_archer_reports_ranged_weapon() -> Array[String]:
	var violations: Array[String] = []
	var template := load(ARCHER_PATH) as FighterTemplate
	var fighter := Fighter.new("archer-stats", template, "player-1", Vector3i(0, 0, 0))
	var weapons := fighter.weapons()

	violations.append_array(
		_expect(
			weapons.size() == template.weapons.size(),
			"a Fighter built from archer.tres must report the same weapon count as its template"
		)
	)
	if weapons.size() == template.weapons.size() and weapons.size() > 0:
		(
			violations
			. append_array(
				_expect(
					weapons[0].range_hexes == template.weapons[0].range_hexes,
					(
						"a Fighter built from archer.tres must report a weapon range_hexes equal to the "
						+ "template's"
					)
				)
			)
		)
		violations.append_array(
			_expect(
				weapons[0].weapon_type == WeaponTemplate.RANGED,
				(
					"a Fighter built from archer.tres must report a weapon whose weapon_type is "
					+ "WeaponTemplate.RANGED"
				)
			)
		)

	return violations


## "Retuning is a file edit" tested rather than merely asserted: duplicate the
## loaded sword.tres, change its dice_count, save the copy to user:// (never
## under resources/), load it back, and confirm a FighterTemplate built around
## it reports the new value -- with no script modified anywhere.
static func _test_retuning_is_a_file_edit() -> Array[String]:
	var violations: Array[String] = []

	var original_sword := load(SWORD_PATH) as WeaponTemplate
	var original_dice_count := original_sword.dice_count

	var retuned := original_sword.duplicate() as WeaponTemplate
	var new_dice_count := original_dice_count + 1
	retuned.dice_count = new_dice_count

	var save_result := ResourceSaver.save(retuned, RETUNED_SWORD_PATH)
	violations.append_array(
		_expect(save_result == OK, "ResourceSaver.save() must succeed for the retuned duplicate")
	)
	if save_result != OK:
		return violations

	var reloaded_variant: Variant = ResourceLoader.load(
		RETUNED_SWORD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	violations.append_array(
		_expect(reloaded_variant != null, "the retuned .tres must load back from user://")
	)
	if reloaded_variant == null:
		_cleanup_retuned_sword()
		return violations

	violations.append_array(
		_expect(
			reloaded_variant is WeaponTemplate,
			"the reloaded retuned resource must still be a WeaponTemplate"
		)
	)
	if not (reloaded_variant is WeaponTemplate):
		_cleanup_retuned_sword()
		return violations

	var reloaded_weapon: WeaponTemplate = reloaded_variant
	var retuned_fighter_template := FighterTemplate.new()
	retuned_fighter_template.weapons = [reloaded_weapon] as Array[WeaponTemplate]

	violations.append_array(
		_expect(
			retuned_fighter_template.weapons[0].dice_count == new_dice_count,
			(
				"a FighterTemplate built around the retuned weapon must report the new "
				+ "dice_count -- retuning is a file edit, not a script edit"
			)
		)
	)
	violations.append_array(
		_expect(
			original_sword.dice_count == original_dice_count,
			"duplicating and retuning a copy must not mutate the originally loaded sword.tres"
		)
	)

	_cleanup_retuned_sword()
	return violations


## Removes the user:// .tres this suite writes, so repeated runs do not depend
## on state a previous run left behind. Never touches anything under
## res://resources/.
static func _cleanup_retuned_sword() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(RETUNED_SWORD_PATH.trim_prefix("user://")):
		dir.remove(RETUNED_SWORD_PATH.trim_prefix("user://"))

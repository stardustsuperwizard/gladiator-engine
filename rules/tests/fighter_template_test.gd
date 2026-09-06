## Tests WeaponTemplate and FighterTemplate: default zero-valued fields, the
## MELEE/RANGED discriminator, has_ability_tag()/has_tag() exact-match
## membership, weapon ordering on a FighterTemplate, and .tres round-trip
## serialization via user://.
##
## Every template here is constructed in memory with .new() -- this suite
## lives under rules/ and extraction_contract_test.gd forbids naming a
## res://resources/ path, so it may not load an authored .tres. Authored
## resources/fighters/ content is sibling task #32.
class_name FighterTemplateTest

const TEST_TRES_PATH := "user://fighter_template_test.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_weapon_template_defaults())
	violations.append_array(_test_fighter_template_defaults())
	violations.append_array(_test_weapon_type_default_and_constants())
	violations.append_array(_test_has_ability_tag_exact_match())
	violations.append_array(_test_has_tag_exact_match())
	violations.append_array(_test_fighter_template_holds_weapons_in_order())
	violations.append_array(_test_tres_round_trip_via_user_dir())

	if violations.is_empty():
		return true

	printerr("\n=== Fighter Template Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_weapon_template_defaults() -> Array[String]:
	var violations: Array[String] = []
	var weapon := WeaponTemplate.new()

	violations.append_array(_expect(weapon.template_id == "", 'template_id must default to ""'))
	violations.append_array(_expect(weapon.display_name == "", 'display_name must default to ""'))
	violations.append_array(_expect(weapon.range_hexes == 0, "range_hexes must default to 0"))
	violations.append_array(_expect(weapon.dice_count == 0, "dice_count must default to 0"))
	violations.append_array(_expect(weapon.damage_value == 0, "damage_value must default to 0"))
	violations.append_array(
		_expect(weapon.ability_tags.is_empty(), "ability_tags must default to an empty array")
	)

	return violations


static func _test_fighter_template_defaults() -> Array[String]:
	var violations: Array[String] = []
	var fighter := FighterTemplate.new()

	violations.append_array(_expect(fighter.template_id == "", 'template_id must default to ""'))
	violations.append_array(_expect(fighter.display_name == "", 'display_name must default to ""'))
	violations.append_array(_expect(fighter.move == 0, "move must default to 0"))
	violations.append_array(_expect(fighter.save == 0, "save must default to 0"))
	violations.append_array(_expect(fighter.health == 0, "health must default to 0"))
	violations.append_array(_expect(fighter.point_value == 0, "point_value must default to 0"))
	violations.append_array(
		_expect(fighter.weapons.is_empty(), "weapons must default to an empty array")
	)
	violations.append_array(_expect(fighter.tags.is_empty(), "tags must default to an empty array"))

	return violations


static func _test_weapon_type_default_and_constants() -> Array[String]:
	var violations: Array[String] = []
	var weapon := WeaponTemplate.new()

	violations.append_array(
		_expect(
			weapon.weapon_type == WeaponTemplate.MELEE,
			"weapon_type must default to WeaponTemplate.MELEE"
		)
	)
	violations.append_array(
		_expect(WeaponTemplate.MELEE == "melee", 'WeaponTemplate.MELEE must equal "melee"')
	)
	violations.append_array(
		_expect(WeaponTemplate.RANGED == "ranged", 'WeaponTemplate.RANGED must equal "ranged"')
	)

	return violations


static func _test_has_ability_tag_exact_match() -> Array[String]:
	var violations: Array[String] = []
	var present_tag := "present-ability-tag"
	var absent_tag := "absent-ability-tag"

	var empty_weapon := WeaponTemplate.new()
	violations.append_array(
		_expect(
			not empty_weapon.has_ability_tag(present_tag),
			"has_ability_tag() must return false on an empty ability_tags set"
		)
	)

	var weapon := WeaponTemplate.new()
	weapon.ability_tags = PackedStringArray([present_tag])

	violations.append_array(
		_expect(
			weapon.has_ability_tag(present_tag),
			"has_ability_tag() must return true for a tag present in ability_tags"
		)
	)
	violations.append_array(
		_expect(
			not weapon.has_ability_tag(absent_tag),
			"has_ability_tag() must return false for a tag absent from ability_tags"
		)
	)
	violations.append_array(
		_expect(
			not weapon.has_ability_tag(present_tag.to_upper()),
			"has_ability_tag() must return false for a case-differing spelling of a present tag"
		)
	)

	return violations


static func _test_has_tag_exact_match() -> Array[String]:
	var violations: Array[String] = []
	var present_tag := "present-fighter-tag"
	var absent_tag := "absent-fighter-tag"

	var empty_fighter := FighterTemplate.new()
	violations.append_array(
		_expect(
			not empty_fighter.has_tag(present_tag),
			"has_tag() must return false on an empty tags set"
		)
	)

	var fighter := FighterTemplate.new()
	fighter.tags = PackedStringArray([present_tag])

	violations.append_array(
		_expect(
			fighter.has_tag(present_tag), "has_tag() must return true for a tag present in tags"
		)
	)
	violations.append_array(
		_expect(
			not fighter.has_tag(absent_tag),
			"has_tag() must return false for a tag absent from tags"
		)
	)
	violations.append_array(
		_expect(
			not fighter.has_tag(present_tag.to_upper()),
			"has_tag() must return false for a case-differing spelling of a present tag"
		)
	)

	return violations


static func _test_fighter_template_holds_weapons_in_order() -> Array[String]:
	var violations: Array[String] = []
	var first_weapon := WeaponTemplate.new()
	first_weapon.template_id = "weapon-a"
	var second_weapon := WeaponTemplate.new()
	second_weapon.template_id = "weapon-b"

	var fighter := FighterTemplate.new()
	fighter.weapons = [first_weapon, second_weapon] as Array[WeaponTemplate]

	violations.append_array(
		_expect(fighter.weapons.size() == 2, "weapons must hold both assigned WeaponTemplates")
	)
	if fighter.weapons.size() == 2:
		violations.append_array(
			_expect(
				fighter.weapons[0] == first_weapon,
				"weapons[0] must be the first WeaponTemplate assigned"
			)
		)
		violations.append_array(
			_expect(
				fighter.weapons[1] == second_weapon,
				"weapons[1] must be the second WeaponTemplate assigned"
			)
		)

	return violations


static func _test_tres_round_trip_via_user_dir() -> Array[String]:
	var violations: Array[String] = []

	var melee_weapon := WeaponTemplate.new()
	melee_weapon.template_id = "melee-weapon"
	melee_weapon.display_name = "Test Blade"
	melee_weapon.range_hexes = 1
	melee_weapon.dice_count = 3
	melee_weapon.damage_value = 2
	melee_weapon.weapon_type = WeaponTemplate.MELEE
	melee_weapon.ability_tags = PackedStringArray(["reach"])

	var ranged_weapon := WeaponTemplate.new()
	ranged_weapon.template_id = "ranged-weapon"
	ranged_weapon.display_name = "Test Bow"
	ranged_weapon.range_hexes = 4
	ranged_weapon.dice_count = 2
	ranged_weapon.damage_value = 1
	ranged_weapon.weapon_type = WeaponTemplate.RANGED
	ranged_weapon.ability_tags = PackedStringArray(["piercing", "long-shot"])

	var fighter := FighterTemplate.new()
	fighter.template_id = "test-fighter"
	fighter.display_name = "Test Fighter"
	fighter.move = 3
	fighter.save = 4
	fighter.health = 5
	fighter.point_value = 6
	fighter.weapons = [melee_weapon, ranged_weapon] as Array[WeaponTemplate]
	fighter.tags = PackedStringArray(["elite"])

	var save_result := ResourceSaver.save(fighter, TEST_TRES_PATH)
	violations.append_array(
		_expect(
			save_result == OK, "ResourceSaver.save() must succeed for a populated FighterTemplate"
		)
	)
	if save_result != OK:
		return violations

	var loaded_variant: Variant = ResourceLoader.load(
		TEST_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	violations.append_array(
		_expect(loaded_variant != null, "ResourceLoader.load() must return the saved .tres")
	)
	if loaded_variant == null:
		return violations

	violations.append_array(
		_expect(loaded_variant is FighterTemplate, "the loaded resource must be a FighterTemplate")
	)
	if not (loaded_variant is FighterTemplate):
		return violations

	var loaded: FighterTemplate = loaded_variant

	violations.append_array(
		_expect(
			loaded.template_id == fighter.template_id,
			"template_id must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded.display_name == fighter.display_name,
			"display_name must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(loaded.move == fighter.move, "move must survive the .tres round trip")
	)
	violations.append_array(
		_expect(loaded.save == fighter.save, "save must survive the .tres round trip")
	)
	violations.append_array(
		_expect(loaded.health == fighter.health, "health must survive the .tres round trip")
	)
	violations.append_array(
		_expect(
			loaded.point_value == fighter.point_value,
			"point_value must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(loaded.tags == fighter.tags, "tags must survive the .tres round trip")
	)
	violations.append_array(
		_expect(
			loaded.weapons.size() == 2,
			"both nested WeaponTemplates must survive the .tres round trip"
		)
	)
	if loaded.weapons.size() != 2:
		return violations

	var loaded_melee := loaded.weapons[0]
	var loaded_ranged := loaded.weapons[1]

	violations.append_array(
		_expect(
			loaded_melee.template_id == melee_weapon.template_id,
			"weapons[0].template_id must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_melee.display_name == melee_weapon.display_name,
			"weapons[0].display_name must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_melee.range_hexes == melee_weapon.range_hexes,
			"weapons[0].range_hexes must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_melee.dice_count == melee_weapon.dice_count,
			"weapons[0].dice_count must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_melee.damage_value == melee_weapon.damage_value,
			"weapons[0].damage_value must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_melee.weapon_type == melee_weapon.weapon_type,
			"weapons[0].weapon_type must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_melee.ability_tags == melee_weapon.ability_tags,
			"weapons[0].ability_tags must survive the .tres round trip"
		)
	)

	violations.append_array(
		_expect(
			loaded_ranged.template_id == ranged_weapon.template_id,
			"weapons[1].template_id must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_ranged.weapon_type == ranged_weapon.weapon_type,
			"weapons[1].weapon_type must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(
			loaded_ranged.ability_tags == ranged_weapon.ability_tags,
			"weapons[1].ability_tags must survive the .tres round trip"
		)
	)

	_cleanup_tres()

	return violations


## Removes the .tres this suite writes under user:// so repeated runs do not
## depend on state a previous run left behind.
static func _cleanup_tres() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(TEST_TRES_PATH.trim_prefix("user://")):
		dir.remove(TEST_TRES_PATH.trim_prefix("user://"))

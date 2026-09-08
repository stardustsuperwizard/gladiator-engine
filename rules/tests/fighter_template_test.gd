## Tests FighterTemplate: default zero-valued fields, the six combat stats
## spec §3 gives a fighter, has_tag()/has_ability_tag() exact-match membership,
## and .tres round-trip serialization via user://.
##
## There is no weapon resource here and no `weapons` field to test. Spec §3 as
## revised 2026-09-08 collapsed the fighter/weapon split into the stats below,
## and the `Weapon` entity was deleted from the tree with it.
##
## Every template here is constructed in memory with .new() -- this suite
## lives under rules/ and extraction_contract_test.gd forbids naming a
## res://resources/ path, so it may not load an authored .tres. The authored
## resources/fighters/ content is exercised by tests/resource_data_test.gd.
class_name FighterTemplateTest

const TEST_TRES_PATH := "user://fighter_template_test.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_fighter_template_defaults())
	violations.append_array(_test_has_ability_tag_exact_match())
	violations.append_array(_test_has_tag_exact_match())
	violations.append_array(_test_tres_round_trip_via_user_dir())

	if violations.is_empty():
		return true

	printerr("\n=== Fighter Template Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_fighter_template_defaults() -> Array[String]:
	var violations: Array[String] = []
	var fighter := FighterTemplate.new()

	violations.append_array(_expect(fighter.template_id == "", 'template_id must default to ""'))
	violations.append_array(_expect(fighter.display_name == "", 'display_name must default to ""'))
	violations.append_array(_expect(fighter.move == 0, "move must default to 0"))
	violations.append_array(_expect(fighter.save == 0, "save must default to 0"))
	violations.append_array(_expect(fighter.health == 0, "health must default to 0"))
	violations.append_array(_expect(fighter.range_hexes == 0, "range_hexes must default to 0"))
	violations.append_array(_expect(fighter.attack == 0, "attack must default to 0"))
	violations.append_array(_expect(fighter.damage == 0, "damage must default to 0"))
	violations.append_array(_expect(fighter.tags.is_empty(), "tags must default to an empty array"))
	violations.append_array(
		_expect(fighter.ability_tags.is_empty(), "ability_tags must default to an empty array")
	)

	return violations


static func _test_has_ability_tag_exact_match() -> Array[String]:
	var violations: Array[String] = []
	var present_tag := "present-ability-tag"
	var absent_tag := "absent-ability-tag"

	var empty_fighter := FighterTemplate.new()
	violations.append_array(
		_expect(
			not empty_fighter.has_ability_tag(present_tag),
			"has_ability_tag() must return false on an empty ability_tags set"
		)
	)

	var fighter := FighterTemplate.new()
	fighter.ability_tags = PackedStringArray([present_tag])

	violations.append_array(
		_expect(
			fighter.has_ability_tag(present_tag),
			"has_ability_tag() must return true for a tag present in ability_tags"
		)
	)
	violations.append_array(
		_expect(
			not fighter.has_ability_tag(absent_tag),
			"has_ability_tag() must return false for a tag absent from ability_tags"
		)
	)
	violations.append_array(
		_expect(
			not fighter.has_ability_tag(present_tag.to_upper()),
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


static func _test_tres_round_trip_via_user_dir() -> Array[String]:
	var violations: Array[String] = []

	var fighter := FighterTemplate.new()
	fighter.template_id = "test-fighter"
	fighter.display_name = "Test Fighter"
	fighter.move = 3
	fighter.save = 4
	fighter.health = 5
	fighter.range_hexes = 2
	fighter.attack = 3
	fighter.damage = 1
	fighter.tags = PackedStringArray(["elite"])
	fighter.ability_tags = PackedStringArray(["special"])

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
			loaded.range_hexes == fighter.range_hexes,
			"range_hexes must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(loaded.attack == fighter.attack, "attack must survive the .tres round trip")
	)
	violations.append_array(
		_expect(loaded.damage == fighter.damage, "damage must survive the .tres round trip")
	)
	violations.append_array(
		_expect(loaded.tags == fighter.tags, "tags must survive the .tres round trip")
	)
	violations.append_array(
		_expect(
			loaded.ability_tags == fighter.ability_tags,
			"ability_tags must survive the .tres round trip"
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

## Tests Fighter.to_dict() / Fighter.from_dict(): the round trip, the
## JSON-safety and fixed key order of the wire shape, that GameState accepts it
## as an opaque fighter payload, and every malformed-input refusal from_dict()
## documents.
##
## Split from FighterTest rather than living in it, the same way
## BoardSerializationTest is split from BoardTest: one file was approaching
## .gdlintrc's 1000-line ceiling, which is deliberately not raisable. Templates
## come from FighterTest.make_template() so the two suites cannot drift apart
## about what an authored fighter looks like, and so this one also never names
## an authored content path -- extraction_contract_test.gd forbids it.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail once
## during development before the implementation made it pass.
class_name FighterSerializationTest

## The keys to_dict() must build, in the order it must build them. Fixed order
## is what makes JSON.stringify() of two identically built fighters identical,
## which is in turn what makes GameState.digest() a usable identity.
const EXPECTED_KEYS := [
	"id",
	"template_id",
	"owner_id",
	"position",
	"damage_counter",
	"status_flags",
]


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_round_trip_preserves_state_and_isolates())
	violations.append_array(_test_to_dict_shape_is_json_safe())
	violations.append_array(_test_identical_fighters_stringify_identically())
	violations.append_array(_test_to_dict_is_accepted_by_game_state())
	violations.append_array(_test_from_dict_refusals())

	if violations.is_empty():
		return true

	printerr("\n=== Fighter Serialization Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_round_trip_preserves_state_and_isolates() -> Array[String]:
	var violations: Array[String] = []
	var template := FighterTest.make_template(3)
	var destination := Vector3i(2, -3, 1)
	var fighter := Fighter.new("fighter-1", template, "player-2", Vector3i.ZERO)
	fighter.move_to(destination)
	fighter.apply_damage(2)
	fighter.set_status_flag("moved")
	fighter.set_status_flag("guarded")

	var restored := Fighter.from_dict(fighter.to_dict(), template)

	violations.append_array(
		_expect(restored != null, "from_dict() must not refuse a well-formed record")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.to_dict() == fighter.to_dict(),
			"to_dict() of a round-tripped fighter must equal to_dict() of the original"
		)
	)
	violations.append_array(
		_expect(restored.id() == "fighter-1", "the id must survive the round trip")
	)
	violations.append_array(
		_expect(restored.owner_id() == "player-2", "the owner must survive the round trip")
	)
	violations.append_array(
		_expect(restored.position() == destination, "the position must survive the round trip")
	)
	violations.append_array(
		_expect(restored.damage_counter() == 2, "the damage counter must survive the round trip")
	)
	violations.append_array(
		_expect(
			restored.status_flags() == (["moved", "guarded"] as Array[String]),
			"the status flags must survive the round trip, in order"
		)
	)
	violations.append_array(
		_expect(
			restored.template() == template,
			"from_dict() must hold the template it was handed, not one it resolved"
		)
	)

	restored.apply_damage(5)
	restored.move_to(Vector3i.ZERO)
	restored.set_status_flag("charged")

	violations.append_array(
		_expect(
			fighter.damage_counter() == 2,
			(
				"the restored fighter must be a distinct object -- damaging it must not "
				+ "damage the original"
			)
		)
	)
	violations.append_array(
		_expect(
			fighter.position() == destination,
			"mutating the restored fighter must not move the original"
		)
	)
	violations.append_array(
		_expect(
			not fighter.has_status_flag("charged"),
			"mutating the restored fighter must not flag the original"
		)
	)
	violations.append_array(
		FighterTest.expect_template_unchanged(template, 3, "a to_dict()/from_dict() round trip")
	)

	return violations


static func _test_to_dict_shape_is_json_safe() -> Array[String]:
	var violations: Array[String] = []
	var template := FighterTest.make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i(1, -1, 0))
	fighter.apply_damage(1)
	fighter.set_status_flag("moved")

	var data := fighter.to_dict()

	violations.append_array(
		_expect(
			data.keys() == EXPECTED_KEYS, "to_dict() must build its keys in exactly the fixed order"
		)
	)
	violations.append_array(
		_expect(typeof(data["id"]) == TYPE_STRING, '"id" must be a plain String, not a StringName')
	)
	violations.append_array(
		_expect(
			data["template_id"] == FighterTest.TEMPLATE_ID,
			'"template_id" must be copied from the template'
		)
	)
	violations.append_array(
		_expect(typeof(data["owner_id"]) == TYPE_STRING, '"owner_id" must be a plain String')
	)
	violations.append_array(
		_expect(
			typeof(data["position"]) == TYPE_ARRAY,
			'"position" must be a plain Array, not a Vector3i'
		)
	)
	violations.append_array(
		_expect(data["position"] == [1, -1, 0], '"position" must serialize as [x, y, z]')
	)
	violations.append_array(
		_expect(typeof(data["damage_counter"]) == TYPE_INT, '"damage_counter" must be an int')
	)
	violations.append_array(
		_expect(typeof(data["status_flags"]) == TYPE_ARRAY, '"status_flags" must be an Array')
	)
	for flag: Variant in data["status_flags"]:
		violations.append_array(
			_expect(
				typeof(flag) == TYPE_STRING,
				'every "status_flags" entry must be a plain String, not a StringName'
			)
		)

	var reparsed: Variant = JSON.parse_string(JSON.stringify(data))
	violations.append_array(
		_expect(
			typeof(reparsed) == TYPE_DICTIONARY,
			"to_dict() must survive JSON.parse_string(JSON.stringify(...))"
		)
	)
	if typeof(reparsed) != TYPE_DICTIONARY:
		return violations

	var rebuilt := Fighter.from_dict(reparsed, template)
	violations.append_array(
		_expect(rebuilt != null, "from_dict() must accept a record that has been through JSON")
	)
	if rebuilt != null:
		violations.append_array(
			_expect(
				rebuilt.to_dict() == data,
				"from_dict() of a JSON-reparsed record must yield an equal to_dict()"
			)
		)

	return violations


static func _test_identical_fighters_stringify_identically() -> Array[String]:
	var template := FighterTest.make_template(3)

	var a := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)
	a.move_to(Vector3i(1, -1, 0))
	a.apply_damage(2)
	a.set_status_flag("moved")
	a.set_status_flag("guarded")

	var b := Fighter.new("fighter-1", template, "player-1", Vector3i.ZERO)
	b.move_to(Vector3i(1, -1, 0))
	b.apply_damage(2)
	b.set_status_flag("moved")
	b.set_status_flag("guarded")

	return _expect(
		JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()),
		(
			"two identically built fighters must stringify to the identical string, character "
			+ "for character -- GameState.digest() hashes exactly this"
		)
	)


## The seam GameState committed to sight-unseen: a Fighter.to_dict() is a valid
## opaque fighter payload, and carrying one changes nothing about a GameState
## round trip.
static func _test_to_dict_is_accepted_by_game_state() -> Array[String]:
	var violations: Array[String] = []
	var template := FighterTest.make_template(3)
	var coord := Vector3i(1, -1, 0)
	var fighter := Fighter.new("fighter-1", template, "player-1", coord)
	fighter.apply_damage(2)
	fighter.set_status_flag("moved")
	fighter.set_status_flag("guarded")

	var board := Board.new()
	board.add_hex(coord, Board.HexType.NORMAL)
	board.place_occupant(coord, StringName(fighter.id()))

	var state := GameState.new(board, DeterministicRng.new(20260906))
	state.add_player(fighter.owner_id())

	violations.append_array(
		_expect(
			state.add_fighter(fighter.id(), fighter.to_dict()),
			"GameState.add_fighter() must accept a Fighter.to_dict() payload"
		)
	)

	var digest_before := state.digest()
	var restored_state := GameState.from_dict(state.to_dict())

	violations.append_array(
		_expect(
			restored_state != null, "GameState.from_dict() must accept a state holding a fighter"
		)
	)
	if restored_state == null:
		return violations

	violations.append_array(
		_expect(
			restored_state.digest() == digest_before,
			"a GameState carrying a Fighter payload must round-trip with an unchanged digest"
		)
	)

	var payload := restored_state.fighter(fighter.id())
	var rebuilt := Fighter.from_dict(payload, template)

	violations.append_array(
		_expect(rebuilt != null, "a payload retrieved from a round-tripped GameState must rebuild")
	)
	if rebuilt != null:
		violations.append_array(
			_expect(
				rebuilt.to_dict() == fighter.to_dict(),
				"a fighter rebuilt out of a round-tripped GameState must equal the original"
			)
		)

	return violations


static func _test_from_dict_refusals() -> Array[String]:
	var violations: Array[String] = []
	var template := FighterTest.make_template(3)
	var fighter := Fighter.new("fighter-1", template, "player-1", Vector3i(1, -1, 0))
	fighter.apply_damage(2)
	fighter.set_status_flag("moved")

	violations.append_array(
		_expect(
			Fighter.from_dict(fighter.to_dict(), template) != null,
			"the base record every case below mutates must itself be accepted"
		)
	)

	var missing_id := fighter.to_dict()
	missing_id.erase("id")
	violations.append_array(
		_expect(
			Fighter.from_dict(missing_id, template) == null,
			'from_dict() must return null when "id" is missing'
		)
	)

	var missing_owner := fighter.to_dict()
	missing_owner.erase("owner_id")
	violations.append_array(
		_expect(
			Fighter.from_dict(missing_owner, template) == null,
			'from_dict() must return null when "owner_id" is missing'
		)
	)

	var short_position := fighter.to_dict()
	short_position["position"] = [0, 0]
	violations.append_array(
		_expect(
			Fighter.from_dict(short_position, template) == null,
			'from_dict() must return null when "position" has two elements'
		)
	)

	var unparsed_position := fighter.to_dict()
	unparsed_position["position"] = [0, 0, "0"]
	violations.append_array(
		_expect(
			Fighter.from_dict(unparsed_position, template) == null,
			'from_dict() must return null when a "position" component is not an int'
		)
	)

	var invalid_position := fighter.to_dict()
	invalid_position["position"] = [1, 1, 1]
	violations.append_array(
		_expect(
			Fighter.from_dict(invalid_position, template) == null,
			'from_dict() must return null when "position" fails HexCoord.is_valid()'
		)
	)

	var text_counter := fighter.to_dict()
	text_counter["damage_counter"] = "2"
	violations.append_array(
		_expect(
			Fighter.from_dict(text_counter, template) == null,
			'from_dict() must return null when "damage_counter" is not an integer'
		)
	)

	var fractional_counter := fighter.to_dict()
	fractional_counter["damage_counter"] = 1.5
	violations.append_array(
		_expect(
			Fighter.from_dict(fractional_counter, template) == null,
			'from_dict() must return null when "damage_counter" is a fractional float'
		)
	)

	var negative_counter := fighter.to_dict()
	negative_counter["damage_counter"] = -1
	violations.append_array(
		_expect(
			Fighter.from_dict(negative_counter, template) == null,
			(
				'from_dict() must return null when "damage_counter" is negative -- '
				+ "apply_damage() cannot produce one, so no well-formed record holds one"
			)
		)
	)

	var flags_not_array := fighter.to_dict()
	flags_not_array["status_flags"] = "moved"
	violations.append_array(
		_expect(
			Fighter.from_dict(flags_not_array, template) == null,
			'from_dict() must return null when "status_flags" is not an Array'
		)
	)

	var flags_not_strings := fighter.to_dict()
	flags_not_strings["status_flags"] = ["moved", 7]
	violations.append_array(
		_expect(
			Fighter.from_dict(flags_not_strings, template) == null,
			'from_dict() must return null when a "status_flags" entry is not a String'
		)
	)

	var duplicate_flags := fighter.to_dict()
	duplicate_flags["status_flags"] = ["moved", "moved"]
	violations.append_array(
		_expect(
			Fighter.from_dict(duplicate_flags, template) == null,
			(
				'from_dict() must return null for a repeated "status_flags" entry -- '
				+ "set_status_flag()'s own refusal is what rejects it"
			)
		)
	)

	violations.append_array(
		_expect(
			Fighter.from_dict(fighter.to_dict(), null) == null,
			"from_dict() must return null when handed no template -- it never resolves one"
		)
	)

	return violations

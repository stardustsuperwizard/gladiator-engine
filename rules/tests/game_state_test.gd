## Tests GameState and PlayerState: the round trip, the generator's position
## surviving it, digest sensitivity, ordering, JSON compatibility, the
## independence of a restored state, and every refusal path.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
##
## Every draw here goes through `state.rng`, receiver-qualified. There is no
## bare `randi()` in this file and no entry for it in
## AmbientRngContractTest.EXEMPT_FILES -- `_test_files_are_not_rng_exempt()`
## pins that.
class_name GameStateTest

const SEED := 20260906

## The range every draw in this file uses. Wide enough that two sequences
## agreeing on ten consecutive values is not coincidence.
const DRAW_LOW := 1
const DRAW_HIGH := 1000000


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_full_state_round_trips_to_equal_digest())
	violations.append_array(_test_round_trip_resumes_the_generator())
	violations.append_array(_test_identical_sequences_produce_equal_digests())
	violations.append_array(_test_changing_only_the_seed_changes_the_digest())
	violations.append_array(_test_changing_only_a_score_changes_the_digest())
	violations.append_array(_test_changing_only_round_number_changes_the_digest())
	violations.append_array(_test_changing_only_a_fighter_payload_changes_the_digest())
	violations.append_array(_test_changing_only_one_card_id_changes_the_digest())
	violations.append_array(_test_digest_is_stable_and_64_lowercase_hex())
	violations.append_array(_test_order_is_insertion_order_and_survives_round_trip())
	violations.append_array(_test_identical_states_stringify_identically())
	violations.append_array(_test_serialized_form_survives_json_reparse())
	violations.append_array(_test_restored_state_is_independent())
	violations.append_array(_test_add_player_and_player_lookup_refusals())
	violations.append_array(_test_add_fighter_and_fighter_lookup_refusals())
	violations.append_array(_test_fighter_payload_is_opaque_and_copied())
	violations.append_array(_test_from_dict_rejects_missing_board())
	violations.append_array(_test_from_dict_rejects_missing_rng())
	violations.append_array(_test_from_dict_rejects_malformed_nested_rng())
	violations.append_array(_test_from_dict_rejects_malformed_nested_board())
	violations.append_array(_test_from_dict_rejects_turn_order_naming_absent_player())
	violations.append_array(_test_from_dict_rejects_fighters_key_absent_from_order())
	violations.append_array(_test_from_dict_rejects_non_integer_counters())
	violations.append_array(_test_player_state_from_dict_refusals())
	violations.append_array(_test_no_method_draws_a_random_number())
	violations.append_array(_test_files_are_not_rng_exempt())

	if violations.is_empty():
		return true

	printerr("\n=== Game State Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## The reference state every round-trip case is built from: a board carrying
## several hex types and two occupants, two players with non-empty piles and
## distinct scores, three fighters with distinct payloads, `round_number` 2
## and `turns_taken` 5.
##
## Built by a fixed sequence of calls with a fixed seed, so calling it twice
## must produce two states with the same digest -- which is itself one of the
## cases below.
static func _build_state(seed_value: int = SEED) -> GameState:
	var board := Board.new()
	board.add_hex(Vector3i(0, 0, 0), Board.HexType.STARTING)
	board.add_hex(Vector3i(1, -1, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(2, -2, 0), Board.HexType.BLOCKED)
	board.add_hex(Vector3i(0, 1, -1), Board.HexType.HAZARD)
	board.add_hex(Vector3i(-1, 1, 0), Board.HexType.EDGE)
	board.add_hex(Vector3i(-2, 2, 0), Board.HexType.NORMAL)
	board.place_occupant(Vector3i(0, 0, 0), &"fighter_a")
	board.place_occupant(Vector3i(1, -1, 0), &"fighter_b")

	var state := GameState.new(board, DeterministicRng.new(seed_value))
	state.round_number = 2
	state.turns_taken = 5

	state.add_player("north")
	var north := state.player("north")
	north.hand.append_array(["card_thrust", "card_feint"] as Array[String])
	north.deck.append_array(["card_parry", "card_lunge", "card_riposte"] as Array[String])
	north.discard.append("card_stumble")
	north.scored.append("objective_north")
	north.score = 3

	state.add_player("south")
	var south := state.player("south")
	south.hand.append("card_shove")
	south.deck.append_array(["card_guard", "card_charge"] as Array[String])
	south.discard.append_array(["card_trip", "card_fumble"] as Array[String])
	south.scored.append_array(["objective_south", "objective_centre"] as Array[String])
	south.score = 7

	# Payload values are Strings and nested Arrays of Strings, not numbers.
	# The payload is opaque and GameState never canonicalises it, so a number
	# inside one is whatever JSON makes of it -- see
	# _test_serialized_form_survives_json_reparse() for why that matters.
	state.add_fighter("fighter_a", {"template": "murmillo", "weapons": ["gladius", "scutum"]})
	state.add_fighter("fighter_b", {"template": "retiarius", "weapons": ["trident", "net"]})
	state.add_fighter("fighter_c", {"template": "thraex", "weapons": ["sica"]})

	return state


static func _round_trip(state: GameState) -> GameState:
	return GameState.from_dict(state.to_dict())


static func _test_full_state_round_trips_to_equal_digest() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var restored := _round_trip(state)

	violations.append_array(
		_expect(restored != null, "from_dict() must accept the reference state's own to_dict()")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.digest() == state.digest(),
			"a full state must round-trip through to_dict()/from_dict() to an equal digest()"
		)
	)
	violations.append_array(
		_expect(restored.round_number == 2, "round_number must survive the round trip")
	)
	violations.append_array(
		_expect(restored.turns_taken == 5, "turns_taken must survive the round trip")
	)
	violations.append_array(
		_expect(
			restored.board.occupant_at(Vector3i(1, -1, 0)) == &"fighter_b",
			"a board occupant must survive the round trip"
		)
	)
	violations.append_array(
		_expect(restored.player("south").score == 7, "a player score must survive the round trip")
	)
	violations.append_array(
		_expect(
			(
				restored.player("north").deck
				== (["card_parry", "card_lunge", "card_riposte"] as Array)
			),
			"a card pile must survive the round trip in order"
		)
	)
	violations.append_array(
		_expect(
			restored.fighter("fighter_c") == {"template": "thraex", "weapons": ["sica"]},
			"a fighter payload must survive the round trip"
		)
	)

	return violations


## The seed-versus-state trap. A state that serialized only its generator's
## *seed* would restore a generator rewound to the start of its sequence, and
## the restored state would replay the first ten draws instead of continuing
## with the next ten. Every replay, save/load and network sync built on this
## state depends on it resuming.
##
## Note this is not the same test as DeterministicRngTest's: that one pins
## DeterministicRng.from_dict(), this one pins that GameState actually nests
## the generator's *state* and not merely its seed.
static func _test_round_trip_resumes_the_generator() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	var first_ten: Array[int] = []
	for i in range(10):
		first_ten.append(state.rng.next_int(DRAW_LOW, DRAW_HIGH))

	var snapshot := state.to_dict()

	# What the original yields *next* -- taken after the snapshot, so the
	# restored generator has to agree with these, not with first_ten.
	var expected: Array[int] = []
	for i in range(10):
		expected.append(state.rng.next_int(DRAW_LOW, DRAW_HIGH))

	var restored := GameState.from_dict(snapshot)
	violations.append_array(
		_expect(restored != null, "from_dict() must accept a snapshot taken mid-match")
	)
	if restored == null:
		return violations

	for i in range(10):
		var draw := restored.rng.next_int(DRAW_LOW, DRAW_HIGH)
		violations.append_array(
			_expect(
				draw == expected[i],
				(
					(
						"SEED-VERSUS-STATE TRAP: a restored state's generator must resume the "
						+ "sequence after the snapshot, not rewind to the seed and replay it -- "
						+ "draw %d after restore was %d, expected %d (it was %d if only the seed "
						+ "was serialized)"
					)
					% [i, draw, expected[i], first_ten[i]]
				)
			)
		)

	return violations


## Two separately constructed states, not one compared against itself: the
## claim is that the *sequence of calls* plus the seed determines the digest,
## which only a second independent build can demonstrate.
static func _test_identical_sequences_produce_equal_digests() -> Array[String]:
	var first := _build_state()
	var second := _build_state()
	return _expect(
		first.digest() == second.digest(),
		"two states built by the same sequence of calls with the same seed must have equal digest()"
	)


static func _test_changing_only_the_seed_changes_the_digest() -> Array[String]:
	return _expect(
		_build_state(SEED).digest() != _build_state(SEED + 1).digest(),
		"changing only the seed must change digest()"
	)


static func _test_changing_only_a_score_changes_the_digest() -> Array[String]:
	var state := _build_state()
	var before := state.digest()
	state.player("north").score += 1
	return _expect(state.digest() != before, "changing only a player score must change digest()")


static func _test_changing_only_round_number_changes_the_digest() -> Array[String]:
	var state := _build_state()
	var before := state.digest()
	state.round_number += 1
	return _expect(state.digest() != before, "changing only round_number must change digest()")


static func _test_changing_only_a_fighter_payload_changes_the_digest() -> Array[String]:
	var baseline := _build_state().digest()

	var state := _build_state()
	# Rebuilt rather than mutated in place: fighter() hands back a copy, which
	# is itself the point of _test_fighter_payload_is_opaque_and_copied().
	var altered := GameState.new(state.board, state.rng)
	altered.round_number = state.round_number
	altered.turns_taken = state.turns_taken
	for player_id in state.turn_order():
		altered.add_player(player_id)
		altered._players[player_id] = state.player(player_id)
	for fighter_id in state.fighter_ids():
		var payload := state.fighter(fighter_id)
		if fighter_id == "fighter_c":
			payload["template"] = "hoplomachus"
		altered.add_fighter(fighter_id, payload)

	return _expect(
		altered.digest() != baseline, "changing only one fighter payload must change digest()"
	)


static func _test_changing_only_one_card_id_changes_the_digest() -> Array[String]:
	var state := _build_state()
	var before := state.digest()
	state.player("south").deck[1] = "card_charge_variant"
	return _expect(state.digest() != before, "changing only one card id must change digest()")


static func _test_digest_is_stable_and_64_lowercase_hex() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var digest := state.digest()

	violations.append_array(
		_expect(
			digest == state.digest(), "digest() must be stable across calls on an unmutated state"
		)
	)
	violations.append_array(
		_expect(digest.length() == 64, "digest() must be 64 characters, got %d" % digest.length())
	)
	violations.append_array(
		_expect(
			RegEx.create_from_string("^[0-9a-f]{64}$").search(digest) != null,
			"digest() must be lowercase hex, got %s" % digest
		)
	)

	return violations


static func _test_order_is_insertion_order_and_survives_round_trip() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	# Ordered comparison: Array == Array in GDScript compares element by
	# element in order, so a reordered array is a failure here, not a pass.
	violations.append_array(
		_expect(
			state.turn_order() == (["north", "south"] as Array[String]),
			"turn_order() must return player ids in the order they were added"
		)
	)
	violations.append_array(
		_expect(
			state.fighter_ids() == (["fighter_a", "fighter_b", "fighter_c"] as Array[String]),
			"fighter_ids() must return fighter ids in the order they were added"
		)
	)

	var restored := _round_trip(state)
	if restored == null:
		return violations + (["from_dict() must accept the reference state"] as Array[String])

	(
		violations
		. append_array(
			_expect(
				restored.turn_order() == state.turn_order(),
				"a round-tripped state's turn_order() must be identical, same elements in the same order"
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				restored.fighter_ids() == state.fighter_ids(),
				"a round-tripped state's fighter_ids() must be identical, same elements in the same order"
			)
		)
	)
	violations.append_array(
		_expect(
			restored.board.coords() == state.board.coords(),
			"a round-tripped state's board coords() must be identical, in the same order"
		)
	)

	return violations


## Character-for-character, not merely equal as dictionaries. digest() hashes
## this string, so anything that varies in it -- a key order that follows
## Dictionary iteration rather than turn_order, say -- breaks the identity
## every later Feature compares states with.
static func _test_identical_states_stringify_identically() -> Array[String]:
	var first := JSON.stringify(_build_state().to_dict())
	var second := JSON.stringify(_build_state().to_dict())
	return _expect(
		first == second,
		(
			"JSON.stringify(to_dict()) of two identically built states must be equal as strings, "
			+ "character for character"
		)
	)


## Proves the serialized form really is JSON-compatible: no Vector3i, no
## StringName, nothing that stringifies to something JSON cannot parse back.
##
## Godot's JSON.parse_string() returns every number as a float -- JSON has one
## number type -- so the reparsed dictionary carries 2.0 where to_dict() put
## 2. from_dict() accepts that and emits an int again, which is why the digest
## still matches. Fighter payloads are exempt from that coercion on purpose:
## they are opaque and GameState never reads a key of one, so payload values
## here are Strings and Arrays of Strings, which JSON round-trips unchanged.
static func _test_serialized_form_survives_json_reparse() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	var reparsed: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	violations.append_array(
		_expect(
			typeof(reparsed) == TYPE_DICTIONARY,
			"JSON.stringify(to_dict()) must parse back to a Dictionary"
		)
	)
	if typeof(reparsed) != TYPE_DICTIONARY:
		return violations

	var restored := GameState.from_dict(reparsed)
	violations.append_array(
		_expect(restored != null, "from_dict() must accept a dictionary that has been through JSON")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.digest() == state.digest(),
			"from_dict() of a JSON-reparsed to_dict() must yield an equal digest()"
		)
	)

	return violations


static func _test_restored_state_is_independent() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var before := state.digest()

	var restored := _round_trip(state)
	violations.append_array(
		_expect(restored != null, "from_dict() must accept the reference state")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.board != state.board,
			"a restored state's Board must be a new object, not the original"
		)
	)
	violations.append_array(
		_expect(
			restored.rng != state.rng,
			"a restored state's DeterministicRng must be a new object, not the original"
		)
	)
	violations.append_array(
		_expect(
			restored.player("north") != state.player("north"),
			"a restored state's PlayerState must be a new object, not the original"
		)
	)

	restored.board.add_hex(Vector3i(3, -3, 0), Board.HexType.NORMAL)
	restored.player("north").score = 99
	restored.rng.next_int(DRAW_LOW, DRAW_HIGH)
	restored.round_number = 40
	restored.add_fighter("fighter_d", {"template": "provocator"})

	violations.append_array(
		_expect(
			state.digest() == before,
			(
				"mutating a restored state's board, a player's score, its rng, its counters or its "
				+ "fighters must leave the original state's digest() unchanged"
			)
		)
	)
	violations.append_array(
		_expect(
			not state.board.has_hex(Vector3i(3, -3, 0)),
			"a hex added to a restored board must not appear on the original board"
		)
	)
	violations.append_array(
		_expect(
			state.player("north").score == 3,
			"a score written on a restored PlayerState must not reach the original"
		)
	)

	return violations


static func _test_add_player_and_player_lookup_refusals() -> Array[String]:
	var violations: Array[String] = []
	var state := GameState.new(Board.new(), DeterministicRng.new(1))

	violations.append_array(
		_expect(state.add_player("north"), "add_player() must accept a fresh non-empty id")
	)
	violations.append_array(
		_expect(not state.add_player(""), "add_player() must return false for an empty id")
	)
	violations.append_array(
		_expect(not state.add_player("north"), "add_player() must return false for a duplicate id")
	)
	violations.append_array(
		_expect(
			state.turn_order() == (["north"] as Array[String]),
			"a refused add_player() must leave turn_order() unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.player("north") != null, "player() must return the PlayerState for a known id"
		)
	)
	violations.append_array(
		_expect(state.player("east") == null, "player() must return null for an unknown id")
	)

	return violations


static func _test_add_fighter_and_fighter_lookup_refusals() -> Array[String]:
	var violations: Array[String] = []
	var state := GameState.new(Board.new(), DeterministicRng.new(1))

	violations.append_array(
		_expect(
			state.add_fighter("fighter_a", {"template": "murmillo"}),
			"add_fighter() must accept a fresh non-empty id"
		)
	)
	violations.append_array(
		_expect(not state.add_fighter("", {}), "add_fighter() must return false for an empty id")
	)
	violations.append_array(
		_expect(
			not state.add_fighter("fighter_a", {"template": "retiarius"}),
			"add_fighter() must return false for a duplicate id"
		)
	)
	violations.append_array(
		_expect(
			state.fighter("fighter_a") == {"template": "murmillo"},
			"a refused add_fighter() must leave the existing payload unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.fighter_ids() == (["fighter_a"] as Array[String]),
			"a refused add_fighter() must leave fighter_ids() unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.fighter("fighter_z") == {},
			"fighter() must return an empty Dictionary for an unknown id"
		)
	)

	return violations


## The opaque-payload seam. GameState stores and emits a fighter payload and
## never reads a key of it, so nothing here depends on what a fighter is --
## the fighter model is a separate Feature. What this pins is that the payload
## cannot be edited through the caller's dictionary or through fighter()'s
## return value.
static func _test_fighter_payload_is_opaque_and_copied() -> Array[String]:
	var violations: Array[String] = []
	var state := GameState.new(Board.new(), DeterministicRng.new(1))

	var payload := {"template": "murmillo", "weapons": ["gladius"]}
	state.add_fighter("fighter_a", payload)

	payload["template"] = "mutated_by_caller"
	payload["weapons"].append("mutated_nested")
	violations.append_array(
		_expect(
			state.fighter("fighter_a") == {"template": "murmillo", "weapons": ["gladius"]},
			"mutating the Dictionary passed to add_fighter() must not reach the stored payload"
		)
	)

	var read_back := state.fighter("fighter_a")
	read_back["template"] = "mutated_by_reader"
	violations.append_array(
		_expect(
			state.fighter("fighter_a")["template"] == "murmillo",
			"mutating fighter()'s return value must not reach the stored payload"
		)
	)

	return violations


static func _test_from_dict_rejects_missing_board() -> Array[String]:
	var data := _build_state().to_dict()
	data.erase("board")
	return _expect(
		GameState.from_dict(data) == null, 'from_dict() must return null when "board" is missing'
	)


static func _test_from_dict_rejects_missing_rng() -> Array[String]:
	var data := _build_state().to_dict()
	data.erase("rng")
	return _expect(
		GameState.from_dict(data) == null, 'from_dict() must return null when "rng" is missing'
	)


## The nested refusal must propagate. DeterministicRng.from_dict() returns
## null for a snapshot with no "state" key, and GameState must not paper over
## that with a fresh generator -- a state whose generator position was
## invented is exactly the irreproducible state this Feature exists to prevent.
static func _test_from_dict_rejects_malformed_nested_rng() -> Array[String]:
	var data := _build_state().to_dict()
	data["rng"] = {"seed": "1"}
	return _expect(
		GameState.from_dict(data) == null,
		"from_dict() must return null when the nested DeterministicRng.from_dict() refuses"
	)


static func _test_from_dict_rejects_malformed_nested_board() -> Array[String]:
	var data := _build_state().to_dict()
	data["board"] = {"hexes": "not an array"}
	return _expect(
		GameState.from_dict(data) == null,
		"from_dict() must return null when the nested Board.from_dict() refuses"
	)


static func _test_from_dict_rejects_turn_order_naming_absent_player() -> Array[String]:
	var violations: Array[String] = []

	var missing_player := _build_state().to_dict()
	(missing_player["players"] as Dictionary).erase("south")
	violations.append_array(
		_expect(
			GameState.from_dict(missing_player) == null,
			'from_dict() must return null when turn_order names a player absent from "players"'
		)
	)

	var extra_player := _build_state().to_dict()
	(extra_player["players"] as Dictionary)["east"] = PlayerState.new().to_dict()
	violations.append_array(
		_expect(
			GameState.from_dict(extra_player) == null,
			'from_dict() must return null when "players" holds a key absent from turn_order'
		)
	)

	return violations


static func _test_from_dict_rejects_fighters_key_absent_from_order() -> Array[String]:
	var violations: Array[String] = []

	var extra_fighter := _build_state().to_dict()
	(extra_fighter["fighters"] as Dictionary)["fighter_d"] = {"template": "provocator"}
	violations.append_array(
		_expect(
			GameState.from_dict(extra_fighter) == null,
			'from_dict() must return null when "fighters" holds a key absent from fighter_order'
		)
	)

	var missing_fighter := _build_state().to_dict()
	(missing_fighter["fighters"] as Dictionary).erase("fighter_b")
	violations.append_array(
		_expect(
			GameState.from_dict(missing_fighter) == null,
			'from_dict() must return null when fighter_order names a fighter absent from "fighters"'
		)
	)

	return violations


static func _test_from_dict_rejects_non_integer_counters() -> Array[String]:
	var violations: Array[String] = []

	var text_round := _build_state().to_dict()
	text_round["round_number"] = "2"
	violations.append_array(
		_expect(
			GameState.from_dict(text_round) == null,
			"from_dict() must return null when round_number is a String"
		)
	)

	var fractional_turns := _build_state().to_dict()
	fractional_turns["turns_taken"] = 5.5
	violations.append_array(
		_expect(
			GameState.from_dict(fractional_turns) == null,
			"from_dict() must return null when turns_taken is a fractional float"
		)
	)

	return violations


static func _test_player_state_from_dict_refusals() -> Array[String]:
	var violations: Array[String] = []
	var valid := {"hand": [], "deck": [], "discard": [], "scored": [], "score": 0}

	violations.append_array(
		_expect(
			PlayerState.from_dict(valid) != null, "from_dict() must accept a well-formed record"
		)
	)

	for key in ["hand", "deck", "discard", "scored", "score"]:
		var missing := valid.duplicate(true)
		missing.erase(key)
		violations.append_array(
			_expect(
				PlayerState.from_dict(missing) == null,
				'PlayerState.from_dict() must return null when "%s" is missing' % key
			)
		)

	var non_string_card := valid.duplicate(true)
	non_string_card["hand"] = [7]
	violations.append_array(
		_expect(
			PlayerState.from_dict(non_string_card) == null,
			"PlayerState.from_dict() must return null when a pile holds a non-String card id"
		)
	)

	var text_score := valid.duplicate(true)
	text_score["score"] = "3"
	violations.append_array(
		_expect(
			PlayerState.from_dict(text_score) == null,
			"PlayerState.from_dict() must return null when score is a String"
		)
	)

	return violations


## `state.rng` is the only route to the generator. A convenience passthrough
## on GameState -- roll_die(), next_int() -- would hide the generator behind
## the state, which is the ambient-randomness habit under a different name, so
## no GameState method may advance the generator's position.
static func _test_no_method_draws_a_random_number() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	for method_name in ["roll_die", "next_int", "randi", "random", "draw"]:
		violations.append_array(
			_expect(
				not state.has_method(method_name),
				(
					"GameState must not expose %s() -- state.rng is the only route to the generator"
					% method_name
				)
			)
		)

	var position := state.rng.get_state()

	state.turn_order()
	state.fighter_ids()
	state.player("north")
	state.player("unknown")
	state.fighter("fighter_a")
	state.fighter("unknown")
	state.add_player("east")
	state.add_fighter("fighter_d", {"template": "provocator"})
	state.to_dict()
	state.digest()
	GameState.from_dict(state.to_dict())

	violations.append_array(
		_expect(
			state.rng.get_state() == position,
			"no GameState method may advance the generator's position"
		)
	)

	return violations


## The ambient RNG contract covers these files rather than exempting them.
## EXEMPT_FILES is for scanners that name the forbidden identifiers as data;
## an entry for ordinary rules code would be a standing hole.
static func _test_files_are_not_rng_exempt() -> Array[String]:
	var violations: Array[String] = []

	for path in [
		"res://rules/state/game_state.gd",
		"res://rules/state/player_state.gd",
		"res://rules/tests/game_state_test.gd",
	]:
		violations.append_array(
			_expect(
				path not in AmbientRngContractTest.EXEMPT_FILES,
				"%s must be scanned by the ambient RNG contract, not exempted from it" % path
			)
		)

	return violations

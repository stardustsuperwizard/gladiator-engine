## Tests Flanking.bonus_count(): the NONE/FLANKED/SURROUNDED tiers, the
## exclusion of the other active participant, owner filtering, adjacency-only
## range, capping at SURROUNDED, and skipping malformed candidate entries.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name FlankingTest

const PLAYER_A := "player_a"
const PLAYER_B := "player_b"

## Cube-coordinate fixture shared by every test below.
const ORIGIN := Vector3i(0, 0, 0)


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_no_adjacent_fighters_returns_none())
	violations.append_array(_test_one_adjacent_enemy_returns_flanked())
	violations.append_array(_test_two_adjacent_enemies_return_surrounded())
	violations.append_array(_test_three_or_more_adjacent_enemies_stay_capped_at_surrounded())
	violations.append_array(_test_excluded_fighter_id_is_not_counted())
	violations.append_array(_test_same_owner_adjacent_fighter_is_not_counted())
	violations.append_array(_test_enemy_at_distance_two_is_not_counted())
	violations.append_array(_test_symmetric_check_on_one_board_gives_independent_answers())
	violations.append_array(_test_malformed_candidates_are_skipped())
	violations.append_array(_test_empty_candidates_returns_none())

	if violations.is_empty():
		return true

	printerr("\n=== Flanking Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Builds one normalised candidate entry, exactly the shape bonus_count()
## expects: {"id": String, "owner_id": String, "position": Vector3i}.
static func _candidate(id: String, owner_id: String, position: Vector3i) -> Dictionary:
	return {
		Flanking.ID_KEY: id,
		Flanking.OWNER_ID_KEY: owner_id,
		Flanking.POSITION_KEY: position,
	}


static func _test_no_adjacent_fighters_returns_none() -> Array[String]:
	var candidates: Array[Dictionary] = [
		_candidate("far", PLAYER_B, HexCoord.neighbour(ORIGIN, 0) + HexCoord.DIRECTIONS[0]),
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.NONE, "no adjacent fighters at all must return NONE, got %d" % result
	)


static func _test_one_adjacent_enemy_returns_flanked() -> Array[String]:
	var candidates: Array[Dictionary] = [
		_candidate("enemy1", PLAYER_B, HexCoord.neighbour(ORIGIN, 0)),
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.FLANKED,
		(
			"exactly one adjacent enemy other than the excluded fighter must return FLANKED, got %d"
			% result
		)
	)


static func _test_two_adjacent_enemies_return_surrounded() -> Array[String]:
	var candidates: Array[Dictionary] = [
		_candidate("enemy1", PLAYER_B, HexCoord.neighbour(ORIGIN, 0)),
		_candidate("enemy2", PLAYER_B, HexCoord.neighbour(ORIGIN, 1)),
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.SURROUNDED,
		(
			"two adjacent enemies other than the excluded fighter must return SURROUNDED, got %d"
			% result
		)
	)


static func _test_three_or_more_adjacent_enemies_stay_capped_at_surrounded() -> Array[String]:
	var candidates: Array[Dictionary] = [
		_candidate("enemy1", PLAYER_B, HexCoord.neighbour(ORIGIN, 0)),
		_candidate("enemy2", PLAYER_B, HexCoord.neighbour(ORIGIN, 1)),
		_candidate("enemy3", PLAYER_B, HexCoord.neighbour(ORIGIN, 2)),
		_candidate("enemy4", PLAYER_B, HexCoord.neighbour(ORIGIN, 3)),
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.SURROUNDED,
		(
			(
				"four adjacent enemies must still return SURROUNDED (%d), capped rather than "
				+ "counted, got %d"
			)
			% [Flanking.SURROUNDED, result]
		)
	)


## Asserts the exclusion actually changes the answer: the same single adjacent
## enemy is excluded by id in one call and not excluded in another.
static func _test_excluded_fighter_id_is_not_counted() -> Array[String]:
	var violations: Array[String] = []
	var candidates: Array[Dictionary] = [
		_candidate("attacker", PLAYER_B, HexCoord.neighbour(ORIGIN, 0)),
	]

	var excluded_result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)
	violations.append_array(
		_expect(
			excluded_result == Flanking.NONE,
			(
				"an adjacent enemy whose id equals excluded_fighter_id must not be counted, got %d"
				% excluded_result
			)
		)
	)

	var included_result := Flanking.bonus_count(ORIGIN, PLAYER_A, "someone_else", candidates)
	violations.append_array(
		_expect(
			included_result == Flanking.FLANKED,
			(
				(
					"the same candidate, no longer excluded, must be counted -- proving the "
					+ "exclusion in the prior call actually changed the answer, got %d"
				)
				% included_result
			)
		)
	)

	return violations


static func _test_same_owner_adjacent_fighter_is_not_counted() -> Array[String]:
	var candidates: Array[Dictionary] = [
		_candidate("ally", PLAYER_A, HexCoord.neighbour(ORIGIN, 0)),
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.NONE,
		"an adjacent fighter sharing subject_owner_id must not be counted, got %d" % result
	)


static func _test_enemy_at_distance_two_is_not_counted() -> Array[String]:
	var far_position := HexCoord.neighbour(ORIGIN, 0) + HexCoord.DIRECTIONS[0]
	var candidates: Array[Dictionary] = [
		_candidate("enemy_far", PLAYER_B, far_position),
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.NONE,
		"an enemy at distance 2 or more must not be counted, got %d" % result
	)


## One board arrangement, both directions of spec §8's symmetric check:
## attacker at ORIGIN, target adjacent to it. Two of player_a's other
## fighters flank the target (not adjacent to the attacker); one of
## player_b's other fighters flanks the attacker (not adjacent to the
## target). bonus_count() is called once per subject, each excluding the
## other active participant, and the two answers must differ -- the
## attacker being flanked, not just the target, is the case spec §8 requires.
static func _test_symmetric_check_on_one_board_gives_independent_answers() -> Array[String]:
	var violations: Array[String] = []

	var attacker_position := ORIGIN
	var target_position := HexCoord.neighbour(ORIGIN, 0)

	# Adjacent to target_position, distance 2 from attacker_position.
	var target_flanker_a := target_position + HexCoord.DIRECTIONS[0]
	var target_flanker_b := target_position + HexCoord.DIRECTIONS[1]

	# Adjacent to attacker_position, distance 2 from target_position.
	var attacker_flanker := HexCoord.neighbour(ORIGIN, 2)

	violations.append_array(
		_expect(
			HexCoord.are_adjacent(attacker_position, target_position),
			"fixture error: attacker and target must be adjacent"
		)
	)
	violations.append_array(
		_expect(
			(
				not HexCoord.are_adjacent(attacker_position, target_flanker_a)
				and not HexCoord.are_adjacent(attacker_position, target_flanker_b)
			),
			"fixture error: the target's flankers must not also be adjacent to the attacker"
		)
	)
	violations.append_array(
		_expect(
			not HexCoord.are_adjacent(target_position, attacker_flanker),
			"fixture error: the attacker's flanker must not also be adjacent to the target"
		)
	)

	var candidates: Array[Dictionary] = [
		_candidate("attacker", PLAYER_A, attacker_position),
		_candidate("target", PLAYER_B, target_position),
		_candidate("target_flanker_a", PLAYER_A, target_flanker_a),
		_candidate("target_flanker_b", PLAYER_A, target_flanker_b),
		_candidate("attacker_flanker", PLAYER_B, attacker_flanker),
	]

	var target_bonus := Flanking.bonus_count(target_position, PLAYER_B, "attacker", candidates)
	violations.append_array(
		_expect(
			target_bonus == Flanking.SURROUNDED,
			(
				"the target, excluding the attacker, must be SURROUNDED by its two flankers, got %d"
				% target_bonus
			)
		)
	)

	var attacker_bonus := Flanking.bonus_count(attacker_position, PLAYER_A, "target", candidates)
	violations.append_array(
		_expect(
			attacker_bonus == Flanking.FLANKED,
			(
				(
					"the attacker, excluding the target, must independently be FLANKED by its own "
					+ "adjacent enemy, got %d"
				)
				% attacker_bonus
			)
		)
	)

	violations.append_array(
		_expect(
			target_bonus != attacker_bonus,
			"the two calls on one board arrangement must produce independent, differing answers"
		)
	)

	return violations


## A missing owner_id, a missing position, and a position that is not a
## Vector3i each describe a fighter that would otherwise be an adjacent
## enemy -- and each must be skipped rather than counted or erroring.
static func _test_malformed_candidates_are_skipped() -> Array[String]:
	var violations: Array[String] = []
	var adjacent := HexCoord.neighbour(ORIGIN, 0)

	var missing_owner_id := {
		Flanking.ID_KEY: "no_owner",
		Flanking.POSITION_KEY: adjacent,
	}
	var missing_position := {
		Flanking.ID_KEY: "no_position",
		Flanking.OWNER_ID_KEY: PLAYER_B,
	}
	var wrong_position_type := {
		Flanking.ID_KEY: "wrong_position_type",
		Flanking.OWNER_ID_KEY: PLAYER_B,
		Flanking.POSITION_KEY: [adjacent.x, adjacent.y, adjacent.z],
	}

	var candidates: Array[Dictionary] = [
		missing_owner_id,
		missing_position,
		wrong_position_type,
	]

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	violations.append_array(
		_expect(
			result == Flanking.NONE,
			(
				(
					"a candidate missing owner_id, missing position, or holding a non-Vector3i "
					+ "position must be skipped entirely, got %d"
				)
				% result
			)
		)
	)

	return violations


static func _test_empty_candidates_returns_none() -> Array[String]:
	var candidates: Array[Dictionary] = []

	var result := Flanking.bonus_count(ORIGIN, PLAYER_A, "attacker", candidates)

	return _expect(
		result == Flanking.NONE, "an empty candidates array must return NONE, got %d" % result
	)

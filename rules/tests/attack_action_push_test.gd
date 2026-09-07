## Push-back tests for `AttackAction`, spec §7.6-7.7.
##
## **Not a second test suite.** `test_bootstrap.gd`'s `_suites` gains no entry
## for this file, and it defines no independent `run() -> bool` of its own --
## `run()` below returns `Array[String]`, the same shape every private test
## method in `AttackActionTest` already returns. `AttackActionTest.run()`
## calls it directly and folds the result into its own violations, so a
## failure here still reports as "FAIL Attack Action Test", the one suite of
## record; nothing here ever prints its own PASS/FAIL line.
##
## **Why a second file at all.** Adding these tests to `attack_action_test.gd`
## itself pushes that file past gdlint's `max-file-lines` (.gdlintrc). That
## file's own comment prescribes exactly this response: "when a file
## approaches the limit, split it" -- rather than raising the ceiling or
## thinning the acceptance coverage to fit.
##
## **No fixture is redefined.** Every helper below -- `_weapon()`, `_place()`,
## `_build_state()`, `ATTACKER_HEX` and the rest -- is a one-line forward onto
## `AttackActionTest`'s own, so this file carries no second copy of a fixture
## the parent suite already defines and whose tests already exercise it.
class_name AttackActionPushTest
extends RefCounted

const ATTACKER_HEX := AttackActionTest.ATTACKER_HEX
const TARGET_HEX := AttackActionTest.TARGET_HEX
const FAR_HEX := AttackActionTest.FAR_HEX


static func run() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(_test_push_back_hit_moves_the_target_away())
	violations.append_array(_test_pushed_target_gains_no_status_flag())
	violations.append_array(_test_push_back_drawn_moves_the_target_and_spares_damage())
	violations.append_array(_test_push_back_miss_does_not_move_the_target())
	violations.append_array(_test_push_back_false_never_moves_the_target())
	violations.append_array(_test_a_defeated_target_is_not_pushed())
	violations.append_array(_test_push_destination_blocked_leaves_the_target_in_place())
	violations.append_array(_test_push_destination_occupied_leaves_the_target_in_place())
	violations.append_array(_test_push_destination_off_board_leaves_the_target_in_place())
	violations.append_array(_test_push_destination_tie_break_uses_directions_order())
	violations.append_array(_test_ranged_push_moves_the_target_one_hex_directly_away())
	violations.append_array(_test_equal_seeds_produce_identical_digest_with_a_push())

	return violations


# --- Fixtures, forwarded onto AttackActionTest's own ----------------------


static func _expect(condition: bool, message: String) -> Array[String]:
	return AttackActionTest._expect(condition, message)


static func _fighter_template(save: int, health: int) -> FighterTemplate:
	return AttackActionTest._fighter_template(save, health)


static func _weapon(
	range_hexes: int, dice_count: int, damage_value: int, weapon_type: String = WeaponTemplate.MELEE
) -> WeaponTemplate:
	return AttackActionTest._weapon(range_hexes, dice_count, damage_value, weapon_type)


static func _always_profile() -> DiceProfile:
	return AttackActionTest._always_profile()


static func _never_profile() -> DiceProfile:
	return AttackActionTest._never_profile()


static func _attack_profile() -> DiceProfile:
	return AttackActionTest._attack_profile()


static func _save_profile() -> DiceProfile:
	return AttackActionTest._save_profile()


static func _build_state(seed_value: int, blocked: Array[Vector3i] = []) -> GameState:
	return AttackActionTest._build_state(seed_value, blocked)


static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate,
	damage: int = 0
) -> void:
	AttackActionTest._place(state, fighter_id, owner_id, coord, template, damage)


static func _stored_damage(state: GameState, fighter_id: String, template: FighterTemplate) -> int:
	return AttackActionTest._stored_damage(state, fighter_id, template)


static func _stored_position(
	state: GameState, fighter_id: String, template: FighterTemplate
) -> Vector3i:
	return AttackActionTest._stored_position(state, fighter_id, template)


static func _happy_path_state(seed_value: int, template: FighterTemplate) -> GameState:
	return AttackActionTest._happy_path_state(seed_value, template)


# --- Tests ------------------------------------------------------------------


## `TARGET_HEX`'s six neighbours, by `HexCoord.DIRECTIONS` index, against
## `ATTACKER_HEX` at the origin: distances `[2, 2, 1, 0, 1, 2]`. Index 3 is
## `ATTACKER_HEX` itself -- occupied and so never a legal destination -- and
## indices 0, 1 and 5 tie for furthest at distance 2. The tie-break keeps the
## lowest index, index 0, which is `FAR_HEX`: `TARGET_HEX + HexCoord.
## DIRECTIONS[0] == FAR_HEX`. Every adjacent-attack push test below relies on
## that identity; `_test_push_destination_tie_break_uses_directions_order()`
## is where it is spelled out and asserted directly.
static func _test_push_back_hit_moves_the_target_away() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(result.success, "a pushing Hit must still resolve successfully")
	)
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.HIT, "this scenario must resolve to a HIT")
	)
	violations.append_array(
		_expect(action.pushed(), "a Hit with push_back true must report pushed()")
	)
	violations.append_array(
		_expect(
			HexCoord.distance(TARGET_HEX, _stored_position(state, "b1", template)) == 1,
			"a push must move the target's stored position by exactly one hex"
		)
	)
	violations.append_array(
		_expect(
			(
				HexCoord.distance(ATTACKER_HEX, _stored_position(state, "b1", template))
				> HexCoord.distance(ATTACKER_HEX, TARGET_HEX)
			),
			"a push must leave the target farther from the attacker than before"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == Board.EMPTY_OCCUPANT,
			"a successful push must free the target's old hex"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(FAR_HEX) == &"b1",
			"a successful push must claim the destination hex for the target"
		)
	)

	return violations


## The strong assertion the architecture constraints call for: after a push
## `status_flags()` is empty, not merely missing `"moved"`. No `"moved"`
## constant exists yet, and none is defined here.
static func _test_pushed_target_gains_no_status_flag() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	action.resolve(state)

	violations.append_array(_expect(action.pushed(), "this scenario must actually push the target"))
	var stored := Fighter.from_dict(state.fighter("b1"), template)
	violations.append_array(
		_expect(
			stored != null and stored.status_flags().is_empty(),
			'a pushed target\'s status_flags() must be empty -- no "moved" flag and no other'
		)
	)

	return violations


## A Drawn is pushable too, and a push changes nothing about damage: the
## target still takes none.
static func _test_push_back_drawn_moves_the_target_and_spares_damage() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	# Two attack dice, two save dice, every face a critical on both: 2 and 2.
	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 2, 2), template, _always_profile(), _always_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(result.success, "a pushing Drawn must still resolve successfully")
	)
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.DRAWN, "this scenario must resolve to a DRAWN")
	)
	violations.append_array(
		_expect(action.pushed(), "a Drawn with push_back true must push the target")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == FAR_HEX,
			"a Drawn push must move the target to the same destination a Hit would"
		)
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", template) == 0,
			"a Drawn push must still leave the stored damage_counter unchanged"
		)
	)

	return violations


## A Miss is never pushed, `push_back` notwithstanding.
static func _test_push_back_miss_does_not_move_the_target() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 2), template, _never_profile(), _always_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.MISS, "this scenario must resolve to a MISS")
	)
	violations.append_array(_expect(result.success, "a Miss must still resolve successfully"))
	violations.append_array(
		_expect(not action.pushed(), "a Miss must never push, even with push_back true")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a Miss must leave the target's stored position unchanged"
		)
	)

	return violations


## `push_back` explicitly `false` moves the target on none of the three
## outcomes -- the default every earlier test in this suite already relies on,
## asserted here directly and for all three at once.
static func _test_push_back_false_never_moves_the_target() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)

	# label, attack profile, save profile, expected outcome
	var cases := [
		["Hit", _always_profile(), _never_profile(), DicePool.Outcome.HIT],
		["Drawn", _always_profile(), _always_profile(), DicePool.Outcome.DRAWN],
		["Miss", _never_profile(), _always_profile(), DicePool.Outcome.MISS],
	]

	for entry in cases:
		var label: String = entry[0]
		var attack_profile: DiceProfile = entry[1]
		var save_profile: DiceProfile = entry[2]
		var expected: DicePool.Outcome = entry[3]

		var state := _build_state(13)
		_place(state, "a1", "p1", ATTACKER_HEX, template)
		_place(state, "b1", "p2", TARGET_HEX, template)

		var action := AttackAction.new(
			"a1", "b1", _weapon(1, 2, 1), template, attack_profile, save_profile, false
		)
		action.resolve(state)

		violations.append_array(
			_expect(
				action.outcome() == expected,
				"the %s case must actually resolve to %s" % [label, expected]
			)
		)
		violations.append_array(
			_expect(not action.pushed(), "push_back false must never push, on a %s" % label)
		)
		violations.append_array(
			_expect(
				_stored_position(state, "b1", template) == TARGET_HEX,
				"push_back false must leave the target's stored position unchanged on a %s" % label
			)
		)

	return violations


## Spec §9 has already taken a defeated target off the board by the time the
## push step runs; it is not pushed on top of that.
static func _test_a_defeated_target_is_not_pushed() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 1)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating attack must resolve successfully"))
	violations.append_array(
		_expect(action.target_defeated(), "this scenario must actually defeat the target")
	)
	violations.append_array(_expect(not action.pushed(), "a defeated target must never be pushed"))
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a defeated target's stored position must be unchanged -- it was removed, not moved"
		)
	)

	return violations


## The destination BLOCKED refuses the push, not the attack.
static func _test_push_destination_blocked_leaves_the_target_in_place() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13, [FAR_HEX])
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			result.success, "a push refused for a BLOCKED destination is still a resolved attack"
		)
	)
	violations.append_array(
		_expect(not action.pushed(), "a BLOCKED destination must refuse the push")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a refused push must leave the target's stored position unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == &"b1",
			"a refused push must leave the target occupying its original hex"
		)
	)

	return violations


## An already-occupied destination refuses the push the same way a BLOCKED one
## does.
static func _test_push_destination_occupied_leaves_the_target_in_place() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_place(state, "c1", "p1", FAR_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			result.success, "a push refused for an occupied destination is still a resolved attack"
		)
	)
	violations.append_array(
		_expect(not action.pushed(), "an occupied destination must refuse the push")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a refused push must leave the target's stored position unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(FAR_HEX) == &"c1",
			"a refused push must leave the occupant already there in place"
		)
	)

	return violations


## The destination having no hex at all -- the target stands on the board
## edge -- refuses the push exactly like a BLOCKED one, through the same
## `Board.place_occupant()` check; this fixture just never adds that hex.
static func _test_push_destination_off_board_leaves_the_target_in_place() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)

	var board := Board.new()
	board.add_hex(ATTACKER_HEX, Board.HexType.NORMAL)
	board.add_hex(TARGET_HEX, Board.HexType.NORMAL)
	var state := GameState.new(board, DeterministicRng.new(13))
	state.add_player("p1")
	state.add_player("p2")
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	violations.append_array(
		_expect(
			not state.board.has_hex(FAR_HEX),
			"this fixture must not contain the push destination at all"
		)
	)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(result.success, "a push refused for a missing hex is still a resolved attack")
	)
	violations.append_array(
		_expect(not action.pushed(), "a destination with no hex at all must refuse the push")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a refused push must leave the target's stored position unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == &"b1",
			"a refused push must leave the target occupying its original hex"
		)
	)

	return violations


## Names the `HexCoord.DIRECTIONS` tie-break directly: indices 0, 1 and 5 of
## `TARGET_HEX`'s neighbours are equally far from `ATTACKER_HEX`, and the
## chosen destination is index 0, `FAR_HEX` -- never index 1 or index 5.
static func _test_push_destination_tie_break_uses_directions_order() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)

	var tied_at_1 := HexCoord.neighbour(TARGET_HEX, 1)
	var tied_at_5 := HexCoord.neighbour(TARGET_HEX, 5)
	var winner := HexCoord.neighbour(TARGET_HEX, 0)

	violations.append_array(
		_expect(winner == FAR_HEX, "this suite's FAR_HEX must be TARGET_HEX's neighbour 0")
	)
	violations.append_array(
		_expect(
			(
				(
					HexCoord.distance(ATTACKER_HEX, tied_at_1)
					== HexCoord.distance(ATTACKER_HEX, winner)
				)
				and (
					HexCoord.distance(ATTACKER_HEX, tied_at_5)
					== HexCoord.distance(ATTACKER_HEX, winner)
				)
			),
			"this scenario requires neighbours 0, 1 and 5 to tie for furthest from the attacker"
		)
	)

	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile(), true
	)
	action.resolve(state)

	violations.append_array(_expect(action.pushed(), "this scenario must actually push the target"))
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == winner,
			"a tie among neighbours must resolve to the lowest HexCoord.DIRECTIONS index"
		)
	)
	violations.append_array(
		_expect(
			(
				_stored_position(state, "b1", template) != tied_at_1
				and _stored_position(state, "b1", template) != tied_at_5
			),
			"a tie among neighbours must not resolve to a higher HexCoord.DIRECTIONS index"
		)
	)

	return violations


## `target + (target - attacker)` is a single hex step and only correct when
## the two are adjacent; this scenario keeps the attacker two hexes from the
## target so a ranged push exercises the real rule instead. `FAR_HEX`'s
## furthest neighbour from `ATTACKER_HEX` is `(3, -3, 0)`, on the straight
## line continuing past `FAR_HEX` away from the attacker -- worked by the same
## distance table `_test_push_destination_tie_break_uses_directions_order()`
## documents, one ring further out.
static func _test_ranged_push_moves_the_target_one_hex_directly_away() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var weapon := _weapon(2, 3, 1, WeaponTemplate.RANGED)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", FAR_HEX, template)

	violations.append_array(
		_expect(
			HexCoord.distance(ATTACKER_HEX, FAR_HEX) == 2,
			"this scenario requires the attacker two hexes from the target"
		)
	)

	var action := AttackAction.new(
		"a1", "b1", weapon, template, _always_profile(), _never_profile(), true
	)
	var result := action.resolve(state)

	var expected_destination := Vector3i(3, -3, 0)
	var stored := _stored_position(state, "b1", template)

	violations.append_array(_expect(result.success, "a ranged pushing Hit must still resolve"))
	violations.append_array(_expect(action.pushed(), "a ranged Hit with push_back true must push"))
	violations.append_array(
		_expect(
			HexCoord.distance(FAR_HEX, stored) == 1,
			"a ranged push must move the target by exactly one hex, same as an adjacent one"
		)
	)
	violations.append_array(
		_expect(
			stored == expected_destination,
			"a ranged push must land on the neighbour continuing straight away from the attacker"
		)
	)
	violations.append_array(
		_expect(
			HexCoord.distance(ATTACKER_HEX, stored) > HexCoord.distance(ATTACKER_HEX, FAR_HEX),
			"a ranged push must leave the target farther from the attacker than before"
		)
	)

	return violations


## The same starting state and the same pushing attack, from equal seeds,
## twice -- the push step draws nothing from `state.rng`, so this must hold
## exactly as it does without a push.
static func _test_equal_seeds_produce_identical_digest_with_a_push() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 3)

	var first_state := _happy_path_state(13, template)
	var first := AttackAction.new(
		"a1", "b1", _weapon(1, 4, 1), template, _attack_profile(), _save_profile(), true
	)
	first.resolve(first_state)

	var second_state := _happy_path_state(13, template)
	var second := AttackAction.new(
		"a1", "b1", _weapon(1, 4, 1), template, _attack_profile(), _save_profile(), true
	)
	second.resolve(second_state)

	violations.append_array(
		_expect(
			first.pushed() == second.pushed(),
			"two resolutions from equal seeds must agree on whether the push happened"
		)
	)
	violations.append_array(
		_expect(
			first_state.digest() == second_state.digest(),
			"two resolutions from equal seeds must leave states with the identical digest"
		)
	)

	return violations

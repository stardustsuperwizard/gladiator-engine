## Tests AttackAction.resolve() in isolation: called directly, with no gate
## involved and no game-side type named anywhere in this file.
##
## That omission is deliberate, and it is the same one `pass_action_test.gd`
## documents. This suite lives under `rules/`, and `rules/` uses no game-side
## class at all -- not by `res://` path and not by global `class_name` -- so the
## assertion that an attack resolves through `ActionRunner.run()` cannot live
## here. It lives in `tests/action_runner_test.gd`, which is game-side.
##
## Every fixture `WeaponTemplate`, `FighterTemplate` and `DiceProfile` here is
## built in memory with faces and numbers chosen for this suite, never loaded
## from `resources/`: `extraction_contract_test.gd` forbids naming a
## `res://resources/` path under `rules/`, and retuning the authored provisional
## content must never be able to break this suite.
##
## **Two fixture styles, on purpose.**
##
## `_attack_profile()` and `_save_profile()` are ordinary multi-face dice, used
## by `_test_hand_worked_attack_matches_worked_sequence()` -- the specification
## test the parent Feature requires -- and by the draw-order and determinism
## tests. Their expected face-index sequence for a fixed seed is recorded in a
## comment at that test, captured once from a real run and then worked by hand
## against spec §7.
##
## Everywhere else the profiles are `_one_face_profile()`: a die whose every
## face shows the same symbol, so the roll is fixed no matter where the
## generator stands. That makes Hit / Drawn / Miss, the flanking tiers and
## defeat assertable on the *rule* rather than on a recorded dice sequence, so
## those tests cannot rot the way a pinned sequence can and cannot pass by
## accident of the seed.
class_name AttackActionTest

const ATTACKER_HEX := Vector3i(0, 0, 0)
const TARGET_HEX := Vector3i(1, -1, 0)

## Adjacent to the target, and to the attacker. Used for the friendly flanker.
const TARGET_FLANK_A := Vector3i(1, 0, -1)

## Adjacent to the target. The second flanker, for the surrounded tier.
const TARGET_FLANK_B := Vector3i(0, -1, 1)

## Adjacent to the attacker and two hexes from the target, so an enemy standing
## here flanks the attacker without also flanking itself into the attack roll.
const ATTACKER_FLANK := Vector3i(-1, 1, 0)

## Two hexes from the attacker, with `TARGET_HEX` on the line between them.
const FAR_HEX := Vector3i(2, -2, 0)

const BOARD_RADIUS := 3


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_every_refusal_leaves_the_state_identical())
	violations.append_array(_test_target_at_exactly_range_is_allowed())
	violations.append_array(_test_missing_injected_data_is_refused())
	violations.append_array(_test_hand_worked_attack_matches_worked_sequence())
	violations.append_array(_test_attack_pool_is_drawn_entirely_before_the_save_pool())
	violations.append_array(_test_hit_applies_the_weapons_damage())
	violations.append_array(_test_drawn_leaves_the_damage_counter_alone())
	violations.append_array(_test_miss_resolves_successfully_and_deals_nothing())
	violations.append_array(_test_flanked_target_unlocks_the_first_bonus_symbol())
	violations.append_array(_test_surrounded_target_unlocks_the_second_bonus_symbol())
	violations.append_array(_test_flanked_attacker_unlocks_a_bonus_on_the_save_roll())
	violations.append_array(_test_happy_path_from_the_parent_feature())
	violations.append_array(_test_defeat_clears_the_hex_and_keeps_the_payload())
	violations.append_array(_test_equal_seeds_produce_identical_outcome_and_digest())

	# Spec §7.6-7.7's push-back tests live in attack_action_push_test.gd, not
	# here: see that file's docstring for why the split exists and why it is
	# not a second suite. Folded into this class's own violations, so a
	# failure still reports as "FAIL Attack Action Test", the one suite of
	# record.
	violations.append_array(AttackActionPushTest.run())

	if violations.is_empty():
		return true

	printerr("\n=== Attack Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures -----------------------------------------------------------


## A weapon built for one test. Every number is an argument, so no test reads a
## balance value it did not choose.
static func _weapon(
	range_hexes: int, dice_count: int, damage_value: int, weapon_type: String = WeaponTemplate.MELEE
) -> WeaponTemplate:
	var weapon := WeaponTemplate.new()
	weapon.template_id = "fixture-weapon"
	weapon.range_hexes = range_hexes
	weapon.dice_count = dice_count
	weapon.damage_value = damage_value
	weapon.weapon_type = weapon_type
	return weapon


static func _fighter_template(save: int, health: int) -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "fixture-fighter"
	template.move = 1
	template.save = save
	template.health = health
	return template


## A four-face attack die: index 0 critical, 1 melee, 2 ranged, 3 opening.
static func _attack_profile() -> DiceProfile:
	var profile := DiceProfile.new()
	profile.profile_id = "fixture-attack-die"
	profile.faces = PackedStringArray(["critical", "melee", "ranged", "opening"])
	profile.match_symbol = "melee"
	profile.bonus_symbols = PackedStringArray(["opening", "advantage"])
	return profile


## A six-face save die. Six faces rather than four so the two pools cannot be
## confused for one another when a draw sequence is read back.
static func _save_profile() -> DiceProfile:
	var profile := DiceProfile.new()
	profile.profile_id = "fixture-save-die"
	profile.faces = PackedStringArray(["critical", "guard", "guard", "blank", "opening", "blank"])
	profile.match_symbol = "guard"
	profile.bonus_symbols = PackedStringArray(["opening", "advantage"])
	return profile


## A die every one of whose faces shows `symbol`, so its roll is fixed wherever
## the generator stands. `match_symbol` is what this die counts by default;
## `bonus_symbols` is the standard ordered pair, so `symbol` can be chosen to
## land inside or outside the success set at a given bonus tier.
static func _one_face_profile(symbol: String, match_symbol: String) -> DiceProfile:
	var profile := DiceProfile.new()
	profile.profile_id = "fixture-fixed-die"
	profile.faces = PackedStringArray([symbol])
	profile.match_symbol = match_symbol
	profile.bonus_symbols = PackedStringArray(["opening", "advantage"])
	return profile


## Every face a critical, so every die is a success on either roll.
static func _always_profile() -> DiceProfile:
	return _one_face_profile(DicePool.CRITICAL, "guard")


## Every face a symbol in no success set at any bonus tier, so no die ever
## counts.
static func _never_profile() -> DiceProfile:
	return _one_face_profile("blank", "guard")


## A radius-`BOARD_RADIUS` board of NORMAL hexes, with `blocked` made BLOCKED.
static func _build_board(blocked: Array[Vector3i]) -> Board:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		for y in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
			var coord := Vector3i(x, y, -x - y)
			if absi(coord.z) > BOARD_RADIUS:
				continue
			board.add_hex(
				coord, Board.HexType.BLOCKED if coord in blocked else Board.HexType.NORMAL
			)
	return board


static func _build_state(seed_value: int, blocked: Array[Vector3i] = []) -> GameState:
	var state := GameState.new(_build_board(blocked), DeterministicRng.new(seed_value))
	state.add_player("p1")
	state.add_player("p2")
	return state


## Records a fighter both ways the engine tracks one: an opaque payload in
## `GameState` and an occupant on the board.
static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate,
	damage: int = 0
) -> void:
	var fighter := Fighter.new(fighter_id, template, owner_id, coord)
	fighter.apply_damage(damage)
	state.add_fighter(fighter_id, fighter.to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


## The stored damage counter for `fighter_id`, read back through `Fighter`.
static func _stored_damage(state: GameState, fighter_id: String, template: FighterTemplate) -> int:
	var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
	return -1 if fighter == null else fighter.damage_counter()


## The stored position for `fighter_id`, read back through `Fighter`. Every
## caller below places its fighters through `_place()` first, so a `null`
## parse here would itself be a fixture bug, not an outcome under test.
static func _stored_position(
	state: GameState, fighter_id: String, template: FighterTemplate
) -> Vector3i:
	var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
	return fighter.position()


## The scenario the parent Feature calls `happy_path`, and the one the
## hand-worked test pins: attacker `a1` adjacent to target `b1`, with exactly
## one other enemy of `b1` -- friendly `a2` -- also adjacent to it, so the
## target is flanked and the attacker is not.
static func _happy_path_state(seed_value: int, template: FighterTemplate) -> GameState:
	var state := _build_state(seed_value)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "a2", "p1", TARGET_FLANK_A, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	return state


# --- Refusals -----------------------------------------------------------


## Every refusal `resolve()` can give from a positioned scenario, one row each.
##
## The baseline roster is attacker `a1` (p1) at `ATTACKER_HEX` and target `b1`
## (p2) adjacent at `TARGET_HEX`, with a melee weapon of range 1. Each row
## changes exactly the one thing that produces its reason -- the actor or target
## id, the target's hex, owner or damage, the weapon, or the hexes made BLOCKED
## -- and each runs on a fresh state whose digest must be byte-identical
## afterwards, because a refusal changes nothing at all.
static func _test_every_refusal_leaves_the_state_identical() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 2)
	var melee := _weapon(1, 3, 1)
	var ranged := _weapon(3, 3, 1, WeaponTemplate.RANGED)
	var clear: Array[Vector3i] = []
	var wall: Array[Vector3i] = [TARGET_HEX]

	# reason, actor, target, target hex, target owner, target damage, weapon, blocked
	var cases := [
		[AttackAction.FAILURE_NO_SUCH_FIGHTER, "ghost", "b1", TARGET_HEX, "p2", 0, melee, clear],
		[AttackAction.FAILURE_NO_SUCH_TARGET, "a1", "ghost", TARGET_HEX, "p2", 0, melee, clear],
		[AttackAction.FAILURE_TARGET_IS_SELF, "a1", "a1", TARGET_HEX, "p2", 0, melee, clear],
		[AttackAction.FAILURE_TARGET_IS_FRIENDLY, "a1", "b1", TARGET_HEX, "p1", 0, melee, clear],
		[AttackAction.FAILURE_TARGET_OUT_OF_RANGE, "a1", "b1", FAR_HEX, "p2", 0, melee, clear],
		[AttackAction.FAILURE_NO_LINE_OF_SIGHT, "a1", "b1", FAR_HEX, "p2", 0, ranged, wall],
		[
			AttackAction.FAILURE_TARGET_ALREADY_DEFEATED,
			"a1",
			"b1",
			TARGET_HEX,
			"p2",
			2,
			melee,
			clear
		],
	]

	for entry in cases:
		var expected: StringName = entry[0]
		var actor: String = entry[1]
		var target: String = entry[2]
		var target_hex: Vector3i = entry[3]
		var target_owner: String = entry[4]
		var target_damage: int = entry[5]
		var weapon: WeaponTemplate = entry[6]
		var blocked: Array[Vector3i] = entry[7]

		var state := _build_state(13, blocked)
		_place(state, "a1", "p1", ATTACKER_HEX, template)
		_place(state, "b1", target_owner, target_hex, template, target_damage)
		var before := state.digest()

		var action := AttackAction.new(
			actor, target, weapon, template, _attack_profile(), _save_profile()
		)
		var result := action.resolve(state)

		violations.append_array(
			_expect(result.reason == expected, "expected %s, got %s" % [expected, result.reason])
		)
		violations.append_array(
			_expect(not result.success, "a %s refusal must return success == false" % expected)
		)
		violations.append_array(
			_expect(
				state.digest() == before,
				"a %s refusal must leave the state digest identical" % expected
			)
		)

	return violations


## The range boundary is inclusive: distance 2 against `range_hexes` 2 resolves
## rather than being refused.
static func _test_target_at_exactly_range_is_allowed() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 3)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", FAR_HEX, template)

	var weapon := _weapon(2, 3, 1, WeaponTemplate.RANGED)
	var action := AttackAction.new("a1", "b1", weapon, template, _attack_profile(), _save_profile())
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			HexCoord.distance(ATTACKER_HEX, FAR_HEX) == weapon.range_hexes,
			"this scenario must stand the target at exactly range_hexes"
		)
	)
	violations.append_array(
		_expect(result.success, "a target at exactly range_hexes must resolve, not be refused")
	)

	return violations


## Each of the four injected objects, nulled one at a time. A refusal, never a
## crash, and never a resolution against a guess.
static func _test_missing_injected_data_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 3)

	var cases := [
		["weapon", null, template, _attack_profile(), _save_profile()],
		["target template", _weapon(1, 3, 1), null, _attack_profile(), _save_profile()],
		["attack profile", _weapon(1, 3, 1), template, null, _save_profile()],
		["save profile", _weapon(1, 3, 1), template, _attack_profile(), null],
	]

	for entry in cases:
		var label: String = entry[0]
		var state := _build_state(13)
		_place(state, "a1", "p1", ATTACKER_HEX, template)
		_place(state, "b1", "p2", TARGET_HEX, template)
		var before := state.digest()

		var weapon: WeaponTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var attack_profile: DiceProfile = entry[3]
		var save_profile: DiceProfile = entry[4]

		var action := AttackAction.new(
			"a1", "b1", weapon, target_template, attack_profile, save_profile
		)
		var result := action.resolve(state)

		violations.append_array(
			_expect(
				result.reason == AttackAction.FAILURE_MISSING_DATA,
				"a null %s must be refused with FAILURE_MISSING_DATA" % label
			)
		)
		violations.append_array(
			_expect(
				state.digest() == before, "a null %s must leave the state digest identical" % label
			)
		)

	return violations


# --- The hand-worked specification --------------------------------------


## The specification test the parent Feature requires: a known board, a known
## seed, fixture dice with explicitly chosen faces, and the expected face-index
## sequence recorded here and worked by hand against spec §7.
##
## Board and roster: `_happy_path_state()` -- attacker `a1` at (0,0,0), friendly
## `a2` at (1,0,-1), target `b1` at (1,-1,0). Weapon: melee, range 1, 4 dice,
## 1 damage. Target template: save 3, health 3.
##
## Spec §8 first. `a2` is an enemy of `b1`, adjacent to it, and is not the
## attacker, so the target is FLANKED: attack bonus 1. Nothing that is an enemy
## of `a1` other than `b1` stands next to `a1`, so the save bonus is 0.
##
## Seed 13, attack pool drawn first: four draws of `next_int(0, 3)` giving face
## indices **3, 2, 1, 3** -> opening, ranged, melee, opening. Then the save
## pool: three draws of `next_int(0, 5)` giving face indices **2, 4, 0** ->
## guard, opening, critical. (Captured once from a real run against this seed;
## everything below it is worked by hand.)
##
## Attack successes, success set {critical, melee} + bonus_symbols[0] = opening,
## because the target is flanked: opening counts, ranged does not, melee counts,
## opening counts -> **3**.
##
## Save successes, success set {critical, guard} and no bonus, because the
## attacker is not flanked: guard counts, opening does **not**, critical counts
## -> **2**.
##
## 3 > 2, so spec §7.5 gives **HIT**.
static func _test_hand_worked_attack_matches_worked_sequence() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 3)
	var state := _happy_path_state(13, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 4, 1), template, _attack_profile(), _save_profile()
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "the hand-worked attack must resolve"))
	violations.append_array(
		_expect(
			action.attack_bonus_count() == Flanking.FLANKED,
			"the hand-worked scenario must read the target as flanked"
		)
	)
	violations.append_array(
		_expect(
			action.save_bonus_count() == Flanking.NONE,
			"the hand-worked scenario must read the attacker as unflanked"
		)
	)
	violations.append_array(
		_expect(
			action.attack_successes() == 3,
			"the hand-worked attack roll must count 3 successes, not %d" % action.attack_successes()
		)
	)
	violations.append_array(
		_expect(
			action.save_successes() == 2,
			"the hand-worked save roll must count 2 successes, not %d" % action.save_successes()
		)
	)
	violations.append_array(
		_expect(
			action.outcome() == DicePool.Outcome.HIT, "3 successes against 2 must resolve to HIT"
		)
	)

	return violations


## Draw order is the contract: the attack pool entirely before the save pool,
## and nothing else in `resolve()` touching the generator.
##
## Asserted twice. The generator's position after resolution must equal a
## generator stepped `weapon.dice_count + target_template.save` times, which
## pins the count. And rolling the two pools by hand in that order on an
## independent generator must reproduce the very success totals the action
## reported, which pins the order -- the two profiles have different face
## counts, so a swapped order draws different symbols.
static func _test_attack_pool_is_drawn_entirely_before_the_save_pool() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 3)
	var attack_profile := _attack_profile()
	var save_profile := _save_profile()
	var weapon := _weapon(1, 4, 1)
	var state := _happy_path_state(13, template)

	var action := AttackAction.new("a1", "b1", weapon, template, attack_profile, save_profile)
	action.resolve(state)

	var reference := DeterministicRng.new(13)
	for _i in range(weapon.dice_count):
		reference.next_int(0, attack_profile.face_count() - 1)
	for _i in range(template.save):
		reference.next_int(0, save_profile.face_count() - 1)

	violations.append_array(
		_expect(
			state.rng.get_state() == reference.get_state(),
			(
				"resolve() must advance the generator by exactly weapon.dice_count + "
				+ "target_template.save draws and touch it nowhere else"
			)
		)
	)

	var replay := DeterministicRng.new(13)
	var attack_roll := DicePool.roll(attack_profile, weapon.dice_count, replay)
	var save_roll := DicePool.roll(save_profile, template.save, replay)
	var expected_attack := DicePool.count_successes(
		attack_roll,
		DicePool.success_symbols(attack_profile, weapon.weapon_type, action.attack_bonus_count())
	)
	var expected_save := DicePool.count_successes(
		save_roll,
		DicePool.success_symbols(save_profile, save_profile.match_symbol, action.save_bonus_count())
	)

	violations.append_array(
		_expect(
			action.attack_successes() == expected_attack,
			"the attack pool must be the first draws taken from the generator"
		)
	)
	violations.append_array(
		_expect(
			action.save_successes() == expected_save,
			"the save pool must be drawn after the attack pool, from where it left the generator"
		)
	)

	return violations


# --- Outcomes -----------------------------------------------------------


static func _test_hit_applies_the_weapons_damage() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var weapon := _weapon(1, 4, 2)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	var before := _stored_damage(state, "b1", template)

	var action := AttackAction.new(
		"a1", "b1", weapon, template, _always_profile(), _never_profile()
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a Hit must return a successful TurnResult"))
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.HIT, "4 successes against 0 must be a HIT")
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", template) == before + weapon.damage_value,
			"a Hit must raise the stored damage_counter by exactly weapon.damage_value"
		)
	)
	violations.append_array(
		_expect(not action.target_defeated(), "a Hit short of health must not report a defeat")
	)

	return violations


static func _test_drawn_leaves_the_damage_counter_alone() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	# Two attack dice, two save dice, every face a critical on both: 2 and 2.
	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 2, 2), template, _always_profile(), _always_profile()
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a Drawn attack must resolve successfully"))
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.DRAWN, "equal totals must resolve to DRAWN")
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", template) == 0,
			"a Drawn attack must leave the stored damage_counter unchanged"
		)
	)

	return violations


## A Miss is a perfectly well resolved attack: `TurnResult.success` is still
## true, and `reason` is still empty.
static func _test_miss_resolves_successfully_and_deals_nothing() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 2), template, _never_profile(), _always_profile()
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.MISS, "0 successes against 1 must be a MISS")
	)
	violations.append_array(
		_expect(result.success, "a resolved Miss must still return TurnResult.success == true")
	)
	violations.append_array(
		_expect(result.reason == &"", 'a resolved Miss must have reason == &""')
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", template) == 0,
			"a Miss must leave the stored damage_counter unchanged"
		)
	)

	return violations


# --- Flanking and surrounding -------------------------------------------


## The attack die shows only `bonus_symbols[0]`, which counts at the FLANKED
## tier and at no lower one -- so the same roll scores nothing without a
## flanker and every die with one.
static func _test_flanked_target_unlocks_the_first_bonus_symbol() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1, 5)
	var weapon := _weapon(1, 3, 1)
	var attack_profile := _one_face_profile("opening", "melee")

	var alone := _build_state(13)
	_place(alone, "a1", "p1", ATTACKER_HEX, template)
	_place(alone, "b1", "p2", TARGET_HEX, template)
	var unflanked := AttackAction.new(
		"a1", "b1", weapon, template, attack_profile, _never_profile()
	)
	unflanked.resolve(alone)

	violations.append_array(
		_expect(
			unflanked.attack_bonus_count() == Flanking.NONE,
			"a target with no other adjacent enemy must read as unflanked"
		)
	)
	violations.append_array(
		_expect(
			unflanked.attack_successes() == 0,
			"bonus_symbols[0] must not count while the target is unflanked"
		)
	)

	var flanked_state := _happy_path_state(13, template)
	var flanked := AttackAction.new("a1", "b1", weapon, template, attack_profile, _never_profile())
	flanked.resolve(flanked_state)

	violations.append_array(
		_expect(
			flanked.attack_bonus_count() == Flanking.FLANKED,
			"exactly one other adjacent enemy must give attack_bonus_count() of 1"
		)
	)
	violations.append_array(
		_expect(
			flanked.attack_successes() == weapon.dice_count,
			"a flanked target must put bonus_symbols[0] into the counted success set"
		)
	)

	return violations


## The attack die shows only `bonus_symbols[1]`, which counts at the SURROUNDED
## tier alone -- so one flanker scores nothing and two score every die.
static func _test_surrounded_target_unlocks_the_second_bonus_symbol() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1, 5)
	var weapon := _weapon(1, 3, 1)
	var attack_profile := _one_face_profile("advantage", "melee")

	var one_state := _happy_path_state(13, template)
	var one := AttackAction.new("a1", "b1", weapon, template, attack_profile, _never_profile())
	one.resolve(one_state)

	violations.append_array(
		_expect(
			one.attack_successes() == 0,
			"bonus_symbols[1] must not count while the target is merely flanked"
		)
	)

	var two_state := _happy_path_state(13, template)
	_place(two_state, "a3", "p1", TARGET_FLANK_B, template)
	var two := AttackAction.new("a1", "b1", weapon, template, attack_profile, _never_profile())
	two.resolve(two_state)

	violations.append_array(
		_expect(
			two.attack_bonus_count() == Flanking.SURROUNDED,
			"two other adjacent enemies must give attack_bonus_count() of 2"
		)
	)
	violations.append_array(
		_expect(
			two.attack_successes() == weapon.dice_count,
			"a surrounded target must put bonus_symbols[1] into the counted success set too"
		)
	)

	# The same two flankers, but one of them already defeated and so already off
	# the board: a fighter that is not standing there flanks nobody, and the
	# target drops back to merely flanked.
	var defeated_state := _happy_path_state(13, template)
	_place(defeated_state, "a3", "p1", TARGET_FLANK_B, template, template.health)
	defeated_state.board.remove_occupant(TARGET_FLANK_B)
	var without := AttackAction.new("a1", "b1", weapon, template, attack_profile, _never_profile())
	without.resolve(defeated_state)

	violations.append_array(
		_expect(
			without.attack_bonus_count() == Flanking.FLANKED,
			"a defeated fighter, already off the board, must not count towards surrounding"
		)
	)

	return violations


## Spec §8 applies the same check symmetrically. The save die shows only
## `bonus_symbols[0]`, so the defence roll scores nothing until an enemy of the
## attacker -- other than the target -- stands next to the attacker.
static func _test_flanked_attacker_unlocks_a_bonus_on_the_save_roll() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 5)
	var save_profile := _one_face_profile("opening", "guard")

	var alone := _build_state(13)
	_place(alone, "a1", "p1", ATTACKER_HEX, template)
	_place(alone, "b1", "p2", TARGET_HEX, template)
	var unflanked := AttackAction.new(
		"a1", "b1", _weapon(1, 1, 1), template, _never_profile(), save_profile
	)
	unflanked.resolve(alone)

	violations.append_array(
		_expect(
			unflanked.save_bonus_count() == Flanking.NONE,
			"an attacker with no adjacent enemy but the target must read as unflanked"
		)
	)
	violations.append_array(
		_expect(
			unflanked.save_successes() == 0,
			"bonus_symbols[0] must not count on defence while the attacker is unflanked"
		)
	)

	var flanked_state := _build_state(13)
	_place(flanked_state, "a1", "p1", ATTACKER_HEX, template)
	_place(flanked_state, "b1", "p2", TARGET_HEX, template)
	_place(flanked_state, "b2", "p2", ATTACKER_FLANK, template)
	var flanked := AttackAction.new(
		"a1", "b1", _weapon(1, 1, 1), template, _never_profile(), save_profile
	)
	flanked.resolve(flanked_state)

	violations.append_array(
		_expect(
			flanked.save_bonus_count() == Flanking.FLANKED,
			"one enemy of the attacker other than the target must give save_bonus_count() of 1"
		)
	)
	violations.append_array(
		_expect(
			flanked.attack_bonus_count() == Flanking.NONE,
			"a fighter two hexes from the target must not also flank the target"
		)
	)
	violations.append_array(
		_expect(
			flanked.save_successes() == template.save,
			"a flanked attacker must put bonus_symbols[0] into the defence success set"
		)
	)
	violations.append_array(
		_expect(
			flanked.outcome() == DicePool.Outcome.MISS,
			"0 attack successes against 3 save successes must be a MISS"
		)
	)

	return violations


## The parent Feature's `happy_path`, end to end and on the fixed seed the
## hand-worked test uses: the attack lands and the damage is applied.
static func _test_happy_path_from_the_parent_feature() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 3)
	var weapon := _weapon(1, 4, 1)
	var state := _happy_path_state(13, template)

	var action := AttackAction.new("a1", "b1", weapon, template, _attack_profile(), _save_profile())
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "the happy path must resolve successfully"))
	violations.append_array(
		_expect(weapon.weapon_type == WeaponTemplate.MELEE, "the happy path uses a melee weapon")
	)
	violations.append_array(
		_expect(
			action.attack_successes() > action.save_successes(),
			"the happy path's attack successes must exceed the defender's"
		)
	)
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.HIT, "the happy path must resolve to a HIT")
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", template) == weapon.damage_value,
			"the happy path must apply the weapon's damage to the target"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == &"b1",
			"a target that survives the happy path must still occupy its hex"
		)
	)

	return violations


# --- Defeat -------------------------------------------------------------


## Spec §9 removes a defeated fighter from the *board*. The payload stays, its
## counter at or above health, so `Fighter.is_defeated()` keeps answering true.
static func _test_defeat_clears_the_hex_and_keeps_the_payload() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 1)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", _weapon(1, 3, 1), template, _always_profile(), _never_profile()
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating attack must resolve successfully"))
	violations.append_array(
		_expect(action.target_defeated(), "a counter taken to health must report target_defeated()")
	)

	var stored := Fighter.from_dict(state.fighter("b1"), template)
	violations.append_array(
		_expect(
			stored != null and stored.is_defeated(),
			"the stored payload must still read as defeated"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == Board.EMPTY_OCCUPANT,
			"a defeated fighter's hex must report no occupant"
		)
	)
	violations.append_array(
		_expect(
			"b1" in state.fighter_ids(),
			"a defeated fighter's payload must still be present in fighter_ids()"
		)
	)

	return violations


# --- Determinism --------------------------------------------------------


## The same starting state and the same attack, from equal seeds, twice.
static func _test_equal_seeds_produce_identical_outcome_and_digest() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 3)

	var first_state := _happy_path_state(13, template)
	var first := AttackAction.new(
		"a1", "b1", _weapon(1, 4, 1), template, _attack_profile(), _save_profile()
	)
	first.resolve(first_state)

	var second_state := _happy_path_state(13, template)
	var second := AttackAction.new(
		"a1", "b1", _weapon(1, 4, 1), template, _attack_profile(), _save_profile()
	)
	second.resolve(second_state)

	violations.append_array(
		_expect(
			first.outcome() == second.outcome(),
			"two resolutions from equal seeds must produce the identical outcome"
		)
	)
	violations.append_array(
		_expect(
			(
				first.attack_successes() == second.attack_successes()
				and first.save_successes() == second.save_successes()
			),
			"two resolutions from equal seeds must count the identical successes"
		)
	)
	violations.append_array(
		_expect(
			first_state.digest() == second_state.digest(),
			"two resolutions from equal seeds must leave states with the identical digest"
		)
	)

	return violations

## Tests AttackAction.resolve() in isolation: called directly, with no gate
## involved and no game-side type named anywhere in this file.
##
## That omission is deliberate, and it is the same one `pass_action_test.gd`
## documents. This suite lives under `rules/`, and `rules/` uses no game-side
## class at all -- not by `res://` path and not by global `class_name` -- so the
## assertion that an attack resolves through `ActionRunner.run()` cannot live
## here. It lives in `tests/action_runner_test.gd`, which is game-side.
##
## Every fixture `FighterTemplate` and `CombatProfile` here is built in memory
## with numbers chosen for this suite, never loaded from `resources/`:
## `extraction_contract_test.gd` forbids naming a `res://resources/` path under
## `rules/`, and retuning the authored provisional content must never be able
## to break this suite.
##
## **Two fixture styles, on purpose.**
##
## `standard_profile()` restates the authored combat dials, and is what the
## target-number suite works spec §7.3's chart against -- there, the effective
## target numbers are the assertion and the dice are irrelevant.
##
## Everywhere an *outcome* is under test the profile is `forced_profile()`: a
## target of `ALWAYS_TARGET` counts every face of the die and one of
## `NEVER_TARGET` counts none, so Hit / Drawn / Miss, damage and defeat are
## assertable on the *rule* rather than on a recorded dice sequence. Nothing
## here pins a captured sequence of die results; an expectation captured from a
## real run would pin Godot's generator rather than spec §7, and would go red
## on an engine upgrade that changed nothing about the rules. What is pinned
## instead is the draw *order*, replayed against an independently seeded
## generator -- see
## `_test_attack_pool_is_drawn_entirely_before_the_save_pool()`.
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

## The second such hex, for the surrounded tier on the save chart. Also
## adjacent to the attacker and two hexes from the target.
const ATTACKER_FLANK_B := Vector3i(-1, 0, 1)

## Two hexes from the attacker, with `TARGET_HEX` on the line between them.
const FAR_HEX := Vector3i(2, -2, 0)

## Four hexes from the attacker along the same line -- the archer's reach in
## the target-number suite.
const LONG_HEX := Vector3i(4, -4, 0)

## Adjacent to `LONG_HEX` and four hexes from the attacker, so a fighter here
## flanks a target standing at long range without flanking the attacker.
const LONG_FLANK_A := Vector3i(4, -3, -1)

## The second neighbour of `LONG_HEX`, for the surrounded tier.
const LONG_FLANK_B := Vector3i(3, -4, 1)

## Wide enough to hold `LONG_HEX` and both of its flankers with a ring to
## spare, so a push at long range still has somewhere to land.
const BOARD_RADIUS := 5

## A target number no face of the die can fail. Every roll counts.
const ALWAYS_TARGET := 1

## A target number no face of the die can meet, for a `die_sides` of 6. No roll
## counts.
const NEVER_TARGET := 7


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_every_refusal_leaves_the_state_identical())
	violations.append_array(_test_target_at_exactly_range_is_allowed())
	violations.append_array(_test_missing_injected_data_is_refused())
	violations.append_array(_test_attack_pool_is_drawn_entirely_before_the_save_pool())
	violations.append_array(_test_hit_applies_the_attackers_damage())
	violations.append_array(_test_drawn_leaves_the_damage_counter_alone())
	violations.append_array(_test_miss_resolves_successfully_and_deals_nothing())
	violations.append_array(_test_flanking_tiers_are_read_off_each_fighters_own_neighbours())
	violations.append_array(_test_a_defeated_flanker_no_longer_counts())
	violations.append_array(_test_defeat_clears_the_hex_and_keeps_the_payload())
	violations.append_array(_test_defeat_awards_the_flat_point_to_the_attackers_owner())
	violations.append_array(_test_hit_drawn_and_miss_without_defeat_award_nothing())
	violations.append_array(_test_refused_attack_awards_nothing())
	violations.append_array(_test_defeat_award_survives_serialization())
	violations.append_array(_test_defeat_award_draws_nothing_from_state_rng())
	violations.append_array(_test_equal_seeds_produce_identical_outcome_and_digest())

	# Spec §7.3's target-number chart and spec §7.6-7.7's push-back live in
	# attack_action_target_test.gd and attack_action_push_test.gd, not here:
	# see those files' docstrings for why the split exists and why neither is
	# a second suite. Folded into this class's own violations, so a failure
	# still reports as "FAIL Attack Action Test", the one suite of record.
	violations.append_array(AttackActionTargetTest.run())
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


## A fighter built for one test. Every stat is an argument, so no test reads a
## balance value it did not choose. `range_hexes`, `attack` and `damage`
## default to the adjacent-melee shape most tests below want.
##
## Public, alongside the two profile builders, because the target-number and
## push suites build their fixtures through these rather than keeping a second,
## drifting copy.
static func fighter_template(
	save: int, health: int, range_hexes: int = 1, attack: int = 3, damage: int = 1
) -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "fixture-fighter"
	template.move = 1
	template.save = save
	template.health = health
	template.range_hexes = range_hexes
	template.attack = attack
	template.damage = damage
	return template


## The authored combat dials, restated in memory: spec §7.3's two baselines,
## the engagement threshold and bonus, the attack and save charts' separate
## flank and surround magnitudes, and the clamp.
##
## Restated rather than loaded, for the reason the class docstring gives. The
## target-number suite hand-works every row of §7.3's chart off exactly these
## values, so they are written out once, here.
static func standard_profile() -> CombatProfile:
	var profile := CombatProfile.new()
	profile.profile_id = "fixture-standard"
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
	return profile


## A profile whose two target numbers are dictated outright, so a pool's
## success count is fixed by the die rather than by the seed: `ALWAYS_TARGET`
## counts every face and `NEVER_TARGET` counts none.
##
## Every modifier is 0 and the clamp is widened to `[ALWAYS_TARGET,
## NEVER_TARGET]`, so no adjacency and no clamping can move either target back
## into the rollable range. That is what makes the outcome tests below
## assertions about the rule rather than about the generator.
static func forced_profile(attack_target: int, save_target: int) -> CombatProfile:
	var profile := CombatProfile.new()
	profile.profile_id = "fixture-forced"
	profile.die_sides = 6
	profile.attack_target = attack_target
	profile.save_target = save_target
	profile.min_target = ALWAYS_TARGET
	profile.max_target = NEVER_TARGET
	return profile


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


## The scenario the parent Feature calls `happy_path`: attacker `a1` adjacent
## to target `b1`, with exactly one other enemy of `b1` -- friendly `a2` --
## also adjacent to it, so the target is flanked and the attacker is not.
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
## (p2) adjacent at `TARGET_HEX`. Each row changes exactly the one thing that
## produces its reason -- the actor or target id, the target's hex, owner or
## damage, the attacker's reach, or the hexes made BLOCKED -- and each runs on
## a fresh state whose digest must be byte-identical afterwards, because a
## refusal changes nothing at all.
##
## Reach is the *attacker's* `range_hexes`, so the two attacker templates below
## differ only in that stat.
static func _test_every_refusal_leaves_the_state_identical() -> Array[String]:
	var violations: Array[String] = []
	var target_template := fighter_template(2, 2)
	var melee := fighter_template(2, 2, 1)
	var ranged := fighter_template(2, 2, 3)
	var profile := standard_profile()
	var clear: Array[Vector3i] = []
	var wall: Array[Vector3i] = [TARGET_HEX]

	# reason, actor, target, target hex, target owner, target damage,
	# attacker template, blocked
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
		var attacker_template: FighterTemplate = entry[6]
		var blocked: Array[Vector3i] = entry[7]

		var state := _build_state(13, blocked)
		_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
		_place(state, "b1", target_owner, target_hex, target_template, target_damage)
		var before := state.digest()

		var action := AttackAction.new(actor, target, attacker_template, target_template, profile)
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


## The range boundary is inclusive: distance 2 against an attacker whose
## `range_hexes` is 2 resolves rather than being refused.
static func _test_target_at_exactly_range_is_allowed() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 3, 2)
	var target_template := fighter_template(2, 3)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", FAR_HEX, target_template)

	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, standard_profile()
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			HexCoord.distance(ATTACKER_HEX, FAR_HEX) == attacker_template.range_hexes,
			"this scenario must stand the target at exactly the attacker's range_hexes"
		)
	)
	violations.append_array(
		_expect(result.success, "a target at exactly range_hexes must resolve, not be refused")
	)

	return violations


## Each of the three injected objects, nulled one at a time. A refusal, never a
## crash, and never a resolution against a guess.
static func _test_missing_injected_data_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := fighter_template(2, 3)

	var cases := [
		["attacker template", null, template, standard_profile()],
		["target template", template, null, standard_profile()],
		["combat profile", template, template, null],
	]

	for entry in cases:
		var label: String = entry[0]
		var state := _build_state(13)
		_place(state, "a1", "p1", ATTACKER_HEX, template)
		_place(state, "b1", "p2", TARGET_HEX, template)
		var before := state.digest()

		var attacker_template: FighterTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var profile: CombatProfile = entry[3]

		var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
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


# --- Draw order ---------------------------------------------------------


## Draw order is the contract: the attack pool entirely before the save pool,
## and nothing else in `resolve()` touching the generator.
##
## Asserted twice. The generator's position after resolution must equal a
## generator stepped `attacker.attack + target.save` times through
## `roll_die(die_sides)`, which pins the count. And rolling the two pools by
## hand in that order on an independent generator, then counting each at the
## target number the action itself reports, must reproduce the very success
## totals it reported -- which pins the order, because the two pools differ in
## size and are counted at different targets.
static func _test_attack_pool_is_drawn_entirely_before_the_save_pool() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(3, 3, 1, 4, 1)
	var target_template := fighter_template(3, 3)
	var profile := standard_profile()

	# The happy path's roster, placed by hand so each fighter is recorded over
	# its own template: attacker `a1`, its friend `a2` flanking the target, and
	# target `b1`. Flanked and engaged, so the attack target is 5 - 1 - 1 = 3
	# against a save target of 5 -- two different targets over two differently
	# sized pools, which is what makes a swapped draw order detectable.
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "a2", "p1", TARGET_FLANK_A, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
	action.resolve(state)

	var reference := DeterministicRng.new(13)
	for _i in range(attacker_template.attack):
		reference.roll_die(profile.die_sides)
	for _i in range(target_template.save):
		reference.roll_die(profile.die_sides)

	violations.append_array(
		_expect(
			state.rng.get_state() == reference.get_state(),
			(
				"resolve() must advance the generator by exactly attacker.attack + "
				+ "target.save draws and touch it nowhere else"
			)
		)
	)

	var replay := DeterministicRng.new(13)
	var attack_roll := DicePool.roll_dice(attacker_template.attack, profile.die_sides, replay)
	var save_roll := DicePool.roll_dice(target_template.save, profile.die_sides, replay)

	violations.append_array(
		_expect(
			action.attack_target() != action.save_target(),
			(
				"this scenario must count the two pools at different targets, or a swapped draw "
				+ "order could pass unnoticed"
			)
		)
	)
	violations.append_array(
		_expect(
			(
				action.attack_successes()
				== DicePool.count_at_or_above(attack_roll, action.attack_target())
			),
			"the attack pool must be the first draws taken from the generator"
		)
	)
	violations.append_array(
		_expect(
			action.save_successes() == DicePool.count_at_or_above(save_roll, action.save_target()),
			"the save pool must be drawn after the attack pool, from where it left the generator"
		)
	)

	return violations


# --- Outcomes -----------------------------------------------------------


static func _test_hit_applies_the_attackers_damage() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 5, 1, 4, 2)
	var target_template := fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)
	var before := _stored_damage(state, "b1", target_template)

	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, forced_profile(ALWAYS_TARGET, NEVER_TARGET)
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a Hit must return a successful TurnResult"))
	violations.append_array(
		_expect(
			action.attack_successes() == attacker_template.attack,
			"a target of ALWAYS_TARGET must count every one of the attacker's dice"
		)
	)
	violations.append_array(
		_expect(
			action.save_successes() == 0,
			"a target of NEVER_TARGET must count none of the target's save dice"
		)
	)
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.HIT, "4 successes against 0 must be a HIT")
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", target_template) == before + attacker_template.damage,
			"a Hit must raise the stored damage_counter by exactly the attacker's damage"
		)
	)
	violations.append_array(
		_expect(not action.target_defeated(), "a Hit short of health must not report a defeat")
	)

	return violations


static func _test_drawn_leaves_the_damage_counter_alone() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 5, 1, 2, 2)
	var target_template := fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	# Two attack dice, two save dice, every die counting on both: 2 and 2.
	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, forced_profile(ALWAYS_TARGET, ALWAYS_TARGET)
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a Drawn attack must resolve successfully"))
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.DRAWN, "equal totals must resolve to DRAWN")
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", target_template) == 0,
			"a Drawn attack must leave the stored damage_counter unchanged"
		)
	)

	return violations


## A Miss is a perfectly well resolved attack: `TurnResult.success` is still
## true, and `reason` is still empty.
static func _test_miss_resolves_successfully_and_deals_nothing() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(1, 5, 1, 3, 2)
	var target_template := fighter_template(1, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, forced_profile(NEVER_TARGET, ALWAYS_TARGET)
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
			_stored_damage(state, "b1", target_template) == 0,
			"a Miss must leave the stored damage_counter unchanged"
		)
	)

	return violations


# --- Flanking and surrounding -------------------------------------------


## Spec §8 applies the same adjacency check twice, on two different fighters:
## the attack bonus counts the *target's* other adjacent enemies and the save
## bonus the *attacker's*. Which magnitude each one then buys is spec §7.3's
## business and is asserted in the target-number suite; what is asserted here
## is that the two tiers are read off the right fighter.
static func _test_flanking_tiers_are_read_off_each_fighters_own_neighbours() -> Array[String]:
	var violations: Array[String] = []
	var template := fighter_template(1, 5)
	var profile := standard_profile()

	var alone := _build_state(13)
	_place(alone, "a1", "p1", ATTACKER_HEX, template)
	_place(alone, "b1", "p2", TARGET_HEX, template)
	var unflanked := AttackAction.new("a1", "b1", template, template, profile)
	unflanked.resolve(alone)

	violations.append_array(
		_expect(
			unflanked.attack_bonus_count() == Flanking.NONE,
			"a target with no other adjacent enemy must read as unflanked"
		)
	)
	violations.append_array(
		_expect(
			unflanked.save_bonus_count() == Flanking.NONE,
			"an attacker with no adjacent enemy but the target must read as unflanked"
		)
	)

	var flanked_state := _happy_path_state(13, template)
	var flanked := AttackAction.new("a1", "b1", template, template, profile)
	flanked.resolve(flanked_state)

	violations.append_array(
		_expect(
			flanked.attack_bonus_count() == Flanking.FLANKED,
			"exactly one other adjacent enemy must give attack_bonus_count() of FLANKED"
		)
	)
	violations.append_array(
		_expect(
			flanked.save_bonus_count() == Flanking.NONE,
			"a friendly flanker of the target must not flank the attacker as well"
		)
	)

	var surrounded_state := _happy_path_state(13, template)
	_place(surrounded_state, "a3", "p1", TARGET_FLANK_B, template)
	var surrounded := AttackAction.new("a1", "b1", template, template, profile)
	surrounded.resolve(surrounded_state)

	violations.append_array(
		_expect(
			surrounded.attack_bonus_count() == Flanking.SURROUNDED,
			"two other adjacent enemies must give attack_bonus_count() of SURROUNDED"
		)
	)

	var defended_state := _build_state(13)
	_place(defended_state, "a1", "p1", ATTACKER_HEX, template)
	_place(defended_state, "b1", "p2", TARGET_HEX, template)
	_place(defended_state, "b2", "p2", ATTACKER_FLANK, template)
	var defended := AttackAction.new("a1", "b1", template, template, profile)
	defended.resolve(defended_state)

	violations.append_array(
		_expect(
			defended.save_bonus_count() == Flanking.FLANKED,
			"one enemy of the attacker other than the target must give save_bonus_count() of 1"
		)
	)
	violations.append_array(
		_expect(
			defended.attack_bonus_count() == Flanking.NONE,
			"a fighter two hexes from the target must not also flank the target"
		)
	)

	return violations


## A fighter the board no longer reports at its recorded position has been
## defeated, and a fighter off the board flanks nobody: the target drops back
## from surrounded to merely flanked.
static func _test_a_defeated_flanker_no_longer_counts() -> Array[String]:
	var template := fighter_template(1, 5)
	var state := _happy_path_state(13, template)
	_place(state, "a3", "p1", TARGET_FLANK_B, template, template.health)
	state.board.remove_occupant(TARGET_FLANK_B)

	var action := AttackAction.new("a1", "b1", template, template, standard_profile())
	action.resolve(state)

	return _expect(
		action.attack_bonus_count() == Flanking.FLANKED,
		"a defeated fighter, already off the board, must not count towards surrounding"
	)


# --- Defeat -------------------------------------------------------------


## Spec §9 removes a defeated fighter from the *board*. The payload stays, its
## counter at or above health, so `Fighter.is_defeated()` keeps answering true.
static func _test_defeat_clears_the_hex_and_keeps_the_payload() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 3)
	var target_template := fighter_template(2, 1)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, forced_profile(ALWAYS_TARGET, NEVER_TARGET)
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating attack must resolve successfully"))
	violations.append_array(
		_expect(action.target_defeated(), "a counter taken to health must report target_defeated()")
	)

	var stored := Fighter.from_dict(state.fighter("b1"), target_template)
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


## Spec §9's flat point, credited to the *attacker's* owner, never the
## defeated fighter's own owner -- and read off `profile.defeat_award` rather
## than restated as a literal, so a retuned dial moves this test with it.
static func _test_defeat_awards_the_flat_point_to_the_attackers_owner() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 3)
	var target_template := fighter_template(2, 1)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	var profile := forced_profile(ALWAYS_TARGET, NEVER_TARGET)
	profile.defeat_award = 3

	var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating attack must resolve successfully"))
	violations.append_array(
		_expect(action.target_defeated(), "this scenario must defeat the target")
	)
	violations.append_array(
		_expect(
			state.player("p1").score == profile.defeat_award,
			"defeating a fighter must raise the attacker's owner's score by exactly defeat_award"
		)
	)
	violations.append_array(
		_expect(
			state.player("p2").score == 0,
			"defeating a fighter must leave the defeated fighter's own owner's score unchanged"
		)
	)

	return violations


## The award is defeat-only: a Hit that falls short of defeat, a Drawn, and a
## Miss must all leave both owners' scores exactly where they started, even
## against a profile whose `defeat_award` is nonzero.
static func _test_hit_drawn_and_miss_without_defeat_award_nothing() -> Array[String]:
	var violations: Array[String] = []

	# label, attacker template, target template, attack target, save target.
	var cases := [
		[
			"a Hit short of defeat",
			fighter_template(2, 5, 1, 4, 2),
			fighter_template(2, 5),
			ALWAYS_TARGET,
			NEVER_TARGET,
		],
		[
			"a Drawn attack",
			fighter_template(2, 5, 1, 2, 2),
			fighter_template(2, 5),
			ALWAYS_TARGET,
			ALWAYS_TARGET,
		],
		[
			"a Miss",
			fighter_template(1, 5, 1, 3, 2),
			fighter_template(1, 5),
			NEVER_TARGET,
			ALWAYS_TARGET,
		],
	]

	for entry in cases:
		var label: String = entry[0]
		var attacker_template: FighterTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var attack_target: int = entry[3]
		var save_target: int = entry[4]

		var state := _build_state(13)
		_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
		_place(state, "b1", "p2", TARGET_HEX, target_template)

		var profile := forced_profile(attack_target, save_target)
		profile.defeat_award = 5

		var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
		action.resolve(state)

		violations.append_array(
			_expect(not action.target_defeated(), "%s must not defeat the target" % label)
		)
		violations.append_array(
			_expect(
				state.player("p1").score == 0,
				"%s must leave the attacker's owner's score unchanged" % label
			)
		)
		violations.append_array(
			_expect(
				state.player("p2").score == 0,
				"%s must leave the target's owner's score unchanged" % label
			)
		)

	return violations


## `_test_every_refusal_leaves_the_state_identical()` already pins every
## refusal's digest byte-for-byte, which covers both players' scores along
## with everything else in the state. This restates one refusal case in terms
## an award-focused reader can check without re-deriving it from a digest.
static func _test_refused_attack_awards_nothing() -> Array[String]:
	var violations: Array[String] = []
	var template := fighter_template(2, 3)
	var profile := standard_profile()
	profile.defeat_award = 5

	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p1", TARGET_HEX, template)

	var action := AttackAction.new("a1", "b1", template, template, profile)
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			result.reason == AttackAction.FAILURE_TARGET_IS_FRIENDLY,
			"this scenario must be refused as a friendly target"
		)
	)
	violations.append_array(
		_expect(state.player("p1").score == 0, "a refused attack must award nothing")
	)

	return violations


## Score is an ordinary field of `PlayerState`, so a defeat award must survive
## the same `to_dict()`/`from_dict()` round trip as everything else `GameState`
## carries.
static func _test_defeat_award_survives_serialization() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 3)
	var target_template := fighter_template(2, 1)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	var profile := forced_profile(ALWAYS_TARGET, NEVER_TARGET)
	profile.defeat_award = 4

	var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
	action.resolve(state)
	violations.append_array(
		_expect(action.target_defeated(), "this scenario must defeat the target")
	)

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(_expect(restored != null, "the resolved state must round-trip"))
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.player("p1").score == state.player("p1").score,
			"the attacker's owner's score must survive a to_dict()/from_dict() round trip"
		)
	)

	return violations


## The award happens after both pools are drawn and touches nothing else: the
## generator's position after a defeating attack must equal one stepped only
## by the attack and save pools, exactly as a non-defeating attack's -- see
## `_test_attack_pool_is_drawn_entirely_before_the_save_pool()`.
static func _test_defeat_award_draws_nothing_from_state_rng() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := fighter_template(2, 3)
	var target_template := fighter_template(2, 1)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", TARGET_HEX, target_template)

	var profile := forced_profile(ALWAYS_TARGET, NEVER_TARGET)
	profile.defeat_award = 4

	var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
	action.resolve(state)
	violations.append_array(
		_expect(action.target_defeated(), "this scenario must defeat the target")
	)

	var reference := DeterministicRng.new(13)
	for _i in range(attacker_template.attack):
		reference.roll_die(profile.die_sides)
	for _i in range(target_template.save):
		reference.roll_die(profile.die_sides)

	violations.append_array(
		_expect(
			state.rng.get_state() == reference.get_state(),
			"awarding the defeat point must draw nothing from state.rng"
		)
	)

	return violations


# --- Determinism --------------------------------------------------------


## The same starting state and the same attack, from equal seeds, twice.
static func _test_equal_seeds_produce_identical_outcome_and_digest() -> Array[String]:
	var violations: Array[String] = []
	var template := fighter_template(3, 3)

	var first_state := _happy_path_state(13, template)
	var first := AttackAction.new("a1", "b1", template, template, standard_profile())
	first.resolve(first_state)

	var second_state := _happy_path_state(13, template)
	var second := AttackAction.new("a1", "b1", template, template, standard_profile())
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

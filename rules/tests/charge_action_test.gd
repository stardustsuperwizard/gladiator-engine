## Tests `ChargeAction.resolve()` in isolation: called directly, with no gate
## involved and no game-side type named anywhere in this file -- the same
## deliberate omission `move_action_test.gd` and `attack_action_test.gd`
## document. The `Authority` gate case for a Charge lives in
## `tests/action_runner_test.gd`.
##
## What this file asserts is what a Charge does of its own: relocate, refuse,
## and flag. What it reaches by composing `AttackAction` -- equivalence to a
## Move then an Attack, Guard's save row and push immunity, defeat and its
## award, and the push -- is asserted in
## `rules/tests/charge_action_equivalence_test.gd`, along with the
## ordering-trap and end-to-end lockout cases. That file is registered as its
## own suite: `.gdlintrc` caps a file at 1000 lines and prescribes splitting
## rather than raising the ceiling.
##
## Every fixture is built in memory through `AttackActionTest`'s own public
## statics -- `extraction_contract_test.gd` forbids naming a `res://resources/`
## path under `rules/`, and reusing those builders avoids a second, drifting
## copy. `AttackActionTest.fighter_template()` hardcodes `move = 1`, which no
## charger can use, so `_template()` below sets `move` afterwards.
##
## **Outcomes are forced, never rolled for**, the technique
## `attack_action_push_test.gd` establishes: `ALWAYS_TARGET` counts every face
## of the die and `NEVER_TARGET` none, so Hit and Miss are assertable on the
## rule rather than on a recorded dice sequence. The target-number cases use
## `standard_profile()`, where the effective targets are the assertion and the
## dice are irrelevant.
class_name ChargeActionTest

## The charging fighter's origin, and the line of hexes running away from it.
## `H4` and `H5` are where the target stands in most scenarios; `H3` is the
## destination adjacent to a target at `H4`.
const ORIGIN := Vector3i(0, 0, 0)
const H1 := Vector3i(1, -1, 0)
const H2 := Vector3i(2, -2, 0)
const H3 := Vector3i(3, -3, 0)
const H4 := Vector3i(4, -4, 0)
const H5 := Vector3i(5, -5, 0)

## Adjacent to `H3`, and to neither `ORIGIN`, `H4` nor `OFF_LINE_H4`. An enemy
## standing here flanks a charger that ends on `H3` and nowhere else.
const NEAR_H3 := Vector3i(3, -2, -1)

## Adjacent to `H4` and to neither `H3` nor `OFF_LINE_H4`. A friendly standing
## here flanks a target at `H4` whichever of the two destinations is chosen.
const NEAR_H4 := Vector3i(5, -4, -1)

## The other destination adjacent to `H4` within a `move` of 4 -- reachable,
## adjacent to the target, and adjacent to no enemy.
const OFF_LINE_H4 := Vector3i(3, -4, 1)

## Wide enough to hold `H5` and every flanker with a ring to spare, so a push
## at the far end still has somewhere to land.
const BOARD_RADIUS := 6

const ACTOR_ID := "a1"
const TARGET_ID := "b1"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_legal_charge_relocates_attacks_and_flags())
	violations.append_array(_test_charge_survives_a_state_round_trip())
	violations.append_array(_test_miss_is_a_successful_charge())
	violations.append_array(_test_turns_and_round_unchanged_after_a_successful_charge())

	violations.append_array(_test_engagement_is_measured_from_the_destination())
	violations.append_array(_test_flanking_is_measured_from_the_destination())

	violations.append_array(_test_attack_half_out_of_range_from_the_destination())
	violations.append_array(_test_attack_half_no_line_of_sight_from_the_destination())
	violations.append_array(_test_attack_half_friendly_target())
	violations.append_array(_test_attack_half_target_is_self())
	violations.append_array(_test_attack_half_target_already_defeated())

	violations.append_array(_test_unreachable_destination_is_refused())
	violations.append_array(_test_destination_is_origin_is_refused())
	violations.append_array(_test_no_such_fighter_is_refused())
	violations.append_array(_test_missing_injected_data_is_refused())
	violations.append_array(_test_unparseable_payload_is_refused())

	violations.append_array(_test_an_actor_that_has_moved_is_refused())
	violations.append_array(_test_an_actor_that_has_charged_is_refused())

	if violations.is_empty():
		return true

	printerr("\n=== Charge Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## A fighter template with every stat this suite chooses, built through
## `AttackActionTest.fighter_template()` and then given the `move` allowance
## that builder hardcodes to 1.
static func _template(
	move: int, save: int = 2, health: int = 5, range_hexes: int = 1, damage: int = 1
) -> FighterTemplate:
	var template := AttackActionTest.fighter_template(save, health, range_hexes, 3, damage)
	template.move = move
	return template


## A hexagonal board of `BOARD_RADIUS` rings around the origin, every hex
## NORMAL except the coordinates listed in `blocked`.
static func _hex_board(blocked: Array[Vector3i] = []) -> Board:
	var board := Board.new()

	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			var coord := Vector3i(x, y, -x - y)
			board.add_hex(
				coord, Board.HexType.BLOCKED if coord in blocked else Board.HexType.NORMAL
			)

	return board


static func _build_state(blocked: Array[Vector3i] = []) -> GameState:
	var state := GameState.new(_hex_board(blocked), DeterministicRng.new(13))
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


static func _stored(state: GameState, fighter_id: String, template: FighterTemplate) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


## Sets `flag` on the stored fighter by hand, through `Fighter.set_status_flag()`
## then `GameState.update_fighter()` -- the seam `charge_lockout_test.gd`
## already uses for the same purpose.
static func _flag(
	state: GameState, fighter_id: String, template: FighterTemplate, flag: String
) -> void:
	var fighter := _stored(state, fighter_id, template)
	fighter.set_status_flag(flag)
	state.update_fighter(fighter_id, fighter.to_dict())


static func _forced(attack_target: int, save_target: int) -> CombatProfile:
	return AttackActionTest.forced_profile(attack_target, save_target)


## Every die counts on this roll.
static func _always() -> int:
	return AttackActionTest.ALWAYS_TARGET


## No die counts on this roll.
static func _never() -> int:
	return AttackActionTest.NEVER_TARGET


## The baseline scenario: a `move`-4 Range-1 charger at `ORIGIN` and an enemy
## at `H4`, four hexes away with a clear path, so `H3` is a legal destination
## adjacent to the target.
static func _baseline_state(template: FighterTemplate, target_damage: int = 0) -> GameState:
	var state := _build_state()
	_place(state, ACTOR_ID, "p1", ORIGIN, template)
	_place(state, TARGET_ID, "p2", H4, template, target_damage)
	return state


static func _charge(
	destination: Vector3i,
	template: FighterTemplate,
	profile: CombatProfile,
	push_back: bool = false,
	target_id: String = TARGET_ID
) -> ChargeAction:
	return ChargeAction.new(
		ACTOR_ID, destination, target_id, template, template, profile, push_back
	)


# --- Shared assertions ------------------------------------------------------


## Resolves `action` and asserts it was refused with `expected`, changing
## nothing at all: the digest is byte-identical and the generator has not
## advanced. `GameState.digest()` covers the board, every payload and every
## score in one comparison.
##
## `template`, when given, adds "the fighter does not move" and "its flags are
## unchanged" directly, on top of what the digest already implies, because both
## are acceptance criteria in their own right. It is `null` for the two
## scenarios that place no readable actor on the board at all.
static func _assert_refused(
	label: String,
	state: GameState,
	action: ChargeAction,
	expected: StringName,
	template: FighterTemplate = null
) -> Array[String]:
	var violations: Array[String] = []
	var digest_before := state.digest()
	var rng_before := state.rng.get_state()
	var flags_before := _actor_flags(state, template)

	var result := action.resolve(state)

	violations.append_array(
		_expect(not result.success, "%s: a refused Charge must return success == false" % label)
	)
	violations.append_array(
		_expect(
			result.reason == expected,
			"%s: must be refused with %s, got %s" % [label, expected, result.reason]
		)
	)
	violations.append_array(
		_expect(
			state.digest() == digest_before,
			"%s: a refused Charge must leave the state digest byte-identical" % label
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_before,
			"%s: a refused Charge must not advance state.rng" % label
		)
	)

	if template == null:
		return violations

	var stored := _stored(state, ACTOR_ID, template)
	violations.append_array(
		_expect(
			stored != null and stored.position() == ORIGIN,
			"%s: the actor's stored position must still be its origin hex" % label
		)
	)
	violations.append_array(
		_expect(
			stored != null and stored.status_flags() == flags_before,
			"%s: a refused Charge must leave the actor's status flags unchanged" % label
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(ORIGIN) == StringName(ACTOR_ID),
			"%s: the actor must still occupy its origin hex on the board" % label
		)
	)

	return violations


## The actor's status flags right now, or an empty array when there is no
## template to parse its payload with.
static func _actor_flags(state: GameState, template: FighterTemplate) -> Array[String]:
	if template == null:
		return []
	var stored := _stored(state, ACTOR_ID, template)
	return [] if stored == null else stored.status_flags()


# --- The legal Charge -------------------------------------------------------


## A `move`-4 Range-1 warrior four hexes from an enemy charges to a hex
## adjacent to it: the board moves, the payload moves, `"charged"` is set and
## `"moved"` is not.
static func _test_legal_charge_relocates_attacks_and_flags() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)
	var action := _charge(H3, template, _forced(_always(), _never()))

	var result := action.resolve(state)

	violations.append_array(
		_expect(
			result.success and result.reason == &"",
			'a legal Charge must return TurnResult.ok(), with reason == &""'
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(ORIGIN) == Board.EMPTY_OCCUPANT,
			"a legal Charge must free the origin hex"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(H3) == StringName(ACTOR_ID),
			"a legal Charge must record the actor as the occupant of the destination"
		)
	)

	var stored := _stored(state, ACTOR_ID, template)
	violations.append_array(
		_expect(
			stored != null and stored.position() == H3,
			"the stored payload's position() must be the destination after a legal Charge"
		)
	)
	violations.append_array(
		_expect(
			stored != null and stored.has_status_flag(ChargeLockout.FLAG_CHARGED),
			'a successful Charge must set the "charged" flag'
		)
	)
	violations.append_array(
		_expect(
			stored != null and not stored.has_status_flag(MoveAction.FLAG_MOVED),
			'a successful Charge must not set the "moved" flag'
		)
	)
	violations.append_array(
		_expect(
			action.attack_half().outcome() == DicePool.Outcome.HIT,
			"this scenario's forced profile must resolve the attack half to a HIT"
		)
	)
	violations.append_array(
		_expect(
			_stored(state, TARGET_ID, template).damage_counter() == template.damage,
			"the attack half's damage must have reached the stored target payload"
		)
	)

	return violations


## The moved position and the "charged" flag both survive a full
## `GameState.to_dict()`/`from_dict()` round trip, not merely a read of the
## live state.
static func _test_charge_survives_a_state_round_trip() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)

	_charge(H3, template, _forced(_always(), _never())).resolve(state)

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(restored != null, "the state after a legal Charge must round-trip")
	)
	if restored == null:
		return violations

	var stored := _stored(restored, ACTOR_ID, template)
	violations.append_array(
		_expect(
			stored != null and stored.position() == H3,
			"the round-tripped actor must report the destination as its position()"
		)
	)
	violations.append_array(
		_expect(
			stored != null and stored.has_status_flag(ChargeLockout.FLAG_CHARGED),
			'the round-tripped actor must still carry the "charged" flag'
		)
	)
	violations.append_array(
		_expect(
			restored.board.occupant_at(H3) == StringName(ACTOR_ID),
			"the round-tripped board must still record the actor at the destination"
		)
	)

	return violations


## A Miss is a resolved Charge: the fighter still relocated and still carries
## the flag, exactly as `AttackAction` treats a Miss as a successful attack.
static func _test_miss_is_a_successful_charge() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)
	var action := _charge(H3, template, _forced(_never(), _always()))

	var result := action.resolve(state)

	violations.append_array(
		_expect(
			action.attack_half().outcome() == DicePool.Outcome.MISS,
			"this scenario's forced profile must resolve the attack half to a MISS"
		)
	)
	violations.append_array(
		_expect(result.success, "a Charge whose attack Missed must still resolve")
	)

	var stored := _stored(state, ACTOR_ID, template)
	violations.append_array(
		_expect(
			stored != null and stored.position() == H3,
			"a Missing Charge must still have relocated the fighter"
		)
	)
	violations.append_array(
		_expect(
			stored != null and stored.has_status_flag(ChargeLockout.FLAG_CHARGED),
			'a Missing Charge must still set the "charged" flag'
		)
	)
	violations.append_array(
		_expect(
			_stored(state, TARGET_ID, template).damage_counter() == 0,
			"a Missing Charge must leave the target's damage counter alone"
		)
	)
	return violations


static func _test_turns_and_round_unchanged_after_a_successful_charge() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)
	var before_turns := state.turns_taken
	var before_round := state.round_number

	var result := _charge(H3, template, _forced(_always(), _never())).resolve(state)

	violations.append_array(
		_expect(result.success, "this scenario must resolve for it to test anything")
	)
	violations.append_array(
		_expect(state.turns_taken == before_turns, "a successful Charge must not touch turns_taken")
	)
	violations.append_array(
		_expect(
			state.round_number == before_round, "a successful Charge must not touch round_number"
		)
	)

	return violations


# --- Spec §7.3's engagement bonus, measured from the destination ------------


## A Range-4 archer standing at reach reports the unengaged attack target; the
## same archer charging into contact reports the engaged one, exactly as a
## Range-1 warrior charging into contact does. Spec §7.3 measures engagement on
## the shot, not on the Range stat.
static func _test_engagement_is_measured_from_the_destination() -> Array[String]:
	var violations: Array[String] = []
	var profile := AttackActionTest.standard_profile()
	var archer := _template(5, 2, 5, 4)

	# The archer stands at H1, exactly four hexes -- its full reach -- from a
	# target at H5, and charges to H4, in contact with it.
	var charge_state := _build_state()
	_place(charge_state, ACTOR_ID, "p1", H1, archer)
	_place(charge_state, TARGET_ID, "p2", H5, archer)
	var charge := ChargeAction.new(ACTOR_ID, H4, TARGET_ID, archer, archer, profile)
	var charge_result := charge.resolve(charge_state)

	violations.append_array(
		_expect(charge_result.success, "the archer's charge into contact must resolve")
	)
	violations.append_array(
		_expect(
			charge.attack_half().attack_target() == 4,
			(
				"a Range-4 archer charging into contact must take §7.3's engagement bonus, "
				+ "attack_target() == 4, got %d" % charge.attack_half().attack_target()
			)
		)
	)

	# The identical fixture, attacked from the archer's original hex instead.
	var reach_state := _build_state()
	_place(reach_state, ACTOR_ID, "p1", H1, archer)
	_place(reach_state, TARGET_ID, "p2", H5, archer)
	var reach := AttackAction.new(ACTOR_ID, TARGET_ID, archer, archer, profile)
	var reach_result := reach.resolve(reach_state)

	violations.append_array(
		_expect(reach_result.success, "the archer's attack from reach must resolve")
	)
	violations.append_array(
		_expect(
			reach.attack_target() == 5,
			(
				"the same archer attacking from its original hex must take no engagement bonus, "
				+ "attack_target() == 5, got %d" % reach.attack_target()
			)
		)
	)

	# A Range-1 warrior charging into contact reaches the identical number.
	var warrior := _template(4)
	var warrior_state := _baseline_state(warrior)
	var warrior_charge := _charge(H3, warrior, profile)
	warrior_charge.resolve(warrior_state)

	violations.append_array(
		_expect(
			warrior_charge.attack_half().attack_target() == 4,
			"a Range-1 warrior charging into contact must reach the same engaged attack target"
		)
	)

	return violations


# --- Spec §8's flanking, measured against the post-move board ---------------


## Two charges against the same fixture, differing only in which hex adjacent
## to the target they end on. One destination stands beside an enemy and the
## other does not, so the *attacker's* own flanking tier -- and the save target
## priced off it -- is decided by the destination, against the board as it
## stands after the move.
static func _test_flanking_is_measured_from_the_destination() -> Array[String]:
	var violations: Array[String] = []
	var profile := AttackActionTest.standard_profile()
	var template := _template(4)

	var flanked := _flanking_state(template)
	var flanked_charge := _charge(H3, template, profile)
	violations.append_array(
		_expect(
			flanked_charge.resolve(flanked).success,
			"the charge onto the flanked destination must resolve"
		)
	)
	violations.append_array(
		_expect(
			flanked_charge.attack_half().save_bonus_count() == Flanking.FLANKED,
			(
				"a destination standing beside an enemy must leave the charger FLANKED, got %d"
				% flanked_charge.attack_half().save_bonus_count()
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				flanked_charge.attack_half().save_target() == 3,
				(
					"§7.3's save chart must price the charger's flanking from the destination: 3, got %d"
					% flanked_charge.attack_half().save_target()
				)
			)
		)
	)

	var clear := _flanking_state(template)
	var clear_charge := _charge(OFF_LINE_H4, template, profile)
	violations.append_array(
		_expect(
			clear_charge.resolve(clear).success,
			"the charge onto the clear destination must resolve"
		)
	)
	violations.append_array(
		_expect(
			clear_charge.attack_half().save_bonus_count() == Flanking.NONE,
			"the other destination, adjacent to no enemy, must leave the charger unflanked"
		)
	)
	violations.append_array(
		_expect(
			clear_charge.attack_half().save_target() == 5,
			"an unflanked charger must take §7.3's unmodified save target"
		)
	)

	# The target's own tier is read off its neighbours on the same post-move
	# board, and the friendly flanker stands beside it in both scenarios.
	violations.append_array(
		_expect(
			(
				flanked_charge.attack_half().attack_bonus_count() == Flanking.FLANKED
				and clear_charge.attack_half().attack_bonus_count() == Flanking.FLANKED
			),
			"the target's own flanking tier must be read off the board as it stands after the move"
		)
	)

	return violations


## The flanking fixture: the charger at `ORIGIN`, its target at `H4`, a
## friendly flanker beside the target at `NEAR_H4`, and an enemy at `NEAR_H3`
## that is adjacent to the `H3` destination and to nothing else in play.
static func _flanking_state(template: FighterTemplate) -> GameState:
	var state := _baseline_state(template)
	_place(state, "a2", "p1", NEAR_H4, template)
	_place(state, "b2", "p2", NEAR_H3, template)
	return state


# --- The attack half's own refusals, every one changing nothing -------------


## Range 1, stopping two hexes short of the target.
static func _test_attack_half_out_of_range_from_the_destination() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _build_state()
	_place(state, ACTOR_ID, "p1", ORIGIN, template)
	_place(state, TARGET_ID, "p2", H5, template)

	violations.append_array(
		_expect(
			HexCoord.distance(H3, H5) > template.range_hexes,
			"this scenario must stand the destination outside the charger's reach"
		)
	)

	var action := _charge(H3, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			"out of range from the destination",
			state,
			action,
			AttackAction.FAILURE_TARGET_OUT_OF_RANGE,
			template
		)
	)

	return violations


## The destination is within reach of the target but a BLOCKED hex stands on
## the line between them. `Board.reachable_from()` routes around that same hex,
## so the destination itself is perfectly reachable -- the refusal is about the
## shot, not about the walk.
static func _test_attack_half_no_line_of_sight_from_the_destination() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4, 2, 5, 3)
	var state := _build_state([H3] as Array[Vector3i])
	_place(state, ACTOR_ID, "p1", ORIGIN, template)
	_place(state, TARGET_ID, "p2", H4, template)

	violations.append_array(
		_expect(
			HexCoord.distance(H1, H4) <= template.range_hexes,
			"this scenario must stand the destination within the charger's reach"
		)
	)
	violations.append_array(
		_expect(
			H1 in state.board.reachable_from(ORIGIN, template.move),
			"this scenario's destination must itself be reachable"
		)
	)
	violations.append_array(
		_expect(
			not state.board.has_line_of_sight(H1, H4),
			"this scenario must actually block the line from the destination to the target"
		)
	)

	var action := _charge(H1, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			"no line of sight from the destination",
			state,
			action,
			AttackAction.FAILURE_NO_LINE_OF_SIGHT,
			template
		)
	)

	return violations


static func _test_attack_half_friendly_target() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _build_state()
	_place(state, ACTOR_ID, "p1", ORIGIN, template)
	_place(state, TARGET_ID, "p1", H4, template)

	var action := _charge(H3, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			"friendly target", state, action, AttackAction.FAILURE_TARGET_IS_FRIENDLY, template
		)
	)

	return violations


static func _test_attack_half_target_is_self() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)

	var action := _charge(H3, template, _forced(_always(), _never()), false, ACTOR_ID)
	violations.append_array(
		_assert_refused(
			"target is self", state, action, AttackAction.FAILURE_TARGET_IS_SELF, template
		)
	)

	return violations


static func _test_attack_half_target_already_defeated() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template, template.health)

	var action := _charge(H3, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			"already-defeated target",
			state,
			action,
			AttackAction.FAILURE_TARGET_ALREADY_DEFEATED,
			template
		)
	)

	return violations


# --- The Charge's own refusals ----------------------------------------------


static func _test_unreachable_destination_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)

	violations.append_array(
		_expect(
			H5 not in state.board.reachable_from(ORIGIN, template.move),
			"this scenario's destination must be outside the charger's move allowance"
		)
	)

	var action := _charge(H5, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			"unreachable destination",
			state,
			action,
			ChargeAction.FAILURE_DESTINATION_UNREACHABLE,
			template
		)
	)

	return violations


static func _test_destination_is_origin_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)

	var action := _charge(ORIGIN, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			"destination is origin",
			state,
			action,
			ChargeAction.FAILURE_DESTINATION_IS_ORIGIN,
			template
		)
	)

	return violations


static func _test_no_such_fighter_is_refused() -> Array[String]:
	var template := _template(4)
	var state := _baseline_state(template)

	var action := ChargeAction.new(
		"ghost", H3, TARGET_ID, template, template, _forced(_always(), _never())
	)
	return _assert_refused("no such fighter", state, action, ChargeAction.FAILURE_NO_SUCH_FIGHTER)


## All three injected objects, one row each: the actor's template, the target's
## template and the `CombatProfile`.
static func _test_missing_injected_data_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var profile := _forced(_always(), _never())

	var cases := [
		["null actor template", null, template, profile],
		["null target template", template, null, profile],
		["null combat profile", template, template, null],
	]

	for entry in cases:
		var label: String = entry[0]
		var actor_template: FighterTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var combat_profile: CombatProfile = entry[3]

		var state := _baseline_state(template)
		var action := ChargeAction.new(
			ACTOR_ID, H3, TARGET_ID, actor_template, target_template, combat_profile
		)
		violations.append_array(
			_assert_refused(label, state, action, ChargeAction.FAILURE_MISSING_DATA, template)
		)

	return violations


## An actor the state does hold whose payload `Fighter.from_dict()` rejects is
## `FAILURE_MISSING_DATA`, not `FAILURE_NO_SUCH_FIGHTER` -- something is wrong
## with the data rather than with the request.
static func _test_unparseable_payload_is_refused() -> Array[String]:
	var template := _template(4)
	var state := _build_state()
	state.add_fighter(ACTOR_ID, {"id": ACTOR_ID, "owner_id": "p1", "position": "not-a-coordinate"})
	_place(state, TARGET_ID, "p2", H4, template)

	var action := _charge(H3, template, _forced(_always(), _never()))
	return _assert_refused(
		"unparseable actor payload", state, action, ChargeAction.FAILURE_MISSING_DATA
	)


# --- Spec §6's precondition -------------------------------------------------


static func _test_an_actor_that_has_moved_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)
	_flag(state, ACTOR_ID, template, MoveAction.FLAG_MOVED)

	var action := _charge(H3, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			'an actor holding "moved"', state, action, ChargeAction.FAILURE_ALREADY_ACTED, template
		)
	)

	return violations


static func _test_an_actor_that_has_charged_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)
	_flag(state, ACTOR_ID, template, ChargeLockout.FLAG_CHARGED)

	var action := _charge(H3, template, _forced(_always(), _never()))
	violations.append_array(
		_assert_refused(
			'an actor holding "charged"',
			state,
			action,
			ChargeAction.FAILURE_ALREADY_ACTED,
			template
		)
	)

	return violations

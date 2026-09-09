## Tests `ChargeLockout.locks_out()` directly, and its consult by
## `MoveAction`, `AttackAction` and `GuardAction`'s own `resolve()`. Called
## directly, with no gate involved and no game-side type named anywhere in
## this file, the same omission `move_action_test.gd`, `attack_action_test.gd`
## and `guard_action_test.gd` document.
##
## Every fixture `FighterTemplate` and `CombatProfile` here is built in memory
## through `AttackActionTest`'s own public statics --
## `extraction_contract_test.gd` forbids naming a `res://resources/` path
## under `rules/`, and reusing those builders avoids a second, drifting copy.
##
## Every scenario places a p1 actor, a p2 enemy the attack sub-test targets,
## and -- depending on the scenario -- a p1 "friendly" fighter in one of five
## states: absent, present and unflagged, present and flagged, present but
## removed from the board, or present as a payload that will not parse. The
## `"charged"` flag is set by hand through `Fighter.set_status_flag()` and
## `state.update_fighter()`, per the Issue -- nothing else in the tree writes
## it yet.
class_name ChargeLockoutTest

const ACTOR_ID := "actor"
const FRIENDLY_ID := "friendly"
const ENEMY_ID := "enemy"

const ACTOR_HEX := Vector3i(0, 0, 0)
const MOVE_DEST := Vector3i(1, -1, 0)
const ENEMY_HEX := Vector3i(-1, 1, 0)
const FRIENDLY_HEX := Vector3i(2, -1, -1)


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_predicate_false_for_null_actor())
	violations.append_array(_test_predicate_false_for_unflagged_actor())
	violations.append_array(_test_predicate_true_when_friendly_unflagged_on_board())
	violations.append_array(_test_predicate_false_when_all_friendly_flagged())
	violations.append_array(_test_predicate_false_when_actor_is_sole_friendly())
	violations.append_array(_test_predicate_false_when_friendly_defeated_off_board())
	violations.append_array(_test_predicate_false_when_only_blocker_is_enemy())
	violations.append_array(_test_predicate_false_when_friendly_payload_unparseable())

	violations.append_array(_test_control_unflagged_actor_resolves_all_three())
	violations.append_array(_test_locked_actor_refused_all_three())
	violations.append_array(_test_released_when_all_friendly_flagged())
	violations.append_array(_test_sole_fighter_released())
	violations.append_array(_test_defeated_friendly_does_not_block_actions())
	violations.append_array(_test_unparseable_friendly_does_not_block_actions())

	violations.append_array(_test_move_consult_order_before_destination_is_origin())
	violations.append_array(_test_attack_consult_order_before_targeting_refusal())
	violations.append_array(_test_attack_identity_refusal_precedes_charge_lockout())
	violations.append_array(_test_pass_action_not_gated())

	if violations.is_empty():
		return true

	printerr("\n=== Charge Lockout Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures --------------------------------------------------------------


static func _template() -> FighterTemplate:
	return AttackActionTest.fighter_template(2, 5)


static func _profile() -> CombatProfile:
	return AttackActionTest.standard_profile()


## A hexagonal board of `radius` rings around the origin, every hex NORMAL --
## wide enough to hold every fixture coordinate below with room to spare.
static func _hex_board(radius: int) -> Board:
	var board := Board.new()
	for x in range(-radius, radius + 1):
		var low := maxi(-radius, -x - radius)
		var high := mini(radius, -x + radius)
		for y in range(low, high + 1):
			var coord := Vector3i(x, y, -x - y)
			board.add_hex(coord, Board.HexType.NORMAL)
	return board


static func _build_state() -> GameState:
	var state := GameState.new(_hex_board(4), DeterministicRng.new(11))
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
	template: FighterTemplate
) -> void:
	var fighter := Fighter.new(fighter_id, template, owner_id, coord)
	state.add_fighter(fighter_id, fighter.to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


## Sets `ChargeLockout.FLAG_CHARGED` on the stored fighter by hand, through
## `Fighter.set_status_flag()` then `state.update_fighter()` -- the seam the
## Issue prescribes, since nothing else in the tree writes this flag yet.
static func _flag(state: GameState, fighter_id: String, template: FighterTemplate) -> void:
	var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
	fighter.set_status_flag(ChargeLockout.FLAG_CHARGED)
	state.update_fighter(fighter_id, fighter.to_dict())


static func _stored_fighter(
	state: GameState, fighter_id: String, template: FighterTemplate
) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


## A fresh state with a p1 actor and a p2 enemy always present -- the enemy is
## the attack sub-test's target in every scenario below -- plus a p1
## "friendly" fighter shaped by `friendly_mode`:
##
## - `"none"`: no friendly fighter at all.
## - `"unflagged"`: present, on the board, no `"charged"` flag.
## - `"flagged"`: present, on the board, holding `"charged"`.
## - `"defeated"`: present in `GameState` but removed from the board, exactly
##   as `AttackAction` leaves a defeat.
## - `"unparseable"`: a payload `Fighter.from_dict()` rejects.
static func _build_scenario(actor_charged: bool, friendly_mode: String) -> GameState:
	var template := _template()
	var state := _build_state()
	_place(state, ACTOR_ID, "p1", ACTOR_HEX, template)
	_place(state, ENEMY_ID, "p2", ENEMY_HEX, template)

	if friendly_mode == "unflagged":
		_place(state, FRIENDLY_ID, "p1", FRIENDLY_HEX, template)
	elif friendly_mode == "flagged":
		_place(state, FRIENDLY_ID, "p1", FRIENDLY_HEX, template)
		_flag(state, FRIENDLY_ID, template)
	elif friendly_mode == "defeated":
		_place(state, FRIENDLY_ID, "p1", FRIENDLY_HEX, template)
		state.board.remove_occupant(FRIENDLY_HEX)
	elif friendly_mode == "unparseable":
		state.add_fighter(
			FRIENDLY_ID, {"id": FRIENDLY_ID, "owner_id": "p1", "position": "not-a-coordinate"}
		)

	if actor_charged:
		_flag(state, ACTOR_ID, template)

	return state


static func _resolve_move(
	state: GameState, destination: Vector3i, template: FighterTemplate
) -> TurnResult:
	return MoveAction.new(ACTOR_ID, destination, template).resolve(state)


static func _resolve_attack(state: GameState, template: FighterTemplate) -> TurnResult:
	return AttackAction.new(ACTOR_ID, ENEMY_ID, template, template, _profile()).resolve(state)


static func _resolve_guard(state: GameState, template: FighterTemplate) -> TurnResult:
	return GuardAction.new(ACTOR_ID, template).resolve(state)


# --- Predicate, called directly ---------------------------------------------


static func _test_predicate_false_for_null_actor() -> Array[String]:
	var state := _build_state()
	return _expect(
		not ChargeLockout.locks_out(state, null), "locks_out() must return false for a null actor"
	)


static func _test_predicate_false_for_unflagged_actor() -> Array[String]:
	var template := _template()
	var state := _build_scenario(false, "unflagged")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		not ChargeLockout.locks_out(state, actor),
		"locks_out() must return false for an actor that does not hold FLAG_CHARGED"
	)


static func _test_predicate_true_when_friendly_unflagged_on_board() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "unflagged")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		ChargeLockout.locks_out(state, actor),
		"a flagged actor with an unflagged friendly still on the board must be locked out"
	)


static func _test_predicate_false_when_all_friendly_flagged() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "flagged")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		not ChargeLockout.locks_out(state, actor),
		"the lockout must release once every friendly fighter carries the flag"
	)


static func _test_predicate_false_when_actor_is_sole_friendly() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "none")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		not ChargeLockout.locks_out(state, actor),
		"a flagged actor that is its player's only fighter must be released immediately"
	)


static func _test_predicate_false_when_friendly_defeated_off_board() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "defeated")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		not ChargeLockout.locks_out(state, actor),
		"an unflagged friendly removed from the board must not hold the lockout open"
	)


static func _test_predicate_false_when_only_blocker_is_enemy() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "none")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		not ChargeLockout.locks_out(state, actor),
		(
			"the p2 enemy every scenario places must never hold the lockout open -- "
			+ "only an unflagged friendly on the board does"
		)
	)


static func _test_predicate_false_when_friendly_payload_unparseable() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "unparseable")
	var actor := _stored_fighter(state, ACTOR_ID, template)
	return _expect(
		not ChargeLockout.locks_out(state, actor),
		"a friendly payload that will not parse must be skipped, not treated as a blocker"
	)


# --- Consulted by the three actions ------------------------------------------


static func _test_control_unflagged_actor_resolves_all_three() -> Array[String]:
	return _assert_all_three_allowed(false, "unflagged", "control")


static func _test_locked_actor_refused_all_three() -> Array[String]:
	return _assert_all_three_refused("unflagged", "locked")


static func _test_released_when_all_friendly_flagged() -> Array[String]:
	return _assert_all_three_allowed(true, "flagged", "released")


static func _test_sole_fighter_released() -> Array[String]:
	return _assert_all_three_allowed(true, "none", "sole fighter")


static func _test_defeated_friendly_does_not_block_actions() -> Array[String]:
	return _assert_all_three_allowed(true, "defeated", "defeated friendly")


static func _test_unparseable_friendly_does_not_block_actions() -> Array[String]:
	return _assert_all_three_allowed(true, "unparseable", "unparseable friendly")


## Resolves a Move, an Attack and a Guard, each against its own fresh state
## built by `_build_scenario(true, friendly_mode)`, and asserts all three are
## refused with their own `FAILURE_CHARGE_LOCKOUT`, leave `state.digest()`
## byte-identical, and leave `state.rng.get_state()` unchanged.
static func _assert_all_three_refused(friendly_mode: String, label: String) -> Array[String]:
	var violations: Array[String] = []
	var template := _template()

	var move_state := _build_scenario(true, friendly_mode)
	var move_digest_before := move_state.digest()
	var move_rng_before := move_state.rng.get_state()
	var move_result := _resolve_move(move_state, MOVE_DEST, template)
	violations.append_array(
		_expect(
			not move_result.success and move_result.reason == MoveAction.FAILURE_CHARGE_LOCKOUT,
			"%s: a locked-out Move must be refused with FAILURE_CHARGE_LOCKOUT" % label
		)
	)
	violations.append_array(
		_expect(
			move_state.digest() == move_digest_before,
			"%s: a refused Move must leave the state digest identical" % label
		)
	)
	violations.append_array(
		_expect(
			move_state.rng.get_state() == move_rng_before,
			"%s: a refused Move must not advance state.rng" % label
		)
	)

	var attack_state := _build_scenario(true, friendly_mode)
	var attack_digest_before := attack_state.digest()
	var attack_rng_before := attack_state.rng.get_state()
	var attack_result := _resolve_attack(attack_state, template)
	violations.append_array(
		_expect(
			(
				not attack_result.success
				and attack_result.reason == AttackAction.FAILURE_CHARGE_LOCKOUT
			),
			"%s: a locked-out Attack must be refused with FAILURE_CHARGE_LOCKOUT" % label
		)
	)
	violations.append_array(
		_expect(
			attack_state.digest() == attack_digest_before,
			"%s: a refused Attack must leave the state digest identical" % label
		)
	)
	violations.append_array(
		_expect(
			attack_state.rng.get_state() == attack_rng_before,
			"%s: a refused Attack must not advance state.rng" % label
		)
	)

	var guard_state := _build_scenario(true, friendly_mode)
	var guard_digest_before := guard_state.digest()
	var guard_rng_before := guard_state.rng.get_state()
	var guard_result := _resolve_guard(guard_state, template)
	violations.append_array(
		_expect(
			not guard_result.success and guard_result.reason == GuardAction.FAILURE_CHARGE_LOCKOUT,
			"%s: a locked-out Guard must be refused with FAILURE_CHARGE_LOCKOUT" % label
		)
	)
	violations.append_array(
		_expect(
			guard_state.digest() == guard_digest_before,
			"%s: a refused Guard must leave the state digest identical" % label
		)
	)
	violations.append_array(
		_expect(
			guard_state.rng.get_state() == guard_rng_before,
			"%s: a refused Guard must not advance state.rng" % label
		)
	)

	return violations


## Resolves a Move, an Attack and a Guard, each against its own fresh state
## built by `_build_scenario(actor_charged, friendly_mode)`, and asserts all
## three resolve successfully.
static func _assert_all_three_allowed(
	actor_charged: bool, friendly_mode: String, label: String
) -> Array[String]:
	var violations: Array[String] = []
	var template := _template()

	var move_state := _build_scenario(actor_charged, friendly_mode)
	var move_result := _resolve_move(move_state, MOVE_DEST, template)
	violations.append_array(
		_expect(
			move_result.success,
			"%s: Move must resolve, got refusal %s" % [label, move_result.reason]
		)
	)

	var attack_state := _build_scenario(actor_charged, friendly_mode)
	var attack_result := _resolve_attack(attack_state, template)
	violations.append_array(
		_expect(
			attack_result.success,
			"%s: Attack must resolve, got refusal %s" % [label, attack_result.reason]
		)
	)

	var guard_state := _build_scenario(actor_charged, friendly_mode)
	var guard_result := _resolve_guard(guard_state, template)
	violations.append_array(
		_expect(
			guard_result.success,
			"%s: Guard must resolve, got refusal %s" % [label, guard_result.reason]
		)
	)

	return violations


# --- Consult order -----------------------------------------------------------


## A locked-out Move to the actor's own hex must report FAILURE_CHARGE_LOCKOUT,
## not FAILURE_DESTINATION_IS_ORIGIN -- the lockout is consulted right after
## the fighter's identity and before the destination is looked at.
static func _test_move_consult_order_before_destination_is_origin() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "unflagged")
	var result := _resolve_move(state, ACTOR_HEX, template)
	return _expect(
		result.reason == MoveAction.FAILURE_CHARGE_LOCKOUT,
		(
			"a locked-out Move to the actor's own hex must report FAILURE_CHARGE_LOCKOUT, not "
			+ "FAILURE_DESTINATION_IS_ORIGIN, got %s" % result.reason
		)
	)


## A locked-out Attack against a friendly target must report
## FAILURE_CHARGE_LOCKOUT, not FAILURE_TARGET_IS_FRIENDLY -- the lockout runs
## between _identity_refusal() and _targeting_refusal().
static func _test_attack_consult_order_before_targeting_refusal() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "unflagged")
	var result := AttackAction.new(ACTOR_ID, FRIENDLY_ID, template, template, _profile()).resolve(
		state
	)
	return _expect(
		result.reason == AttackAction.FAILURE_CHARGE_LOCKOUT,
		(
			"a locked-out Attack against a friendly target must report FAILURE_CHARGE_LOCKOUT, not "
			+ "FAILURE_TARGET_IS_FRIENDLY, got %s" % result.reason
		)
	)


## `_identity_refusal()` must still precede the lockout: a null template is
## FAILURE_MISSING_DATA even for an actor that would otherwise be locked out.
static func _test_attack_identity_refusal_precedes_charge_lockout() -> Array[String]:
	var template := _template()
	var state := _build_scenario(true, "unflagged")
	var result := AttackAction.new(ACTOR_ID, ENEMY_ID, null, template, _profile()).resolve(state)
	return _expect(
		result.reason == AttackAction.FAILURE_MISSING_DATA,
		"a missing attacker template must still report FAILURE_MISSING_DATA, got %s" % result.reason
	)


# --- Pass is not gated --------------------------------------------------------


## A locked-out actor's Pass still resolves -- spec §6 lists Move, Attack and
## Guard only, and Pass is the action a locked-out fighter still has.
static func _test_pass_action_not_gated() -> Array[String]:
	var state := _build_scenario(true, "unflagged")
	var result := PassAction.new(ACTOR_ID).resolve(state)
	return _expect(result.success, "PassAction must not be gated by the Charge lockout")

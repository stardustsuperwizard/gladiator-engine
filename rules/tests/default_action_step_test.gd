## Tests `DefaultActionStep.action_for()` directly. Called directly, with no
## gate involved and no game-side type named anywhere in this file, the same
## omission `charge_lockout_test.gd` and `guard_action_test.gd` document.
##
## Every fixture `FighterTemplate` here is built through `AttackActionTest`'s
## own public static, `fighter_template()` -- `extraction_contract_test.gd`
## forbids naming a `res://resources/` path under `rules/`, and reusing that
## builder avoids a second, drifting copy.
##
## `ChargeLockout.locks_out()` parses a candidate blocker off the *locked
## fighter's own template*, not off whatever `templates` map a caller of
## `DefaultActionStep` happens to be carrying. Two scenarios below lean on
## that: a fighter can serve as another's Charge-lockout blocker while being
## excluded from `action_for()`'s own selection for an entirely different
## reason -- its id absent from `templates`, or a payload that will not
## parse -- because those are two independent questions asked of two
## different template sources.
class_name DefaultActionStepTest

const HEX_ORIGIN := Vector3i(0, 0, 0)
const HEX_A := Vector3i(1, -1, 0)
const HEX_B := Vector3i(2, -2, 0)
const HEX_FAR := Vector3i(-3, 3, 0)
const HEX_ENEMY_NEAR := Vector3i(1, 0, -1)


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_returns_third_fighter_in_deployment_order())
	violations.append_array(_test_first_eligible_wins_over_better_placed())
	violations.append_array(_test_null_when_every_fighter_off_board_or_locked_out())
	violations.append_array(_test_null_when_player_owns_no_fighter())
	violations.append_array(_test_null_when_player_id_names_no_player())
	violations.append_array(_test_other_players_fighter_never_named())
	violations.append_array(_test_missing_template_and_unparseable_payload_skipped())
	violations.append_array(_test_returned_actions_all_resolve_successfully())
	violations.append_array(_test_action_returned_unresolved())
	violations.append_array(_test_rng_unchanged_across_every_scenario())

	if violations.is_empty():
		return true

	printerr("\n=== Default Action Step Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ----------------------------------------------------------------


static func _template() -> FighterTemplate:
	return AttackActionTest.fighter_template(2, 5)


## A hexagonal board of `radius` rings around the origin, every hex NORMAL --
## wide enough to hold every fixture coordinate above with room to spare.
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
	var state := GameState.new(_hex_board(6), DeterministicRng.new(17))
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


## Sets `ChargeLockout.FLAG_CHARGED` on the stored fighter by hand -- nothing
## else in the tree writes it yet, the same seam `charge_lockout_test.gd`
## documents.
static func _flag(state: GameState, fighter_id: String, template: FighterTemplate) -> void:
	var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
	fighter.set_status_flag(ChargeLockout.FLAG_CHARGED)
	state.update_fighter(fighter_id, fighter.to_dict())


static func _stored_fighter(
	state: GameState, fighter_id: String, template: FighterTemplate
) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


# --- Deployment order and first-eligible selection ---------------------------


## Three p1 fighters, added in this order: (1) placed then removed from the
## board -- defeated -- (2) charged while (3), a friendly unflagged fighter,
## is still on the board, which is exactly what holds (2)'s Charge lockout
## open. `action_for()` must skip both and name the third.
static func _test_returns_third_fighter_in_deployment_order() -> Array[String]:
	var template := _template()
	var state := _build_state()

	_place(state, "defeated", "p1", HEX_ORIGIN, template)
	state.board.remove_occupant(HEX_ORIGIN)

	_place(state, "charged", "p1", HEX_A, template)
	_place(state, "eligible", "p1", HEX_B, template)
	_flag(state, "charged", template)

	var templates := {"defeated": template, "charged": template, "eligible": template}
	var action := DefaultActionStep.action_for(state, "p1", templates)

	return _expect(
		action != null and action.actor_id() == "eligible",
		(
			"action_for() must skip the defeated and locked-out fighters and return a "
			+ "GuardAction on the third, got %s"
			% (action.actor_id() if action != null else "null")
		)
	)


## Two eligible p1 fighters: the earlier stands alone, the later stands
## adjacent to a p2 enemy. `action_for()` names the earlier -- first eligible
## in deployment order, never the better-placed one, and there is no notion
## of "better placed" to begin with.
static func _test_first_eligible_wins_over_better_placed() -> Array[String]:
	var template := _template()
	var state := _build_state()

	_place(state, "earlier", "p1", HEX_FAR, template)
	_place(state, "later", "p1", HEX_ORIGIN, template)
	_place(state, "enemy", "p2", HEX_ENEMY_NEAR, template)

	var templates := {"earlier": template, "later": template, "enemy": template}
	var action := DefaultActionStep.action_for(state, "p1", templates)

	return _expect(
		action != null and action.actor_id() == "earlier",
		(
			"action_for() must return the earlier, alone, fighter rather than the later one "
			+ "standing adjacent to an enemy, got %s"
			% (action.actor_id() if action != null else "null")
		)
	)


# --- Null paths ----------------------------------------------------------------


## One p1 fighter defeated (off the board). A second, charged, is locked out
## by a third that is unflagged and on the board -- a genuine Charge lockout
## blocker -- but that third fighter's id is deliberately absent from
## `templates`, so `action_for()`'s own selection skips it for a different
## reason than the lockout. Every p1 fighter therefore fails selection, and
## `action_for()` returns null.
static func _test_null_when_every_fighter_off_board_or_locked_out() -> Array[String]:
	var template := _template()
	var state := _build_state()

	_place(state, "defeated", "p1", HEX_ORIGIN, template)
	state.board.remove_occupant(HEX_ORIGIN)

	_place(state, "locked", "p1", HEX_A, template)
	_place(state, "blocker", "p1", HEX_B, template)
	_flag(state, "locked", template)

	# "blocker" is on the board, friendly and unflagged -- exactly what holds
	# "locked"'s Charge lockout open -- but is absent from templates below, so
	# action_for() itself never considers it a candidate.
	var templates := {"defeated": template, "locked": template}
	var action := DefaultActionStep.action_for(state, "p1", templates)

	return _expect(
		action == null,
		"action_for() must return null when every fighter is off the board or locked out"
	)


static func _test_null_when_player_owns_no_fighter() -> Array[String]:
	var template := _template()
	var state := _build_state()
	_place(state, "enemy", "p2", HEX_ORIGIN, template)

	var action := DefaultActionStep.action_for(state, "p1", {"enemy": template})

	return _expect(action == null, "action_for() must return null when the player owns no fighter")


static func _test_null_when_player_id_names_no_player() -> Array[String]:
	var template := _template()
	var state := _build_state()
	_place(state, "fighter", "p1", HEX_ORIGIN, template)

	var action := DefaultActionStep.action_for(state, "p3", {"fighter": template})

	return _expect(
		action == null,
		"action_for() must return null when player_id names no player in turn_order()"
	)


# --- Ownership -----------------------------------------------------------------


## A p2 fighter placed first, in deployment order, and fully eligible for its
## own owner -- never named when the deciding player is p1.
static func _test_other_players_fighter_never_named() -> Array[String]:
	var template := _template()
	var state := _build_state()

	_place(state, "p2_fighter", "p2", HEX_ORIGIN, template)
	_place(state, "p1_fighter", "p1", HEX_A, template)

	var templates := {"p2_fighter": template, "p1_fighter": template}
	var action := DefaultActionStep.action_for(state, "p1", templates)

	return _expect(
		action != null and action.actor_id() == "p1_fighter",
		(
			"action_for() must never name a fighter owned by the other player, got %s"
			% (action.actor_id() if action != null else "null")
		)
	)


# --- Missing template and unparseable payload ----------------------------------


## Three p1 fighters: the first has no entry in `templates`, the second has a
## template but a stored payload that will not parse, and the third is
## genuinely eligible. `action_for()` skips the first two and names the
## third, rather than refusing outright.
static func _test_missing_template_and_unparseable_payload_skipped() -> Array[String]:
	var template := _template()
	var state := _build_state()

	_place(state, "no_template", "p1", HEX_ORIGIN, template)
	state.add_fighter(
		"unparseable", {"id": "unparseable", "owner_id": "p1", "position": "not-a-coordinate"}
	)
	_place(state, "eligible", "p1", HEX_A, template)

	# "no_template" is deliberately absent below; "unparseable" is present but
	# names a payload Fighter.from_dict() rejects.
	var templates := {"unparseable": template, "eligible": template}
	var action := DefaultActionStep.action_for(state, "p1", templates)

	return _expect(
		action != null and action.actor_id() == "eligible",
		(
			"action_for() must skip a fighter absent from templates and one whose payload will "
			+ "not parse, and return the genuinely eligible fighter, got %s"
			% (action.actor_id() if action != null else "null")
		)
	)


# --- Every returned action resolves --------------------------------------------


## Every scenario above that returns a non-null action must return one that
## `resolve()`s successfully against the exact state it was chosen from -- the
## selector's eligibility set must never disagree with GuardAction's own
## refusals.
static func _test_returned_actions_all_resolve_successfully() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()

	var scenarios: Array = [
		["deployment order", _scenario_deployment_order(template)],
		["first eligible", _scenario_first_eligible(template)],
		["ownership", _scenario_ownership(template)],
		["missing template / unparseable", _scenario_missing_and_unparseable(template)],
	]

	for scenario in scenarios:
		var label: String = scenario[0]
		var entry: Dictionary = scenario[1]
		var state: GameState = entry["state"]
		var templates: Dictionary = entry["templates"]
		var player_id: String = entry["player_id"]

		var action := DefaultActionStep.action_for(state, player_id, templates)
		if action == null:
			violations.append("%s: expected a non-null action to resolve" % label)
			continue

		var result := action.resolve(state)
		violations.append_array(
			_expect(
				result.success,
				(
					(
						"%s: GuardAction returned by action_for() must resolve successfully, got "
						+ "refusal %s"
					)
					% [label, result.reason]
				)
			)
		)

	return violations


static func _scenario_deployment_order(template: FighterTemplate) -> Dictionary:
	var state := _build_state()
	_place(state, "defeated", "p1", HEX_ORIGIN, template)
	state.board.remove_occupant(HEX_ORIGIN)
	_place(state, "charged", "p1", HEX_A, template)
	_place(state, "eligible", "p1", HEX_B, template)
	_flag(state, "charged", template)
	return {
		"state": state,
		"player_id": "p1",
		"templates": {"defeated": template, "charged": template, "eligible": template},
	}


static func _scenario_first_eligible(template: FighterTemplate) -> Dictionary:
	var state := _build_state()
	_place(state, "earlier", "p1", HEX_FAR, template)
	_place(state, "later", "p1", HEX_ORIGIN, template)
	_place(state, "enemy", "p2", HEX_ENEMY_NEAR, template)
	return {
		"state": state,
		"player_id": "p1",
		"templates": {"earlier": template, "later": template, "enemy": template},
	}


static func _scenario_ownership(template: FighterTemplate) -> Dictionary:
	var state := _build_state()
	_place(state, "p2_fighter", "p2", HEX_ORIGIN, template)
	_place(state, "p1_fighter", "p1", HEX_A, template)
	return {
		"state": state,
		"player_id": "p1",
		"templates": {"p2_fighter": template, "p1_fighter": template},
	}


static func _scenario_missing_and_unparseable(template: FighterTemplate) -> Dictionary:
	var state := _build_state()
	_place(state, "no_template", "p1", HEX_ORIGIN, template)
	state.add_fighter(
		"unparseable", {"id": "unparseable", "owner_id": "p1", "position": "not-a-coordinate"}
	)
	_place(state, "eligible", "p1", HEX_A, template)
	return {
		"state": state,
		"player_id": "p1",
		"templates": {"unparseable": template, "eligible": template},
	}


# --- Unresolved ------------------------------------------------------------------


## `action_for()` must not resolve anything itself: `power_step_open` stays
## false, the fighter it names has not gained FLAG_GUARDED, and the state's
## digest is byte-identical before and after the call.
static func _test_action_returned_unresolved() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var entry := _scenario_deployment_order(template)
	var state: GameState = entry["state"]

	var digest_before := state.digest()
	var power_step_open_before := state.power_step_open

	var action := DefaultActionStep.action_for(state, "p1", entry["templates"])

	violations.append_array(_expect(action != null, "expected a non-null action"))
	violations.append_array(
		_expect(
			state.power_step_open == power_step_open_before,
			"action_for() must not open the Power Step"
		)
	)
	violations.append_array(
		_expect(state.digest() == digest_before, "action_for() must leave the state digest unchanged")
	)

	if action != null:
		var named := _stored_fighter(state, action.actor_id(), template)
		violations.append_array(
			_expect(
				not named.has_status_flag(GuardAction.FLAG_GUARDED),
				"action_for() must not set FLAG_GUARDED on the fighter it names"
			)
		)

	return violations


# --- Randomness --------------------------------------------------------------


## `state.rng.get_state()` must be unchanged after every call above, including
## the null paths -- action_for() draws nothing from the generator.
static func _test_rng_unchanged_across_every_scenario() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()

	var calls: Array = [
		["deployment order", _scenario_deployment_order(template)],
		["first eligible", _scenario_first_eligible(template)],
		["ownership", _scenario_ownership(template)],
		["missing template / unparseable", _scenario_missing_and_unparseable(template)],
	]

	for call in calls:
		var label: String = call[0]
		var entry: Dictionary = call[1]
		var state: GameState = entry["state"]
		var rng_before := state.rng.get_state()
		DefaultActionStep.action_for(state, entry["player_id"], entry["templates"])
		violations.append_array(
			_expect(
				state.rng.get_state() == rng_before, "%s: action_for() must not advance state.rng" % label
			)
		)

	# The three null paths.
	var no_fighter_state := _build_state()
	_place(no_fighter_state, "enemy", "p2", HEX_ORIGIN, template)
	var no_fighter_rng_before := no_fighter_state.rng.get_state()
	DefaultActionStep.action_for(no_fighter_state, "p1", {"enemy": template})
	violations.append_array(
		_expect(
			no_fighter_state.rng.get_state() == no_fighter_rng_before,
			"player owns no fighter: action_for() must not advance state.rng"
		)
	)

	var no_player_state := _build_state()
	_place(no_player_state, "fighter", "p1", HEX_ORIGIN, template)
	var no_player_rng_before := no_player_state.rng.get_state()
	DefaultActionStep.action_for(no_player_state, "p3", {"fighter": template})
	violations.append_array(
		_expect(
			no_player_state.rng.get_state() == no_player_rng_before,
			"unknown player_id: action_for() must not advance state.rng"
		)
	)

	var all_locked_state := _build_state()
	_place(all_locked_state, "defeated", "p1", HEX_ORIGIN, template)
	all_locked_state.board.remove_occupant(HEX_ORIGIN)
	_place(all_locked_state, "locked", "p1", HEX_A, template)
	_place(all_locked_state, "blocker", "p1", HEX_B, template)
	_flag(all_locked_state, "locked", template)
	var all_locked_rng_before := all_locked_state.rng.get_state()
	DefaultActionStep.action_for(
		all_locked_state, "p1", {"defeated": template, "locked": template}
	)
	violations.append_array(
		_expect(
			all_locked_state.rng.get_state() == all_locked_rng_before,
			"every fighter off board or locked out: action_for() must not advance state.rng"
		)
	)

	return violations

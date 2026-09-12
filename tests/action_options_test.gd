## Tests `ActionOptions`: every query's shape and omissions, that every
## affordance it offers builds a `TurnAction` that actually resolves through
## `ActionRunner`, that every builder names the fighter it was asked for and
## refuses an unknown one, and that no query mutates `state`.
##
## Lives under `tests/` rather than `rules/tests/`, for the reason
## `tests/action_runner_test.gd`'s own docstring gives: `ActionOptions` is
## `res://scripts/` code, which `rules/tests/extraction_contract_test.gd` fails
## the build over.
class_name ActionOptionsTest

## Wide enough to hold every fixture below with room to spare -- the largest
## distance any scenario needs is 5, the same radius `charge_action_test.gd`
## uses for the identical reason.
const BOARD_RADIUS := 5

## `f1` (`p1`) at `CHARGE_ORIGIN` and `f2` (`p2`) at `CHARGE_TARGET_HEX` --
## `_charge_fixture()`'s two fixed hexes.
const CHARGE_ORIGIN := Vector3i(0, 0, 0)
const CHARGE_TARGET_HEX := Vector3i(4, -4, 0)


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_actable_fighters_filters_by_player_and_board_occupancy())
	violations.append_array(_test_actable_fighters_preserves_fighter_ids_order())
	violations.append_array(_test_actable_fighters_unknown_player_is_empty())

	violations.append_array(_test_move_destinations_matches_reachable_from())
	violations.append_array(_test_move_destinations_empty_when_charge_locked_out())
	violations.append_array(_test_move_destinations_empty_for_unknown_fighter())

	violations.append_array(_test_attack_targets_omits_invalid_and_keeps_legal())
	violations.append_array(_test_attack_targets_results_resolve_through_action_runner())
	violations.append_array(_test_attack_targets_empty_when_charge_locked_out())

	violations.append_array(_test_charge_targets_and_destinations_resolve_through_action_runner())
	violations.append_array(_test_charge_targets_empty_when_no_legal_destination())

	violations.append_array(_test_builders_return_correct_actor_id())
	violations.append_array(_test_builders_return_null_for_unknown_fighter())

	violations.append_array(_test_queries_leave_state_untouched())

	if violations.is_empty():
		return true

	printerr("\n=== Action Options Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


static func _template(
	move: int = 0,
	save: int = 2,
	health: int = 5,
	range_hexes: int = 1,
	attack: int = 3,
	damage: int = 1,
	template_id: String = "action-options-test-fighter"
) -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = template_id
	template.move = move
	template.save = save
	template.health = health
	template.range_hexes = range_hexes
	template.attack = attack
	template.damage = damage
	return template


## An attack target every face of the die meets and a save target no face
## meets, so a candidate `AttackAction`/`ChargeAction` resolves rather than
## refuses -- the outcome itself is not what these tests are about.
static func _profile() -> CombatProfile:
	var profile := CombatProfile.new()
	profile.profile_id = "action-options-test-profile"
	profile.die_sides = 6
	profile.attack_target = 1
	profile.save_target = 7
	profile.min_target = 1
	profile.max_target = 7
	return profile


static func _options(templates: FighterTemplates) -> ActionOptions:
	return ActionOptions.new(templates, _profile())


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
	var state := GameState.new(_hex_board(blocked), DeterministicRng.new(7))
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
	if damage > 0:
		fighter.apply_damage(damage)
	state.add_fighter(fighter_id, fighter.to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


## Sets `flag` on the stored fighter, through `Fighter.set_status_flag()` then
## `GameState.update_fighter()` -- the same seam `charge_lockout_test.gd` and
## `charge_action_test.gd` both use for the identical purpose.
static func _flag(
	state: GameState, fighter_id: String, template: FighterTemplate, flag: String
) -> void:
	var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
	fighter.set_status_flag(flag)
	state.update_fighter(fighter_id, fighter.to_dict())


# --- actable_fighters() -------------------------------------------------


## A defeated fighter -- one the board no longer reports at its recorded
## position -- is omitted, and a player's query never names another player's
## fighter.
static func _test_actable_fighters_filters_by_player_and_board_occupancy() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)
	_place(state, "f2", "p1", Vector3i(1, -1, 0), template)
	_place(state, "f3", "p2", Vector3i(2, -2, 0), template)

	# f2 is defeated in every sense this class is allowed to read: the board
	# no longer reports it at its recorded position, exactly as
	# AttackAction._apply_hit() leaves a defeated fighter.
	state.board.remove_occupant(Vector3i(1, -1, 0))

	var p1_expected: Array[String] = ["f1"]
	violations.append_array(
		_expect(
			options.actable_fighters(state, "p1") == p1_expected,
			"actable_fighters(p1) must omit a fighter the board no longer reports at its own hex"
		)
	)

	var p2_expected: Array[String] = ["f3"]
	violations.append_array(
		_expect(
			options.actable_fighters(state, "p2") == p2_expected,
			"actable_fighters(p2) must name only p2's own fighters"
		)
	)

	return violations


static func _test_actable_fighters_preserves_fighter_ids_order() -> Array[String]:
	var template := _template()
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f2", "p1", Vector3i(0, 0, 0), template)
	_place(state, "f1", "p1", Vector3i(1, -1, 0), template)

	var expected: Array[String] = ["f2", "f1"]
	return _expect(
		options.actable_fighters(state, "p1") == expected,
		"actable_fighters() must preserve state.fighter_ids() order, not any other ordering"
	)


static func _test_actable_fighters_unknown_player_is_empty() -> Array[String]:
	var template := _template()
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)

	return _expect(
		options.actable_fighters(state, "no_such_player").is_empty(),
		"actable_fighters() for a player id the state does not hold must be empty"
	)


# --- move_destinations() -------------------------------------------------


static func _test_move_destinations_matches_reachable_from() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(2)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var origin := Vector3i(0, 0, 0)
	var occupied := Vector3i(1, -1, 0)
	var blocked_hex := Vector3i(0, -1, 1)

	var state := _build_state([blocked_hex])
	_place(state, "f1", "p1", origin, template)
	_place(state, "f2", "p1", occupied, template)

	var expected := state.board.reachable_from(origin, template.move)
	var result := options.move_destinations(state, "f1")

	violations.append_array(
		_expect(
			result == expected,
			"move_destinations() must equal Board.reachable_from(position, fighter.move())"
		)
	)
	violations.append_array(
		_expect(origin not in result, "move_destinations() must not include the fighter's own hex")
	)
	violations.append_array(
		_expect(occupied not in result, "move_destinations() must not include an occupied hex")
	)
	violations.append_array(
		_expect(blocked_hex not in result, "move_destinations() must not include a blocked hex")
	)

	return violations


static func _test_move_destinations_empty_when_charge_locked_out() -> Array[String]:
	var template := _template(2)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)
	# A friendly fighter still on the board and still unflagged is what keeps
	# ChargeLockout.locks_out() true for f1.
	_place(state, "f2", "p1", Vector3i(1, -1, 0), template)
	_flag(state, "f1", template, ChargeLockout.FLAG_CHARGED)

	return _expect(
		options.move_destinations(state, "f1").is_empty(),
		"move_destinations() must be empty for a fighter ChargeLockout.locks_out() refuses"
	)


static func _test_move_destinations_empty_for_unknown_fighter() -> Array[String]:
	var templates := FighterTemplates.new()
	var options := _options(templates)
	var state := _build_state()

	return _expect(
		options.move_destinations(state, "ghost").is_empty(),
		"move_destinations() must be empty for a fighter id the state does not hold"
	)


# --- attack_targets() ------------------------------------------------------


## One fighter of every kind attack_targets() must omit, and exactly one it
## must keep: the fighter itself, a friendly fighter, one out of range, one
## with no line of sight, one already defeated, and one legal target.
static func _test_attack_targets_omits_invalid_and_keeps_legal() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(0, 2, 5, 2, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var origin := Vector3i(0, 0, 0)
	var friend_hex := Vector3i(1, -1, 0)
	var valid_hex := Vector3i(1, 0, -1)
	var far_hex := Vector3i(-3, 3, 0)
	var blocked_mid := Vector3i(0, 1, -1)
	var blocked_hex := Vector3i(0, 2, -2)
	var defeated_hex := Vector3i(-1, 0, 1)

	var state := _build_state([blocked_mid])
	_place(state, "f1", "p1", origin, template)
	_place(state, "friend", "p1", friend_hex, template)
	_place(state, "valid", "p2", valid_hex, template)
	_place(state, "far", "p2", far_hex, template)
	_place(state, "blocked", "p2", blocked_hex, template)
	_place(state, "defeated", "p2", defeated_hex, template, template.health)

	violations.append_array(
		_expect(
			not state.board.has_line_of_sight(origin, blocked_hex),
			"this fixture must actually block the line from the origin to the blocked target"
		)
	)

	var result := options.attack_targets(state, "f1")
	var expected: Array[String] = ["valid"]

	violations.append_array(
		_expect(result == expected, "attack_targets() must contain exactly the legal target")
	)

	return violations


## Every id `attack_targets()` returns must build an `AttackAction` that
## resolves successfully through an `ActionRunner`.
static func _test_attack_targets_results_resolve_through_action_runner() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(0, 2, 5, 1, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)
	_place(state, "f2", "p2", Vector3i(1, -1, 0), template)

	var targets := options.attack_targets(state, "f1")
	var expected: Array[String] = ["f2"]
	violations.append_array(
		_expect(targets == expected, "this fixture must offer exactly one attack target")
	)

	for target_id in targets:
		var action := options.attack(state, "f1", target_id)
		violations.append_array(
			_expect(action != null, "attack() must build an AttackAction for a legal target")
		)
		var result := ActionRunner.new(Authority.new(state)).run(action, "p1")
		violations.append_array(
			_expect(
				result.success,
				(
					"every attack_targets() result must build an AttackAction that resolves "
					+ "through ActionRunner, got reason %s" % result.reason
				)
			)
		)

	return violations


static func _test_attack_targets_empty_when_charge_locked_out() -> Array[String]:
	var template := _template(0, 2, 5, 1, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)
	_place(state, "f2", "p1", Vector3i(1, -1, 0), template)
	_place(state, "f3", "p2", Vector3i(0, 1, -1), template)
	_flag(state, "f1", template, ChargeLockout.FLAG_CHARGED)

	return _expect(
		options.attack_targets(state, "f1").is_empty(),
		"attack_targets() must be empty for a fighter ChargeLockout.locks_out() refuses"
	)


# --- charge_targets() / charge_destinations() -------------------------------


## `f1` (`p1`) at `CHARGE_ORIGIN` and `f2` (`p2`) at `CHARGE_TARGET_HEX`, over
## `template` -- freshly built each call, since
## `_test_charge_targets_and_destinations_resolve_through_action_runner()` needs
## one independent copy per destination it tries.
static func _charge_fixture(template: FighterTemplate) -> GameState:
	var state := _build_state()
	_place(state, "f1", "p1", CHARGE_ORIGIN, template)
	_place(state, "f2", "p2", CHARGE_TARGET_HEX, template)
	return state


## Every hex `charge_destinations()` offers builds a `ChargeAction` that
## resolves successfully through an `ActionRunner`, on a fresh copy of the
## fixture per destination -- a Charge that succeeds changes the actor's
## position and flags, and re-using one mutated state across destinations
## would make every destination after the first look illegal.
static func _test_charge_targets_and_destinations_resolve_through_action_runner() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4, 2, 5, 1, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var probe_state := _charge_fixture(template)
	var targets := options.charge_targets(probe_state, "f1")
	var expected_targets: Array[String] = ["f2"]
	violations.append_array(
		_expect(
			targets == expected_targets, "this fixture's only enemy must be a legal charge target"
		)
	)

	var destinations := options.charge_destinations(probe_state, "f1", "f2")
	violations.append_array(
		_expect(
			not destinations.is_empty(), "this fixture must offer at least one charge destination"
		)
	)

	for destination in destinations:
		var fresh_state := _charge_fixture(template)
		var action := options.charge(fresh_state, "f1", "f2", destination)
		violations.append_array(
			_expect(action != null, "charge() must build a ChargeAction for a legal destination")
		)
		var result := ActionRunner.new(Authority.new(fresh_state)).run(action, "p1")
		violations.append_array(
			_expect(
				result.success,
				(
					"every charge_destinations() result must build a ChargeAction that resolves "
					+ "through ActionRunner, got reason %s" % result.reason
				)
			)
		)

	return violations


## A fighter that can move but never into range of its only possible target
## has no legal charge at all: `charge_targets()` is empty even though
## `move_destinations()` is not.
static func _test_charge_targets_empty_when_no_legal_destination() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(1, 2, 5, 1, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var origin := Vector3i(0, 0, 0)
	var far_target := Vector3i(5, -5, 0)

	var state := _build_state()
	_place(state, "f1", "p1", origin, template)
	_place(state, "f2", "p2", far_target, template)

	violations.append_array(
		_expect(
			not options.move_destinations(state, "f1").is_empty(),
			"this fixture's fighter must still be able to move somewhere"
		)
	)
	violations.append_array(
		_expect(
			options.charge_targets(state, "f1").is_empty(),
			(
				"charge_targets() must be empty when no reachable hex ever brings the target "
				+ "into range"
			)
		)
	)
	violations.append_array(
		_expect(
			options.charge_destinations(state, "f1", "f2").is_empty(),
			"charge_destinations() must be empty under the identical condition"
		)
	)

	return violations


# --- Builders ----------------------------------------------------------------


static func _test_builders_return_correct_actor_id() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(2, 2, 5, 1, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var origin := Vector3i(0, 0, 0)
	var neighbour := Vector3i(1, -1, 0)
	var far := Vector3i(4, -4, 0)

	var state := _build_state()
	_place(state, "f1", "p1", origin, template)
	_place(state, "f2", "p2", neighbour, template)
	_place(state, "f3", "p2", far, template)

	var move_action := options.move(state, "f1", Vector3i(0, 1, -1))
	violations.append_array(
		_expect(
			move_action != null and move_action.actor_id() == "f1",
			"move() must build an action whose actor_id() is the fighter asked for"
		)
	)

	var attack_action := options.attack(state, "f1", "f2")
	violations.append_array(
		_expect(
			attack_action != null and attack_action.actor_id() == "f1",
			"attack() must build an action whose actor_id() is the fighter asked for"
		)
	)

	var guard_action := options.guard(state, "f1")
	violations.append_array(
		_expect(
			guard_action != null and guard_action.actor_id() == "f1",
			"guard() must build an action whose actor_id() is the fighter asked for"
		)
	)

	var charge_action := options.charge(state, "f1", "f3", Vector3i(3, -3, 0))
	violations.append_array(
		_expect(
			charge_action != null and charge_action.actor_id() == "f1",
			"charge() must build an action whose actor_id() is the fighter asked for"
		)
	)

	return violations


static func _test_builders_return_null_for_unknown_fighter() -> Array[String]:
	var violations: Array[String] = []
	var template := _template()
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)

	violations.append_array(
		_expect(
			options.move(state, "ghost", Vector3i(1, -1, 0)) == null,
			"move() must return null for an unknown fighter id"
		)
	)
	violations.append_array(
		_expect(
			options.attack(state, "ghost", "f1") == null,
			"attack() must return null for an unknown attacker id"
		)
	)
	violations.append_array(
		_expect(
			options.attack(state, "f1", "ghost") == null,
			"attack() must return null for an unknown target id"
		)
	)
	violations.append_array(
		_expect(
			options.guard(state, "ghost") == null,
			"guard() must return null for an unknown fighter id"
		)
	)
	violations.append_array(
		_expect(
			options.charge(state, "ghost", "f1", Vector3i(1, -1, 0)) == null,
			"charge() must return null for an unknown actor id"
		)
	)
	violations.append_array(
		_expect(
			options.charge(state, "f1", "ghost", Vector3i(1, -1, 0)) == null,
			"charge() must return null for an unknown target id"
		)
	)

	return violations


# --- Read-only ---------------------------------------------------------------


static func _test_queries_leave_state_untouched() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(2, 2, 5, 1, 3, 1)
	var templates := FighterTemplates.new()
	templates.register(template)
	var options := _options(templates)

	var state := _build_state()
	_place(state, "f1", "p1", Vector3i(0, 0, 0), template)
	_place(state, "f2", "p2", Vector3i(1, -1, 0), template)
	_place(state, "f3", "p2", Vector3i(4, -4, 0), template)

	var before := state.digest()

	options.actable_fighters(state, "p1")
	violations.append_array(
		_expect(state.digest() == before, "actable_fighters() must not mutate state")
	)

	options.move_destinations(state, "f1")
	violations.append_array(
		_expect(state.digest() == before, "move_destinations() must not mutate state")
	)

	options.attack_targets(state, "f1")
	violations.append_array(
		_expect(state.digest() == before, "attack_targets() must not mutate state")
	)

	options.charge_targets(state, "f1")
	violations.append_array(
		_expect(state.digest() == before, "charge_targets() must not mutate state")
	)

	options.charge_destinations(state, "f1", "f2")
	violations.append_array(
		_expect(state.digest() == before, "charge_destinations() must not mutate state")
	)

	return violations

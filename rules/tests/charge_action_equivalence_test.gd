## The `ChargeAction` cases that prove nothing was re-derived: equivalence to a
## Move followed by an Attack, the flag-ordering trap, spec §6's lockout end to
## end, and the four resolution effects Charge inherits wholesale from the
## attack half -- Guard's save row, Guard's push immunity, defeat with its
## award, and the push itself.
##
## **Why a second file.** Keeping all of it in
## `rules/tests/charge_action_test.gd` puts that file past `.gdlintrc`'s
## `max-file-lines`. That file's own comment prescribes exactly this response:
## "when a file approaches the limit, split it" -- rather than raising the
## ceiling or thinning the coverage to fit. The line the split falls on is
## which claim a case makes: the sibling file asserts what Charge does of its
## own -- relocate, refuse, flag -- and this one asserts that what it does not
## do itself it reaches by composition. The inherited-effect cases moved here
## for that reason as much as for the line count.
##
## Unlike `attack_action_push_test.gd`, this file is registered in
## `tests/test_bootstrap.gd`'s `_suites` in its own right: the file it was
## split from is nowhere near needing a nested call, and a suite of record is
## the plainer arrangement of the two.
##
## **No fixture is redefined.** Every helper below is a one-line forward onto
## `ChargeActionTest`'s own, so this file carries no second copy of a fixture
## the sibling suite already defines.
##
## **The equivalence case is the one that proves composition.** A Charge and a
## Move-then-Attack from the same starting state and the same seed must leave
## the same board, the same payloads, the same scores, the same generator
## position and -- once the one flag that is deliberately different is
## normalised -- the same `GameState.digest()`. A re-derived relocation, a
## re-derived draw order or a re-derived chart would move at least one of
## those.
class_name ChargeActionEquivalenceTest

const ORIGIN := ChargeActionTest.ORIGIN
const H2 := ChargeActionTest.H2
const H3 := ChargeActionTest.H3
const H4 := ChargeActionTest.H4
const NEAR_H3 := ChargeActionTest.NEAR_H3
const NEAR_H4 := ChargeActionTest.NEAR_H4

const ACTOR_ID := ChargeActionTest.ACTOR_ID
const TARGET_ID := ChargeActionTest.TARGET_ID

## The charging player's second fighter. It carries no flag, which is what
## makes it the regression subject for the ordering trap and the blocker that
## holds spec §6's lockout open afterwards.
const FRIENDLY_ID := "a2"

## The enemy standing beside the destination, so the save chart has a flanking
## row to price and the equivalence comparison is not a comparison of two
## unmodified charts.
const ENEMY_FLANKER_ID := "b2"

## The friendly fighter's hex: adjacent to the origin, off the charge path, and
## adjacent to neither the target nor the destination.
const FRIENDLY_HEX := Vector3i(-1, 1, 0)


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_charge_equals_move_then_attack())
	violations.append_array(_test_charge_resolves_with_an_unflagged_friendly_present())
	violations.append_array(_test_lockout_in_force_after_a_charge())
	violations.append_array(_test_lockout_releases_once_every_friendly_has_charged())

	violations.append_array(_test_guarded_target_uses_the_guard_save_row())
	violations.append_array(_test_guarded_target_is_not_pushed())
	violations.append_array(_test_defeat_removes_the_target_and_awards_the_point())
	violations.append_array(_test_push_back_is_delivered_through_the_attack_half())

	if violations.is_empty():
		return true

	printerr("\n=== Charge Action Equivalence Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures, forwarded onto ChargeActionTest's own ------------------------


static func _template(
	move: int, save: int = 2, health: int = 5, range_hexes: int = 1, damage: int = 1
) -> FighterTemplate:
	return ChargeActionTest._template(move, save, health, range_hexes, damage)


static func _build_state() -> GameState:
	return ChargeActionTest._build_state()


static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate
) -> void:
	ChargeActionTest._place(state, fighter_id, owner_id, coord, template)


static func _stored(state: GameState, fighter_id: String, template: FighterTemplate) -> Fighter:
	return ChargeActionTest._stored(state, fighter_id, template)


static func _flag(
	state: GameState, fighter_id: String, template: FighterTemplate, flag: String
) -> void:
	ChargeActionTest._flag(state, fighter_id, template, flag)


static func _baseline_state(template: FighterTemplate, target_damage: int = 0) -> GameState:
	return ChargeActionTest._baseline_state(template, target_damage)


static func _charge(
	destination: Vector3i,
	template: FighterTemplate,
	profile: CombatProfile,
	push_back: bool = false,
	target_id: String = TARGET_ID
) -> ChargeAction:
	return ChargeActionTest._charge(destination, template, profile, push_back, target_id)


static func _forced(attack_target: int, save_target: int) -> CombatProfile:
	return ChargeActionTest._forced(attack_target, save_target)


## Every die counts on this roll.
static func _always() -> int:
	return AttackActionTest.ALWAYS_TARGET


## No die counts on this roll.
static func _never() -> int:
	return AttackActionTest.NEVER_TARGET


## A Miss, forced: no damage lands, so the target survives every scenario that
## needs it standing afterwards.
static func _missing_profile() -> CombatProfile:
	return AttackActionTest.forced_profile(
		AttackActionTest.NEVER_TARGET, AttackActionTest.ALWAYS_TARGET
	)


# --- Equivalence ------------------------------------------------------------


## The scenario both halves of the equivalence case run against: the charger at
## `ORIGIN`, its target at `H4`, a friendly flanker beside the target and an
## enemy flanker beside the destination, so both of §7.3's charts have a row to
## price and §8 has something to measure on each side.
static func _equivalence_state(template: FighterTemplate) -> GameState:
	var state := _build_state()
	_place(state, ACTOR_ID, "p1", ORIGIN, template)
	_place(state, TARGET_ID, "p2", H4, template)
	_place(state, FRIENDLY_ID, "p1", NEAR_H4, template)
	_place(state, ENEMY_FLANKER_ID, "p2", NEAR_H3, template)
	return state


## One `ChargeAction` against one `MoveAction` followed by one `AttackAction`,
## from two states built identically from the same seed. Everything observable
## must match, and the one thing that deliberately does not -- `"charged"`
## against `"moved"` -- is normalised before the digests are compared.
static func _test_charge_equals_move_then_attack() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var profile := AttackActionTest.standard_profile()

	var stepwise := _equivalence_state(template)
	var rng_before := stepwise.rng.get_state()
	var move_result := MoveAction.new(ACTOR_ID, H3, template).resolve(stepwise)
	var attack_result := AttackAction.new(ACTOR_ID, TARGET_ID, template, template, profile).resolve(
		stepwise
	)

	var charged := _equivalence_state(template)
	var charge_result := (
		ChargeAction.new(ACTOR_ID, H3, TARGET_ID, template, template, profile).resolve(charged)
	)

	violations.append_array(
		_expect(
			move_result.success and attack_result.success,
			"the stepwise Move and Attack must both resolve for this comparison to mean anything"
		)
	)
	violations.append_array(_expect(charge_result.success, "the Charge must resolve"))
	violations.append_array(
		_expect(
			stepwise.rng.get_state() != rng_before,
			"this scenario must actually draw dice, or the generator comparison is vacuous"
		)
	)
	violations.append_array(
		_expect(
			stepwise.rng.get_state() == charged.rng.get_state(),
			"a Charge must leave the generator exactly where a Move then an Attack leaves it"
		)
	)
	violations.append_array(
		_expect(
			JSON.stringify(stepwise.board.to_dict()) == JSON.stringify(charged.board.to_dict()),
			"a Charge must leave the identical board"
		)
	)

	for player_id in stepwise.turn_order():
		violations.append_array(
			_expect(
				stepwise.player(player_id).score == charged.player(player_id).score,
				"a Charge must leave %s holding the identical score" % player_id
			)
		)

	for fighter_id in [TARGET_ID, FRIENDLY_ID, ENEMY_FLANKER_ID]:
		violations.append_array(
			_expect(
				(
					JSON.stringify(stepwise.fighter(fighter_id))
					== JSON.stringify(charged.fighter(fighter_id))
				),
				"a Charge must leave %s's payload identical" % fighter_id
			)
		)

	violations.append_array(_assert_actor_payloads_match_but_for_the_flag(stepwise, charged))
	violations.append_array(_assert_digests_match_once_normalised(stepwise, charged))

	return violations


## The actor's two payloads differ in exactly one place: the status flag. Each
## carries the flag its own action sets, and everything else -- position,
## damage counter, owner, template id -- is byte-identical.
static func _assert_actor_payloads_match_but_for_the_flag(
	stepwise: GameState, charged: GameState
) -> Array[String]:
	var violations: Array[String] = []
	var stepwise_actor := stepwise.fighter(ACTOR_ID)
	var charged_actor := charged.fighter(ACTOR_ID)

	violations.append_array(
		_expect(
			(
				JSON.stringify(stepwise_actor.get("status_flags"))
				== JSON.stringify([MoveAction.FLAG_MOVED])
			),
			'the stepwise actor must carry exactly the "moved" flag'
		)
	)
	violations.append_array(
		_expect(
			(
				JSON.stringify(charged_actor.get("status_flags"))
				== JSON.stringify([ChargeLockout.FLAG_CHARGED])
			),
			'the charging actor must carry exactly the "charged" flag'
		)
	)

	stepwise_actor.erase("status_flags")
	charged_actor.erase("status_flags")
	violations.append_array(
		_expect(
			JSON.stringify(stepwise_actor) == JSON.stringify(charged_actor),
			"the two actor payloads must be identical in every field but the status flag"
		)
	)

	return violations


## With the one flag made identical, the two whole states hash the same. This
## is the strongest form of the claim: nothing anywhere in either state
## differs.
static func _assert_digests_match_once_normalised(
	stepwise: GameState, charged: GameState
) -> Array[String]:
	var normalised := charged.fighter(ACTOR_ID)
	normalised["status_flags"] = [MoveAction.FLAG_MOVED]
	charged.update_fighter(ACTOR_ID, normalised)

	return _expect(
		charged.digest() == stepwise.digest(),
		(
			"with the one differing flag normalised, a Charge must leave a state whose digest is "
			+ "byte-identical to the Move-then-Attack state's"
		)
	)


# --- The ordering trap and spec §6's lockout, end to end --------------------


## The lockout fixture: the charger, its target, and a second friendly fighter
## carrying no flag at all.
static func _lockout_state(template: FighterTemplate) -> GameState:
	var state := _build_state()
	_place(state, ACTOR_ID, "p1", ORIGIN, template)
	_place(state, TARGET_ID, "p2", H4, template)
	_place(state, FRIENDLY_ID, "p1", FRIENDLY_HEX, template)
	return state


## The regression test for steps 2 and 4 of the resolution sequence. The
## charging player owns a fighter that has not charged, so committing
## `"charged"` before the attack half resolved would make the composed
## `AttackAction` refuse the charger with its own Charge-lockout constant and
## fail the whole action.
static func _test_charge_resolves_with_an_unflagged_friendly_present() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _lockout_state(template)

	var action := ChargeAction.new(ACTOR_ID, H3, TARGET_ID, template, template, _missing_profile())
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			result.success,
			(
				"a Charge must resolve while the charging player owns an unflagged fighter, got "
				+ "refusal %s -- the flag was committed before the attack half" % result.reason
			)
		)
	)
	violations.append_array(
		_expect(
			_stored(state, ACTOR_ID, template).has_status_flag(ChargeLockout.FLAG_CHARGED),
			'the charger must carry "charged" once the Charge has resolved'
		)
	)
	violations.append_array(
		_expect(
			not _stored(state, FRIENDLY_ID, template).has_status_flag(ChargeLockout.FLAG_CHARGED),
			"a Charge must flag only its own actor"
		)
	)

	return violations


## A fresh fixture with the Charge already resolved, for the lockout cases
## below. Each of the three actions gets its own, so none can see another's
## effect.
static func _charged_state(template: FighterTemplate) -> GameState:
	var state := _lockout_state(template)
	ChargeAction.new(ACTOR_ID, H3, TARGET_ID, template, template, _missing_profile()).resolve(state)
	return state


## After a successful Charge the same fighter is refused a Move, an Attack and
## a Guard, because a friendly fighter still on the board has not charged.
static func _test_lockout_in_force_after_a_charge() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)

	(
		violations
		. append_array(
			_expect(
				_stored(_charged_state(template), ACTOR_ID, template).has_status_flag(
					ChargeLockout.FLAG_CHARGED
				),
				"the fixture Charge must have resolved and set the flag for these cases to test anything"
			)
		)
	)

	var move_result := MoveAction.new(ACTOR_ID, H2, template).resolve(_charged_state(template))
	violations.append_array(
		_expect(
			move_result.reason == MoveAction.FAILURE_CHARGE_LOCKOUT,
			"a charged fighter must be refused a Move, got %s" % move_result.reason
		)
	)

	var attack_result := (
		AttackAction
		. new(ACTOR_ID, TARGET_ID, template, template, _missing_profile())
		. resolve(_charged_state(template))
	)
	violations.append_array(
		_expect(
			attack_result.reason == AttackAction.FAILURE_CHARGE_LOCKOUT,
			"a charged fighter must be refused an Attack, got %s" % attack_result.reason
		)
	)

	var guard_result := GuardAction.new(ACTOR_ID, template).resolve(_charged_state(template))
	violations.append_array(
		_expect(
			guard_result.reason == GuardAction.FAILURE_CHARGE_LOCKOUT,
			"a charged fighter must be refused a Guard, got %s" % guard_result.reason
		)
	)

	return violations


## Once every friendly fighter still on the board carries `"charged"` -- the
## second one set by hand in the fixture, since nothing else in a single Action
## Step would -- all three are permitted again.
static func _test_lockout_releases_once_every_friendly_has_charged() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)

	var move_state := _charged_state(template)
	_flag(move_state, FRIENDLY_ID, template, ChargeLockout.FLAG_CHARGED)
	var move_result := MoveAction.new(ACTOR_ID, H2, template).resolve(move_state)
	violations.append_array(
		_expect(
			move_result.success,
			"a released fighter must be permitted a Move, got refusal %s" % move_result.reason
		)
	)

	var attack_state := _charged_state(template)
	_flag(attack_state, FRIENDLY_ID, template, ChargeLockout.FLAG_CHARGED)
	var attack_result := (
		AttackAction
		. new(ACTOR_ID, TARGET_ID, template, template, _missing_profile())
		. resolve(attack_state)
	)
	violations.append_array(
		_expect(
			attack_result.success,
			"a released fighter must be permitted an Attack, got refusal %s" % attack_result.reason
		)
	)

	var guard_state := _charged_state(template)
	_flag(guard_state, FRIENDLY_ID, template, ChargeLockout.FLAG_CHARGED)
	var guard_result := GuardAction.new(ACTOR_ID, template).resolve(guard_state)
	violations.append_array(
		_expect(
			guard_result.success,
			"a released fighter must be permitted a Guard, got refusal %s" % guard_result.reason
		)
	)

	return violations


# --- Guard, defeat and the push, all inherited from the attack half ---------


## Spec §6 and §7.3's Guard row: a guarded target subtracts `guard_modifier`
## from the save target. Inherited from `AttackAction`, not reimplemented --
## the assertion is only that charging reaches the same chart.
static func _test_guarded_target_uses_the_guard_save_row() -> Array[String]:
	var violations: Array[String] = []
	var profile := AttackActionTest.standard_profile()
	var template := _template(4)

	var guarded_state := _baseline_state(template)
	_flag(guarded_state, TARGET_ID, template, GuardAction.FLAG_GUARDED)
	var guarded := _charge(H3, template, profile)
	violations.append_array(
		_expect(
			guarded.resolve(guarded_state).success, "a Charge into a guarded target must resolve"
		)
	)
	violations.append_array(
		_expect(
			guarded.attack_half().save_target() == 4,
			(
				"a guarded target must resolve the save chart with the guard row: 4, got %d"
				% guarded.attack_half().save_target()
			)
		)
	)

	var open_state := _baseline_state(template)
	var open := _charge(H3, template, profile)
	open.resolve(open_state)
	violations.append_array(
		_expect(
			open.attack_half().save_target() == 5,
			"an unguarded target must take the unmodified save target, for the comparison to hold"
		)
	)

	return violations


## Spec §6's second Guard effect: push immunity. A forced Hit with `push_back`
## requested does not move a guarded target.
static func _test_guarded_target_is_not_pushed() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)
	_flag(state, TARGET_ID, template, GuardAction.FLAG_GUARDED)

	var action := _charge(H3, template, _forced(_always(), _never()), true)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "the pushing Charge must resolve"))
	violations.append_array(
		_expect(
			action.attack_half().outcome() == DicePool.Outcome.HIT,
			"this scenario must resolve the attack half to a HIT"
		)
	)
	violations.append_array(
		_expect(not action.attack_half().pushed(), "a guarded target must not be pushed")
	)
	violations.append_array(
		_expect(
			_stored(state, TARGET_ID, template).position() == H4,
			"a guarded target's stored position must be unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(H4) == StringName(TARGET_ID),
			"a guarded target must still occupy its own hex"
		)
	)

	return violations


## Spec §9's defeat and its flat award, both reached through the attack half.
static func _test_defeat_removes_the_target_and_awards_the_point() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4, 2, 1)
	var profile := _forced(_always(), _never())
	profile.defeat_award = 3
	var state := _baseline_state(template)

	var action := _charge(H3, template, profile)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating Charge must resolve successfully"))
	violations.append_array(
		_expect(action.attack_half().target_defeated(), "this scenario must defeat the target")
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(H4) == Board.EMPTY_OCCUPANT,
			"a defeated target must be removed from the board"
		)
	)
	violations.append_array(
		_expect(
			state.player("p1").score == profile.defeat_award,
			"a defeating Charge must credit defeat_award to the charging fighter's owner"
		)
	)
	violations.append_array(
		_expect(
			_stored(state, ACTOR_ID, template).has_status_flag(ChargeLockout.FLAG_CHARGED),
			'a defeating Charge must still set the "charged" flag'
		)
	)

	return violations


## Spec §7.6-7.7's push, requested through `_init()` and delivered by the
## attack half on a forced Hit.
static func _test_push_back_is_delivered_through_the_attack_half() -> Array[String]:
	var violations: Array[String] = []
	var template := _template(4)
	var state := _baseline_state(template)

	var action := _charge(H3, template, _forced(_always(), _never()), true)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a pushing Charge must resolve successfully"))
	violations.append_array(
		_expect(action.attack_half().pushed(), "a forced Hit with push_back true must push")
	)

	var pushed_to := _stored(state, TARGET_ID, template).position()
	violations.append_array(
		_expect(
			HexCoord.distance(H4, pushed_to) == 1, "a push must move the target by exactly one hex"
		)
	)
	violations.append_array(
		_expect(
			HexCoord.distance(H3, pushed_to) > HexCoord.distance(H3, H4),
			"a push must leave the target farther from the charger's destination than before"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(pushed_to) == StringName(TARGET_ID),
			"a push must claim the destination hex for the target"
		)
	)

	return violations

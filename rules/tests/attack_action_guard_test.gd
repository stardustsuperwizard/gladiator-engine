## Tests `AttackAction`'s two reads of spec §6's `"guarded"` flag: the
## save-chart bonus (spec §7.3) and push immunity (spec §6, §7.6-7.7).
##
## **A registered suite of its own**, unlike `attack_action_target_test.gd` and
## `attack_action_push_test.gd`. Those two are reached by a call inside
## `attack_action_test.gd`, but that file sits at .gdlintrc's 1000-line file
## cap already, and the cap is not to be raised -- so this suite is registered
## directly in `tests/test_bootstrap.gd`'s `_suites` instead of adding one more
## call to that file. `tests/orphan_test_contract_test.gd` accepts either
## route; this one is the deliberate exception, not an oversight.
##
## Called directly, with no gate involved and no game-side type named anywhere
## in this file, the same omission `attack_action_test.gd` documents.
##
## **No fixture is redefined.** Every helper below is a one-line forward onto
## `AttackActionTest`'s own public fixtures -- `fighter_template()`,
## `standard_profile()`, `forced_profile()` and the hex constants -- so this
## file carries no second, drifting copy. `standard_profile()` already sets
## `guard_modifier = 1`, which is what every save-chart row below is worked
## against.
##
## Guarding a fighter goes through `GuardAction` itself, never through a
## payload literal: reaching into a fighter's dictionary and appending
## `"guarded"` to `"status_flags"` directly would duplicate the serialization
## contract `GuardAction` already owns.
class_name AttackActionGuardTest

const ATTACKER_HEX := AttackActionTest.ATTACKER_HEX
const TARGET_HEX := AttackActionTest.TARGET_HEX
const ATTACKER_FLANK := AttackActionTest.ATTACKER_FLANK
const ATTACKER_FLANK_B := AttackActionTest.ATTACKER_FLANK_B


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_guarded_defender_lowers_the_save_target())
	violations.append_array(_test_unguarded_defender_is_the_control())
	violations.append_array(_test_stacking_guarded_and_attacker_flanked())
	violations.append_array(_test_stacking_guarded_and_attacker_surrounded_clamps())
	violations.append_array(_test_push_immunity_on_a_hit())
	violations.append_array(_test_push_immunity_on_a_drawn())
	violations.append_array(_test_push_control_unguarded_target_is_still_pushed())
	violations.append_array(_test_guard_blocks_only_the_push())
	violations.append_array(_test_rng_position_is_unaffected_by_guard())

	if violations.is_empty():
		return true

	printerr("\n=== Attack Action Guard Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


# --- Fixtures, forwarded onto AttackActionTest's own ----------------------


static func _expect(condition: bool, message: String) -> Array[String]:
	return AttackActionTest._expect(condition, message)


static func _fighter_template(
	save: int, health: int, range_hexes: int = 1, attack: int = 3, damage: int = 1
) -> FighterTemplate:
	return AttackActionTest.fighter_template(save, health, range_hexes, attack, damage)


static func _standard_profile() -> CombatProfile:
	return AttackActionTest.standard_profile()


static func _forced_profile(attack_target: int, save_target: int) -> CombatProfile:
	return AttackActionTest.forced_profile(attack_target, save_target)


## Every die counts on this roll.
static func _always() -> int:
	return AttackActionTest.ALWAYS_TARGET


## No die counts on this roll.
static func _never() -> int:
	return AttackActionTest.NEVER_TARGET


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


## Resolves a Guard on `fighter_id` through `GuardAction` itself, never by
## touching the stored payload directly.
static func _guard(state: GameState, fighter_id: String, template: FighterTemplate) -> void:
	var result := GuardAction.new(fighter_id, template).resolve(state)
	if not result.success:
		push_error("test fixture failed to guard %s: %s" % [fighter_id, result.reason])


# --- Save chart -----------------------------------------------------------


## Against `standard_profile()`, an attack on a guarded defender by an
## unflanked attacker reports save_target() == 4: 5 - guard_modifier(1).
static func _test_guarded_defender_lowers_the_save_target() -> Array[String]:
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_guard(state, "b1", template)

	var action := AttackAction.new("a1", "b1", template, template, _standard_profile())
	action.resolve(state)

	return _expect(
		action.save_target() == 4,
		"a guarded, unflanked defender must report save_target() == 4, got %d" % action.save_target()
	)


## The same attack on an unguarded defender reports save_target() == 5: the
## control proving the guarded row actually moved the number.
static func _test_unguarded_defender_is_the_control() -> Array[String]:
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new("a1", "b1", template, template, _standard_profile())
	action.resolve(state)

	return _expect(
		action.save_target() == 5,
		"an unguarded, unflanked defender must report save_target() == 5, got %d" % action.save_target()
	)


## A guarded defender whose attacker is flanked reports save_target() == 2:
## 5 - guard_modifier(1) - save_flank_modifier(2).
static func _test_stacking_guarded_and_attacker_flanked() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_place(state, "b2", "p2", ATTACKER_FLANK, template)
	_guard(state, "b1", template)

	var action := AttackAction.new("a1", "b1", template, template, _standard_profile())
	action.resolve(state)

	violations.append_array(
		_expect(
			action.save_bonus_count() == Flanking.FLANKED,
			"this scenario must actually flank the attacker for the stacking claim to mean anything"
		)
	)
	violations.append_array(
		_expect(
			action.save_target() == 2,
			(
				"a guarded defender whose attacker is flanked must report save_target() == 2, got %d"
				% action.save_target()
			)
		)
	)

	return violations


## A guarded defender whose attacker is surrounded: the unclamped arithmetic
## is 5 - guard_modifier(1) - save_surround_modifier(3) == 1, and
## clamped_target() raises it to min_target's floor of 2. Asserted explicitly
## against the profile's own fields so this cannot silently degenerate into
## the flanked case above.
static func _test_stacking_guarded_and_attacker_surrounded_clamps() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var profile := _standard_profile()
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_place(state, "b2", "p2", ATTACKER_FLANK, template)
	_place(state, "b3", "p2", ATTACKER_FLANK_B, template)
	_guard(state, "b1", template)

	var unclamped := profile.save_target - profile.guard_modifier - profile.save_surround_modifier
	violations.append_array(
		_expect(
			unclamped == 1,
			(
				"this scenario's unclamped arithmetic must be exactly 1 (5 - 1 - 3), got %d"
				% unclamped
			)
		)
	)

	var action := AttackAction.new("a1", "b1", template, template, profile)
	action.resolve(state)

	violations.append_array(
		_expect(
			action.save_bonus_count() == Flanking.SURROUNDED,
			"this scenario must actually surround the attacker for the stacking claim to mean anything"
		)
	)
	violations.append_array(
		_expect(
			action.save_target() == 2,
			(
				"a guarded defender whose attacker is surrounded must report save_target() == 2 "
				+ "after the clamp raises it off 1, got %d"
			) % action.save_target()
		)
	)

	return violations


# --- Push immunity ----------------------------------------------------------


## A guarded target hit while push_back is requested has pushed() false, an
## unchanged position, and Board.occupant_at() still reporting it at that hex.
static func _test_push_immunity_on_a_hit() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_guard(state, "b1", template)

	var action := AttackAction.new(
		"a1", "b1", template, template, _forced_profile(_always(), _never()), true
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a guarded Hit must still resolve successfully"))
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.HIT, "this scenario must resolve to a HIT")
	)
	violations.append_array(
		_expect(not action.pushed(), "a guarded target on a Hit must report pushed() == false")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a guarded target's stored position must be unchanged after a Hit"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == &"b1",
			"Board.occupant_at() must still report the guarded target at its original hex after a Hit"
		)
	)

	return violations


## The same immunity on a Drawn.
static func _test_push_immunity_on_a_drawn() -> Array[String]:
	var violations: Array[String] = []

	# Two attack dice against two save dice, so ALWAYS against ALWAYS ties.
	var template := _fighter_template(2, 5, 1, 2, 2)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_guard(state, "b1", template)

	var action := AttackAction.new(
		"a1", "b1", template, template, _forced_profile(_always(), _always()), true
	)
	var result := action.resolve(state)

	violations.append_array(
		_expect(result.success, "a guarded Drawn must still resolve successfully")
	)
	violations.append_array(
		_expect(action.outcome() == DicePool.Outcome.DRAWN, "this scenario must resolve to a DRAWN")
	)
	violations.append_array(
		_expect(not action.pushed(), "a guarded target on a Drawn must report pushed() == false")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) == TARGET_HEX,
			"a guarded target's stored position must be unchanged after a Drawn"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(TARGET_HEX) == &"b1",
			"Board.occupant_at() must still report the guarded target at its original hex after a Drawn"
		)
	)

	return violations


## An *unguarded* target on the identical fixture, forced outcome and
## push_back is still pushed() true and does move -- proving the flag, not the
## fixture, caused the immunity above.
static func _test_push_control_unguarded_target_is_still_pushed() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)

	var action := AttackAction.new(
		"a1", "b1", template, template, _forced_profile(_always(), _never()), true
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "the control Hit must still resolve successfully"))
	violations.append_array(
		_expect(action.pushed(), "an unguarded target on the same fixture must still be pushed()")
	)
	violations.append_array(
		_expect(
			_stored_position(state, "b1", template) != TARGET_HEX,
			"an unguarded target must actually move off its original hex"
		)
	)

	return violations


## Guard blocks the push and nothing else: a guarded target still takes the
## attacker's damage() on a Hit, and a guarded target can still be defeated.
static func _test_guard_blocks_only_the_push() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(2, 5)
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, template)
	_place(state, "b1", "p2", TARGET_HEX, template)
	_guard(state, "b1", template)
	var before := _stored_damage(state, "b1", template)

	var action := AttackAction.new(
		"a1", "b1", template, template, _forced_profile(_always(), _never()), true
	)
	action.resolve(state)

	violations.append_array(
		_expect(
			_stored_damage(state, "b1", template) == before + template.damage,
			"a guarded target on a Hit must still take the attacker's damage() in full"
		)
	)

	var defeat_template := _fighter_template(2, 1)
	var defeat_state := _build_state(13)
	_place(defeat_state, "a1", "p1", ATTACKER_HEX, defeat_template)
	_place(defeat_state, "b1", "p2", TARGET_HEX, defeat_template)
	_guard(defeat_state, "b1", defeat_template)

	var defeat_action := AttackAction.new(
		"a1", "b1", defeat_template, defeat_template, _forced_profile(_always(), _never()), true
	)
	defeat_action.resolve(defeat_state)

	violations.append_array(
		_expect(
			defeat_action.target_defeated(), "a guarded target must still be defeatable by a Hit"
		)
	)
	violations.append_array(
		_expect(
			not defeat_action.pushed(), "a defeated, guarded target must not report pushed()"
		)
	)

	return violations


# --- Determinism -------------------------------------------------------------


## Resolving an attack against a guarded defender leaves state.rng at the same
## position it reaches against an unguarded defender from the same seed and
## the same fixture -- Guard changes the target number, never the draw.
static func _test_rng_position_is_unaffected_by_guard() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(3, 5)

	var guarded_state := _build_state(13)
	_place(guarded_state, "a1", "p1", ATTACKER_HEX, template)
	_place(guarded_state, "b1", "p2", TARGET_HEX, template)
	_guard(guarded_state, "b1", template)
	AttackAction.new("a1", "b1", template, template, _standard_profile()).resolve(guarded_state)

	var unguarded_state := _build_state(13)
	_place(unguarded_state, "a1", "p1", ATTACKER_HEX, template)
	_place(unguarded_state, "b1", "p2", TARGET_HEX, template)
	AttackAction.new("a1", "b1", template, template, _standard_profile()).resolve(unguarded_state)

	violations.append_array(
		_expect(
			guarded_state.rng.get_state() == unguarded_state.rng.get_state(),
			"resolving against a guarded defender must leave state.rng at the same position as an "
			+ "unguarded one, from the same seed and fixture"
		)
	)

	return violations

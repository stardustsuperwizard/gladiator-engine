## Tests `GameMode` and `Deathmatch`: the id -> implementation registry spec
## §11.2 resolves through, and the seam both `AttackAction._apply_hit()` and
## `ChargeAction`'s composed attack half route a defeat's VP award through.
##
## Every fixture is built in memory through `AttackActionTest`'s and
## `ChargeActionTest`'s own public statics -- `extraction_contract_test.gd`
## forbids naming a `res://resources/` path under `rules/`, and reusing those
## builders avoids a second, drifting copy of a fixture either suite already
## defines.
##
## **The award-routing cases below duplicate none of `attack_action_test.gd`'s
## coverage.** That suite already pins the Deathmatch-default behaviour --
## every `AttackAction.new()` call site there omits `game_mode` entirely, so it
## proves the *default* stays `Deathmatch.MODE_ID`. What this suite adds is the
## seam itself: an explicit mode, known or not, actually reaches
## `GameMode.defeat_award()`.
class_name GameModeTest

## A mode id no registry row names.
const UNKNOWN_MODE := "treasure"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_deathmatch_and_registry_agree_on_the_authored_number())
	violations.append_array(_test_is_known_true_for_deathmatch_false_for_unknown())
	violations.append_array(_test_unknown_mode_awards_zero())
	violations.append_array(_test_attack_defeat_under_deathmatch_awards_the_profile_amount())
	violations.append_array(_test_attack_defeat_under_an_unknown_mode_awards_zero())
	violations.append_array(_test_charge_defeat_routes_through_the_same_seam())

	if violations.is_empty():
		return true

	printerr("\n=== Game Mode Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Registry ----------------------------------------------------------


## `GameMode.defeat_award(Deathmatch.MODE_ID, profile)` equals
## `Deathmatch.defeat_award(profile)` equals `profile.defeat_award` -- the
## chain the Issue's acceptance criteria states, asserted as one chain rather
## than two separate equalities so a break in either link is one failure, not
## two disagreeing ones.
static func _test_deathmatch_and_registry_agree_on_the_authored_number() -> Array[String]:
	var violations: Array[String] = []
	var profile := AttackActionTest.standard_profile()
	profile.defeat_award = 3

	violations.append_array(
		_expect(
			GameMode.defeat_award(Deathmatch.MODE_ID, profile) == Deathmatch.defeat_award(profile),
			"GameMode.defeat_award() for Deathmatch's own id must equal Deathmatch.defeat_award()"
		)
	)
	violations.append_array(
		_expect(
			Deathmatch.defeat_award(profile) == profile.defeat_award,
			"Deathmatch.defeat_award() must equal the profile's own defeat_award, unchanged"
		)
	)

	return violations


static func _test_is_known_true_for_deathmatch_false_for_unknown() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			GameMode.is_known(Deathmatch.MODE_ID),
			"GameMode.is_known() must be true for Deathmatch's own id"
		)
	)
	violations.append_array(
		_expect(
			not GameMode.is_known(UNKNOWN_MODE),
			"GameMode.is_known() must be false for a mode id no registry row names"
		)
	)

	return violations


## An unregistered mode awards 0 regardless of the profile's own
## `defeat_award` -- §11.2 says nothing outside the active mode awards VP, so
## an unrecognised mode is not a fallback to Deathmatch.
static func _test_unknown_mode_awards_zero() -> Array[String]:
	var profile := AttackActionTest.standard_profile()
	profile.defeat_award = 5

	return _expect(
		GameMode.defeat_award(UNKNOWN_MODE, profile) == 0,
		"an unregistered mode id must award 0, regardless of the profile's own defeat_award"
	)


# --- Attack --------------------------------------------------------------


## A defeat resolved through `AttackAction` with an explicit Deathmatch mode
## raises the attacker's owner's score by exactly `defeat_award`, and the
## defeated fighter is still removed from the board.
static func _test_attack_defeat_under_deathmatch_awards_the_profile_amount() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := AttackActionTest.fighter_template(2, 3)
	var target_template := AttackActionTest.fighter_template(2, 1)
	var state := AttackActionTest._build_state(13)
	AttackActionTest._place(state, "a1", "p1", AttackActionTest.ATTACKER_HEX, attacker_template)
	AttackActionTest._place(state, "b1", "p2", AttackActionTest.TARGET_HEX, target_template)

	var profile := AttackActionTest.forced_profile(
		AttackActionTest.ALWAYS_TARGET, AttackActionTest.NEVER_TARGET
	)
	profile.defeat_award = 3

	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, profile, false, Deathmatch.MODE_ID
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating attack must resolve successfully"))
	violations.append_array(
		_expect(action.target_defeated(), "this scenario must defeat the target")
	)
	(
		violations
		. append_array(
			_expect(
				state.board.occupant_at(AttackActionTest.TARGET_HEX) == Board.EMPTY_OCCUPANT,
				(
					"a defeated fighter's hex must report no occupant under Deathmatch, exactly as it does "
					+ "with no mode named at all"
				)
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				state.player("p1").score == profile.defeat_award,
				(
					"a defeat resolved under Deathmatch must raise the attacker's owner's score by exactly "
					+ "defeat_award"
				)
			)
		)
	)

	return violations


## The same defeat, resolved with a mode id no registry knows: the fighter
## still comes off the board, but 0 VP is awarded -- proving the award is the
## mode's to give and not an unconditional rule of spec §9.
static func _test_attack_defeat_under_an_unknown_mode_awards_zero() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := AttackActionTest.fighter_template(2, 3)
	var target_template := AttackActionTest.fighter_template(2, 1)
	var state := AttackActionTest._build_state(13)
	AttackActionTest._place(state, "a1", "p1", AttackActionTest.ATTACKER_HEX, attacker_template)
	AttackActionTest._place(state, "b1", "p2", AttackActionTest.TARGET_HEX, target_template)

	var profile := AttackActionTest.forced_profile(
		AttackActionTest.ALWAYS_TARGET, AttackActionTest.NEVER_TARGET
	)
	profile.defeat_award = 3

	var action := AttackAction.new(
		"a1", "b1", attacker_template, target_template, profile, false, UNKNOWN_MODE
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating attack must resolve successfully"))
	violations.append_array(
		_expect(action.target_defeated(), "this scenario must defeat the target")
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(AttackActionTest.TARGET_HEX) == Board.EMPTY_OCCUPANT,
			"a defeated fighter must still be removed from the board even under an unknown mode"
		)
	)
	violations.append_array(
		_expect(
			state.player("p1").score == 0,
			(
				"a defeat resolved under an unregistered mode must award 0 VP, proving the award "
				+ "is the mode's and not spec section 9's"
			)
		)
	)

	return violations


# --- Charge ----------------------------------------------------------------


## A defeating Charge credits the identical award an Attack would, because
## both route through `AttackAction._apply_hit()` -- `ChargeAction` composes
## rather than re-derives, and this is the same seam.
static func _test_charge_defeat_routes_through_the_same_seam() -> Array[String]:
	var violations: Array[String] = []
	var template := ChargeActionTest._template(4, 2, 1)
	var state := ChargeActionTest._baseline_state(template)

	var profile := ChargeActionTest._forced(ChargeActionTest._always(), ChargeActionTest._never())
	profile.defeat_award = 3

	var action := ChargeAction.new(
		ChargeActionTest.ACTOR_ID,
		ChargeActionTest.H3,
		ChargeActionTest.TARGET_ID,
		template,
		template,
		profile,
		false,
		Deathmatch.MODE_ID
	)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a defeating Charge must resolve successfully"))
	violations.append_array(
		_expect(action.attack_half().target_defeated(), "this scenario must defeat the target")
	)
	(
		violations
		. append_array(
			_expect(
				state.player("p1").score == profile.defeat_award,
				(
					"a defeating Charge under Deathmatch must credit the same award a standalone Attack "
					+ "would, routed through the same seam"
				)
			)
		)
	)

	return violations

## Tests `RoundDriver`: a whole round of spec §5.2's Combat Segment played
## through the gate, without the test hand-rolling the sequence.
##
## **The loop condition is `driver.active_player_id()`, everywhere.** No case
## in this file counts Turns to decide when the round is over, and no case
## calls `Authority.set_active_player()` -- which is the difference between
## this suite and `tests/end_segment_round_test.gd`, where the test rotates the
## active player itself because nothing else could. `MAX_TURNS` below bounds a
## runaway loop and is not a loop condition: reaching it is reported as a
## failure rather than quietly stopping at the right answer.
##
## **The round structure is the authored one.** `turns_per_player` and
## `rounds_per_match` are read off `res://resources/round/round_profile.tres`
## -- 4 and 3 -- so a full round here is eight Turns, two players alternating.
## Nothing in this file restates either number as a literal.
##
## **The End Segment is not submitted through the runner, and that is the
## point.** `driver.end_segment()` calls `EndSegment.run()` directly: it is not
## a `TurnAction`, no player submits it, and it has no requester whose
## entitlement `Authority` could answer. Every *command* in this file reaches a
## resolver through `RoundDriver`, which reaches it through `ActionRunner`.
##
## Lives under `tests/` rather than `rules/tests/`, for the reason
## `tests/power_step_gate_test.gd`'s docstring gives: it names `RoundDriver`,
## `ActionRunner` and `Authority`, which are `res://scripts/` code, and
## `rules/tests/extraction_contract_test.gd` fails the build over a `rules/`
## file that names one.
##
## `tests/round_driver_decline_test.gd` carries the `decline()` half of this
## suite, split off rather than nested here for the reason
## `rules/tests/charge_action_equivalence_test.gd` documents: `.gdlintrc`'s
## 1000-line cap is a signal to split a file, not to raise the cap. It is
## registered in `_suites` in its own right, so its name appears in the
## headless run's output.
class_name RoundDriverTest

## The authored round structure, read rather than restated.
const ROUND_PROFILE_PATH := "res://resources/round/round_profile.tres"

## The authored combat numbers the Charge and Attack cases resolve against.
const COMBAT_PROFILE_PATH := "res://resources/combat/combat_profile.tres"

## This suite's one fighter template, shared by both fighters.
const TEMPLATE_ID := "round-driver-test-fighter"

## A hexagonal board of this many rings, which is big enough for the Charge
## cases to have two distinct hexes adjacent to the target.
const BOARD_RADIUS := 3

## `f1` starts here, `f2` there, and a Charge in round 1 and again in round 2
## ends on the two hexes below -- both adjacent to `F2_HOME`, and different
## from each other, since spec §6's Charge must end somewhere it did not start.
const ORIGIN := Vector3i(0, 0, 0)
const F2_HOME := Vector3i(3, -3, 0)
const CHARGE_HEX_ROUND_1 := Vector3i(2, -2, 0)
const CHARGE_HEX_ROUND_2 := Vector3i(3, -2, -1)

## The seed the ordinary cases run on. Nothing about this value matters beyond
## its being fixed.
const SEED := 11

## The seed `GOLDEN_DIGEST` is pinned to.
const GOLDEN_SEED := 20260910

## The digest `_build_state(GOLDEN_SEED)` plus `_play_golden_round()` must
## produce.
##
## **This constant is what makes the determinism claim cross-process**, the
## same argument `rules/tests/determinism_test.gd`'s own `GOLDEN_DIGEST`
## docstring makes at length: comparing two runs inside one Godot process
## proves only that the process is self-consistent, while a digest computed by
## a previous process and re-derived by every run since -- including every CI
## run -- is a genuine assertion across processes.
##
## **What legitimately changes this value**, and the only correct response to
## each: a change to `_build_state()` or `_play_golden_round()` in this file,
## or to any resolver the golden round drives, or to `GameState.to_dict()` and
## the `to_dict()`s it nests. In every case: run the suite, take the digest
## reported in the failure message, confirm the change was intended, and
## update this constant.
##
## What is **never** the correct response: loosening the assertion, deleting
## the case, or comparing the two in-process runs and nothing else.
const GOLDEN_DIGEST := "c6889a727343b46773bc27ad0b31a2de8eb35c5afec73dd470c53f01c8ceb943"

## The order `active_player_id()` must report across a full round: two players,
## four Turns each, alternating.
const EXPECTED_ORDER: Array[String] = ["p1", "p2", "p1", "p2", "p1", "p2", "p1", "p2"]

## A bound on every Turn loop in this file, not a count of the Turns one should
## take. Reaching it is a failure: a loop is meant to stop because
## `driver.active_player_id()` came back empty.
const MAX_TURNS := 24


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_full_round_of_eight_turns_runs_through_the_driver())
	violations.append_array(_test_the_end_segment_entry_point_begins_the_next_round())
	violations.append_array(_test_the_gate_is_synced_from_the_rule_not_seeded_by_construction())
	violations.append_array(_test_a_charge_in_round_1_charges_again_in_round_2())
	violations.append_array(_test_the_played_round_pins_a_golden_digest())

	if violations.is_empty():
		return true

	printerr("\n=== Round Driver Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## This suite's one template. `move` is 2 so a Charge can cross two hexes,
## `range_hexes` 1 so the attack half reaches an adjacent target, and `health`
## 8 so the golden round's four attacks cannot defeat anybody -- an
## already-defeated target is refused, and this suite is not the place to test
## that refusal.
static func _template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = TEMPLATE_ID
	template.move = 2
	template.save = 2
	template.health = 8
	template.range_hexes = 1
	template.attack = 3
	template.damage = 1
	return template


## The template lookup `RoundDriver` is constructed over. Registered from
## `_template()` rather than from the authored roster, so this suite's fighters
## resolve to the template their payloads name.
static func _templates() -> FighterTemplates:
	var templates := FighterTemplates.new()
	templates.register(_template())
	return templates


static func _combat_profile() -> CombatProfile:
	return load(COMBAT_PROFILE_PATH)


## A hexagonal board of `BOARD_RADIUS` rings, all NORMAL.
static func _board() -> Board:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			board.add_hex(Vector3i(x, y, -x - y), Board.HexType.NORMAL)
	return board


## Two players, one fighter each, and the authored round structure. `p1` is
## active by construction -- `Authority` seeds the active player from the front
## of the turn order, and `TurnSequence` names the same player at
## `turns_taken` 0.
static func _build_state(state_seed: int) -> GameState:
	var profile: RoundProfile = load(ROUND_PROFILE_PATH)

	var state := GameState.new(_board(), DeterministicRng.new(state_seed))
	state.add_player("p1")
	state.add_player("p2")
	state.turns_per_player = profile.turns_per_player
	state.rounds_per_match = profile.rounds_per_match

	_place(state, "f1", "p1", ORIGIN)
	_place(state, "f2", "p2", F2_HOME)
	return state


static func _place(state: GameState, fighter_id: String, owner_id: String, coord: Vector3i) -> void:
	state.add_fighter(fighter_id, Fighter.new(fighter_id, _template(), owner_id, coord).to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


## The stored fighter, parsed back over this suite's one template.
static func _stored(state: GameState, fighter_id: String) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), _template())


## The other player. Two players, so this is total.
static func _opponent(player_id: String) -> String:
	return "p2" if player_id == "p1" else "p1"


## The fighter `player_id` owns in this suite's fixture.
static func _fighter_of(player_id: String) -> String:
	return "f1" if player_id == "p1" else "f2"


## True when no fighter still on the board holds any flag in
## `StatusFlags.round_level()`. A fighter the board no longer reports at its
## recorded position is spec §9's defeated, and §10 step 5 leaves its stored
## payload alone, so it is not asked.
static func _board_is_clear_of_round_flags(state: GameState) -> bool:
	for fighter_id in state.fighter_ids():
		var fighter := _stored(state, fighter_id)
		if fighter == null:
			continue
		if state.board.occupant_at(fighter.position()) != StringName(fighter_id):
			continue

		for flag in StatusFlags.round_level():
			if fighter.has_status_flag(flag):
				return false

	return true


# --- Shared Turn helpers ----------------------------------------------------


## Both Power Step passes for the Turn `active` is taking, each submitted
## through the driver as its own player: spec §5.3's Step ends on two passes in
## a row, and the driver never supplies either one on a player's behalf.
static func _play_power_step(driver: RoundDriver, active: String) -> Array[String]:
	var violations: Array[String] = []
	var opponent := _opponent(active)

	var first := driver.pass_power_step(active)
	violations.append_array(
		_expect(first.success, "the active player's pass must resolve, got %s" % first.reason)
	)

	var second := driver.pass_power_step(opponent)
	violations.append_array(
		_expect(second.success, "the opponent's pass must resolve, got %s" % second.reason)
	)

	return violations


## Every Turn the round still has, each one a Guard by the active player's own
## fighter followed by both Power Step passes. Stops when the driver reports
## nobody active.
static func _play_remaining_turns_as_guards(driver: RoundDriver) -> Array[String]:
	var violations: Array[String] = []
	var played := 0

	while not driver.active_player_id().is_empty():
		played += 1
		if played > MAX_TURNS:
			violations.append_array(
				_expect(false, "the driver never reported the round over in %d Turns" % MAX_TURNS)
			)
			return violations

		var active := driver.active_player_id()
		var guarded := driver.submit(GuardAction.new(_fighter_of(active), _template()), active)
		violations.append_array(
			_expect(guarded.success, "%s's Guard must resolve, got %s" % [active, guarded.reason])
		)
		violations.append_array(_play_power_step(driver, active))

	return violations


## The non-active player's action is refused by the gate and changes nothing.
## Run inside the round rather than after it, so the refusal being tested is a
## wrong-turn one and not a no-active-player one.
static func _expect_the_non_active_player_is_refused(
	driver: RoundDriver, state: GameState, active: String
) -> Array[String]:
	var opponent := _opponent(active)
	var before := state.digest()

	var refused := driver.submit(GuardAction.new(_fighter_of(opponent), _template()), opponent)

	var violations: Array[String] = []
	violations.append_array(
		_expect(
			not refused.success and refused.reason == Authority.REFUSED_NOT_YOUR_TURN,
			(
				"the non-active player's action must be refused REFUSED_NOT_YOUR_TURN, got %s"
				% refused.reason
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused action must leave the state identical")
	)
	return violations


# --- The full round ---------------------------------------------------------


static func _test_a_full_round_of_eight_turns_runs_through_the_driver() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(SEED)
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	var reported: Array[String] = []

	# The loop condition is the driver's own answer, and nothing else. `played`
	# bounds a runaway; it is not consulted to decide the round is over.
	var played := 0
	while not driver.active_player_id().is_empty():
		played += 1
		if played > MAX_TURNS:
			violations.append_array(
				_expect(false, "the driver never reported the round over in %d Turns" % MAX_TURNS)
			)
			return violations

		var active := driver.active_player_id()
		reported.append(active)

		violations.append_array(_expect_the_non_active_player_is_refused(driver, state, active))

		var acted := driver.submit(GuardAction.new(_fighter_of(active), _template()), active)
		violations.append_array(
			_expect(acted.success, "%s's action must resolve, got %s" % [active, acted.reason])
		)
		violations.append_array(
			_expect(
				authority.active_player_id() == active,
				(
					"the gate's active player must be the one the driver reported (%s), got %s"
					% [active, authority.active_player_id()]
				)
			)
		)

		violations.append_array(_play_power_step(driver, active))

	violations.append_array(
		_expect(
			reported == EXPECTED_ORDER,
			"the driver must report %s across the round, got %s" % [EXPECTED_ORDER, reported]
		)
	)
	violations.append_array(
		_expect(
			state.combat_segment_complete(),
			"the round's eight Turns must leave the Combat Segment complete"
		)
	)
	violations.append_array(
		_expect(
			driver.active_player_id().is_empty(),
			(
				"a complete Combat Segment must leave no active player, got %s"
				% [driver.active_player_id()]
			)
		)
	)
	violations.append_array(_expect_no_ninth_turn(driver, state))

	return violations


## A submission and a decline after the Combat Segment is over are both refused
## `REFUSED_NO_ACTIVE_PLAYER`, and neither writes a byte. This is what stops a
## stale active player on the gate from permitting a ninth Turn.
static func _expect_no_ninth_turn(driver: RoundDriver, state: GameState) -> Array[String]:
	var before := state.digest()

	var submitted := driver.submit(GuardAction.new("f1", _template()), "p1")
	var violations: Array[String] = []
	violations.append_array(
		_expect(
			not submitted.success and submitted.reason == Authority.REFUSED_NO_ACTIVE_PLAYER,
			(
				"a submission after the round must be refused REFUSED_NO_ACTIVE_PLAYER, got %s"
				% submitted.reason
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused submission must leave the state identical")
	)

	var declined := driver.decline("p1")
	violations.append_array(
		_expect(
			not declined.success and declined.reason == Authority.REFUSED_NO_ACTIVE_PLAYER,
			(
				"a decline after the round must be refused REFUSED_NO_ACTIVE_PLAYER, got %s"
				% declined.reason
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused decline must leave the state identical")
	)

	return violations


# --- The Segment boundary ---------------------------------------------------


static func _test_the_end_segment_entry_point_begins_the_next_round() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(SEED)
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	violations.append_array(_play_remaining_turns_as_guards(driver))
	violations.append_array(
		_expect(
			not _board_is_clear_of_round_flags(state),
			"the round's Guards must leave a round-level flag for the End Segment to clear"
		)
	)

	var ended := driver.end_segment()

	violations.append_array(
		_expect(ended.success, "the driver's End Segment must run, got %s" % ended.reason)
	)
	violations.append_array(
		_expect(
			state.round_number == 2 and state.turns_taken == 0,
			(
				"round 2 must begin at round_number 2 with turns_taken 0, got %d and %d"
				% [state.round_number, state.turns_taken]
			)
		)
	)
	violations.append_array(
		_expect(
			_board_is_clear_of_round_flags(state),
			"round 2 must begin with no round-level flag on any fighter on the board"
		)
	)
	violations.append_array(
		_expect(
			not state.power_step_open and state.power_step_passes().is_empty(),
			"round 2 must begin with the Power Step closed and the pass record empty"
		)
	)
	violations.append_array(
		_expect(
			driver.active_player_id() == "p1",
			"round 2's first Turn must belong to p1, got %s" % driver.active_player_id()
		)
	)
	# The gate as well as the driver: the End Segment re-syncs on its way out,
	# and the round's last Turn left p2 on the gate.
	violations.append_array(
		_expect(
			authority.active_player_id() == "p1",
			(
				"the End Segment must leave the gate on round 2's first player, got %s"
				% authority.active_player_id()
			)
		)
	)

	return violations


## A state resumed mid-round -- `turns_taken` at 1, as
## `GameState.from_dict()` would restore it -- is the case that shows the gate
## is synced from the rule rather than seeded by construction. `Authority`
## seeds its active player from the front of the turn order, so the gate says
## p1 while `TurnSequence` says p2, and only the driver's sync reconciles them.
static func _test_the_gate_is_synced_from_the_rule_not_seeded_by_construction() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(SEED)
	state.turns_taken = 1

	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	violations.append_array(
		_expect(
			driver.active_player_id() == "p2",
			"the resumed round's Turn must belong to p2, got %s" % driver.active_player_id()
		)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p1",
			"the gate must still be seeded on p1 before the driver syncs it"
		)
	)

	var acted := driver.submit(GuardAction.new("f2", _template()), "p2")

	violations.append_array(
		_expect(acted.success, "the resumed round's action must resolve, got %s" % acted.reason)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p2",
			"submitting must have synced the gate to p2, got %s" % authority.active_player_id()
		)
	)

	return violations


static func _test_a_charge_in_round_1_charges_again_in_round_2() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(SEED)
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	var charged := driver.submit(_charge(CHARGE_HEX_ROUND_1), "p1")
	violations.append_array(
		_expect(charged.success, "round 1's Charge must resolve, got %s" % charged.reason)
	)
	violations.append_array(
		_expect(
			_stored(state, "f1").has_status_flag(StatusFlags.CHARGED),
			"a resolved Charge must leave the charged flag on the actor"
		)
	)
	violations.append_array(_play_power_step(driver, "p1"))
	violations.append_array(_play_remaining_turns_as_guards(driver))

	var ended := driver.end_segment()
	violations.append_array(
		_expect(ended.success, "the driver's End Segment must run, got %s" % ended.reason)
	)
	violations.append_array(
		_expect(
			not _stored(state, "f1").has_status_flag(StatusFlags.CHARGED),
			"the End Segment must have cleared round 1's charged flag"
		)
	)

	var again := driver.submit(_charge(CHARGE_HEX_ROUND_2), "p1")

	violations.append_array(
		_expect(again.success, "round 2's Charge must resolve, got %s" % again.reason)
	)
	violations.append_array(
		_expect(
			_stored(state, "f1").position() == CHARGE_HEX_ROUND_2,
			"round 2's Charge must have relocated the actor to its destination"
		)
	)

	return violations


## `f1` charges `f2`, ending on `destination`.
static func _charge(destination: Vector3i) -> ChargeAction:
	return ChargeAction.new("f1", destination, "f2", _template(), _template(), _combat_profile())


# --- Determinism ------------------------------------------------------------


static func _test_the_played_round_pins_a_golden_digest() -> Array[String]:
	var violations: Array[String] = []

	var first_state := _build_state(GOLDEN_SEED)
	violations.append_array(_play_golden_round(first_state))
	var first := first_state.digest()

	var second_state := _build_state(GOLDEN_SEED)
	violations.append_array(_play_golden_round(second_state))
	var second := second_state.digest()

	violations.append_array(
		_expect(
			first == GOLDEN_DIGEST,
			"the golden round's digest must be the pinned constant, got %s" % first
		)
	)
	violations.append_array(
		_expect(
			first == second,
			(
				"replaying the identical sequence must produce the identical digest, got %s and %s"
				% [first, second]
			)
		)
	)

	return violations


## The recorded action sequence `GOLDEN_DIGEST` is pinned to: p1 Charges on its
## first Turn and Attacks on its other three, p2 Guards on all four of its own,
## and every Turn ends on both Power Step passes. The Charge and the Attacks
## are what put draws from `state.rng` into the round, so the digest covers the
## generator's position as well as the board.
static func _play_golden_round(state: GameState) -> Array[String]:
	var violations: Array[String] = []
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	var played := 0
	while not driver.active_player_id().is_empty():
		played += 1
		if played > MAX_TURNS:
			violations.append_array(
				_expect(false, "the golden round never ended in %d Turns" % MAX_TURNS)
			)
			return violations

		var active := driver.active_player_id()
		var action := _golden_action(active, played)
		var acted := driver.submit(action, active)
		violations.append_array(
			_expect(
				acted.success,
				"the golden round's Turn %d must resolve, got %s" % [played, acted.reason]
			)
		)
		violations.append_array(_play_power_step(driver, active))

	violations.append_array(
		_expect(played == EXPECTED_ORDER.size(), "the golden round must be eight Turns long")
	)
	return violations


## The golden round's action for the Turn `active` is taking: p2 Guards, p1
## Charges on the round's first Turn and Attacks on the rest.
static func _golden_action(active: String, turn_number: int) -> TurnAction:
	if active != "p1":
		return GuardAction.new("f2", _template())

	if turn_number == 1:
		return _charge(CHARGE_HEX_ROUND_1)

	return AttackAction.new("f1", "f2", _template(), _template(), _combat_profile())

## Tests `RoundDriver.decline()`: spec §5.3's one explicit way not to choose.
##
## The second half of `tests/round_driver_test.gd`, split into its own
## registered suite rather than nested inside it, for the reason
## `rules/tests/charge_action_equivalence_test.gd` documents: `.gdlintrc`'s
## 1000-line cap is a signal to split a file, not to raise the cap. That file
## carries the full round, the reported turn order, the gate sync, the Segment
## boundary and the golden digest; this one carries what a decline does, what
## it refuses, and what it leaves alone.
##
## **A decline is a command like any other.** The `GuardAction` that
## `DefaultActionStep` names is submitted through `ActionRunner` as the
## declining player, which is why a decline by the non-active player comes back
## `Authority.REFUSED_NOT_YOUR_TURN` and resolves nothing.
##
## **An empty Action Step is not a skipped Turn.** A player whose every fighter
## is off the board has no default to submit; the Turn still has its Power
## Step, both passes still land, and `turns_taken` still rises.
##
## **On the "held by `ChargeLockout`" half of that case.** A player with an
## on-board fighter always has an *eligible* one, so the empty Action Step is
## reachable only through spec §9's defeat, and that is what
## `_test_a_decline_with_no_eligible_fighter_writes_nothing()` builds. The
## reason is the lockout's own definition: it holds a charged fighter only
## while a friendly fighter still on the board lacks the flag, and that
## unflagged friendly is itself eligible. Lockout therefore narrows which
## fighter the default names and cannot on its own empty the set; that
## narrowing is `DefaultActionStep`'s own rule and
## `rules/tests/default_action_step_test.gd`'s to prove.
## `_test_a_decline_falls_through_to_the_first_eligible_fighter()` here covers
## the same fall-through through a decline, using defeat as the skip.
##
## Lives under `tests/` rather than `rules/tests/` for the reason its sibling's
## docstring gives: it names `res://scripts/` code.
class_name RoundDriverDeclineTest

const ROUND_PROFILE_PATH := "res://resources/round/round_profile.tres"

const TEMPLATE_ID := "round-driver-decline-test-fighter"

const BOARD_RADIUS := 3

## `p1`'s one fighter, and `p2`'s two. `p2`'s are added in this order, so
## `F2_FIRST` is the first of them in `GameState.fighter_ids()` order and the
## one an un-chosen Action Step names.
const F1_HOME := Vector3i(0, 0, 0)
const F2_FIRST_HOME := Vector3i(3, -3, 0)
const F2_SECOND_HOME := Vector3i(2, -3, 1)

const SEED := 17

## A bound on every Turn loop in this file, not a count of the Turns one should
## take. Reaching it is a failure.
const MAX_TURNS := 24

## The Turns `p2` takes in a round, as the authored profile sets it. Read back
## off the state rather than restated as a literal.
const EXPECTED_DECLINES := 4


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_round_of_declines_completes())
	violations.append_array(_test_a_decline_is_incomplete_until_both_passes())
	violations.append_array(_test_a_decline_with_no_eligible_fighter_writes_nothing())
	violations.append_array(_test_a_decline_falls_through_to_the_first_eligible_fighter())
	violations.append_array(_test_a_decline_by_the_non_active_player_is_refused())
	violations.append_array(_test_a_decline_syncs_the_gate_from_the_rule())

	if violations.is_empty():
		return true

	printerr("\n=== Round Driver Decline Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


static func _template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = TEMPLATE_ID
	template.move = 1
	template.save = 2
	template.health = 5
	return template


static func _templates() -> FighterTemplates:
	var templates := FighterTemplates.new()
	templates.register(_template())
	return templates


static func _board() -> Board:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			board.add_hex(Vector3i(x, y, -x - y), Board.HexType.NORMAL)
	return board


## Two players and three fighters, added `f1`, `f2_first`, `f2_second` -- so
## `fighter_ids()` reports them in that order and `f2_first` is what an
## un-chosen Action Step names for `p2`.
static func _build_state() -> GameState:
	var profile: RoundProfile = load(ROUND_PROFILE_PATH)

	var state := GameState.new(_board(), DeterministicRng.new(SEED))
	state.add_player("p1")
	state.add_player("p2")
	state.turns_per_player = profile.turns_per_player
	state.rounds_per_match = profile.rounds_per_match

	_place(state, "f1", "p1", F1_HOME)
	_place(state, "f2_first", "p2", F2_FIRST_HOME)
	_place(state, "f2_second", "p2", F2_SECOND_HOME)
	return state


static func _place(state: GameState, fighter_id: String, owner_id: String, coord: Vector3i) -> void:
	state.add_fighter(fighter_id, Fighter.new(fighter_id, _template(), owner_id, coord).to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


static func _stored(state: GameState, fighter_id: String) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), _template())


## Spec §9's defeat, as the board expresses it: the fighter is no longer the
## occupant of its own recorded position. The stored payload is left exactly as
## it is, which is what `EndSegment` and `DefaultActionStep` both assume.
static func _take_off_the_board(state: GameState, fighter_id: String) -> void:
	state.board.remove_occupant(_stored(state, fighter_id).position())


## Every fighter's position and damage counter, keyed by fighter id. Compared
## before and after a decline to show what it did and did not touch.
static func _snapshot(state: GameState) -> Dictionary:
	var snapshot: Dictionary = {}
	for fighter_id in state.fighter_ids():
		var fighter := _stored(state, fighter_id)
		snapshot[fighter_id] = [fighter.position(), fighter.damage_counter()]
	return snapshot


# --- Shared Turn helpers ----------------------------------------------------


static func _play_power_step(driver: RoundDriver, active: String) -> Array[String]:
	var violations: Array[String] = []
	var opponent := "p2" if active == "p1" else "p1"

	var first := driver.pass_power_step(active)
	violations.append_array(
		_expect(first.success, "the active player's pass must resolve, got %s" % first.reason)
	)

	var second := driver.pass_power_step(opponent)
	violations.append_array(
		_expect(second.success, "the opponent's pass must resolve, got %s" % second.reason)
	)

	return violations


## `p1`'s Turn: a Guard on its one fighter, then both passes.
static func _play_p1_turn(driver: RoundDriver) -> Array[String]:
	var guarded := driver.submit(GuardAction.new("f1", _template()), "p1")
	var violations: Array[String] = []
	violations.append_array(
		_expect(guarded.success, "p1's Guard must resolve, got %s" % guarded.reason)
	)
	violations.append_array(_play_power_step(driver, "p1"))
	return violations


# --- A whole round of declines ----------------------------------------------


static func _test_a_round_of_declines_completes() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	var opening := _snapshot(state)
	var declines := 0

	var played := 0
	while not driver.active_player_id().is_empty():
		played += 1
		if played > MAX_TURNS:
			violations.append_array(
				_expect(false, "the driver never reported the round over in %d Turns" % MAX_TURNS)
			)
			return violations

		var active := driver.active_player_id()
		if active == "p1":
			violations.append_array(_play_p1_turn(driver))
			continue

		declines += 1
		violations.append_array(
			_expect_the_decline_touches_only_the_default(driver, authority, state, opening)
		)
		violations.append_array(_play_power_step(driver, "p2"))

	violations.append_array(
		_expect(
			declines == EXPECTED_DECLINES,
			"p2 must have declined %d Turns, got %d" % [EXPECTED_DECLINES, declines]
		)
	)
	violations.append_array(
		_expect(
			state.combat_segment_complete(),
			"a round in which one player declines every Turn must still complete"
		)
	)

	return violations


## One declined Turn, and everything it must leave alone: the board, the
## opponent's fighter, the declining player's positions and damage counters,
## and every fighter of theirs but the first eligible one.
static func _expect_the_decline_touches_only_the_default(
	driver: RoundDriver, authority: Authority, state: GameState, opening: Dictionary
) -> Array[String]:
	var board_before := state.board.to_dict()
	var f1_before := state.fighter("f1")
	var turns_before := state.turns_taken

	var declined := driver.decline("p2")

	var violations: Array[String] = []
	violations.append_array(
		_expect(declined.success, "p2's decline must resolve, got %s" % declined.reason)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p2",
			(
				"the decline must go to the gate as the active player p2, got %s"
				% authority.active_player_id()
			)
		)
	)
	violations.append_array(
		_expect(
			_stored(state, "f2_first").has_status_flag(StatusFlags.GUARDED),
			"a declined Turn must leave the guarded flag on p2's first eligible fighter"
		)
	)
	violations.append_array(
		_expect(
			not _stored(state, "f2_second").has_status_flag(StatusFlags.GUARDED),
			"a declined Turn must not touch p2's other fighters"
		)
	)
	violations.append_array(
		_expect(state.fighter("f1") == f1_before, "a declined Turn must not touch p1's fighter")
	)
	violations.append_array(
		_expect(
			state.board.to_dict() == board_before, "a declined Turn must not write to the board"
		)
	)
	violations.append_array(
		_expect(
			_snapshot(state) == opening,
			"a declined Turn must leave every position and damage counter as it began"
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == turns_before,
			"a declined Turn must not complete until its Power Step has ended"
		)
	)

	return violations


# --- Turn completion --------------------------------------------------------


static func _test_a_decline_is_incomplete_until_both_passes() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	violations.append_array(_play_p1_turn(driver))

	var before := state.turns_taken
	var declined := driver.decline("p2")

	violations.append_array(
		_expect(declined.success, "p2's decline must resolve, got %s" % declined.reason)
	)
	violations.append_array(
		_expect(
			state.turns_taken == before,
			"a decline must not complete the Turn on its own, got %d" % state.turns_taken
		)
	)

	var first := driver.pass_power_step("p2")
	violations.append_array(_expect(first.success, "p2's pass must resolve, got %s" % first.reason))
	violations.append_array(
		_expect(
			state.turns_taken == before,
			"one pass must not complete the Turn, got %d" % state.turns_taken
		)
	)

	var second := driver.pass_power_step("p1")
	violations.append_array(
		_expect(second.success, "p1's pass must resolve, got %s" % second.reason)
	)
	violations.append_array(
		_expect(
			state.turns_taken == before + 1,
			"the second pass must complete the declined Turn, got %d" % state.turns_taken
		)
	)

	return violations


# --- An empty Action Step ---------------------------------------------------


static func _test_a_decline_with_no_eligible_fighter_writes_nothing() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	_take_off_the_board(state, "f2_first")
	_take_off_the_board(state, "f2_second")

	violations.append_array(_play_p1_turn(driver))

	var board_before := state.board.to_dict()
	var first_before := state.fighter("f2_first")
	var second_before := state.fighter("f2_second")
	var rng_before := state.rng.get_state()
	var turns_before := state.turns_taken

	var declined := driver.decline("p2")

	violations.append_array(
		_expect(
			declined.success,
			"a decline with no eligible fighter must succeed, got %s" % declined.reason
		)
	)
	violations.append_array(
		_expect(
			(
				state.fighter("f2_first") == first_before
				and state.fighter("f2_second") == second_before
			),
			"an empty Action Step must set no flag and move no counter"
		)
	)
	violations.append_array(
		_expect(
			state.board.to_dict() == board_before,
			"an empty Action Step must not write to the board"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_before,
			"an empty Action Step must draw nothing from the rng"
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == turns_before,
			"an empty Action Step must not complete the Turn on its own"
		)
	)

	violations.append_array(_play_power_step(driver, "p2"))

	violations.append_array(
		_expect(
			state.turns_taken == turns_before + 1,
			"an empty Action Step is not a skipped Turn: its two passes must still complete it"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_before,
			"completing the Turn must draw nothing from the rng"
		)
	)

	return violations


## The default names the *first eligible* fighter, not the first one: a
## defeated leader is skipped and the Guard lands on the next.
static func _test_a_decline_falls_through_to_the_first_eligible_fighter() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	_take_off_the_board(state, "f2_first")

	violations.append_array(_play_p1_turn(driver))

	var declined := driver.decline("p2")

	violations.append_array(
		_expect(declined.success, "p2's decline must resolve, got %s" % declined.reason)
	)
	violations.append_array(
		_expect(
			not _stored(state, "f2_first").has_status_flag(StatusFlags.GUARDED),
			"a defeated fighter must not take the default Action Step"
		)
	)
	violations.append_array(
		_expect(
			_stored(state, "f2_second").has_status_flag(StatusFlags.GUARDED),
			"the default must fall through to p2's first *eligible* fighter"
		)
	)

	return violations


# --- The gate ---------------------------------------------------------------


static func _test_a_decline_by_the_non_active_player_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	var before := state.digest()
	var refused := driver.decline("p2")

	violations.append_array(
		_expect(
			not refused.success and refused.reason == Authority.REFUSED_NOT_YOUR_TURN,
			(
				"a decline by the non-active player must be refused REFUSED_NOT_YOUR_TURN, got %s"
				% refused.reason
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused decline must leave the state identical")
	)

	# The same refusal on the branch that has no command to put to the gate:
	# p2 has nothing eligible, so the driver answers with the gate's own
	# constant rather than submitting anything.
	_take_off_the_board(state, "f2_first")
	_take_off_the_board(state, "f2_second")

	var empty_before := state.digest()
	var empty := driver.decline("p2")

	violations.append_array(
		_expect(
			not empty.success and empty.reason == Authority.REFUSED_NOT_YOUR_TURN,
			(
				"an empty-Action-Step decline by the non-active player must be refused too, got %s"
				% empty.reason
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == empty_before, "a refused decline must leave the state identical")
	)

	return violations


## A decline syncs the gate from the rule, exactly as a submission does. The
## state is resumed mid-round -- `turns_taken` at 1, as `GameState.from_dict()`
## would restore it -- so `Authority` is seeded on p1 while `TurnSequence` names
## p2, and only the driver's sync reconciles them. See
## `RoundDriverTest._test_the_gate_is_synced_from_the_rule_not_seeded_by_construction()`
## for the same case on the submission path.
static func _test_a_decline_syncs_the_gate_from_the_rule() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	state.turns_taken = 1

	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, _templates())

	violations.append_array(
		_expect(
			authority.active_player_id() == "p1",
			"the gate must still be seeded on p1 before the driver syncs it"
		)
	)

	var declined := driver.decline("p2")

	violations.append_array(
		_expect(
			declined.success, "the resumed round's decline must resolve, got %s" % declined.reason
		)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p2",
			"declining must have synced the gate to p2, got %s" % authority.active_player_id()
		)
	)
	violations.append_array(
		_expect(
			_stored(state, "f2_first").has_status_flag(StatusFlags.GUARDED),
			"the resumed round's decline must leave the guarded flag on p2's first fighter"
		)
	)

	return violations

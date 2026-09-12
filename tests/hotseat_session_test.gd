## Tests `HotseatSession`: which step of which Turn a match is on, who must act
## next, and where the Combat Segment ends.
##
## **Nothing in this file counts a Turn.** Every loop is driven by
## `session.phase()` and `session.player_to_act()`, which is the property the
## session exists to provide -- a view that has to keep its own Turn counter has
## been handed the rules to re-implement. `MAX_STEPS` below bounds a runaway
## loop and is not a loop condition: reaching it is reported as a failure rather
## than quietly stopping at the right answer.
##
## **No case calls `Authority.set_active_player()`.** The gate is synced from
## `TurnSequence` by `RoundDriver`, underneath the session, and a test that
## rotated the active player itself would be proving something else.
##
## **The round structure is the authored one.** `turns_per_player` and
## `rounds_per_match` are read off `res://resources/round/round_profile.tres`,
## and neither is restated as a literal anywhere in this file -- including in
## the three-round case, whose stopping condition is `Phase.MATCH_COMPLETE` and
## not a count of rounds.
##
## **The session is not a second gate, and two cases say so.** A submission by
## the non-active player comes back `Authority.REFUSED_NOT_YOUR_TURN` and a
## second consecutive pass by the same player comes back
## `PowerStepPassAction.FAILURE_ALREADY_PASSED` -- the gate's answer and the
## action's answer respectively, each reaching the caller unmodified, and each
## leaving `state.digest()` byte-identical.
##
## Lives under `tests/` rather than `rules/tests/` for the reason
## `tests/round_driver_test.gd`'s docstring gives: it names `HotseatSession`,
## `RoundDriver` and `Authority`, which are `res://scripts/` code, and
## `rules/tests/extraction_contract_test.gd` fails the build over a `rules/`
## file that names one.
class_name HotseatSessionTest

## The authored round structure, read rather than restated.
const ROUND_PROFILE_PATH := "res://resources/round/round_profile.tres"

## This suite's one fighter template, shared by every fighter.
const TEMPLATE_ID := "hotseat-session-test-fighter"

## A hexagonal board of this many rings.
const BOARD_RADIUS := 3

## `p1` owns `F1_ID` and `F3_ID`, `p2` owns `F2_ID`. The two `p1` fighters are
## what the decline case needs: `F1_ID` is added first, so it is the first of
## `p1`'s in `GameState.fighter_ids()` order and the one an un-chosen Action
## Step must name.
const F1_ID := "f1"
const F2_ID := "f2"
const F3_ID := "f3"

const F1_HOME := Vector3i(0, 0, 0)
const F2_HOME := Vector3i(3, -3, 0)
const F3_HOME := Vector3i(-2, 2, 0)

## The seed every case runs on. Nothing about this value matters beyond its
## being fixed.
const SEED := 29

## A bound on every loop in this file, not a count of the steps one should
## take. Reaching it is a failure: a loop is meant to stop because the session
## reported the phase it was waiting for.
const MAX_STEPS := 200


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_phase_tracks_the_step_the_turn_is_on())
	violations.append_array(_test_the_power_step_hands_over_to_the_opponent())
	violations.append_array(_test_a_three_round_match_plays_on_phase_alone())
	violations.append_array(_test_the_segment_boundary_begins_the_next_round())
	violations.append_array(_test_the_final_round_completes_the_match())
	violations.append_array(_test_the_session_refuses_nothing_of_its_own())
	violations.append_array(_test_a_decline_guards_the_first_eligible_fighter())

	if violations.is_empty():
		return true

	printerr("\n=== Hotseat Session Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## This suite's one template. Nothing here Attacks or Charges, so only `health`
## and `save` need to be sane; `move` and `range_hexes` are authored anyway so
## the template is a well-formed one rather than a half-filled resource.
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


## The template lookup the session's driver is constructed over. Registered
## from `_template()` rather than from the authored roster, so this suite's
## fighters resolve to the template their payloads name.
static func _templates() -> FighterTemplates:
	var templates := FighterTemplates.new()
	templates.register(_template())
	return templates


## A hexagonal board of `BOARD_RADIUS` rings, all NORMAL.
static func _board() -> Board:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			board.add_hex(Vector3i(x, y, -x - y), Board.HexType.NORMAL)
	return board


static func _profile() -> RoundProfile:
	return load(ROUND_PROFILE_PATH)


## Two players and three fighters, on the authored round structure. `p1` is
## active by construction -- `TurnSequence` names the front of the turn order
## at `turns_taken` 0.
static func _build_state() -> GameState:
	var profile := _profile()

	var state := GameState.new(_board(), DeterministicRng.new(SEED))
	state.add_player("p1")
	state.add_player("p2")
	state.turns_per_player = profile.turns_per_player
	state.rounds_per_match = profile.rounds_per_match

	_place(state, F1_ID, "p1", F1_HOME)
	_place(state, F2_ID, "p2", F2_HOME)
	_place(state, F3_ID, "p1", F3_HOME)
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


## The fighter each player Guards with in this suite's loops.
static func _fighter_of(player_id: String) -> String:
	return F1_ID if player_id == "p1" else F2_ID


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


## A session over a freshly built state, and the state and gate behind it, so a
## case can assert against all three.
static func _session() -> Array:
	var state := _build_state()
	var authority := Authority.new(state)
	return [HotseatSession.new(authority, _templates()), state, authority]


# --- Driving a round through the session ------------------------------------


## Plays the round the session is in, one reported step at a time, until the
## phase is no longer a step of a Turn -- `SEGMENT_COMPLETE` or
## `MATCH_COMPLETE`. Every decision comes from `phase()` and `player_to_act()`;
## nothing here counts a Turn or names a player itself.
static func _play_round(session: HotseatSession) -> Array[String]:
	var violations: Array[String] = []

	# Bounded so a session that never reports the round over fails instead of
	# spinning. The bound is not the stopping condition: the loop is meant to
	# return on the phase below, and exhausting it is reported as a failure.
	for _step in MAX_STEPS:
		var phase := session.phase()
		if phase != HotseatSession.Phase.ACTION_STEP and phase != HotseatSession.Phase.POWER_STEP:
			return violations

		violations.append_array(_play_step(session, phase))

	violations.append_array(
		_expect(false, "the session never reported the round over in %d steps" % MAX_STEPS)
	)
	return violations


## The one command the reported phase asks for: a Guard by the player named in
## the Action Step, that player's own Power Step pass otherwise.
static func _play_step(session: HotseatSession, phase: HotseatSession.Phase) -> Array[String]:
	var actor := session.player_to_act()
	if phase == HotseatSession.Phase.ACTION_STEP:
		var acted := session.submit(GuardAction.new(_fighter_of(actor), _template()), actor)
		return _expect(acted.success, "%s's Guard must resolve, got %s" % [actor, acted.reason])

	var passed := session.pass_power_step(actor)
	return _expect(passed.success, "%s's pass must resolve, got %s" % [actor, passed.reason])


# --- The step of the Turn ---------------------------------------------------


static func _test_phase_tracks_the_step_the_turn_is_on() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"a freshly built state must report ACTION_STEP, got %d" % session.phase()
		)
	)
	violations.append_array(
		_expect(
			session.active_player_id() == "p1" and session.player_to_act() == "p1",
			"the first Turn's Action Step must belong to p1, got %s" % session.player_to_act()
		)
	)
	var active_alone: Array[String] = ["p1"]
	violations.append_array(
		_expect(
			session.players_to_act() == active_alone,
			"an Action Step must name the active player alone, got %s" % [session.players_to_act()]
		)
	)

	var acted := session.submit(GuardAction.new(F1_ID, _template()), "p1")
	violations.append_array(
		_expect(acted.success, "the Action Step's Guard must resolve, got %s" % acted.reason)
	)
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"a resolved core action must open the Power Step, got phase %d" % session.phase()
		)
	)

	violations.append_array(_pass_both(session, "p1"))

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"both passes must return the match to an Action Step, got phase %d" % session.phase()
		)
	)
	violations.append_array(
		_expect(
			session.active_player_id() == "p2",
			(
				"the completed Turn must have advanced the active player to p2, got %s"
				% session.active_player_id()
			)
		)
	)

	return violations


## Both Power Step passes for the Turn `active` is taking, each submitted
## through the session as its own player: the session never supplies either one
## on a player's behalf.
static func _pass_both(session: HotseatSession, active: String) -> Array[String]:
	var violations: Array[String] = []

	var first := session.pass_power_step(active)
	violations.append_array(
		_expect(first.success, "the active player's pass must resolve, got %s" % first.reason)
	)

	var second := session.pass_power_step(_opponent(active))
	violations.append_array(
		_expect(second.success, "the opponent's pass must resolve, got %s" % second.reason)
	)

	return violations


static func _test_the_power_step_hands_over_to_the_opponent() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]

	var acted := session.submit(GuardAction.new(F1_ID, _template()), "p1")
	violations.append_array(
		_expect(acted.success, "the Action Step's Guard must resolve, got %s" % acted.reason)
	)

	violations.append_array(
		_expect(
			session.player_to_act() == "p1",
			"an open Power Step must name the active player first, got %s" % session.player_to_act()
		)
	)
	var both_players: Array[String] = ["p1", "p2"]
	violations.append_array(
		_expect(
			session.players_to_act() == both_players,
			(
				"an unpassed Power Step must name both players, active first, got %s"
				% [session.players_to_act()]
			)
		)
	)

	var passed := session.pass_power_step("p1")
	violations.append_array(
		_expect(passed.success, "the active player's pass must resolve, got %s" % passed.reason)
	)

	violations.append_array(
		_expect(
			session.player_to_act() == "p2",
			"after the active player's pass the opponent must act, got %s" % session.player_to_act()
		)
	)
	var opponent_alone: Array[String] = ["p2"]
	violations.append_array(
		_expect(
			session.players_to_act() == opponent_alone,
			(
				"the player who just passed must not be named again, got %s"
				% [session.players_to_act()]
			)
		)
	)

	return violations


# --- A whole match ----------------------------------------------------------


## The acceptance case: three rounds end to end, driven by nothing but the two
## questions a view asks. The stopping condition is `MATCH_COMPLETE`; the round
## structure is asserted afterwards, from the authored profile, rather than
## counted on the way through.
static func _test_a_three_round_match_plays_on_phase_alone() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]

	var steps := 0
	while session.phase() != HotseatSession.Phase.MATCH_COMPLETE:
		steps += 1
		if steps > MAX_STEPS:
			violations.append_array(
				_expect(false, "the session never reported MATCH_COMPLETE in %d steps" % MAX_STEPS)
			)
			return violations

		var phase := session.phase()
		if phase == HotseatSession.Phase.SEGMENT_COMPLETE:
			var advanced := session.advance_segment()
			violations.append_array(
				_expect(advanced.success, "the Segment must advance, got %s" % advanced.reason)
			)
			continue

		violations.append_array(_play_step(session, phase))

	var profile := _profile()
	violations.append_array(
		_expect(
			state.round_number == profile.rounds_per_match,
			(
				"the match must end on the authored final round (%d), got %d"
				% [profile.rounds_per_match, state.round_number]
			)
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == profile.turns_per_player * state.turn_order().size(),
			(
				"the final round must have taken every Turn it has (%d), got %d"
				% [profile.turns_per_player * state.turn_order().size(), state.turns_taken]
			)
		)
	)
	violations.append_array(
		_expect(
			session.players_to_act().is_empty() and session.player_to_act().is_empty(),
			"a complete match must name nobody to act, got %s" % [session.players_to_act()]
		)
	)

	return violations


# --- The Segment boundary ---------------------------------------------------


static func _test_the_segment_boundary_begins_the_next_round() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]
	var authority: Authority = parts[2]

	violations.append_array(_play_round(session))

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.SEGMENT_COMPLETE,
			(
				"a non-final round's played-out Segment must report SEGMENT_COMPLETE, got phase %d"
				% session.phase()
			)
		)
	)
	violations.append_array(
		_expect(
			session.players_to_act().is_empty() and session.player_to_act().is_empty(),
			"a complete Segment must name nobody to act, got %s" % [session.players_to_act()]
		)
	)
	violations.append_array(
		_expect(
			not _board_is_clear_of_round_flags(state),
			"the round's Guards must leave a round-level flag for the End Segment to clear"
		)
	)

	var round_before := state.round_number
	var advanced := session.advance_segment()

	violations.append_array(
		_expect(advanced.success, "the Segment boundary must advance, got %s" % advanced.reason)
	)
	violations.append_array(
		_expect(
			state.round_number == round_before + 1 and state.turns_taken == 0,
			(
				"the next round must begin one round higher with turns_taken 0, got %d and %d"
				% [state.round_number, state.turns_taken]
			)
		)
	)
	violations.append_array(
		_expect(
			_board_is_clear_of_round_flags(state),
			"the next round must begin with no round-level flag on any fighter on the board"
		)
	)
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"the next round must begin on an Action Step, got phase %d" % session.phase()
		)
	)
	violations.append_array(
		_expect(
			session.player_to_act() == state.turn_order()[0],
			(
				"the next round's first Turn must belong to the front of the turn order, got %s"
				% session.player_to_act()
			)
		)
	)
	# The gate as well as the session: `RoundDriver.end_segment()` re-syncs on
	# its way out, and the round's last Turn left the other player on the gate.
	violations.append_array(
		_expect(
			authority.active_player_id() == state.turn_order()[0],
			(
				"the Segment boundary must leave the gate on the next round's first player, got %s"
				% authority.active_player_id()
			)
		)
	)

	return violations


static func _test_the_final_round_completes_the_match() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]

	var rounds := 0
	while session.phase() == HotseatSession.Phase.SEGMENT_COMPLETE or rounds == 0:
		rounds += 1
		if rounds > MAX_STEPS:
			violations.append_array(
				_expect(false, "the match never reached its final round in %d rounds" % MAX_STEPS)
			)
			return violations

		if session.phase() == HotseatSession.Phase.SEGMENT_COMPLETE:
			var advanced := session.advance_segment()
			violations.append_array(
				_expect(advanced.success, "the Segment must advance, got %s" % advanced.reason)
			)

		violations.append_array(_play_round(session))

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.MATCH_COMPLETE,
			(
				"the final round's complete Segment must report MATCH_COMPLETE, got phase %d"
				% session.phase()
			)
		)
	)
	violations.append_array(
		_expect(
			state.is_final_round(),
			(
				"the match must have reached the authored final round, got round %d"
				% state.round_number
			)
		)
	)
	violations.append_array(
		_expect(
			session.players_to_act().is_empty() and session.player_to_act().is_empty(),
			"a complete match must name nobody to act, got %s" % [session.players_to_act()]
		)
	)

	var before := state.digest()
	var refused := session.advance_segment()

	violations.append_array(
		_expect(
			not refused.success and refused.reason == EndSegment.FAILURE_FINAL_ROUND,
			"advancing past the final round must fail FAILURE_FINAL_ROUND, got %s" % refused.reason
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused Segment must leave the state identical")
	)

	return violations


# --- The session is not a second gate ---------------------------------------


static func _test_the_session_refuses_nothing_of_its_own() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]

	var before_submission := state.digest()
	var refused := session.submit(GuardAction.new(F2_ID, _template()), "p2")

	violations.append_array(
		_expect(
			not refused.success and refused.reason == Authority.REFUSED_NOT_YOUR_TURN,
			(
				"the non-active player's action must come back REFUSED_NOT_YOUR_TURN, got %s"
				% refused.reason
			)
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before_submission,
			"a refused submission must leave the state identical"
		)
	)

	var acted := session.submit(GuardAction.new(F1_ID, _template()), "p1")
	violations.append_array(
		_expect(acted.success, "the Action Step's Guard must resolve, got %s" % acted.reason)
	)
	var first := session.pass_power_step("p1")
	violations.append_array(
		_expect(first.success, "the active player's pass must resolve, got %s" % first.reason)
	)

	var before_second_pass := state.digest()
	var again := session.pass_power_step("p1")

	violations.append_array(
		_expect(
			not again.success and again.reason == PowerStepPassAction.FAILURE_ALREADY_PASSED,
			"a second consecutive pass must come back FAILURE_ALREADY_PASSED, got %s" % again.reason
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before_second_pass, "a failed pass must leave the state identical"
		)
	)
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"a failed pass must leave the Power Step open, got phase %d" % session.phase()
		)
	)

	return violations


# --- Declining the Action Step ----------------------------------------------


static func _test_a_decline_guards_the_first_eligible_fighter() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]

	var declined := session.decline("p1")

	violations.append_array(
		_expect(declined.success, "p1's decline must resolve, got %s" % declined.reason)
	)
	violations.append_array(
		_expect(
			_stored(state, F1_ID).has_status_flag(StatusFlags.GUARDED),
			"the decline must Guard p1's first fighter in fighter_ids() order"
		)
	)
	violations.append_array(
		_expect(
			not _stored(state, F3_ID).has_status_flag(StatusFlags.GUARDED),
			"the decline must Guard one fighter, not every fighter p1 owns"
		)
	)

	# The declined Turn is a Turn like any other: its Power Step opened, and
	# only its two passes complete it.
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"a decline must open the Power Step, got phase %d" % session.phase()
		)
	)
	violations.append_array(
		_expect(state.turns_taken == 0, "a decline must not complete the Turn on its own")
	)

	var first := session.pass_power_step("p1")
	violations.append_array(
		_expect(first.success, "the declining player's pass must resolve, got %s" % first.reason)
	)
	violations.append_array(
		_expect(
			state.turns_taken == 0 and session.phase() == HotseatSession.Phase.POWER_STEP,
			"one pass must not complete the declined Turn"
		)
	)

	var second := session.pass_power_step("p2")
	violations.append_array(
		_expect(second.success, "the opponent's pass must resolve, got %s" % second.reason)
	)
	violations.append_array(
		_expect(
			state.turns_taken == 1 and session.phase() == HotseatSession.Phase.ACTION_STEP,
			(
				"the declined Turn must complete on its second pass, got %d and phase %d"
				% [state.turns_taken, session.phase()]
			)
		)
	)
	violations.append_array(
		_expect(
			session.player_to_act() == "p2",
			"the next Turn must belong to p2, got %s" % session.player_to_act()
		)
	)

	return violations

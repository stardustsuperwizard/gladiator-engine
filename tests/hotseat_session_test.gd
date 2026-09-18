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
## **The round's length is derived and the match's is authored.** Spec §5.2 as
## revised 2026-09-17 gives a player a Turn per unactivated champion on the
## board, so this fixture -- two champions for `p1`, one for `p2` -- is a
## three-Turn round, and no case restates that as a literal: the three-round
## case stops on `Phase.MATCH_COMPLETE` and reads the Turn count back off the
## fixture. `rounds_per_match` is read off
## `res://resources/round/round_profile.tres`; `turns_per_player` is seeded
## onto the state beside it and read by nothing.
##
## **Every Turn names its own champion.** `_unacted_champion_of()` picks the
## first of the acting player's champions that is still on the board and has
## not spent its activation -- the question `DefaultActionStep` asks -- because
## a second action by a champion that already acted is what
## `FAILURE_ALREADY_ACTIVATED` now refuses.
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

## Where the elimination case re-homes `F2_ID`: a free neighbour of `F1_HOME`,
## so `F1_ID` is in range of p2's only fighter without anybody having to Move.
const F2_ADJACENT := Vector3i(1, -1, 0)

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
	violations.append_array(_test_a_mid_round_elimination_completes_the_match())
	violations.append_array(_test_the_outcome_reports_the_live_state())
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


## This suite's one template, and every stat on it is now load-bearing for at
## least one case. Most cases only Guard, and need `health` and `save`; the
## elimination case resolves a real `AttackAction` through the session, which
## reads `range_hexes` to reach an adjacent target, `attack` for the size of the
## dice pool and `damage` for what a Hit takes off -- with `health` deciding how
## much damage `_elimination_session()` has to apply to leave its fighter one
## point from defeat. Only `move` is authored purely so the template is a
## well-formed one rather than a half-filled resource.
##
## The targets the Attack rolls against come from `_forced_hit_profile()` and
## not from here, which is why `attack` and `save` set the pool's size rather
## than its outcome.
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


## The champion `player_id` Guards with next in this suite's loops: the first
## they own, in `state.fighter_ids()` order, still on the board and with spec
## §5.2's activation unspent. `""` when they have none left, which is also when
## the session stops naming them.
static func _unacted_champion_of(state: GameState, player_id: String) -> String:
	for fighter_id in state.fighter_ids():
		var fighter := _stored(state, fighter_id)
		if fighter == null:
			continue
		if fighter.owner_id() != player_id:
			continue
		if state.board.occupant_at(fighter.position()) != StringName(fighter_id):
			continue
		if Activation.has_activated(state, fighter_id):
			continue

		return fighter_id

	return ""


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


## A combat profile whose outcome is dictated by the die rather than by the
## seed: every attack die counts (`attack_target` 1) and no save die does
## (`save_target` 7), with the clamp widened so neither can be pulled back into
## the rollable range and every modifier left at zero so no adjacency can move
## them. The elimination case below is an assertion about what the session
## reports, not about a roll, and this is what keeps it one.
static func _forced_hit_profile() -> CombatProfile:
	var profile := CombatProfile.new()
	profile.profile_id = "hotseat-session-test-forced"
	profile.die_sides = 6
	profile.attack_target = 1
	profile.save_target = 7
	profile.min_target = 1
	profile.max_target = 7
	return profile


## A session over a freshly built state, and the state and gate behind it, so a
## case can assert against all three.
static func _session() -> Array:
	var state := _build_state()
	var profile := _profile()
	var authority := Authority.new(state)
	return [HotseatSession.new(authority, profile, _templates()), state, authority]


## The same three, over a state one resolved Attack away from eliminating p2:
## p2's only fighter is re-homed next to p1's and damaged to one point short of
## defeat, so a single Hit takes it off the board.
##
## Built by rewriting the fighter rather than by adding a parameter to `_place()`
## that only this case would ever pass, and committed through
## `GameState.update_fighter()` -- the same seam every other case uses.
static func _elimination_session() -> Array:
	var state := _build_state()
	var template := _template()

	state.board.remove_occupant(F2_HOME)
	var doomed := Fighter.new(F2_ID, template, "p2", F2_ADJACENT)
	doomed.apply_damage(template.health - 1)
	state.update_fighter(F2_ID, doomed.to_dict())
	state.board.place_occupant(F2_ADJACENT, StringName(F2_ID))

	var authority := Authority.new(state)
	return [HotseatSession.new(authority, _profile(), _templates()), state, authority]


# --- Driving a round through the session ------------------------------------


## Plays the round the session is in, one reported step at a time, until the
## phase is no longer a step of a Turn -- `SEGMENT_COMPLETE` or
## `MATCH_COMPLETE`. Every decision comes from `phase()` and `player_to_act()`;
## nothing here counts a Turn or names a player itself.
static func _play_round(session: HotseatSession, state: GameState) -> Array[String]:
	var violations: Array[String] = []

	# Bounded so a session that never reports the round over fails instead of
	# spinning. The bound is not the stopping condition: the loop is meant to
	# return on the phase below, and exhausting it is reported as a failure.
	for _step in MAX_STEPS:
		var phase := session.phase()
		if phase != HotseatSession.Phase.ACTION_STEP and phase != HotseatSession.Phase.POWER_STEP:
			return violations

		violations.append_array(_play_step(session, state, phase))

	violations.append_array(
		_expect(false, "the session never reported the round over in %d steps" % MAX_STEPS)
	)
	return violations


## The one command the reported phase asks for: a Guard by the player named in
## the Action Step, that player's own Power Step pass otherwise.
static func _play_step(
	session: HotseatSession, state: GameState, phase: HotseatSession.Phase
) -> Array[String]:
	var actor := session.player_to_act()
	if phase == HotseatSession.Phase.ACTION_STEP:
		var champion := _unacted_champion_of(state, actor)
		var acted := session.submit(GuardAction.new(champion, _template()), actor)
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
## structure is asserted afterwards, from the fixture and the authored profile,
## rather than counted on the way through.
##
## **The final round stops one completed Turn short, on purpose.** §11.1's
## round limit is reached the moment the last champion on the board spends its
## activation, which happens inside that Turn's Action Step -- so `phase()`,
## which asks §11.3 first and by design, reports `MATCH_COMPLETE` before that
## Turn's Power Step can end. `turns_taken` rises only when a Power Step ends,
## so it stops at one less than the round's Turns. That is the same shape as
## the elimination this class already reports mid-round; see
## `HotseatSession.active_player_id()`'s own docstring.
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

		violations.append_array(_play_step(session, state, phase))

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
	(
		violations
		. append_array(
			_expect(
				state.turns_taken == state.fighter_ids().size() - 1,
				(
					"the final round must have completed every Turn but the one §11.3 ended (%d), got %d"
					% [state.fighter_ids().size() - 1, state.turns_taken]
				)
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

	violations.append_array(_play_round(session, state))

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

		violations.append_array(_play_round(session, state))

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
	var before_round := state.round_number
	var before_turns := state.turns_taken
	var advanced := session.advance_segment()

	violations.append_array(
		_expect(
			advanced.success,
			(
				"the final round's Segment must run the match-end form and succeed, got %s"
				% advanced.reason
			)
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before,
			"the match-end form must leave the state digest identical (no mutations)"
		)
	)
	violations.append_array(
		_expect(
			state.round_number == before_round, "the match-end form must not advance round_number"
		)
	)
	violations.append_array(
		_expect(state.turns_taken == before_turns, "the match-end form must not reset turns_taken")
	)

	return violations


## §11.3's elimination ends the match **inside a Turn**. The moment p1's Attack
## takes p2's last fighter off the board the session reports `MATCH_COMPLETE`,
## names nobody to act and hands back an ended outcome -- with no further Turn
## taken and no End Segment having run.
##
## The Attack is submitted through the session like any other command, so what
## ends the match is a resolved action and not a board edit this case made.
static func _test_a_mid_round_elimination_completes_the_match() -> Array[String]:
	var violations: Array[String] = []
	var parts := _elimination_session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"the case must begin mid-round on an Action Step, got phase %d" % session.phase()
		)
	)
	violations.append_array(
		_expect(
			not session.outcome().over,
			"the outcome must be unended while both sides still hold a fighter"
		)
	)

	var round_before := state.round_number
	var turns_before := state.turns_taken
	var killed := session.submit(
		AttackAction.new(F1_ID, F2_ID, _template(), _template(), _forced_hit_profile()), "p1"
	)

	violations.append_array(
		_expect(killed.success, "p1's Attack must resolve, got %s" % killed.reason)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(F2_ADJACENT) == Board.EMPTY_OCCUPANT,
			"the Attack must have taken p2's last fighter off the board"
		)
	)
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.MATCH_COMPLETE,
			(
				"an elimination must report MATCH_COMPLETE inside the Turn, got phase %d"
				% session.phase()
			)
		)
	)
	violations.append_array(
		_expect(
			session.players_to_act().is_empty() and session.player_to_act().is_empty(),
			"a match ended mid-round must name nobody to act, got %s" % [session.players_to_act()]
		)
	)
	violations.append_array(
		_expect(
			session.active_player_id().is_empty(),
			(
				"a match ended mid-round must name no active player, got %s"
				% session.active_player_id()
			)
		)
	)
	violations.append_array(
		_expect(
			state.round_number == round_before and state.turns_taken == turns_before,
			(
				"no End Segment and no further Turn may have run, got round %d and %d Turns"
				% [state.round_number, state.turns_taken]
			)
		)
	)

	var outcome := session.outcome()
	violations.append_array(
		_expect(
			outcome.over and outcome.ended_by == MatchOutcome.ENDING_ELIMINATION,
			"the outcome must report the match ended by elimination, got %s" % outcome.ended_by
		)
	)
	violations.append_array(
		_expect(
			outcome.winner_id == "p1",
			"the surviving side must be the winner, got %s" % outcome.winner_id
		)
	)

	return violations


## `outcome()` is a read of the live state and nothing else: unended while the
## match is in play, and the ended `MatchOutcome` once §11.3's condition holds.
##
## Nothing here counts a round. The loop stops on `MATCH_COMPLETE`, which is the
## phase the session derives from the same question `outcome()` answers.
static func _test_the_outcome_reports_the_live_state() -> Array[String]:
	var violations: Array[String] = []
	var parts := _session()
	var session: HotseatSession = parts[0]
	var state: GameState = parts[1]

	var in_play := session.outcome()
	violations.append_array(
		_expect(not in_play.over, "a match still in play must report an unended outcome")
	)
	violations.append_array(
		_expect(
			in_play.ended_by == &"" and in_play.winner_id.is_empty(),
			"an unended outcome must name no ending and no winner, got %s" % in_play.ended_by
		)
	)
	violations.append_array(
		_expect(
			in_play.deciding_rule == &"",
			"an unended outcome must name no deciding rule, got %s" % in_play.deciding_rule
		)
	)

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

		violations.append_array(_play_step(session, state, phase))

	var ended := session.outcome()
	violations.append_array(
		_expect(
			ended.over and ended.ended_by == MatchOutcome.ENDING_ROUND_LIMIT,
			"a match played to its round limit must report that ending, got %s" % ended.ended_by
		)
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

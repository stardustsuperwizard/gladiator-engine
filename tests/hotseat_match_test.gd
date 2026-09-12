## Tests `HotseatMatch`: the hotseat match scene, driven the way two people at
## one screen drive it.
##
## Every case instantiates `res://scenes/main.tscn` itself, adds it to the
## running `SceneTree` -- under the bootstrap autoload rather than directly
## under `root`, for the reason `_host()` sets out -- so `_ready()` builds the
## match, drives the scene's public intent methods, and frees the node before
## returning. Nothing here reaches inside the scene to submit:
## `select_fighter()`, `choose_action()`, `select_hex()`, `decline_turn()`,
## `pass_power_step()` and `advance_segment()` are the whole surface, and they
## are the same six things the buttons and `BoardView.hex_selected` are
## connected to.
##
## **Nothing in this file counts a Turn.** Every loop is driven by
## `HotseatMatch.session()`'s own `phase()`, the same discipline
## `tests/hotseat_session_test.gd` states for itself -- a view that needs its
## own Turn counter has been handed the rules to re-implement, and so has a
## suite that needs one to drive it. `MAX_STEPS` bounds a runaway loop and is
## never a loop's stopping condition: reaching it is reported as a failure.
##
## **The assertions are the session's answers, not the scene's labels** --
## except where the label is the thing under test. `phase()`,
## `active_player_id()` and `player_to_act()` come off `HotseatSession`, and
## the HUD is checked only against those.
##
## **The round structure is the authored one.** `MatchSetup` builds the state
## from `res://resources/round/round_profile.tres`, and no case here restates a
## round count or a Turn count -- the three-round case stops on
## `Phase.MATCH_COMPLETE`.
##
## Lives under `tests/` rather than `rules/tests/` for the reason
## `tests/hotseat_session_test.gd`'s docstring gives: it names `HotseatMatch`,
## `HotseatSession`, `MatchSetup` and `Authority`, which are `res://scripts/`
## code, and `rules/tests/extraction_contract_test.gd` fails the build over a
## `rules/` file that names one.
class_name HotseatMatchTest

## The scene under test, which is also the project's main scene.
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

## A bound on every loop in this file, not a count of the steps one should
## take. Reaching it is a failure.
const MAX_STEPS := 400


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_boots_showing_round_phase_and_player())
	violations.append_array(_test_a_turn_plays_through_the_intent_methods())
	violations.append_array(_test_decline_needs_no_fighter_selected())
	violations.append_array(_test_a_tap_selects_a_fighter_then_moves_it())
	violations.append_array(_test_attack_and_charge_submit_from_the_hud())
	violations.append_array(_test_a_refusal_is_logged_verbatim_and_recoverable())
	violations.append_array(_test_the_segment_boundary_is_offered_not_taken())
	violations.append_array(_test_the_final_round_stops_offering_commands())

	if violations.is_empty():
		return true

	printerr("\n=== Hotseat Match Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## The node this suite's scene instances are parented to: the bootstrap
## autoload that is running the suites, itself a child of
## `(Engine.get_main_loop() as SceneTree).root`.
##
## Not `root` itself, and not by preference. Every suite here runs inside
## `TestBootstrap._ready()`, and that `_ready()` is reached from the engine's
## own walk over `root`'s children -- which leaves `root` blocked for the whole
## of it, so a `root.add_child()` from in here fails outright with "Parent node
## is busy setting up children, `add_child()` failed" and the scene never
## enters the tree at all. Measured on 4.7.1-stable, not assumed: `root`
## already holds both `TestBootstrap` and the booted `Main` by the time a suite
## runs, and every `add_child()` on it from this file failed.
##
## The autoload node is not blocked -- `Node::_propagate_ready()` clears that
## flag on a node before notifying it -- and it gives an added scene exactly
## what `root` would: a live `SceneTree`, `_ready()` fired on entry,
## `is_inside_tree()` true and `get_tree()` answering. The scene under test
## boots identically either way; only its path differs.
static func _host() -> Node:
	return TestBootstrap


## An instance of the main scene, in the tree and therefore already through
## `_ready()`. Every case that calls this must end in `_close_match()`.
static func _open_match() -> HotseatMatch:
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	var scene := packed.instantiate() as HotseatMatch
	_host().add_child(scene)
	return scene


## Takes the scene back out of the tree and frees it immediately. `free()`
## rather than `queue_free()`: a suite runs inside one frame, and a queued
## deletion would still be pending when the run finishes.
static func _close_match(scene: HotseatMatch) -> void:
	_host().remove_child(scene)
	scene.free()


## The text of the HUD `Label` named `label_name`. Searched by name rather than
## by path so a change to the sidebar's arrangement does not silently pass.
static func _label_text(scene: HotseatMatch, label_name: String) -> String:
	var label := scene.find_child(label_name, true, false) as Label
	return "" if label == null else label.text


static func _button(scene: HotseatMatch, button_name: String) -> Button:
	return scene.find_child(button_name, true, false) as Button


## The affordances the scene itself asks for, built over the same authored
## templates and combat numbers, so a case can name a legal destination without
## restating a fighter's Move stat.
static func _options() -> ActionOptions:
	return ActionOptions.new(MatchSetup.templates(), MatchSetup.combat_profile())


# --- Cases ------------------------------------------------------------------


## The scene boots with a match already built, and the HUD says which round it
## is, which Step the Turn is on, and who must act.
static func _test_boots_showing_round_phase_and_player() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var session := scene.session()

	violations.append_array(_expect(session != null, "boot: the scene built no session"))
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"boot: the opening phase is not the Action Step"
		)
	)
	violations.append_array(
		_expect(
			session.active_player_id() == MatchSetup.PLAYER_ONE,
			"boot: the front of the turn order is not active"
		)
	)
	violations.append_array(_expect(scene.state().round_number == 1, "boot: not on round 1"))
	violations.append_array(_expect(scene.log_lines().is_empty(), "boot: the log is not empty"))

	violations.append_array(
		_expect(
			str(scene.state().round_number) in _label_text(scene, "RoundLabel"),
			"boot: the HUD does not show the round number"
		)
	)
	violations.append_array(
		_expect(
			(
				str(HotseatMatch.PHASE_LABELS[HotseatSession.Phase.ACTION_STEP])
				in _label_text(scene, "PhaseLabel")
			),
			"boot: the HUD does not show the phase"
		)
	)
	violations.append_array(
		_expect(
			session.player_to_act() in _label_text(scene, "PlayerLabel"),
			"boot: the HUD does not name the player who must act"
		)
	)

	_close_match(scene)
	return violations


## One complete Turn through the intent methods: a chosen action, then both
## Power Step passes, with the phase and the active player moving as the
## session reports them and every result reaching the log.
static func _test_a_turn_plays_through_the_intent_methods() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var session := scene.session()
	var first_player := session.active_player_id()

	scene.select_fighter(MatchSetup.P1_WARRIOR_ID)
	scene.choose_action(HotseatMatch.ACTION_GUARD)

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"turn: a resolved Action Step did not open the Power Step"
		)
	)
	violations.append_array(
		_expect(scene.log_lines().size() == 1, "turn: the Guard was not logged")
	)
	violations.append_array(
		_expect(scene.log_lines()[0].ends_with("ok"), "turn: the Guard was not logged as a success")
	)
	violations.append_array(
		_expect(
			session.player_to_act() == first_player,
			"turn: the active player is not the first to pass"
		)
	)

	var first_pass := scene.pass_power_step()
	violations.append_array(_expect(first_pass.success, "turn: the first pass was not accepted"))
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"turn: one pass ended the Power Step"
		)
	)

	var second_player := session.player_to_act()
	violations.append_array(
		_expect(
			second_player != first_player and not second_player.is_empty(),
			"turn: the Power Step did not hand over to the opponent"
		)
	)
	violations.append_array(
		_expect(
			second_player in _button(scene, "PassButton").text,
			"turn: the Pass button does not name the player whose pass it is"
		)
	)
	violations.append_array(
		_expect(
			_button(scene, "PassButton").visible, "turn: the Pass button is hidden mid Power Step"
		)
	)

	var second_pass := scene.pass_power_step()
	violations.append_array(_expect(second_pass.success, "turn: the second pass was not accepted"))
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"turn: two passes did not complete the Turn"
		)
	)
	violations.append_array(
		_expect(
			session.active_player_id() == second_player,
			"turn: the next Turn does not belong to the opponent"
		)
	)
	violations.append_array(
		_expect(scene.log_lines().size() == 3, "turn: the log did not record all three results")
	)

	_close_match(scene)
	return violations


## Spec §5.3's Decline is reachable with nothing selected, and comes to what
## `HotseatSession.decline()` comes to.
static func _test_decline_needs_no_fighter_selected() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var session := scene.session()

	violations.append_array(
		_expect(
			not _button(scene, "DeclineButton").disabled,
			"decline: the button is disabled on an open Action Step"
		)
	)

	var result := scene.decline_turn()

	violations.append_array(_expect(result.success, "decline: declining was not accepted"))
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"decline: the declined Turn did not reach its Power Step"
		)
	)
	violations.append_array(
		_expect(scene.log_lines().size() == 1, "decline: the decline was not logged")
	)

	_close_match(scene)
	return violations


## A tap with nothing pending selects the fighter standing there and returns
## `null`; a tap after the Move button submits the Move and hands back its
## result.
static func _test_a_tap_selects_a_fighter_then_moves_it() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()

	var selection := scene.select_hex(MatchSetup.P1_WARRIOR_START)
	violations.append_array(
		_expect(selection == null, "move: selecting a fighter returned a result")
	)
	violations.append_array(
		_expect(
			MatchSetup.P1_WARRIOR_ID in _label_text(scene, "SelectionLabel"),
			"move: the HUD does not show the selected fighter"
		)
	)

	scene.choose_action(HotseatMatch.ACTION_MOVE)

	var destinations := _options().move_destinations(scene.state(), MatchSetup.P1_WARRIOR_ID)
	if destinations.is_empty():
		violations.append("move: the opening position offers the warrior no destination")
		_close_match(scene)
		return violations

	var destination: Vector3i = destinations[0]
	var result := scene.select_hex(destination)

	violations.append_array(_expect(result != null, "move: the tap submitted nothing"))
	if result != null:
		violations.append_array(_expect(result.success, "move: the Move was not accepted"))
	violations.append_array(
		_expect(
			scene.state().board.occupant_at(destination) == StringName(MatchSetup.P1_WARRIOR_ID),
			"move: the board does not show the fighter at its destination"
		)
	)
	violations.append_array(
		_expect(
			scene.session().phase() == HotseatSession.Phase.POWER_STEP,
			"move: a resolved Move did not open the Power Step"
		)
	)

	_close_match(scene)
	return violations


## Attack submits on the tap that names its target, and Charge takes its two
## taps -- target, then destination -- before it submits anything.
##
## Both commands are doomed from the opening position, which is the point: the
## scene submits the tap it was given rather than pre-filtering one that the
## rules will refuse, and the action's own failure reaches the log verbatim.
static func _test_attack_and_charge_submit_from_the_hud() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var before := scene.state().digest()

	scene.select_fighter(MatchSetup.P1_ARCHER_ID)
	scene.choose_action(HotseatMatch.ACTION_ATTACK)
	var attack := scene.select_hex(MatchSetup.P2_ARCHER_START)

	violations.append_array(_expect(attack != null, "attack: the tap submitted nothing"))
	if attack != null:
		violations.append_array(
			_expect(
				attack.reason == AttackAction.FAILURE_TARGET_OUT_OF_RANGE,
				"attack: an out-of-range Attack did not come back out of range"
			)
		)
	violations.append_array(
		_expect(
			scene.log_lines()[0].ends_with(String(AttackAction.FAILURE_TARGET_OUT_OF_RANGE)),
			"attack: the log does not carry the failure reason verbatim"
		)
	)
	violations.append_array(
		_expect(scene.state().digest() == before, "attack: a failed Attack changed the state")
	)

	scene.select_fighter(MatchSetup.P1_WARRIOR_ID)
	scene.choose_action(HotseatMatch.ACTION_CHARGE)
	var naming_target := scene.select_hex(MatchSetup.P2_WARRIOR_START)

	violations.append_array(
		_expect(naming_target == null, "charge: naming the target submitted a command")
	)
	violations.append_array(
		_expect(
			MatchSetup.P2_WARRIOR_ID in _label_text(scene, "SelectionLabel"),
			"charge: the HUD does not show the named target"
		)
	)
	violations.append_array(
		_expect(scene.log_lines().size() == 1, "charge: naming the target wrote to the log")
	)

	var charge := scene.select_hex(MatchSetup.P2_ARCHER_START)

	violations.append_array(_expect(charge != null, "charge: the second tap submitted nothing"))
	violations.append_array(
		_expect(scene.log_lines().size() == 2, "charge: the Charge was not logged")
	)
	if charge != null and not charge.success:
		violations.append_array(
			_expect(
				scene.log_lines()[1].ends_with(String(charge.reason)),
				"charge: the log does not carry the failure reason verbatim"
			)
		)

	_close_match(scene)
	return violations


## A refusal reaches the log carrying its reason verbatim, changes no state,
## and leaves the scene usable.
static func _test_a_refusal_is_logged_verbatim_and_recoverable() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var session := scene.session()
	var before := scene.state().digest()

	scene.select_fighter(MatchSetup.P2_WARRIOR_ID)
	scene.choose_action(HotseatMatch.ACTION_GUARD)

	violations.append_array(
		_expect(scene.log_lines().size() == 1, "refusal: the refused command was not logged")
	)
	violations.append_array(
		_expect(
			scene.log_lines()[0].ends_with(String(Authority.REFUSED_NOT_YOUR_FIGHTER)),
			"refusal: the log does not carry the reason verbatim"
		)
	)
	violations.append_array(_expect(scene.state().digest() == before, "refusal: the state changed"))
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"refusal: the Turn did not stay open"
		)
	)

	scene.select_fighter(MatchSetup.P1_WARRIOR_ID)
	scene.choose_action(HotseatMatch.ACTION_GUARD)

	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.POWER_STEP,
			"refusal: the scene was not usable afterwards"
		)
	)

	_close_match(scene)
	return violations


## A complete Combat Segment, played on the session's phase alone, ends with
## the scene offering the next round rather than taking it -- and taking it
## opens round 2 with the flags cleared and the front of the turn order active.
static func _test_the_segment_boundary_is_offered_not_taken() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var session := scene.session()

	var steps := _play_until(scene, HotseatSession.Phase.SEGMENT_COMPLETE)
	if steps < 0:
		violations.append("segment: the Combat Segment never completed")
		_close_match(scene)
		return violations

	violations.append_array(
		_expect(scene.state().round_number == 1, "segment: the scene advanced the round itself")
	)
	violations.append_array(
		_expect(
			_button(scene, "AdvanceButton").visible,
			"segment: the next round is not offered at SEGMENT_COMPLETE"
		)
	)

	var result := scene.advance_segment()

	violations.append_array(_expect(result.success, "segment: the End Segment was refused"))
	violations.append_array(
		_expect(scene.state().round_number == 2, "segment: the next round did not begin")
	)
	violations.append_array(
		_expect(
			scene.state().power_step_passes().is_empty(), "segment: the pass record did not clear"
		)
	)
	violations.append_array(
		_expect(
			session.active_player_id() == scene.state().turn_order()[0],
			"segment: round 2 does not start with the front of the turn order"
		)
	)
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.ACTION_STEP,
			"segment: round 2 did not open on an Action Step"
		)
	)

	_close_match(scene)
	return violations


## The final round's complete Segment stops the scene: no commands offered, the
## match reported over, no winner named, and #173 pointed at.
static func _test_the_final_round_stops_offering_commands() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()
	var session := scene.session()

	var steps := _play_until(scene, HotseatSession.Phase.MATCH_COMPLETE)
	if steps < 0:
		violations.append("match: the match never completed")
		_close_match(scene)
		return violations

	var status := _label_text(scene, "StatusLabel")

	violations.append_array(
		_expect(
			status == HotseatMatch.MATCH_OVER_TEXT, "match: the HUD does not report the match over"
		)
	)
	violations.append_array(_expect("#173" in status, "match: the HUD does not point at #173"))
	violations.append_array(
		_expect(
			not (MatchSetup.PLAYER_ONE in status) and not (MatchSetup.PLAYER_TWO in status),
			"match: the HUD names a winner"
		)
	)
	violations.append_array(
		_expect(
			_button(scene, "DeclineButton").disabled and _button(scene, "GuardButton").disabled,
			"match: commands are still offered after the match is over"
		)
	)
	violations.append_array(
		_expect(
			(
				not _button(scene, "PassButton").visible
				and not _button(scene, "AdvanceButton").visible
			),
			"match: a next round or a pass is still offered after the match is over"
		)
	)

	var refused := scene.advance_segment()
	violations.append_array(
		_expect(
			not refused.success and refused.reason == EndSegment.FAILURE_FINAL_ROUND,
			"match: advancing past the final round was not refused"
		)
	)
	violations.append_array(
		_expect(
			scene.log_lines()[scene.log_lines().size() - 1].ends_with(
				String(EndSegment.FAILURE_FINAL_ROUND)
			),
			"match: the final-round refusal was not logged verbatim"
		)
	)
	violations.append_array(
		_expect(
			session.phase() == HotseatSession.Phase.MATCH_COMPLETE,
			"match: the phase moved off MATCH_COMPLETE"
		)
	)

	_close_match(scene)
	return violations


# --- Helpers ----------------------------------------------------------------


## Plays the scene forward, one intent call per step, until the session reports
## `target`. Returns the number of steps taken, or `-1` if `MAX_STEPS` was
## reached first.
##
## Every step is chosen by the phase the session reports, never by a count: an
## open Action Step is declined, an open Power Step is passed, and a complete
## Segment is advanced. Nothing here knows how many Turns a round has.
static func _play_until(scene: HotseatMatch, target: HotseatSession.Phase) -> int:
	var session := scene.session()

	for step in MAX_STEPS:
		var phase := session.phase()
		if phase == target:
			return step

		if phase == HotseatSession.Phase.POWER_STEP:
			scene.pass_power_step()
		elif phase == HotseatSession.Phase.ACTION_STEP:
			scene.decline_turn()
		elif phase == HotseatSession.Phase.SEGMENT_COMPLETE:
			scene.advance_segment()
		else:
			return -1

	return -1

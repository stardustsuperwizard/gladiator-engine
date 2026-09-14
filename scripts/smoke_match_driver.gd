## Plays `res://scenes/main.tscn` through to `MATCH_COMPLETE` on a fixed
## sequence of commands, so a headless run can answer "does the game still play
## start to finish?" without a person at the screen.
##
## **Test infrastructure, not a rule.** Every command leaves through
## `HotseatMatch`'s own intent methods -- `select_fighter()`, `choose_action()`,
## `select_hex()`, `decline_turn()`, `pass_power_step()` and
## `advance_segment()` -- which is the same surface the buttons and
## `BoardView.hex_selected` are connected to. Nothing here submits to
## `HotseatSession`, `RoundDriver`, `ActionRunner` or `Authority` directly, and
## nothing here resolves: `tests/gate_bypass_contract_test.gd` fails the build
## on a receiver-qualified `.resolve(` or a `res://rules/` literal appearing in
## `scripts/`, and this file carries neither.
##
## **Nothing here counts a Turn to decide what to do next.** Every step is
## chosen by the phase `HotseatSession.phase()` reports and the player
## `HotseatSession.player_to_act()` names -- the discipline
## `tests/hotseat_match_test.gd` states for itself. `MAX_STEPS` bounds a runaway
## loop and is never a loop's stopping condition: reaching it is reported as a
## failure. The Turn and round counts in `Result` are a report of what the run
## did, read off `GameState.round_number` and off the Action Steps this driver
## acted on; no rule is restated to produce them, and neither number stops
## anything.
##
## **The sequence is fixed and deliberately not all declines.** The first
## Action Step is a real Move -- a fighter selected, the Move button chosen, and
## a hex `ActionOptions` offered tapped -- because a run made only of declines
## and passes would exercise neither `ActionOptions` nor the board, and those
## are precisely the parts a smoke run exists to catch. Every later Action Step
## declines, every Power Step passes, and every complete Segment advances.
##
## **It restates no number.** Which fighter to move and which hex to move it to
## both come off `ActionOptions`, the same affordance the HUD highlights; the
## roster, the starting hexes and the seed all come off `MatchSetup`. There is
## no seed dial here and nothing draws from an ambient RNG -- determinism is
## `MatchSetup.DEFAULT_SEED`'s, and this driver only has to avoid spoiling it.
##
## **It prints nothing.** `run()` hands back a `Result`, and the caller decides
## whether that becomes the completion marker or a failure line.
## `scripts/smoke_bootstrap.gd` is that caller.
class_name SmokeMatchDriver
extends RefCounted

## The user argument that arms the smoke run, as
## `godot --headless --path <project> -- --smoke` supplies it.
##
## Read from `OS.get_cmdline_user_args()` -- the arguments after a bare `--` --
## rather than from `OS.get_cmdline_args()`, because the engine consumes
## unrecognised leading arguments. Lives here rather than in either bootstrap
## because both of them need it: `scripts/smoke_bootstrap.gd` to arm itself and
## `tests/test_bootstrap.gd` to yield, and neither can name the other.
const SMOKE_FLAG := "--smoke"

## The completion marker, defined here and nowhere else.
##
## T2's shell script greps the headless log for
## `^Smoke match complete: [0-9]+ rounds, [0-9]+ turns\.$`, so this format is a
## contract rather than a preference. Every line the project prints in that
## shape is this constant formatted.
const MARKER_FORMAT := "Smoke match complete: %d rounds, %d turns."

## How a failed run reads. Printed on stderr, never on stdout, so a failure
## cannot be mistaken for the marker above.
const FAILURE_FORMAT := "Smoke run failed: %s"

## A bound on the loop in `run()`, not a count of the steps a match takes.
## Reaching it is a failure -- see the class docstring.
const MAX_STEPS := 400

const FAILURE_STEP_CAP := "step cap of %d reached before the match completed"
const FAILURE_NO_FIGHTER := "no fighter was offered to %s to act with"
const FAILURE_NO_DESTINATION := "no Move destination was offered to %s"
const FAILURE_NO_COMMAND := "no command could be built for %s"
const FAILURE_REFUSED := "%s was refused: %s"
const FAILURE_UNEXPECTED_PHASE := "the session reported no playable phase (%d)"

## The scene under the driver. Driven through its intent methods only.
var _match: HotseatMatch

## The loop bound this instance runs with. Injected so a suite can short-circuit
## a run and see the failure that produces.
var _max_steps: int

## What a selected fighter may do, built over the same authored templates and
## combat numbers the scene builds its own over. Used to *choose* a command,
## never to submit one -- the submission goes out through `HotseatMatch`.
var _options: ActionOptions

## How many Action Steps this run has acted on, which is how many Turns it has
## played. A report, not a stopping condition.
var _turns: int = 0

## Whether the one deliberate core action has been played yet.
var _moved: bool = false


## `match_scene` must already be in the tree, so its `_ready()` has built the
## match. `max_steps` bounds the loop and defaults to `MAX_STEPS`.
func _init(match_scene: HotseatMatch, max_steps: int = MAX_STEPS) -> void:
	_match = match_scene
	_max_steps = max_steps
	_options = ActionOptions.new(MatchSetup.templates(), MatchSetup.combat_profile())


## Plays the sequence until the session reports `MATCH_COMPLETE`, and reports
## what that took.
##
## Stops on the first command the rules did not accept, rather than pressing on
## and reporting a match that completed around a failure. Reaching `_max_steps`
## is itself a failure.
func run() -> Result:
	var session := _match.session()

	for _step in _max_steps:
		var phase := session.phase()
		if phase == HotseatSession.Phase.MATCH_COMPLETE:
			return Result.new(true, _match.state().round_number, _turns)

		var reason := _step_for(phase, session.player_to_act())
		if not reason.is_empty():
			return _failed(reason)

	return _failed(FAILURE_STEP_CAP % _max_steps)


## The completion marker for `result`, which is `MARKER_FORMAT` formatted and
## nothing else.
static func completion_marker(result: Result) -> String:
	return MARKER_FORMAT % [result.rounds, result.turns]


## The one-line failure report for `reason`, for stderr. Takes the reason
## rather than a `Result` so a caller that failed before it had one -- no main
## scene to drive, say -- reports in the same shape.
static func failure_line(reason: String) -> String:
	return FAILURE_FORMAT % reason


## True when this process was launched with `SMOKE_FLAG` after a bare `--`.
static func requested() -> bool:
	return OS.get_cmdline_user_args().has(SMOKE_FLAG)


## The one command `phase` calls for, submitted. Returns `""` when the rules
## accepted it and the failure reason when they did not.
func _step_for(phase: HotseatSession.Phase, player: String) -> String:
	match phase:
		HotseatSession.Phase.ACTION_STEP:
			return _action_step(player)
		HotseatSession.Phase.POWER_STEP:
			return _accepted("%s's pass" % player, _match.pass_power_step())
		HotseatSession.Phase.SEGMENT_COMPLETE:
			return _accepted("the End Segment", _match.advance_segment())

	return FAILURE_UNEXPECTED_PHASE % phase


## The first Action Step plays the Move; every later one declines.
func _action_step(player: String) -> String:
	_turns += 1

	if _moved:
		return _accepted("%s's decline" % player, _match.decline_turn())

	_moved = true
	return _move(player)


## `player`'s first actable fighter, moved to the first hex `ActionOptions`
## offers it -- chosen the way the HUD chooses, submitted the way a tap
## submits.
func _move(player: String) -> String:
	var state := _match.state()
	var fighters := _options.actable_fighters(state, player)
	if fighters.is_empty():
		return FAILURE_NO_FIGHTER % player

	var fighter_id: String = fighters[0]
	var destinations := _options.move_destinations(state, fighter_id)
	if destinations.is_empty():
		return FAILURE_NO_DESTINATION % fighter_id

	_match.select_fighter(fighter_id)
	_match.choose_action(HotseatMatch.ACTION_MOVE)

	return _accepted("%s's Move" % fighter_id, _match.select_hex(destinations[0]))


## `""` when `result` is a success, and the reason it was not otherwise. A
## `null` is a command `HotseatMatch` could not build and had nothing to
## submit.
func _accepted(label: String, result: TurnResult) -> String:
	if result == null:
		return FAILURE_NO_COMMAND % label
	if not result.success:
		return FAILURE_REFUSED % [label, result.reason]

	return ""


## A failed run, carrying the counts it reached before it stopped.
func _failed(reason: String) -> Result:
	return Result.new(false, _match.state().round_number, _turns, reason)


## What a run came to: whether it completed, how far it got, and why it stopped
## if it did not complete.
##
## Structured rather than pre-formatted so the caller decides what to print --
## `completion_marker()` and `failure_line()` above are the two things it can be
## turned into.
class Result:
	extends RefCounted

	## True when the run reached `HotseatSession.Phase.MATCH_COMPLETE`.
	var success: bool

	## `GameState.round_number` when the run stopped.
	var rounds: int

	## How many Action Steps the run acted on.
	var turns: int

	## Why the run stopped, or `""` on success.
	var reason: String

	func _init(is_success: bool, round_count: int, turn_count: int, why: String = "") -> void:
		success = is_success
		rounds = round_count
		turns = turn_count
		reason = why

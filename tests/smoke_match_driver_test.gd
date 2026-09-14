## Tests `SmokeMatchDriver`: the scripted sequence that plays
## `res://scenes/main.tscn` to `MATCH_COMPLETE` behind the `--smoke` flag.
##
## Every case instantiates the main scene itself and adds it to the running
## `SceneTree` under the bootstrap autoload -- not under `root`, for the reason
## `tests/hotseat_match_test.gd`'s own `_host()` sets out at length -- so
## `_ready()` builds the match, then hands that node to a driver and frees it
## before returning. Nothing here drives the scene itself: the driver is the
## thing under test, and the assertions are made against the `Result` it hands
## back and against the phase `HotseatSession` reports afterwards.
##
## **Nothing in this file counts a Turn**, the same discipline
## `tests/hotseat_match_test.gd` states for itself. The completion case stops on
## `Phase.MATCH_COMPLETE` and restates no round count; the short-circuit case
## caps the driver's own loop and expects the failure that produces.
##
## Lives under `tests/` rather than `rules/tests/` because it names
## `SmokeMatchDriver`, `HotseatMatch`, `HotseatSession` and `MatchSetup`, which
## are `res://scripts/` code -- `rules/tests/extraction_contract_test.gd` fails
## the build over a `rules/` file that names one.
class_name SmokeMatchDriverTest

## The scene under the driver, which is also the project's main scene.
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

## The shape T2's shell script greps the headless log for.
##
## A pattern, not a second copy of the marker: the expected line below is built
## from `SmokeMatchDriver.MARKER_FORMAT` alone, and this only pins the format
## that one constant has to keep.
const MARKER_PATTERN := "^Smoke match complete: [0-9]+ rounds, [0-9]+ turns\\.$"

## How a failed run has to start, as `scripts/smoke_bootstrap.gd` prints it on
## stderr and T2 reads it.
const FAILURE_PREFIX := "Smoke run failed:"

## A loop bound far too low for any match to complete inside, so reaching it is
## the guaranteed outcome rather than a race with the round structure.
const SHORT_CIRCUIT_STEPS := 1

## What `HotseatMatch` writes into its result log for a submitted Move. Read to
## show the sequence submitted a chosen core action rather than only declines
## and passes, neither of which logs anything of this shape.
const MOVE_LOG_FRAGMENT := "move "


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_the_sequence_reaches_match_complete())
	violations.append_array(_test_the_marker_is_built_from_the_one_constant())
	violations.append_array(_test_a_short_circuited_run_reports_failure())

	if violations.is_empty():
		return true

	printerr("\n=== Smoke Match Driver Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


## The node this suite's scene instances are parented to: the bootstrap autoload
## running the suites. Not `root`, which is blocked for the whole of a suite
## run -- `tests/hotseat_match_test.gd`'s `_host()` documents the measurement.
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
## rather than `queue_free()`: a suite runs inside one frame.
static func _close_match(scene: HotseatMatch) -> void:
	_host().remove_child(scene)
	scene.free()


# --- Cases ------------------------------------------------------------------


## The fixed sequence plays the booted scene all the way to `MATCH_COMPLETE`,
## submitting at least one chosen core action on the way.
static func _test_the_sequence_reaches_match_complete() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()

	var result := SmokeMatchDriver.new(scene).run()

	violations.append_array(_expect(result.success, "complete: the run failed: %s" % result.reason))
	violations.append_array(
		_expect(
			scene.session().phase() == HotseatSession.Phase.MATCH_COMPLETE,
			"complete: the sequence did not reach MATCH_COMPLETE"
		)
	)
	violations.append_array(
		_expect(result.reason.is_empty(), "complete: a completed run carried a failure reason")
	)
	violations.append_array(_expect(result.rounds > 0, "complete: no rounds were reported"))
	violations.append_array(_expect(result.turns > 0, "complete: no turns were reported"))
	violations.append_array(
		_expect(
			_submitted_a_move(scene),
			"complete: the sequence submitted no chosen core action, only declines and passes"
		)
	)

	_close_match(scene)
	return violations


## The completion line is `SmokeMatchDriver.MARKER_FORMAT` formatted and nothing
## else, and the shape T2 greps for is the shape it comes out in.
static func _test_the_marker_is_built_from_the_one_constant() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()

	var result := SmokeMatchDriver.new(scene).run()
	var marker := SmokeMatchDriver.completion_marker(result)

	violations.append_array(
		_expect(
			marker == SmokeMatchDriver.MARKER_FORMAT % [result.rounds, result.turns],
			"marker: the completion line is not the one constant formatted"
		)
	)
	violations.append_array(
		_expect(
			RegEx.create_from_string(MARKER_PATTERN).search(marker) != null,
			"marker: the completion line does not match the shape T2 greps for: %s" % marker
		)
	)

	_close_match(scene)
	return violations


## A driver capped below what a match takes reports the cap as a failure, and
## produces a failure line rather than a marker.
static func _test_a_short_circuited_run_reports_failure() -> Array[String]:
	var violations: Array[String] = []
	var scene := _open_match()

	var result := SmokeMatchDriver.new(scene, SHORT_CIRCUIT_STEPS).run()

	violations.append_array(
		_expect(not result.success, "short circuit: a capped run reported success")
	)
	violations.append_array(
		_expect(
			scene.session().phase() != HotseatSession.Phase.MATCH_COMPLETE,
			"short circuit: the capped run completed the match"
		)
	)
	violations.append_array(
		_expect(not result.reason.is_empty(), "short circuit: the failure named no reason")
	)

	var line := SmokeMatchDriver.failure_line(result.reason)

	violations.append_array(
		_expect(
			line == SmokeMatchDriver.FAILURE_FORMAT % result.reason,
			"short circuit: the failure line is not the one constant formatted"
		)
	)
	violations.append_array(
		_expect(
			line.begins_with(FAILURE_PREFIX),
			"short circuit: the failure line does not begin with %s" % FAILURE_PREFIX
		)
	)
	violations.append_array(
		_expect(
			RegEx.create_from_string(MARKER_PATTERN).search(line) == null,
			"short circuit: the failure line reads as a completion marker"
		)
	)

	_close_match(scene)
	return violations


# --- Helpers ----------------------------------------------------------------


## True when the scene's own result log records a submitted Move -- the one
## command in the sequence that goes out through `choose_action()` and
## `select_hex()` rather than through `decline_turn()` or `pass_power_step()`.
static func _submitted_a_move(scene: HotseatMatch) -> bool:
	for line in scene.log_lines():
		if MOVE_LOG_FRAGMENT in line:
			return true

	return false

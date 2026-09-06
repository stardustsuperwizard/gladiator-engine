## Bootstrap autoload: runs every test suite headlessly and makes the result
## the process exit code.
##
## That exit code is the whole point of this file. validate-godot.sh runs
## `godot --headless --quit` and treats a non-zero exit as a failed build, so a
## suite returning false must exit non-zero or the failure is invisible: a
## green check would mean only "the project imports and boots", not "the tests
## pass".
##
## Deliberately carries no class_name -- a global class sharing an autoload's
## name is a parse error in Godot 4 ("hides an autoload singleton").
##
## Adapted from mikeys_game_bones-rules-moba (EXTRACTION_LOG.md #19). The
## source kept the suite list and the run calls as two hand-maintained lists
## and then added drift detection to catch them disagreeing. SUITES below is
## one list used for both, so the drift it was detecting cannot occur.
extends Node

## Every suite, in execution order. Adding a suite here is the only step:
## execution, the expected count, and truncation detection all read this.
##
## Order matters only in that the contract test runs first -- a rules/ module
## that has broken its dependency arrow should say so before anything else
## reports.
var _suites: Array[Dictionary] = [
	{"name": "Extraction Contract Test", "run": ExtractionContractTest.run},
	{"name": "Contract Scanner Test", "run": ContractScannerTest.run},
	{"name": "Ambient RNG Contract Test", "run": AmbientRngContractTest.run},
	{"name": "Ambient RNG Scanner Test", "run": AmbientRngScannerTest.run},
	{"name": "Hex Coord Test", "run": HexCoordTest.run},
	{"name": "Board Test", "run": BoardTest.run},
	{"name": "Board Serialization Test", "run": BoardSerializationTest.run},
	{"name": "Line Of Sight Test", "run": LineOfSightTest.run},
	{"name": "Reachability Test", "run": ReachabilityTest.run},
	{"name": "Deterministic Rng Test", "run": DeterministicRngTest.run},
	{"name": "Game State Test", "run": GameStateTest.run},
	{"name": "Turn Action Test", "run": TurnActionTest.run},
	{"name": "Determinism Test", "run": DeterminismTest.run},
	{"name": "Fighter Template Test", "run": FighterTemplateTest.run},
	{"name": "Fighter Test", "run": FighterTest.run},
	{"name": "Fighter Serialization Test", "run": FighterSerializationTest.run},
	{"name": "Resource Data Test", "run": ResourceDataTest.run},
]

var _passes: Array[String] = []
var _failures: Array[String] = []


func _ready() -> void:
	# Only hijack the process when running headless validation. In the editor
	# or a normal run this autoload does nothing.
	if DisplayServer.get_name() != "headless":
		return

	# Queued BEFORE any suite runs, so the summary is still printed and the
	# exit code still set if a suite aborts on a compile or runtime error.
	# call_deferred fires at the end of this frame.
	call_deferred("_finalize")

	for suite in _suites:
		var callable: Callable = suite["run"]
		_check(suite["name"], callable.call())


func _check(suite_name: String, passed: bool) -> void:
	if passed:
		_passes.append(suite_name)
		print("PASS %s" % suite_name)
	else:
		_failures.append(suite_name)
		printerr("FAIL %s" % suite_name)


func _finalize() -> void:
	_report()
	var truncated := _passes.size() + _failures.size() < _suites.size()
	get_tree().quit(1 if not _failures.is_empty() or truncated else 0)


func _report() -> void:
	var actual := _passes.size() + _failures.size()
	var expected := _suites.size()

	# Fewer suites ran than exist: something aborted partway. Report which
	# never ran rather than a pass count that looks fine on its own.
	if actual < expected:
		var missing: Array[String] = []
		for suite in _suites:
			var suite_name: String = suite["name"]
			if suite_name not in _passes and suite_name not in _failures:
				missing.append(suite_name)
		printerr(
			"\n%d of %d test suites never ran: %s" % [missing.size(), expected, ", ".join(missing)]
		)
		return

	if _failures.is_empty():
		print("\nAll %d test suites passed." % actual)
		return

	printerr("\n%d of %d test suites FAILED: %s" % [_failures.size(), actual, ", ".join(_failures)])

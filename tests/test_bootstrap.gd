## Bootstrap autoload: runs every test suite headlessly and makes the result
## the process exit code.
##
## That exit code is the whole point of this file. validate-godot.sh runs
## `godot --headless --quit` and treats a non-zero exit as a failed build, so a
## suite returning false must exit non-zero or the failure is invisible: a
## green check would mean only "the project imports and boots", not "the tests
## pass".
##
## Before running any suite, two guards verify the harness is functional:
## 1. Engine version floor: reads the required version from project.godot's
##    application/config/features and aborts if the running engine is below it.
## 2. Harness liveness probe: attempts to call _expect(false, "...") on every
##    suite through its registered Callable, and aborts if any returns an empty
##    array, indicating the harness cannot detect failures. If the tree-wide
##    probe finds no callable suites, falls back to a direct static call on
##    HexCoordTest. Prints the probed suite count so a collapse to zero is
##    visible in the log.
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
	{"name": "Gate Bypass Contract Test", "run": GateBypassContractTest.run},
	{"name": "Gate Bypass Scanner Test", "run": GateBypassScannerTest.run},
	{"name": "Orphan Test Contract Test", "run": OrphanTestContractTest.run},
	{"name": "Orphan Test Scanner Test", "run": OrphanTestScannerTest.run},
	{"name": "Base Class Contract Test", "run": BaseClassContractTest.run},
	{"name": "Base Class Scanner Test", "run": BaseClassScannerTest.run},
	{"name": "Inbound Type Contract Test", "run": InboundTypeContractTest.run},
	{"name": "Inbound Type Scanner Test", "run": InboundTypeScannerTest.run},
	{"name": "Hex Coord Test", "run": HexCoordTest.run},
	{"name": "Board Test", "run": BoardTest.run},
	{"name": "Board Serialization Test", "run": BoardSerializationTest.run},
	{"name": "Line Of Sight Test", "run": LineOfSightTest.run},
	{"name": "Reachability Test", "run": ReachabilityTest.run},
	{"name": "Deterministic Rng Test", "run": DeterministicRngTest.run},
	{"name": "Dice Pool Test", "run": DicePoolTest.run},
	{"name": "Combat Profile Test", "run": CombatProfileTest.run},
	{"name": "Construction Budget Test", "run": ConstructionBudgetTest.run},
	{"name": "Flanking Test", "run": FlankingTest.run},
	{"name": "Game State Test", "run": GameStateTest.run},
	{"name": "Turn Action Test", "run": TurnActionTest.run},
	{"name": "Pass Action Test", "run": PassActionTest.run},
	{"name": "Attack Action Test", "run": AttackActionTest.run},
	{"name": "Determinism Test", "run": DeterminismTest.run},
	{"name": "Fighter Template Test", "run": FighterTemplateTest.run},
	{"name": "Fighter Test", "run": FighterTest.run},
	{"name": "Fighter Serialization Test", "run": FighterSerializationTest.run},
	{"name": "Resource Data Test", "run": ResourceDataTest.run},
	{"name": "Authority Test", "run": AuthorityTest.run},
	{"name": "Action Runner Test", "run": ActionRunnerTest.run},
	{"name": "Command Taxonomy Contract Test", "run": CommandTaxonomyContractTest.run},
]

var _passes: Array[String] = []
var _failures: Array[String] = []


func _ready() -> void:
	# Only hijack the process when running headless validation. In the editor
	# or a normal run this autoload does nothing.
	if DisplayServer.get_name() != "headless":
		return

	# Guard 1: Engine version floor
	if not _check_engine_version():
		return

	# Guard 2: Harness liveness probe
	if not _check_harness_liveness():
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


func _check_engine_version() -> bool:
	# Read the declared engine version from project.godot's
	# application/config/features entry.
	var config := ConfigFile.new()
	var load_result := config.load("res://project.godot")
	if load_result != OK:
		printerr("ERROR: Failed to load project.godot: error %d" % load_result)
		get_tree().quit(1)
		return false

	var features: PackedStringArray = config.get_value("application", "config/features", [])

	if features is not PackedStringArray or features.is_empty():
		printerr("ERROR: No engine version found in project.godot application/config/features")
		get_tree().quit(1)
		return false

	# Find the MAJOR.MINOR entry (e.g., "4.7"). It must contain a dot and
	# have numeric parts on both sides.
	var declared_version: String = ""
	for feature in features:
		var parts: PackedStringArray = feature.split(".")
		if parts.size() >= 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			declared_version = feature
			break

	if declared_version.is_empty():
		printerr(
			"ERROR: No MAJOR.MINOR version entry found in project.godot application/config/features"
		)
		get_tree().quit(1)
		return false

	# Compare against running engine version
	var version_info: Dictionary = Engine.get_version_info()
	var running_major: int = version_info["major"]
	var running_minor: int = version_info["minor"]
	var running_version: String = "%d.%d" % [running_major, running_minor]

	# Parse declared version
	var declared_parts: PackedStringArray = declared_version.split(".")
	if declared_parts.size() < 2:
		printerr("ERROR: Invalid version format in project.godot: %s" % declared_version)
		get_tree().quit(1)
		return false

	var declared_major: int = int(declared_parts[0])
	var declared_minor: int = int(declared_parts[1])

	# Check if running version is below declared version
	if (
		running_major < declared_major
		or (running_major == declared_major and running_minor < declared_minor)
	):
		printerr(
			(
				"ERROR: Engine version %s is below required version %s"
				% [running_version, declared_version]
			)
		)
		get_tree().quit(1)
		return false

	return true


func _check_harness_liveness() -> bool:
	# Attempt to probe every suite's _expect through its registered Callable.
	# This validates that the harness can detect failures on the running engine.
	var probed_count := 0

	# Try tree-wide probe first: test each suite's Callable
	for suite in _suites:
		var callable: Callable = suite["run"]
		var obj: Variant = callable.get_object()

		if obj == null:
			continue

		# Check if this object has the _expect method
		if obj.has_method("_expect"):
			var result: Variant = obj.call("_expect", false, "harness liveness probe")

			# Type guard is part of the failure condition: must be non-empty Array
			if not (result is Array and not result.is_empty()):
				printerr(
					(
						"ERROR: Harness liveness probe failed on %s: _expect(false, ...) returned %s"
						% [suite["name"], result]
					)
				)
				printerr(
					"The test harness cannot detect assertion failures on this engine version."
				)
				get_tree().quit(1)
				return false

			probed_count += 1

	# If tree-wide probe succeeded and found callable suites, report coverage
	if probed_count > 0:
		print("Probed %d suites for harness liveness" % probed_count)
		return true

	# Fallback: probe HexCoordTest directly if tree-wide found no probes
	# This is used only if dynamic dispatch through Callable doesn't work
	var result: Variant = HexCoordTest._expect(false, "harness liveness probe")

	# Type guard is part of the failure condition: must be non-empty Array
	if not (result is Array and not result.is_empty()):
		printerr("ERROR: Harness liveness probe failed: _expect(false, ...) returned empty array")
		printerr("The test harness cannot detect assertion failures on this engine version.")
		get_tree().quit(1)
		return false

	return true


func _finalize() -> void:
	_report()
	var truncated: bool = _passes.size() + _failures.size() < _suites.size()
	get_tree().quit(1 if not _failures.is_empty() or truncated else 0)


func _report() -> void:
	var actual: int = _passes.size() + _failures.size()
	var expected: int = _suites.size()

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

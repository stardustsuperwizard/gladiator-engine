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
## 2. Harness liveness probe: puts _expect(false, "...") through every suite in
##    _suites that defines it, reached through the Callable already registered
##    there, and aborts if any returns an empty array -- which would mean the
##    harness cannot detect assertion failures on the running engine.
##
##    How the dispatch works, measured on 4.7.1-stable rather than assumed.
##    Callable.get_object() on a static-method Callable returns the GDScript
##    resource itself, and Object.has_method() on that resource DOES resolve
##    the script's own static methods: it answers false for the six contract
##    suites that define no _expect and true for the twenty-eight that do.
##    Script.has_static_method() is documented but is NOT bound for scripting
##    on this engine -- calling it raises "Invalid call. Nonexistent function
##    'has_static_method' in base 'GDScript'". So the existence check has to be
##    has_method(), and it has to happen before the call: Object.call() on a
##    method the object lacks is not a call that returns null, it is a runtime
##    error that halts the calling function outright.
##
##    Because the tree-wide form works, the narrowed single-suite fallback the
##    Issue permitted is not used. A collapse to zero probed suites is itself
##    treated as a harness failure, and the probed count is printed against the
##    suite count on every path so any partial collapse is visible in the log.
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

	if features.is_empty():
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
	# Put a known-false assertion through every suite that defines _expect,
	# reached through the Callable already registered in _suites. No second
	# list: the one list is the source of what gets probed, as it is of what
	# gets run.
	var probed_count := 0
	var without_expect: Array[String] = []

	for suite in _suites:
		var callable: Callable = suite["run"]
		var obj: Object = callable.get_object()

		# The existence check must precede the call. Object.call() on a method
		# the object does not have is a runtime error that halts this function,
		# not a call that returns null, so it cannot double as the check.
		# has_method() on the GDScript resource resolves the script's statics;
		# Script.has_static_method() is unbound for scripting on 4.7.1-stable.
		if obj == null or not obj.has_method("_expect"):
			without_expect.append(suite["name"])
			continue

		var result: Variant = obj.call("_expect", false, "harness liveness probe")

		# The type guard is part of the failure condition, not a precondition
		# for detecting it: a non-Array return is as broken as an empty one.
		if not (result is Array and not result.is_empty()):
			printerr(
				(
					"ERROR: Harness liveness probe failed on %s: _expect(false, ...) returned %s"
					% [suite["name"], result]
				)
			)
			printerr("The test harness cannot detect assertion failures on this engine version.")
			get_tree().quit(1)
			return false

		probed_count += 1

	# Printed on every path, including zero, so a collapse in coverage shows up
	# in the log instead of quietly reducing the guard to nothing.
	print(
		(
			"Harness liveness probe: %d of %d suites probed (%d define no _expect: %s)"
			% [
				probed_count,
				_suites.size(),
				without_expect.size(),
				", ".join(without_expect) if not without_expect.is_empty() else "none"
			]
		)
	)

	# Zero probes is itself a harness collapse: the guard would be reporting
	# success without having asserted anything.
	if probed_count == 0:
		printerr("ERROR: Harness liveness probe covered no suites; no suite defines _expect.")
		printerr("The test harness cannot detect assertion failures on this engine version.")
		get_tree().quit(1)
		return false

	return true


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

## Tests the gate bypass scanner itself.
##
## `GateBypassContractTest` passes vacuously the day it is written: `scripts/`
## holds two files, one of them exempt, and `scenes/` holds no script at all. A
## green build therefore says nothing about whether the scanner works, so its
## correctness rests here instead.
##
## Two ways to be useless, and both are pinned below. A scanner that misses
## `action.resolve(state)` enforces nothing. A scanner that also flags
## `PassAction.new("f1")` or `result.success` blocks the very thing the
## architectural commitment requires -- a UI that gathers intent and renders
## the result -- and would be deleted rather than fixed.
##
## Exercises the pure functions on synthetic lines rather than planting files
## in the tree. See EXTRACTION_LOG.md #2.
class_name GateBypassScannerTest

const RUNNER_PATH := "res://scripts/action_runner.gd"
const AUTHORITY_PATH := "res://scripts/authority.gd"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_detects_receiver_qualified_resolve())
	violations.append_array(_test_detects_rules_path())
	violations.append_array(_test_ignores_resolve_inside_a_comment())
	violations.append_array(_test_allows_naming_rules_types())
	violations.append_array(_test_reports_a_rules_path_inside_a_string())
	violations.append_array(_test_exempt_list_holds_only_the_runner())
	violations.append_array(_test_runner_is_clean_only_because_it_is_exempt())
	violations.append_array(_test_authority_is_clean_on_its_merits())

	if violations.is_empty():
		return true

	printerr("\n=== Gate Bypass Scanner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## True when scan() reports at least one violation against this file.
static func _scan_reports(file_path: String) -> bool:
	for violation in GateBypassContractTest.scan():
		if violation.begins_with(file_path + ":"):
			return true
	return false


## True when any line of this file, read as GDScript, violates.
static func _file_has_a_violating_line(file_path: String) -> bool:
	var content := ExtractionContractTest.read_file(file_path)
	for line in content.split("\n"):
		if GateBypassContractTest.line_violates(line, true):
			return true
	return false


## Resolving is the operation the gate owns. A scanner that misses this
## enforces nothing at all.
static func _test_detects_receiver_qualified_resolve() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		"var r := action.resolve(state)",
		"return _action.resolve(_state)",
		"action.resolve (state)",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				GateBypassContractTest.line_violates(line, true),
				"a receiver-qualified resolve call must be detected: %s" % line
			)
		)

	return violations


## Reaching into the module by path, in a script and in a scene. The scene case
## is a Node subclassing rules code, which is the violation in its most direct
## form.
static func _test_detects_rules_path() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			GateBypassContractTest.line_violates(
				'preload("res://rules/state/turn_action.gd")', true
			),
			"a preload of a rules path must be detected"
		)
	)
	violations.append_array(
		_expect(
			GateBypassContractTest.line_violates(
				'load("res://rules/actions/pass_action.gd")', true
			),
			"a load of a rules path must be detected"
		)
	)
	violations.append_array(
		_expect(
			GateBypassContractTest.line_violates(
				'[ext_resource type="Script" path="res://rules/actions/pass_action.gd"]', false
			),
			"a scene attaching a script from rules/ must be detected"
		)
	)

	return violations


## Comments are discussion, not execution; code before one is still code.
static func _test_ignores_resolve_inside_a_comment() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			not GateBypassContractTest.line_violates("# var r := action.resolve(state)", true),
			"a resolve call appearing only inside a comment must not count"
		)
	)
	violations.append_array(
		_expect(
			GateBypassContractTest.line_violates(
				"var r := action.resolve(state)  # the gate does this", true
			),
			"a resolve call before a trailing comment must still be detected"
		)
	)

	return violations


## The pattern the commitment exists to require. Constructing a command and
## reading a result are how a UI gathers intent and renders what comes back --
## if this fails, the scanner blocks every view that will ever be written.
static func _test_allows_naming_rules_types() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		'var a := PassAction.new("f1")',
		"if result.success:",
		"func resolve(state: GameState) -> TurnResult:",
		'var result: TurnResult = _runner.run(action, "p1")',
		"if result.reason == Authority.REFUSED_NOT_YOUR_TURN:",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				not GateBypassContractTest.line_violates(line, true),
				"naming a rules type is not resolving and must be allowed: %s" % line
			)
		)

	return violations


## String literals are not stripped, so a rules path spelled out in one is
## reported. Being wrong in this direction costs a false positive; being wrong
## in the other lets a runtime `load()` through.
static func _test_reports_a_rules_path_inside_a_string() -> Array[String]:
	return _expect(
		GateBypassContractTest.line_violates('var s := "res://rules/"', true),
		"a rules path inside a string literal must be reported"
	)


## The exemption is a list of one. `Authority` names rules types throughout and
## resolves nothing, so exempting it would hide it later starting to.
static func _test_exempt_list_holds_only_the_runner() -> Array[String]:
	var violations: Array[String] = []
	var exempt := GateBypassContractTest.EXEMPT_FILES

	violations.append_array(
		_expect(RUNNER_PATH in exempt, "%s must be the exempt path" % RUNNER_PATH)
	)
	violations.append_array(
		_expect(AUTHORITY_PATH not in exempt, "%s must not be exempt" % AUTHORITY_PATH)
	)
	violations.append_array(
		_expect(exempt.size() == 1, "exactly one file may be exempt, found %d" % exempt.size())
	)

	return violations


## The runner really does resolve, so its clean report is the exemption doing
## work rather than a predicate that never fires. Were the entry removed, the
## build would fail -- which is what makes it the single documented hole.
static func _test_runner_is_clean_only_because_it_is_exempt() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			not ExtractionContractTest.read_file(RUNNER_PATH).is_empty(),
			"%s must exist and be readable" % RUNNER_PATH
		)
	)
	violations.append_array(
		_expect(
			_file_has_a_violating_line(RUNNER_PATH),
			(
				"%s must contain a line the predicate flags -- otherwise its exemption is vacuous"
				% RUNNER_PATH
			)
		)
	)
	violations.append_array(
		_expect(not _scan_reports(RUNNER_PATH), "%s must be reported clean by scan()" % RUNNER_PATH)
	)

	return violations


## Not exempt, and still clean: the line this test draws is who resolves, not
## who may say a rules type's name.
static func _test_authority_is_clean_on_its_merits() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			not ExtractionContractTest.read_file(AUTHORITY_PATH).is_empty(),
			"%s must exist and be readable" % AUTHORITY_PATH
		)
	)
	violations.append_array(
		_expect(
			not _file_has_a_violating_line(AUTHORITY_PATH),
			"%s must not violate, since it names rules types but resolves nothing" % AUTHORITY_PATH
		)
	)
	violations.append_array(
		_expect(
			not _scan_reports(AUTHORITY_PATH),
			"%s must be reported clean by scan()" % AUTHORITY_PATH
		)
	)

	return violations

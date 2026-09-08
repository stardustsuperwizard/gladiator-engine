## Tests the base class scanner itself.
##
## BaseClassContractTest passes vacuously the day it is written: every class
## under rules/ already extends RefCounted, Resource, or TurnAction, so a
## green build says only "nothing is broken yet", not "this guard works". Its
## correctness rests here instead, the same reasoning
## OrphanTestScannerTest and AmbientRngScannerTest give for their own
## contract tests.
##
## Every synthetic fixture below is built from an array of quoted line
## strings joined with "\n", never written as a literal file-scope `extends`
## line in this file's own source. That is what keeps `Control` and `Node2D`
## appearing in this file's prose and fixtures from ever being read as this
## file's own declaration -- a fixture line only ever exists inside a quoted
## string, one array element per program line, so it never begins a program
## line of its own.
##
## Exercises the pure functions on synthetic `{path: source}` maps rather than
## planting files in the tree. See EXTRACTION_LOG.md #23 on the four orphaned
## .uid files the source repo left behind doing exactly that.
class_name BaseClassScannerTest

const BUILTINS_ONLY: Array[String] = ["RefCounted", "Resource"]
const WITH_TURN_ACTION: Array[String] = ["RefCounted", "Resource", "TurnAction"]

const ATTACK_ACTION_PATH := "res://rules/actions/attack_action.gd"
const PASS_ACTION_PATH := "res://rules/actions/pass_action.gd"
const CONTRACT_PATH := "res://rules/tests/base_class_contract_test.gd"
const SCANNER_PATH := "res://rules/tests/base_class_scanner_test.gd"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_scene_tree_bases_are_reported())
	violations.append_array(_test_quoted_path_base_is_reported())
	violations.append_array(_test_permitted_bases_are_not_reported())
	violations.append_array(_test_implicit_ref_counted_is_not_reported())
	violations.append_array(_test_indented_extends_is_file_scope_limit())
	violations.append_array(_test_violation_format_is_path_line_extends())
	violations.append_array(_test_empty_scan_is_reported_as_a_violation())
	violations.append_array(_test_allowlist_is_derived_not_hand_listed())
	violations.append_array(_test_the_real_allowlist_contains_turn_action())
	violations.append_array(_test_the_real_tree_has_no_violation())
	violations.append_array(_test_real_action_files_are_clean())
	violations.append_array(_test_this_guards_own_files_are_clean())

	if violations.is_empty():
		return true

	printerr("\n=== Base Class Scanner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A synthetic file body: a class_name line, then whatever body lines the
## case needs, one array element per program line.
static func _source(declared: String, body: Array[String]) -> String:
	var lines: Array[String] = ["## A synthetic fixture.", "class_name " + declared]
	lines.append_array(body)
	return "\n".join(lines)


## True when some reported violation names this path.
static func _reports(violations: Array[String], path: String) -> bool:
	for violation in violations:
		if violation.begins_with(path + ":"):
			return true
	return false


## Must-fail: the scene-tree hierarchy the allowlist exists to exclude.
## Node2D and Control specifically, so this is demonstrably not a bare
## `Node` string match.
static func _test_scene_tree_bases_are_reported() -> Array[String]:
	var violations: Array[String] = []
	var forbidden_bases: Array[String] = ["Node", "Node2D", "Control", "CharacterBody2D"]

	for base_class: String in forbidden_bases:
		var path := "res://rules/tests/synthetic_%s_test.gd" % base_class.to_lower()
		var sources := {path: _source("Synthetic" + base_class + "Test", ["extends " + base_class])}
		var reported := BaseClassContractTest.violations_for(BUILTINS_ONLY, sources)

		violations.append_array(
			_expect(_reports(reported, path), "extends %s must be reported" % base_class)
		)

	return violations


## The quoted-path form names no allowlisted identifier and must be reported
## just like a bare scene-tree name.
static func _test_quoted_path_base_is_reported() -> Array[String]:
	var path := "res://rules/tests/synthetic_quoted_test.gd"
	var sources := {
		path: _source("SyntheticQuotedTest", ['extends "res://rules/state/turn_action.gd"'])
	}
	var reported := BaseClassContractTest.violations_for(BUILTINS_ONLY, sources)

	return _expect(
		_reports(reported, path), "a quoted-path extends must be reported: %s" % [reported]
	)


## Must-pass: the two built-ins, and a rules-side class_name allowlisted by
## the caller -- the shape AttackAction extends TurnAction takes in the real
## tree.
static func _test_permitted_bases_are_not_reported() -> Array[String]:
	var violations: Array[String] = []
	var sources := {
		"res://rules/tests/synthetic_ref_counted_test.gd":
		_source("SyntheticRefCountedTest", ["extends RefCounted"]),
		"res://rules/tests/synthetic_resource_test.gd":
		_source("SyntheticResourceTest", ["extends Resource"]),
		"res://rules/tests/synthetic_turn_action_test.gd":
		_source("SyntheticTurnActionTest", ["extends TurnAction"]),
	}
	var reported := BaseClassContractTest.violations_for(WITH_TURN_ACTION, sources)

	violations.append_array(
		_expect(reported.is_empty(), "no permitted base should be reported, got: %s" % [reported])
	)

	return violations


## The implicit case: 21 of the 22 files under rules/tests/ declare a
## class_name and no extends line at all, taking GDScript's implicit
## RefCounted. A synthetic source doing the same must not be reported.
static func _test_implicit_ref_counted_is_not_reported() -> Array[String]:
	var violations: Array[String] = []
	var path := "res://rules/tests/synthetic_implicit_test.gd"
	var source := _source(
		"SyntheticImplicitTest", ["", "static func run() -> bool:", "\treturn true"]
	)

	violations.append_array(
		_expect(
			BaseClassContractTest.declared_base_class(source).is_empty(),
			"a source with no extends line must declare no base class"
		)
	)
	violations.append_array(
		_expect(
			BaseClassContractTest.violations_for(BUILTINS_ONLY, {path: source}).is_empty(),
			"a class_name with no extends line at all must not be reported"
		)
	)

	return violations


## The documented file-scope limit: an inner class's indented `extends` is not
## the file's own declaration and is not read at all. Pinned here as a named
## limit rather than an accident of the pattern -- the same limit
## OrphanTestContractTest.declared_class_name accepts for `class_name`.
static func _test_indented_extends_is_file_scope_limit() -> Array[String]:
	var violations: Array[String] = []
	var path := "res://rules/tests/synthetic_inner_test.gd"
	var source := _source(
		"SyntheticInnerTest",
		["", "class Inner:", "\textends Node", "", "static func run() -> bool:", "\treturn true"]
	)

	violations.append_array(
		_expect(
			BaseClassContractTest.declared_base_class(source).is_empty(),
			(
				"an indented extends must not be read as the file's own -- documented limit of a"
				+ " line scanner, not a defect"
			)
		)
	)
	violations.append_array(
		_expect(
			BaseClassContractTest.violations_for(BUILTINS_ONLY, {path: source}).is_empty(),
			"an inner class's indented extends Node must pass unseen at file scope"
		)
	)

	return violations


## The report names the path, the 1-indexed line, and the exact extends
## target -- "path:line: extends X".
static func _test_violation_format_is_path_line_extends() -> Array[String]:
	var path := "res://rules/tests/synthetic_format_test.gd"
	var source := _source("SyntheticFormatTest", ["extends Node"])
	var reported := BaseClassContractTest.violations_for(BUILTINS_ONLY, {path: source})

	if reported.size() != 1:
		return ["expected exactly one violation, got: %s" % [reported]] as Array[String]

	return _expect(
		reported[0] == "%s:3: extends Node" % path,
		"violation must read 'path:line: extends X', got: %s" % reported[0]
	)


## The second vacuity hazard, from the contract test's own side: an empty scan
## must be reported rather than passed clean.
static func _test_empty_scan_is_reported_as_a_violation() -> Array[String]:
	var reported := BaseClassContractTest.result_for({})

	return _expect(
		not reported.is_empty(), "an empty scan of rules/ must itself be reported as a violation"
	)


## The allowlist is derived from what rules/ declares, not hand-listed beyond
## the two built-ins.
static func _test_allowlist_is_derived_not_hand_listed() -> Array[String]:
	var violations: Array[String] = []
	var sources := {
		"res://rules/state/synthetic_base_test.gd":
		_source("SyntheticBase", ["extends RefCounted"]),
	}
	var allowed := BaseClassContractTest.allowed_names_for(sources)

	violations.append_array(
		_expect("RefCounted" in allowed, "the built-in RefCounted must remain in the allowlist")
	)
	violations.append_array(
		_expect("Resource" in allowed, "the built-in Resource must remain in the allowlist")
	)
	violations.append_array(
		_expect(
			"SyntheticBase" in allowed,
			"a class_name declared under rules/ must be derived into the allowlist"
		)
	)

	return violations


## The derivation case against the real tree: TurnAction is declared under
## rules/state/, so it must appear in the derived allowlist, and the
## allowlist must be non-empty.
static func _test_the_real_allowlist_contains_turn_action() -> Array[String]:
	var violations: Array[String] = []
	var allowed := BaseClassContractTest.real_allowed_base_classes()

	violations.append_array(_expect(not allowed.is_empty(), "the real allowlist must not be empty"))
	violations.append_array(
		_expect(
			"TurnAction" in allowed,
			"the real allowlist must contain TurnAction, got: %s" % [allowed]
		)
	)

	return violations


## The tree as it stands: every file under rules/ extends something the
## allowlist permits.
static func _test_the_real_tree_has_no_violation() -> Array[String]:
	var reported := BaseClassContractTest.scan()

	return _expect(
		reported.is_empty(), "rules/ must contain no base class violation: %s" % [reported]
	)


## AttackAction and PassAction are the live example of the derived case:
## both extend TurnAction, a rules/-declared class_name, and neither is
## reported by path.
static func _test_real_action_files_are_clean() -> Array[String]:
	var violations: Array[String] = []
	var reported := BaseClassContractTest.scan()

	violations.append_array(
		_expect(not _reports(reported, ATTACK_ACTION_PATH), "%s must be clean" % ATTACK_ACTION_PATH)
	)
	violations.append_array(
		_expect(not _reports(reported, PASS_ACTION_PATH), "%s must be clean" % PASS_ACTION_PATH)
	)

	return violations


## This guard's own two files declare a class_name and no extends line at
## all, which the allowlist permits without an EXEMPT_FILES entry -- pinned
## here rather than merely assumed.
static func _test_this_guards_own_files_are_clean() -> Array[String]:
	var violations: Array[String] = []
	var sources := BaseClassContractTest.rules_sources()

	violations.append_array(
		_expect(sources.has(CONTRACT_PATH), "%s must be among the scanned files" % CONTRACT_PATH)
	)
	violations.append_array(
		_expect(sources.has(SCANNER_PATH), "%s must be among the scanned files" % SCANNER_PATH)
	)

	if sources.has(CONTRACT_PATH):
		violations.append_array(
			_expect(
				BaseClassContractTest.declared_base_class(sources[CONTRACT_PATH]).is_empty(),
				"%s must declare no file-scope extends" % CONTRACT_PATH
			)
		)
	if sources.has(SCANNER_PATH):
		violations.append_array(
			_expect(
				BaseClassContractTest.declared_base_class(sources[SCANNER_PATH]).is_empty(),
				"%s must declare no file-scope extends" % SCANNER_PATH
			)
		)

	return violations

## Tests the inbound type scanner itself.
##
## `InboundTypeContractTest` passes vacuously the day it is written: nothing
## in rules/ names a game-side type today, so a green build says only
## "nothing violates yet", not "this guard works". Its correctness rests
## here instead.
##
## Two ways to be useless, and both are pinned below. A scanner that misses
## `Authority.new(state)` or `ActionRunner.new()` enforces nothing. A scanner
## that also flags `authority_id` or a docstring naming the same class blocks
## the very docstrings `rules/state/turn_action.gd` and
## `rules/actions/attack_action.gd` carry on purpose today, and would be
## deleted rather than fixed.
##
## Naming `Authority` and `ActionRunner` here, in code position, is expected
## and is not the committed literal list the epic forbids -- the prohibition
## is on the scanner deriving its forbidden set from a hand-written list, not
## on this self-test asserting that the derivation and the matching both
## work. `GateBypassScannerTest` sets this precedent with its
## `RUNNER_PATH`/`AUTHORITY_PATH` constants. This file may say so only
## because it lives under tests/, which `InboundTypeContractTest` never
## scans -- see that file's docstring on why the pair sits here and not under
## rules/tests/.
##
## Exercises the pure functions on synthetic lines and a synthetic
## {path: source} map, rather than planting files in the tree. See
## EXTRACTION_LOG.md #2 and #23.
class_name InboundTypeScannerTest

## Real-tree anchors: both name Authority and ActionRunner in `##`
## docstrings today, correctly and on purpose, and both must keep passing.
const TURN_ACTION_PATH := "res://rules/state/turn_action.gd"
const ATTACK_ACTION_PATH := "res://rules/actions/attack_action.gd"

## The two classes the current tree derives. Named here as the expected
## result of a derivation, not as a hand-written forbidden list fed to the
## scanner -- see the class docstring.
const AUTHORITY_CLASS := "Authority"
const ACTION_RUNNER_CLASS := "ActionRunner"

## The forbidden set fed to the pure predicate in every synthetic case below.
const SYNTHETIC_FORBIDDEN: Array[String] = ["Authority", "ActionRunner"]


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_detects_forbidden_construction())
	violations.append_array(_test_detects_reference_before_trailing_comment())
	violations.append_array(_test_ignores_reference_inside_a_comment())
	violations.append_array(_test_ignores_docstring_mention())
	violations.append_array(_test_ignores_partial_identifier_matches())
	violations.append_array(_test_reports_a_reference_inside_a_string())
	violations.append_array(_test_derivation_contains_the_two_game_side_classes())
	violations.append_array(_test_class_names_in_reads_file_scope_declarations_only())
	violations.append_array(_test_empty_derivation_is_a_violation())
	violations.append_array(_test_turn_action_mentions_are_meaningful())
	violations.append_array(_test_turn_action_is_clean_by_path())
	violations.append_array(_test_attack_action_mentions_are_meaningful())
	violations.append_array(_test_attack_action_is_clean_by_path())
	violations.append_array(_test_the_real_tree_has_no_violation())

	if violations.is_empty():
		return true

	printerr("\n=== Inbound Type Scanner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## True when some reported violation names this path.
static func _reports(violations: Array[String], path: String) -> bool:
	for violation in violations:
		if violation.begins_with(path + ":"):
			return true
	return false


## True when scan() reports at least one violation against this file.
static func _scan_reports(file_path: String) -> bool:
	return _reports(InboundTypeContractTest.scan(), file_path)


## Constructing either game-side type in code is the violation this scanner
## exists to catch. A scanner that misses either enforces nothing at all.
static func _test_detects_forbidden_construction() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		"var gate := Authority.new(state)",
		"_runner = ActionRunner.new()",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				InboundTypeContractTest.line_violates(line, SYNTHETIC_FORBIDDEN),
				"a code reference to a forbidden class must be detected: %s" % line
			)
		)

	return violations


## A reference before a trailing comment is still code, and must still be
## detected.
static func _test_detects_reference_before_trailing_comment() -> Array[String]:
	return _expect(
		InboundTypeContractTest.line_violates(
			"var gate := Authority.new(state)  # constructs the gate", SYNTHETIC_FORBIDDEN
		),
		"a reference before a trailing comment must still be detected"
	)


## Comments are discussion, not execution.
static func _test_ignores_reference_inside_a_comment() -> Array[String]:
	return _expect(
		not InboundTypeContractTest.line_violates(
			"# var gate := Authority.new(state)", SYNTHETIC_FORBIDDEN
		),
		"a reference appearing only inside a comment must not count"
	)


## The specific docstring pattern rules/state/turn_action.gd and
## rules/actions/attack_action.gd both carry on purpose today: naming a
## forbidden class in a `##` docstring line is discussion of the constraint,
## not a violation of it.
static func _test_ignores_docstring_mention() -> Array[String]:
	return _expect(
		not InboundTypeContractTest.line_violates(
			"## Neither this class nor any subclass may reference Authority or ActionRunner.",
			SYNTHETIC_FORBIDDEN
		),
		"a docstring line naming a forbidden class must not be detected"
	)


## Whole-identifier matching: a name that only appears as a substring of a
## longer identifier is not a reference to anything.
static func _test_ignores_partial_identifier_matches() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		'var authority_id := "f1"',
		"var _ActionRunner_registry := {}",
		"var gate := ActionRunnerish.new()",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				not InboundTypeContractTest.line_violates(line, SYNTHETIC_FORBIDDEN),
				"a partial identifier match must not be detected: %s" % line
			)
		)

	return violations


## String literals are not stripped, so a forbidden name inside one is
## reported. Being wrong in this direction costs a false positive; being
## wrong in the other lets a name assembled or referenced through a string
## through unseen.
static func _test_reports_a_reference_inside_a_string() -> Array[String]:
	return _expect(
		InboundTypeContractTest.line_violates('var s := "Authority"', SYNTHETIC_FORBIDDEN),
		"a forbidden name inside a string literal must be reported, matching every other scanner here"
	)


## The derivation, run against the real tree: it must actually find the two
## classes scripts/ declares today, or the contract test's own docstring
## claim is untested.
static func _test_derivation_contains_the_two_game_side_classes() -> Array[String]:
	var violations: Array[String] = []
	var forbidden := InboundTypeContractTest.forbidden_class_names()

	violations.append_array(
		_expect(not forbidden.is_empty(), "the derived forbidden set must not be empty")
	)
	violations.append_array(
		_expect(
			AUTHORITY_CLASS in forbidden,
			"%s must be in the derived forbidden set" % AUTHORITY_CLASS
		)
	)
	violations.append_array(
		_expect(
			ACTION_RUNNER_CLASS in forbidden,
			"%s must be in the derived forbidden set" % ACTION_RUNNER_CLASS
		)
	)

	return violations


## class_names_in() reads file-scope class_name declarations only, on a
## synthetic map, so this pins the parse without depending on scripts/ ever
## staying exactly two files.
static func _test_class_names_in_reads_file_scope_declarations_only() -> Array[String]:
	var violations: Array[String] = []
	var sources := {
		"res://scripts/one.gd": "class_name SyntheticOne\nextends RefCounted\n",
		"res://scripts/two.gd": "class_name SyntheticTwo\nextends RefCounted\n",
		"res://scripts/three.gd": "extends RefCounted\n# class_name SyntheticCommentedOut\n",
	}
	var names := InboundTypeContractTest.class_names_in(sources)

	violations.append_array(
		_expect(
			names.size() == 2, "exactly two names must be parsed, got %d: %s" % [names.size(), names]
		)
	)
	violations.append_array(
		_expect("SyntheticOne" in names, "SyntheticOne must be parsed from its file-scope declaration")
	)
	violations.append_array(
		_expect("SyntheticTwo" in names, "SyntheticTwo must be parsed from its file-scope declaration")
	)
	violations.append_array(
		_expect(
			"SyntheticCommentedOut" not in names,
			"a commented-out class_name line must not be parsed as a declaration"
		)
	)

	return violations


## The vacuity guard: an empty derived set is itself reported as a violation
## naming both source directories, rather than the scan passing clean.
static func _test_empty_derivation_is_a_violation() -> Array[String]:
	var violations: Array[String] = []
	var reported := InboundTypeContractTest.violations_for([] as Array[String])

	violations.append_array(
		_expect(
			reported.size() == 1,
			"an empty derived set must report exactly one violation, got %d" % reported.size()
		)
	)

	if reported.is_empty():
		return violations

	violations.append_array(
		_expect(
			"res://scripts/" in reported[0] and "res://scenes/" in reported[0],
			"the violation must name both source directories: %s" % reported[0]
		)
	)

	return violations


## The real-file cases below prove nothing if the file does not actually
## mention the forbidden classes at all -- a test asserting "clean" against a
## file that never named them would pass for the wrong reason.
static func _test_turn_action_mentions_are_meaningful() -> Array[String]:
	var violations: Array[String] = []
	var content := ExtractionContractTest.read_file(TURN_ACTION_PATH)

	violations.append_array(
		_expect(
			AUTHORITY_CLASS in content,
			"%s must mention %s for the clean-by-path case to be meaningful"
			% [TURN_ACTION_PATH, AUTHORITY_CLASS]
		)
	)
	violations.append_array(
		_expect(
			ACTION_RUNNER_CLASS in content,
			"%s must mention %s for the clean-by-path case to be meaningful"
			% [TURN_ACTION_PATH, ACTION_RUNNER_CLASS]
		)
	)

	return violations


## rules/state/turn_action.gd names both classes in a `##` docstring, on
## purpose -- that docstring is the sentence saying no subclass may reference
## them -- and must keep passing.
static func _test_turn_action_is_clean_by_path() -> Array[String]:
	return _expect(
		not _scan_reports(TURN_ACTION_PATH), "%s must be reported clean by scan()" % TURN_ACTION_PATH
	)


static func _test_attack_action_mentions_are_meaningful() -> Array[String]:
	var violations: Array[String] = []
	var content := ExtractionContractTest.read_file(ATTACK_ACTION_PATH)

	violations.append_array(
		_expect(
			AUTHORITY_CLASS in content,
			"%s must mention %s for the clean-by-path case to be meaningful"
			% [ATTACK_ACTION_PATH, AUTHORITY_CLASS]
		)
	)
	violations.append_array(
		_expect(
			ACTION_RUNNER_CLASS in content,
			"%s must mention %s for the clean-by-path case to be meaningful"
			% [ATTACK_ACTION_PATH, ACTION_RUNNER_CLASS]
		)
	)

	return violations


## rules/actions/attack_action.gd names both classes in a `##` docstring too,
## and must keep passing for the same reason.
static func _test_attack_action_is_clean_by_path() -> Array[String]:
	return _expect(
		not _scan_reports(ATTACK_ACTION_PATH),
		"%s must be reported clean by scan()" % ATTACK_ACTION_PATH
	)


## The tree as it stands: nothing in rules/ references a game-side type in
## code today.
static func _test_the_real_tree_has_no_violation() -> Array[String]:
	var reported := InboundTypeContractTest.scan()

	return _expect(
		reported.is_empty(), "rules/ must contain no inbound type reference: %s" % ", ".join(reported)
	)

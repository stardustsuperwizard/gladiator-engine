## Tests the orphan-test scanner itself.
##
## `OrphanTestContractTest` passes vacuously the day it is written: every test
## file in the tree already runs, so a green build says only "nothing is broken
## yet", not "this guard works". Its correctness rests here instead.
##
## The failure this file exists to prevent is a guard that is green, silent,
## and enforcing nothing. There are four ways to build one, and each is pinned
## below rather than merely avoided:
##
## 1. **An empty seed.** If the `_suites` parser reads nothing, the closure has
##    no seed. `_test_the_real_bootstrap_parses_to_a_seeded_set` fails the
##    build in that case instead of letting the check quietly stop meaning
##    anything.
## 2. **Self-reference.** A file must not be read as reaching itself, whether
##    through its own `class_name` declaration line or through a call it makes
##    to itself.
## 3. **Scanner-source contamination.** This file and the contract test are
##    both registered, so both are traversed for references. Writing a real
##    suite class name in call position in either one would hand that class
##    reachability for free -- so every synthetic fixture here uses an invented
##    name, and `_test_the_push_suite_is_reached_from_one_file_only` checks
##    that exactly one file in the whole tree reaches the push suite.
## 4. **A checker that always returns nothing.** Several cases below assert a
##    violation *is* reported, so an unconditional empty array fails this
##    suite.
##
## The mutual-orphan case is the specific bug worth naming: a scan that asked
## "is this name mentioned anywhere under `tests/`" would clear two dead suites
## that happen to call each other, and a whole disconnected island of them.
## Reachability is a closure seeded from `_suites` alone, and that case pins it.
##
## Exercises the pure function on synthetic `{path: source}` maps rather than
## planting files in the tree. See EXTRACTION_LOG.md #2 and #23.
class_name OrphanTestScannerTest

## The suite that is registered and therefore seeds every synthetic closure
## below. Invented, like every other name in the fixtures.
const SUITE_CLASS := "SyntheticSuiteTest"
const SUITE_PATH := "res://tests/synthetic_suite_test.gd"

## Real-tree anchors. The class names appear here only as bare strings, never
## followed by a `.`, so naming them creates no reachability -- which is the
## point of detection being call-shaped.
const PUSH_TEST_PATH := "res://rules/tests/attack_action_push_test.gd"
const PUSH_TEST_CLASS := "AttackActionPushTest"
const ATTACK_TEST_PATH := "res://rules/tests/attack_action_test.gd"
const ATTACK_TEST_CLASS := "AttackActionTest"
const CONTRACT_PATH := "res://tests/orphan_test_contract_test.gd"
const SCANNER_PATH := "res://tests/orphan_test_scanner_test.gd"
const KNOWN_SUITE_CLASS := "ExtractionContractTest"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_registered_file_is_clean())
	violations.append_array(_test_a_called_file_is_clean())
	violations.append_array(_test_reachability_is_transitive())
	violations.append_array(_test_an_orphan_is_reported_by_path_and_class())
	violations.append_array(_test_mutual_orphans_are_both_reported())
	violations.append_array(_test_a_comment_creates_no_reachability())
	violations.append_array(_test_a_file_cannot_reach_itself())
	violations.append_array(_test_a_bare_mention_is_not_a_call())
	violations.append_array(_test_a_file_without_a_class_name_is_reported())
	violations.append_array(_test_declared_class_name_is_file_scope_only())
	violations.append_array(_test_an_unreadable_bootstrap_parses_to_nothing())
	violations.append_array(_test_the_real_bootstrap_parses_to_a_seeded_set())
	violations.append_array(_test_the_real_tree_has_no_orphan())
	violations.append_array(_test_the_push_suite_is_reached_from_one_file_only())
	violations.append_array(_test_the_bootstrap_is_an_input_not_a_candidate())
	violations.append_array(_test_this_guard_is_inside_the_set_it_scans())

	if violations.is_empty():
		return true

	printerr("\n=== Orphan Test Scanner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A synthetic file body, given the class it declares and the lines that
## follow.
static func _source(declared: String, body: Array[String]) -> String:
	var lines: Array[String] = ["## A synthetic fixture.", "class_name " + declared, ""]
	lines.append_array(body)
	return "\n".join(lines)


## The registered seed used by most fixtures: one suite that runs, whose body
## is whatever the case needs it to say.
static func _suite_source(body: Array[String]) -> String:
	return _source(SUITE_CLASS, body)


## True when some reported violation names this path.
static func _reports(violations: Array[String], path: String) -> bool:
	for violation in violations:
		if violation.begins_with(path + ":"):
			return true
	return false


## The one entry point under test, run against a synthetic map with the
## synthetic suite as the only registered name.
static func _check(sources: Dictionary) -> Array[String]:
	return OrphanTestContractTest.violations_for([SUITE_CLASS] as Array[String], sources)


## The base case: a file the bootstrap lists runs, and is not reported.
static func _test_registered_file_is_clean() -> Array[String]:
	var sources := {SUITE_PATH: _suite_source(["static func run() -> bool:", "\treturn true"])}

	return _expect(_check(sources).is_empty(), "a file registered in _suites must not be reported")


## The second clause of the rule, and the one that lets a helper suite exist
## without its own bootstrap entry.
static func _test_a_called_file_is_clean() -> Array[String]:
	var called_path := "res://tests/synthetic_called_test.gd"
	var sources := {
		SUITE_PATH:
		_suite_source(
			["static func run() -> bool:", "\treturn SyntheticCalledTest.run().is_empty()"]
		),
		called_path: _source("SyntheticCalledTest", ["static func run() -> Array: return []"]),
	}

	return _expect(
		_check(sources).is_empty(),
		"a file called in code from a registered file must not be reported"
	)


## Reachability is a closure, not one hop. A helper called by a helper still
## runs.
static func _test_reachability_is_transitive() -> Array[String]:
	var middle_path := "res://tests/synthetic_middle_test.gd"
	var leaf_path := "res://tests/synthetic_leaf_test.gd"
	var sources := {
		SUITE_PATH: _suite_source(["\tSyntheticMiddleTest.run()"]),
		middle_path: _source("SyntheticMiddleTest", ["\tSyntheticLeafTest.run()"]),
		leaf_path: _source("SyntheticLeafTest", ["\treturn true"]),
	}

	return _expect(
		_check(sources).is_empty(), "reachability must be transitive through called files"
	)


## The violation this guard exists to produce. Path first, so the message names
## the file to open, and the class name too, so the fix is obvious.
static func _test_an_orphan_is_reported_by_path_and_class() -> Array[String]:
	var violations: Array[String] = []
	var orphan_path := "res://tests/synthetic_orphan_test.gd"
	var sources := {
		SUITE_PATH: _suite_source(["\treturn true"]),
		orphan_path: _source("SyntheticOrphanTest", ["\treturn true"]),
	}
	var reported := _check(sources)

	violations.append_array(
		_expect(
			reported.size() == 1, "exactly one orphan must be reported, got %d" % reported.size()
		)
	)

	if reported.is_empty():
		return violations

	violations.append_array(
		_expect(
			reported[0].begins_with(orphan_path + ":"),
			"the report must lead with the path: %s" % reported[0]
		)
	)
	violations.append_array(
		_expect(
			"SyntheticOrphanTest" in reported[0], "the report must name the class: %s" % reported[0]
		)
	)

	return violations


## The specific bug a mention-anywhere scan would have. Two dead suites calling
## each other clear each other under that rule; under a closure seeded from
## _suites, neither is ever traversed and both are reported.
static func _test_mutual_orphans_are_both_reported() -> Array[String]:
	var violations: Array[String] = []
	var first_path := "res://tests/synthetic_first_orphan_test.gd"
	var second_path := "res://tests/synthetic_second_orphan_test.gd"
	var sources := {
		SUITE_PATH: _suite_source(["\treturn true"]),
		first_path: _source("SyntheticFirstOrphanTest", ["\tSyntheticSecondOrphanTest.run()"]),
		second_path: _source("SyntheticSecondOrphanTest", ["\tSyntheticFirstOrphanTest.run()"]),
	}
	var reported := _check(sources)

	violations.append_array(
		_expect(
			_reports(reported, first_path), "an orphan naming only another orphan is still dead"
		)
	)
	violations.append_array(
		_expect(_reports(reported, second_path), "both halves of a mutual pair must be reported")
	)
	violations.append_array(
		_expect(
			reported.size() == 2, "exactly two orphans must be reported, got %d" % reported.size()
		)
	)

	return violations


## Comments are discussion, not execution. This is what makes it safe for the
## guard's own docstrings to name the classes it judges.
static func _test_a_comment_creates_no_reachability() -> Array[String]:
	var commented_path := "res://tests/synthetic_commented_test.gd"
	var sources := {
		SUITE_PATH: _suite_source(["\t# SyntheticCommentedTest.run() used to be called here"]),
		commented_path: _source("SyntheticCommentedTest", ["\treturn true"]),
	}

	return _expect(
		_reports(_check(sources), commented_path),
		"a class named only inside a comment must not become reachable"
	)


## The second vacuity hazard. Neither the `class_name` declaration line nor a
## call a file makes to itself may lift it into the reachable set.
static func _test_a_file_cannot_reach_itself() -> Array[String]:
	var self_path := "res://tests/synthetic_self_test.gd"
	var sources := {
		SUITE_PATH: _suite_source(["\treturn true"]),
		self_path:
		_source(
			"SyntheticSelfTest",
			["static func go() -> void:", "\tSyntheticSelfTest.helper()"],
		),
	}

	return _expect(
		_reports(_check(sources), self_path),
		"a file that only ever names itself must still be reported"
	)


## Detection is call-shaped. A name in a list, or spelled out in a string, is
## not an invocation and grants nothing -- which is what stops this scanner's
## own prose and fixtures from clearing the files it judges.
static func _test_a_bare_mention_is_not_a_call() -> Array[String]:
	var mentioned_path := "res://tests/synthetic_mentioned_test.gd"
	var sources := {
		SUITE_PATH:
		_suite_source(
			['\tvar named := "SyntheticMentionedTest"', "\tvar listed := [SyntheticMentionedTest]"]
		),
		mentioned_path: _source("SyntheticMentionedTest", ["\treturn true"]),
	}

	return _expect(
		_reports(_check(sources), mentioned_path),
		"a bare mention is not a call and must not create reachability"
	)


## A test file declaring no file-scope class cannot be registered or called by
## any route this check recognises, so it can never run.
static func _test_a_file_without_a_class_name_is_reported() -> Array[String]:
	var nameless_path := "res://tests/synthetic_nameless_test.gd"
	var sources := {
		SUITE_PATH: _suite_source(["\treturn true"]),
		nameless_path: "extends RefCounted\n\nstatic func run() -> bool:\n\treturn true\n",
	}

	return _expect(
		_reports(_check(sources), nameless_path),
		"a test file declaring no class_name must be reported"
	)


## An inner class's indented declaration is not the file's own, and is not a
## global name the bootstrap could ever register.
static func _test_declared_class_name_is_file_scope_only() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			(
				OrphanTestContractTest.declared_class_name("class_name SyntheticOuterTest\n")
				== "SyntheticOuterTest"
			),
			"a file-scope declaration must be read"
		)
	)
	violations.append_array(
		_expect(
			(
				OrphanTestContractTest
				. declared_class_name("\tclass_name SyntheticInnerTest\n")
				. is_empty()
			),
			"an indented declaration must not be read as the file's own"
		)
	)

	return violations


## The first vacuity hazard, from the other side: a bootstrap the parser cannot
## read yields nothing rather than something plausible.
static func _test_an_unreadable_bootstrap_parses_to_nothing() -> Array[String]:
	var violations: Array[String] = []
	var renamed := 'var _registry: Array[Dictionary] = [\n\t{"run": SyntheticSuiteTest.run},\n]\n'

	violations.append_array(
		_expect(
			OrphanTestContractTest.suite_names_in("").is_empty(),
			"an empty bootstrap must parse to no suites"
		)
	)
	violations.append_array(
		_expect(
			OrphanTestContractTest.suite_names_in(renamed).is_empty(),
			"a renamed suite array must parse to no suites rather than be guessed at"
		)
	)

	return violations


## And the hazard itself: if this ever fails, the closure has no seed and the
## contract test is checking nothing. Better a failed build than a green one.
static func _test_the_real_bootstrap_parses_to_a_seeded_set() -> Array[String]:
	var violations: Array[String] = []
	var registered := OrphanTestContractTest.registered_suite_names()

	(
		violations
		. append_array(
			_expect(
				not registered.is_empty(),
				(
					"the _suites array in %s must parse to at least one suite -- an empty seed checks nothing"
					% OrphanTestContractTest.BOOTSTRAP_PATH
				)
			)
		)
	)
	violations.append_array(
		_expect(
			KNOWN_SUITE_CLASS in registered,
			"%s must be among the parsed suite names" % KNOWN_SUITE_CLASS
		)
	)
	violations.append_array(
		_expect(
			ATTACK_TEST_CLASS in registered,
			"%s must be among the parsed suite names" % ATTACK_TEST_CLASS
		)
	)

	return violations


## The tree as it stands: every test file runs.
static func _test_the_real_tree_has_no_orphan() -> Array[String]:
	var reported := OrphanTestContractTest.scan()

	return _expect(
		reported.is_empty(), "the repository must contain no orphan test: %s" % ", ".join(reported)
	)


## The push suite is the live example of the second clause, and the third
## vacuity hazard's test case. It is not registered; it runs because one
## registered file calls it. Asserting that exactly one file in the tree
## reaches it rules out this scanner's own source, or anything else, having
## cleared it by accident.
static func _test_the_push_suite_is_reached_from_one_file_only() -> Array[String]:
	var violations: Array[String] = []
	var sources := OrphanTestContractTest.test_sources()
	var referrers: Array[String] = []

	for path: String in sources:
		if PUSH_TEST_CLASS in OrphanTestContractTest.references_in(sources[path]):
			referrers.append(path)

	violations.append_array(
		_expect(sources.has(PUSH_TEST_PATH), "%s must be among the files examined" % PUSH_TEST_PATH)
	)
	violations.append_array(
		_expect(
			PUSH_TEST_CLASS not in OrphanTestContractTest.registered_suite_names(),
			"%s must not be registered -- it is the case that passes by reference" % PUSH_TEST_CLASS
		)
	)
	violations.append_array(
		_expect(
			referrers.size() == 1 and referrers[0] == ATTACK_TEST_PATH,
			(
				"%s must be reached from %s alone, found: %s"
				% [PUSH_TEST_CLASS, ATTACK_TEST_PATH, ", ".join(referrers)]
			)
		)
	)

	return violations


## The fourth vacuity hazard. The bootstrap is where the registered set is read
## from; it is not a candidate for being reported as an orphan, and it declares
## no class_name that could be one.
static func _test_the_bootstrap_is_an_input_not_a_candidate() -> Array[String]:
	var violations: Array[String] = []
	var bootstrap_path := OrphanTestContractTest.BOOTSTRAP_PATH

	violations.append_array(
		_expect(
			not OrphanTestContractTest.test_sources().has(bootstrap_path),
			"%s must not be scanned as a candidate" % bootstrap_path
		)
	)
	violations.append_array(
		_expect(
			not ExtractionContractTest.read_file(bootstrap_path).is_empty(),
			"%s must exist and be readable" % bootstrap_path
		)
	)

	return violations


## Both halves of this guard end in _test.gd and sit under tests/, so each is
## inside the set the check scans. Removing either bootstrap entry fails the
## build rather than quietly disabling the guard.
static func _test_this_guard_is_inside_the_set_it_scans() -> Array[String]:
	var violations: Array[String] = []
	var sources := OrphanTestContractTest.test_sources()

	violations.append_array(
		_expect(sources.has(CONTRACT_PATH), "%s must scan itself" % CONTRACT_PATH)
	)
	violations.append_array(
		_expect(sources.has(SCANNER_PATH), "%s must be scanned too" % SCANNER_PATH)
	)

	return violations

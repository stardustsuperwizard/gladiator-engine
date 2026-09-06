## Tests the ambient randomness scanner itself.
##
## A contract test that cannot fail is worse than no contract test: it reports
## PASS on every build while enforcing nothing, and nobody looks again. This
## one has two ways to be useless rather than one. A scanner that misses a bare
## randi() enforces nothing; a scanner that also flags `_rng.randi_range(1, 6)`
## blocks the very pattern the contract exists to require, and would be deleted
## rather than fixed. These cases pin both directions.
##
## Exercises the pure functions on synthetic lines rather than planting files
## in the tree. See EXTRACTION_LOG.md #2.
class_name AmbientRngScannerTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_detects_every_forbidden_call())
	violations.append_array(_test_allows_explicit_receiver())
	violations.append_array(_test_ignores_identifier_ending_in_forbidden_name())
	violations.append_array(_test_detects_call_at_line_start_and_mid_expression())
	violations.append_array(_test_comment_handling())
	violations.append_array(_test_range_call_reported_once_under_its_own_name())

	if violations.is_empty():
		return true

	printerr("\n=== Ambient RNG Scanner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Every name in the forbidden set, each in a call that has no receiver.
static func _test_detects_every_forbidden_call() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		"var roll := randi()",
		"var chance := randf()",
		"var damage := randi_range(1, 6)",
		"var weight := randf_range(0.0, 1.0)",
		"var spread := randfn()",
		"randomize()",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				AmbientRngContractTest.line_violates(line, true),
				"a bare global call must be detected: %s" % line
			)
		)

	return violations


## The pattern the contract exists to protect. A generator owned by the state
## and called through a receiver is the required form, not a violation -- if
## this fails, the scanner blocks DeterministicRng itself.
static func _test_allows_explicit_receiver() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		"var damage := _rng.randi_range(1, 6)",
		"var roll := rng.randi()",
		"return _generator.randf_range(0.0, 1.0)",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				not AmbientRngContractTest.line_violates(line, true),
				"a call with an explicit receiver must be allowed: %s" % line
			)
		)

	return violations


## Name-banning would fail this. The leading character class excludes
## identifier characters precisely so a longer name is not a false positive.
static func _test_ignores_identifier_ending_in_forbidden_name() -> Array[String]:
	var violations: Array[String] = []
	var lines: Array[String] = [
		"var roll := my_randi()",
		"var value := next_randf()",
		"var n := seeded_randi_range(1, 6)",
	]

	for line: String in lines:
		violations.append_array(
			_expect(
				not AmbientRngContractTest.line_violates(line, true),
				"an identifier merely ending in a forbidden name must not count: %s" % line
			)
		)

	return violations


## The "^" alternative carries the start-of-line case; the character class
## carries every other position.
static func _test_detects_call_at_line_start_and_mid_expression() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			AmbientRngContractTest.line_violates("randi()", true),
			"a call at the very start of a line must be detected"
		)
	)
	violations.append_array(
		_expect(
			AmbientRngContractTest.line_violates("var x := 1 + randi()", true),
			"a call appearing mid-expression must be detected"
		)
	)

	return violations


## Comments are discussion, not execution; code before one is still code.
static func _test_comment_handling() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			not AmbientRngContractTest.line_violates("# never call randi() in rules/", true),
			"a comment-only line mentioning a forbidden call must not count"
		)
	)
	violations.append_array(
		_expect(
			AmbientRngContractTest.line_violates("var roll := randi()  # placeholder", true),
			"code carrying a forbidden call before a trailing comment must be detected"
		)
	)

	return violations


## `randi` is a prefix of `randi_range`, so a careless alternation reports the
## same call twice under two names, or names it wrongly. Both make the report
## lie about what the file did.
static func _test_range_call_reported_once_under_its_own_name() -> Array[String]:
	var names := AmbientRngContractTest.calls_in_line("var damage := randi_range(1, 6)", true)
	var reported_once_as_itself := names.size() == 1 and names[0] == "randi_range"
	return _expect(
		reported_once_as_itself, "randi_range must be reported once, as itself: %s" % [names]
	)

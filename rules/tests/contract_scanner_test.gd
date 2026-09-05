## Tests the extraction contract scanner itself.
##
## A contract test that cannot fail is worse than no contract test: it reports
## PASS on every build while enforcing nothing, and nobody looks again. These
## cases pin that ExtractionContractTest.line_violates() actually detects a
## violation, actually ignores a comment, and specifically does not fall for
## the `#`-inside-a-string case that the source repo's split("#") version
## silently missed.
##
## Exercises the pure functions on synthetic lines rather than planting files
## in the tree. See EXTRACTION_LOG.md #2.
class_name ContractScannerTest

const PREFIX := "res://scripts/"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_detects_plain_violation())
	violations.append_array(_test_ignores_comment_only_line())
	violations.append_array(_test_detects_code_before_inline_comment())
	violations.append_array(_test_ignores_prefix_inside_trailing_comment())
	violations.append_array(_test_hash_inside_string_does_not_hide_violation())
	violations.append_array(_test_escaped_quote_does_not_desync())
	violations.append_array(_test_non_gdscript_scans_whole_line())

	if violations.is_empty():
		return true

	printerr("\n=== Contract Scanner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_detects_plain_violation() -> Array[String]:
	var line := 'var path := "res://scripts/authority.gd"'
	return _expect(
		ExtractionContractTest.line_violates(line, PREFIX, true),
		"plain violation should be detected"
	)


static func _test_ignores_comment_only_line() -> Array[String]:
	var line := "# the game side lives in res://scripts/ and is off limits here"
	return _expect(
		not ExtractionContractTest.line_violates(line, PREFIX, true),
		"a comment-only line must not count as a violation"
	)


static func _test_detects_code_before_inline_comment() -> Array[String]:
	var line := 'var path := "res://scripts/x.gd"  # loaded at startup'
	return _expect(
		ExtractionContractTest.line_violates(line, PREFIX, true),
		"code before an inline comment must still be scanned"
	)


static func _test_ignores_prefix_inside_trailing_comment() -> Array[String]:
	var line := "var count := 3  # mirrors res://scripts/ but does not touch it"
	return _expect(
		not ExtractionContractTest.line_violates(line, PREFIX, true),
		"a prefix mentioned only in a trailing comment must not count"
	)


## The regression this scanner exists to avoid.
##
## split("#")[0] truncates this line at the hash inside the string literal,
## leaving `var label := "` and hiding the load() that follows entirely.
static func _test_hash_inside_string_does_not_hide_violation() -> Array[String]:
	var violations: Array[String] = []

	var double_quoted := 'var label := "count #1"; var p := "res://scripts/x.gd"'
	violations.append_array(
		_expect(
			ExtractionContractTest.line_violates(double_quoted, PREFIX, true),
			"a # inside a double-quoted string must not hide the rest of the line"
		)
	)

	var single_quoted := "var label := 'count #1'; var p := 'res://scripts/x.gd'"
	violations.append_array(
		_expect(
			ExtractionContractTest.line_violates(single_quoted, PREFIX, true),
			"a # inside a single-quoted string must not hide the rest of the line"
		)
	)

	return violations


## An escaped quote must not be read as closing the string, or every following
## quote flips the wrong way and the rest of the file scans as inside-out.
static func _test_escaped_quote_does_not_desync() -> Array[String]:
	var line := 'var label := "a \\" # b"; var p := "res://scripts/x.gd"'
	return _expect(
		ExtractionContractTest.line_violates(line, PREFIX, true),
		"an escaped quote must not desync string tracking"
	)


## JSON and .tres have no comment syntax, so the whole line is code.
static func _test_non_gdscript_scans_whole_line() -> Array[String]:
	var line := '"path": "res://scripts/x.gd" # not a comment in JSON'
	return _expect(
		ExtractionContractTest.line_violates(line, PREFIX, false),
		"non-GDScript files must be scanned whole"
	)

## Ambient randomness contract test for the rules module.
##
## Fails the build if any file under rules/ calls Godot's global random
## functions: randi(), randf(), randi_range(), randf_range(), randfn() or
## randomize().
##
## All six read or reseed the same hidden generator, which lives outside the
## game state. A resolver that touches it is not reproducible: the same state
## plus the same action sequence yields a different match in a fresh process,
## and replays, save/load, deterministic tests and network sync fail together.
## Randomness in rules/ is an explicit input -- a RandomNumberGenerator whose
## seed and current state are part of the saved game.
##
## The rule is receiver-awareness, not name-banning. A call is a violation only
## when the identifier is invoked with no receiver, so an owned generator's
## `_rng.randi_range(1, 6)` -- the pattern this contract exists to protect --
## stays legal, and no generator class needs an exemption entry. An identifier
## that merely ends in a forbidden name, like `my_randi()`, is likewise not a
## violation.
##
## It catches the obvious violation, not a determined one. A Callable-style
## reference taken without parentheses (`var f := randi`) and a call assembled
## from a string and invoked by reflection both pass unseen; detecting those
## needs a parser, not a line scanner. That is the honest limit of a lint-style
## check and the reason it runs on every build rather than on request.
##
## Comments are stripped before scanning, via ExtractionContractTest's
## quote-aware strip_comment(). String literals are not stripped: a forbidden
## name inside a string is still reported, which is the safe direction to be
## wrong in, and it is why the scanner test below needs an exemption entry.
class_name AmbientRngContractTest

const RULES_DIR := "res://rules/"

## The global random functions, all of which share one process-wide generator.
##
## Order is irrelevant: the pattern requires "(" immediately after the name, so
## `randi` cannot claim the head of `randi_range(` -- the trailing paren fails
## and the alternation backtracks to the longer name.
const FORBIDDEN_CALLS := ["randi_range", "randf_range", "randomize", "randfn", "randi", "randf"]

## The receiver-aware call pattern; "%s" takes the alternation of
## FORBIDDEN_CALLS.
##
## The leading character class is the whole point. It excludes a preceding "."
## so `_rng.randi_range(1, 6)` does not match, and excludes identifier
## characters so `my_randi()` does not either. Being a consumed character
## rather than a lookbehind, it needs the "^" alternative for a call at the
## very start of a line.
const CALL_PATTERN := "(^|[^A-Za-z0-9_.])(%s)\\s*\\("

## Only .gd is scanned. Unlike the extraction contract there is no .json or
## .tres case: data files cannot call a function.
const SCANNED_EXTENSION := ".gd"

## Contract tests that name the forbidden identifiers as scan-target data
## rather than calling them. A name in a scanner's identifier list or in a
## synthetic test line is a string compared against, not a global generator
## read.
##
## Full paths, not filenames: a suffix match would exempt any future file
## anywhere under rules/ that happened to carry one of these names, which is a
## standing invitation to park a real violation in a file named after a
## contract test. Do not add ordinary rules code, and do not exempt a
## directory.
const EXEMPT_FILES := [
	"res://rules/tests/ambient_rng_contract_test.gd",
	"res://rules/tests/ambient_rng_scanner_test.gd",
]

static var _pattern: RegEx = null


static func run() -> bool:
	var violations := scan()

	if violations.is_empty():
		return true

	var forbidden := ", ".join(FORBIDDEN_CALLS)
	printerr("\n=== Ambient RNG Contract Violations ===")
	printerr("Files in rules/ must not call %s with no receiver." % forbidden)
	printerr("Take a RandomNumberGenerator as an explicit input instead.")
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Scan rules/ and return one "path:line: name" string per violation.
## Separated from run() so the scan is callable without the reporting.
static func scan() -> Array[String]:
	var violations: Array[String] = []

	for file_path in ExtractionContractTest.files_recursive(RULES_DIR):
		if file_path in EXEMPT_FILES:
			continue
		if not file_path.ends_with(SCANNED_EXTENSION):
			continue

		var content := ExtractionContractTest.read_file(file_path)
		if content.is_empty():
			continue

		var lines := content.split("\n")
		for line_num in range(lines.size()):
			# Every scanned file is GDScript, so comments always strip.
			for call_name in calls_in_line(lines[line_num], true):
				violations.append("%s:%d: %s" % [file_path, line_num + 1, call_name])

	return violations


## True when this line invokes a forbidden global with no receiver.
##
## Pure and side-effect free so AmbientRngScannerTest can exercise it directly
## on synthetic lines rather than by planting violation files in the tree.
static func line_violates(line: String, is_gdscript: bool) -> bool:
	return not calls_in_line(line, is_gdscript).is_empty()


## Every distinct forbidden global invoked on this line, in the order found.
##
## Distinct, so one report per identifier per line: `randi_range(1, 6)` is
## reported once, as randi_range, never additionally as randi.
##
## Public rather than private because that naming guarantee is a contract worth
## pinning, and scan() cannot demonstrate it while the module is clean.
static func calls_in_line(line: String, is_gdscript: bool) -> Array[String]:
	var code := ExtractionContractTest.strip_comment(line) if is_gdscript else line
	var names: Array[String] = []
	var offset := 0

	while offset <= code.length():
		var found := _call_pattern().search(code, offset)
		if found == null:
			break

		var call_name := found.get_string(2)
		if call_name not in names:
			names.append(call_name)

		# Resume at the end of the identifier rather than the end of the match.
		# The match also consumes the "(" that follows, and in a nested call
		# such as randi(randf()) that paren is the inner call's own evidence of
		# having no receiver. get_end(2) always advances, so this terminates.
		offset = found.get_end(2)

	return names


## The compiled pattern, built once and reused.
##
## A const cannot hold a compiled RegEx, and recompiling per line would make
## the scan quadratic in the size of the module for no benefit.
static func _call_pattern() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.create_from_string(CALL_PATTERN % "|".join(FORBIDDEN_CALLS))
	return _pattern

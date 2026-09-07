## Orphan test contract test: fails the build on a test file that never runs.
##
## Every `*_test.gd` under `rules/tests/` and `tests/` must actually execute.
## A suite that is written, committed, and never called is worse than no suite
## at all: it reads as coverage, reports nothing, and goes green forever. The
## count in "All N test suites passed." only ever describes what `_suites`
## lists, so a file left out of that array is invisible to every other signal
## the build produces.
##
## **What counts as executed.** A file runs if its declared `class_name` is
## registered in `tests/test_bootstrap.gd`'s `_suites` array, or if that name
## appears in call position inside the comment-stripped source of a file that
## is *already known to run*. The second clause is a transitive closure seeded
## only from `_suites` -- `rules/tests/attack_action_test.gd` is registered and
## calls `AttackActionPushTest.run()`, so the push suite is reached through it
## and needs no entry of its own.
##
## **The closure is seeded, not searched.** Asking "is this name mentioned
## anywhere under `tests/`" would be the obvious implementation and the wrong
## one: two orphan suites that call each other would clear each other, and a
## whole disconnected island of dead tests would report clean. Reachability
## here only ever grows outward from `_suites`.
##
## **It lives under `tests/`, not `rules/tests/`.** It reads
## `res://tests/test_bootstrap.gd`, which is game-side; a rules-module file
## reaching into game-side test infrastructure inverts the one-way dependency
## arrow that `AGENTS.md` names as the first architectural commitment. Note
## that `res://tests/` is not in `ExtractionContractTest.FORBIDDEN_PREFIXES`,
## so that scanner would not mechanically catch the misplacement -- the
## constraint stands on the architecture, not on another test catching it.
##
## **It guards itself.** This file and `tests/orphan_test_scanner_test.gd` both
## end in `_test.gd` and both sit inside `tests/`, so each falls in the set
## this check scans. Deleting either one's `_suites` entry fails this suite.
##
## **`test_bootstrap.gd` is an input, never a subject.** It does not match
## `*_test.gd` and declares no `class_name` -- deliberately, per its own
## docstring, since a global class sharing an autoload's name is a parse error.
## It is where the registered set is read from, and it is not itself a
## candidate for being reported as an orphan.
##
## **Detection is call-shaped and receiver-qualified**, the same reasoning as
## `GateBypassContractTest.RESOLVE_PATTERN`: a reference is the class name
## followed by optional whitespace and a `.`, the shape of
## `SomeSuite.run()`. A bare mention of a name in prose or in a string literal
## is not a call and grants nothing. That is what stops this file and its
## scanner test -- both of which are traversed, being registered -- from
## manufacturing reachability for the very files they are meant to judge, and
## it is why every synthetic fixture in the scanner test uses invented class
## names.
##
## Comments are stripped before matching, via
## `ExtractionContractTest.strip_comment()`; string literals are not, the same
## rule every scanner here follows. A `##` docstring naming a real suite class
## therefore creates no reachability, which is what makes the prose above safe
## to write.
##
## There is no exemption list, and none is wanted. Every file in the tree
## passes on its merits today.
##
## It catches the obvious violation, not a determined one: a suite invoked
## through a `Callable` built at runtime, or named by a string and called by
## reflection, passes unseen. That is the honest limit of a line scanner and
## the reason this runs on every build rather than on request.
class_name OrphanTestContractTest

## The one definition of what runs. Parsed, not imported: reading the array
## literal as text is what lets this file report on a bootstrap that has been
## reformatted or truncated, rather than silently agreeing with it.
const BOOTSTRAP_PATH := "res://tests/test_bootstrap.gd"

## Both test directories. `rules/tests/` holds the module's own suites and
## `tests/` the game-side ones; a file in either that never runs is the same
## failure.
const SCANNED_DIRS := ["res://rules/tests/", "res://tests/"]

## What makes a file a test file. `.uid` sidecars end in neither this nor
## anything else scanned, and `test_bootstrap.gd` deliberately does not match.
const TEST_SUFFIX := "_test.gd"

## The line that opens the `_suites` array literal.
const SUITES_DECLARATION := "var _suites"

## One registered suite per entry line: the identifier before `.run`. The
## receiver-qualified shape excludes the `func run()` declarations that every
## suite file carries.
const SUITE_ENTRY_PATTERN := "\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\.\\s*run\\b"

## A reference in call position. `\b` at the front stops a match starting in
## the middle of a longer identifier, so `MyAttackActionPushTest.run()` yields
## `MyAttackActionPushTest` and never `AttackActionPushTest`.
const REFERENCE_PATTERN := "\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\."

## A file-scope class declaration. Matched against the line with its left
## whitespace intact, so an inner class's indented declaration is not read as
## the file's own.
const CLASS_NAME_PREFIX := "class_name "

static var _suite_pattern: RegEx = null
static var _reference_pattern: RegEx = null


static func run() -> bool:
	var violations := scan()

	if violations.is_empty():
		return true

	printerr("\n=== Orphan Test Contract Violations ===")
	printerr("Every %s file under %s must be executed." % [TEST_SUFFIX, ", ".join(SCANNED_DIRS)])
	printerr(
		(
			"Add the suite to _suites in %s, call it from one that is there, or delete it."
			% BOOTSTRAP_PATH
		)
	)
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Scan the real tree and return one "path: Class is never executed" string per
## violation. Separated from run() so the scan is callable without the
## reporting.
##
## An empty registered set is itself reported, and is the first vacuity hazard
## this guard has to defend against. If the `_suites` literal is renamed,
## reformatted past what the parser reads, or moved, then nothing seeds the
## closure: every file becomes an orphan, or the check quietly stops meaning
## anything. Failing here names the bootstrap rather than burying it under
## twenty-eight spurious orphan reports.
static func scan() -> Array[String]:
	var registered := registered_suite_names()

	if registered.is_empty():
		var complaint := (
			"%s: no registered suites parsed from the %s array -- the closure has no seed"
			% [BOOTSTRAP_PATH, SUITES_DECLARATION]
		)
		return [complaint] as Array[String]

	return violations_for(registered, test_sources())


## Every test file that never runs, given the registered suite names and a
## `{path: source}` map.
##
## Pure and side-effect free -- no DirAccess, no FileAccess -- so
## OrphanTestScannerTest can exercise it on synthetic maps rather than by
## planting files in the tree. The source repo took the latter route and left
## four orphaned `.uid` files behind when its fixtures were deleted
## (EXTRACTION_LOG.md #23).
static func violations_for(registered_names: Array[String], sources: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	var declared := {}

	var paths := sources.keys()
	paths.sort()

	for path: String in paths:
		var declared_name := declared_class_name(sources[path])
		# A test file with no file-scope class_name can be neither registered
		# nor called, so it cannot run by any route this check recognises.
		if declared_name.is_empty():
			violations.append("%s: declares no class_name, so it can never be executed" % path)
			continue
		declared[path] = declared_name

	var reached := _reachable_names(registered_names, sources, declared)

	for path: String in declared:
		var declared_name: String = declared[path]
		if not reached.has(declared_name):
			violations.append("%s: %s is never executed" % [path, declared_name])

	return violations


## The suite class names registered in the real bootstrap.
static func registered_suite_names() -> Array[String]:
	return suite_names_in(ExtractionContractTest.read_file(BOOTSTRAP_PATH))


## The suite class names in a bootstrap source: the identifier before `.run` on
## each line of the `_suites` array literal.
##
## Pure, so the scanner test can pin what an unreadable or reformatted
## bootstrap parses to.
static func suite_names_in(source: String) -> Array[String]:
	var names: Array[String] = []
	var inside := false

	for raw_line in source.split("\n"):
		var line := ExtractionContractTest.strip_comment(raw_line).strip_edges()

		if not inside:
			inside = line.begins_with(SUITES_DECLARATION)
			continue

		if line == "]":
			break

		var found := _suite_regex().search(line)
		if found != null and found.get_string(1) not in names:
			names.append(found.get_string(1))

	return names


## Every `*_test.gd` under the scanned directories, as `{path: source}`.
static func test_sources() -> Dictionary:
	var sources := {}

	for scanned_dir in SCANNED_DIRS:
		for file_path in ExtractionContractTest.files_recursive(scanned_dir):
			if file_path.ends_with(TEST_SUFFIX):
				sources[file_path] = ExtractionContractTest.read_file(file_path)

	return sources


## Every identifier this source uses in call position, comments stripped.
##
## A `class_name` declaration line is skipped outright. `class_name Foo` has no
## `.` and so would not match anyway, but the second vacuity hazard is a file
## being read as reaching itself, and the defence against it should be written
## down rather than left as a property of the pattern.
static func references_in(source: String) -> Array[String]:
	var names: Array[String] = []

	for raw_line in source.split("\n"):
		var line := ExtractionContractTest.strip_comment(raw_line)
		if line.strip_edges(true, false).begins_with(CLASS_NAME_PREFIX):
			continue

		for found: RegExMatch in _reference_regex().search_all(line):
			var name := found.get_string(1)
			if name not in names:
				names.append(name)

	return names


## The file-scope `class_name` this source declares, or "" when it declares
## none.
##
## File scope only: the line is stripped on the right but not the left, so an
## inner class's indented `class_name` does not count. An inner class is not a
## suite the bootstrap could register.
static func declared_class_name(source: String) -> String:
	for raw_line in source.split("\n"):
		var line := ExtractionContractTest.strip_comment(raw_line).strip_edges(false, true)
		if not line.begins_with(CLASS_NAME_PREFIX):
			continue

		var rest := line.trim_prefix(CLASS_NAME_PREFIX).strip_edges()
		var space := rest.find(" ")
		return rest if space < 0 else rest.substr(0, space)

	return ""


## The transitive closure of executed class names, seeded from the registered
## set alone.
##
## Only a file already proven to run has its source read for further
## references, which is the whole point: a pair of orphans naming each other
## are never traversed, so neither is ever reached.
static func _reachable_names(
	registered_names: Array[String], sources: Dictionary, declared: Dictionary
) -> Dictionary:
	var reached := {}
	var pending: Array[String] = []

	for path: String in declared:
		var declared_name: String = declared[path]
		if declared_name in registered_names and not reached.has(declared_name):
			reached[declared_name] = true
			pending.append(path)

	while not pending.is_empty():
		var referenced := references_in(sources[pending.pop_back()])

		for path: String in declared:
			var declared_name: String = declared[path]
			if reached.has(declared_name):
				continue
			if declared_name in referenced:
				reached[declared_name] = true
				pending.append(path)

	return reached


## The compiled suite-entry pattern, built once and reused.
##
## A const cannot hold a compiled RegEx, and recompiling per line would make
## the parse quadratic in the size of the bootstrap for no benefit.
static func _suite_regex() -> RegEx:
	if _suite_pattern == null:
		_suite_pattern = RegEx.create_from_string(SUITE_ENTRY_PATTERN)
	return _suite_pattern


## The compiled reference pattern, built once and reused, for the same reason.
static func _reference_regex() -> RegEx:
	if _reference_pattern == null:
		_reference_pattern = RegEx.create_from_string(REFERENCE_PATTERN)
	return _reference_pattern

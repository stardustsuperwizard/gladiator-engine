## Inbound type contract test for the rules module.
##
## Fails the build if any file under rules/ references, in code, a global
## `class_name` declared under scripts/ or scenes/.
##
## This is the executable form of the first architectural commitment in
## `AGENTS.md`, from the direction `rules/tests/extraction_contract_test.gd`
## does not cover. That scanner catches `rules/` naming a game-side
## **path** -- a `preload()` or `load()` of `res://scripts/...`. It does not
## catch `rules/` naming a game-side **type** by its global `class_name`,
## which needs no path at all: GDScript's global class names are visible
## everywhere once registered, so `Authority.new(state)` compiles inside
## `rules/` with no `preload()` in sight. That gap is what
## `docs/godot-implementation-guide.md` §2 records as holding "by review, not
## by the build" -- this file is what makes it hold by the build.
##
## **The forbidden set is derived, never hand-written.** At scan time this
## walks res://scripts/ and res://scenes/ for .gd files and collects each
## one's file-scope `class_name` declaration, via
## `OrphanTestContractTest.declared_class_name()`. No literal game-side class
## name appears anywhere in this file: a hand-written list is a second copy
## of the truth, and the two would drift the moment a game-side file renamed
## or removed its `class_name` and nobody remembered to edit a list living in
## a different directory.
##
## **The empty-set vacuity guard.** If the derivation returns no names, that
## is reported as a violation naming the two source directories, rather than
## the scan passing clean. This is the same defence
## `OrphanTestContractTest.scan()` makes against an unparseable `_suites`
## array, and for the same reason: a derived check whose derivation silently
## returns nothing is a check that has stopped meaning anything while still
## going green.
##
## **It lives here, under tests/, not rules/tests/.** Two independent
## reasons:
##
## 1. This file must open res://scripts/ to derive its forbidden set, and a
##    file under rules/ naming that prefix fails
##    `rules/tests/extraction_contract_test.gd` -- the very commitment this
##    file exists to enforce from the other direction.
## 2. `InboundTypeScannerTest`, this file's self-test, must contain synthetic
##    lines naming a forbidden class in code position. Under rules/ those
##    string literals would be flagged by this very scanner, since string
##    literals are not stripped (below).
##
## This is the same placement `tests/gate_bypass_contract_test.gd` documents
## for the same two reasons, in the reverse direction: that file scans
## scripts/ and scenes/ for reaching into rules/ by path or by resolving;
## this one scans rules/ for reaching into scripts/ and scenes/ by type name.
##
## **Whole-identifier matching.** Each forbidden name is matched with a word
## boundary on both sides, so a name that merely appears as a substring of a
## longer identifier -- `authority_id`, `ActionRunnerish`, `_ActionRunner` --
## is not a reference to anything and is not reported.
##
## **Comments are stripped before scanning**, via
## `ExtractionContractTest.strip_comment()`. String literals are **not**
## stripped, matching every other scanner here: a forbidden name inside a
## string literal is reported, which is the safe direction to be wrong in.
## Triple-quoted strings spanning lines are not handled either, matching
## `strip_comment()`'s own documented limit -- a docstring line containing a
## forbidden name is reported, again the safe direction.
##
## **No `EXEMPT_FILES` list, and none is wanted.** This scanner reads
## res://rules/ only; tests/ is never among the scanned directories, so this
## file and its self-test pass on their merits without needing to exempt
## their own synthetic fixtures or derivation logic.
##
## It catches the obvious violation, not a determined one. A reference
## assembled from a string and resolved by reflection passes unseen; that
## needs a parser, not a line scanner. That is the honest limit of a
## lint-style check and the reason it runs on every build rather than on
## request.
class_name InboundTypeContractTest

## The one direction this file scans. Deliberately not scripts/ or scenes/ --
## the reverse direction is `GateBypassContractTest`'s job -- and deliberately
## not tests/, per the docstring above.
const RULES_DIR := "res://rules/"

## Where the forbidden set is derived from. `scenes/` holds only scene files
## today and contributes no `class_name`, which is expected, not a bug: a
## `.tscn` declares no global class of its own.
const FORBIDDEN_SOURCE_DIRS := ["res://scripts/", "res://scenes/"]

## Only .gd is scanned on either side: a `class_name` is a GDScript
## declaration, and a reference to one can only appear in GDScript.
const SCANNED_EXTENSION := ".gd"

static var _word_patterns: Dictionary = {}


static func run() -> bool:
	var violations := scan()

	if violations.is_empty():
		return true

	printerr("\n=== Inbound Type Contract Violations ===")
	printerr(
		(
			"Files in %s must not reference, by class_name, a type declared under %s."
			% [RULES_DIR, ", ".join(FORBIDDEN_SOURCE_DIRS)]
		)
	)
	printerr(
		"rules/ depends on nothing outside itself -- construct nothing from scripts/ or scenes/."
	)
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Scan rules/ and return one "path:line: Identifier" string per violation,
## against the forbidden set derived from the current tree. Separated from
## run() so the scan is callable without the reporting.
static func scan() -> Array[String]:
	return violations_for(forbidden_class_names())


## Every violation given an already-derived forbidden set.
##
## Separated from scan() so the empty-derivation guard can be pinned
## directly by InboundTypeScannerTest, without depending on scripts/ or
## scenes/ ever actually going empty in the real tree.
static func violations_for(forbidden: Array[String]) -> Array[String]:
	if forbidden.is_empty():
		return (
			[
				(
					"%s and %s yielded no class_name declarations -- the derivation is empty, so this check would enforce nothing"
					% [FORBIDDEN_SOURCE_DIRS[0], FORBIDDEN_SOURCE_DIRS[1]]
				)
			]
			as Array[String]
		)

	var violations: Array[String] = []

	for file_path in ExtractionContractTest.files_recursive(RULES_DIR):
		if not file_path.ends_with(SCANNED_EXTENSION):
			continue

		var content := ExtractionContractTest.read_file(file_path)
		if content.is_empty():
			continue

		var lines := content.split("\n")
		for line_num in range(lines.size()):
			for identifier in identifiers_in_line(lines[line_num], forbidden):
				violations.append("%s:%d: %s" % [file_path, line_num + 1, identifier])

	return violations


## True when this line references any name in forbidden.
##
## Pure and side-effect free so InboundTypeScannerTest can exercise it
## directly on synthetic lines rather than by planting violation files in the
## tree.
static func line_violates(line: String, forbidden: Array[String]) -> bool:
	return not identifiers_in_line(line, forbidden).is_empty()


## Every name in forbidden that this line references as a whole identifier,
## in the order forbidden lists them.
##
## Public rather than private because the whole-identifier guarantee is a
## contract worth pinning, and scan() cannot demonstrate it while rules/
## stays clean.
static func identifiers_in_line(line: String, forbidden: Array[String]) -> Array[String]:
	var code := ExtractionContractTest.strip_comment(line)
	var found: Array[String] = []

	for name in forbidden:
		if _word_pattern(name).search(code) != null:
			found.append(name)

	return found


## The forbidden set, derived from the current tree: every distinct
## file-scope class_name declared under FORBIDDEN_SOURCE_DIRS.
static func forbidden_class_names() -> Array[String]:
	return class_names_in(source_map())


## {path: source} for every .gd file under FORBIDDEN_SOURCE_DIRS.
static func source_map() -> Dictionary:
	var sources := {}

	for source_dir in FORBIDDEN_SOURCE_DIRS:
		for file_path in ExtractionContractTest.files_recursive(source_dir):
			if file_path.ends_with(SCANNED_EXTENSION):
				sources[file_path] = ExtractionContractTest.read_file(file_path)

	return sources


## Pure: every distinct file-scope class_name across the given {path: source}
## map, in path-sorted order.
##
## Public and pure so InboundTypeScannerTest can pin derivation behaviour --
## including the empty case -- against a synthetic map, without depending on
## scripts/ or scenes/ never changing shape.
static func class_names_in(sources: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var paths := sources.keys()
	paths.sort()

	for path: String in paths:
		var declared: String = OrphanTestContractTest.declared_class_name(sources[path])
		if not declared.is_empty() and declared not in names:
			names.append(declared)

	return names


## The compiled word-boundary pattern for one forbidden name, built once per
## name and reused.
##
## Cached in a Dictionary rather than a single const RegEx because the
## forbidden set is derived, not fixed -- there is no single pattern to
## precompile ahead of time.
static func _word_pattern(name: String) -> RegEx:
	if not _word_patterns.has(name):
		_word_patterns[name] = RegEx.create_from_string("\\b%s\\b" % name)
	return _word_patterns[name]

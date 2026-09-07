## Base class contract test for the rules module.
##
## Fails the build if any file under rules/ declares a file-scope `extends`
## whose target is not `RefCounted`, `Resource`, or a `class_name` declared
## under rules/ itself. `rules/` stays off the scene tree per AGENTS.md's
## second architectural commitment -- `Node`, `Control`, `Node2D`,
## `CharacterBody2D` and the rest of the engine's scene-tree hierarchy are all
## equally forbidden, and enumerating them as a blocklist is a losing game.
## An allowlist derived from what rules/ itself declares is the one that does
## not need editing every time a scene-tree class is invented.
##
## The allowlist is `RefCounted`, `Resource`, plus every file-scope
## `class_name` found by scanning res://rules/ -- so `AttackAction extends
## TurnAction` and `PassAction extends TurnAction` pass, and any future
## rules-side base class does too without an edit here.
##
## **No `extends` line at all is not a violation.** GDScript takes an implicit
## `RefCounted` when a file declares no `extends`, and 21 of the 22 files
## under rules/tests/ rely on exactly that -- only
## rules/tests/attack_action_push_test.gd writes `extends RefCounted`
## explicitly. A check that treated a missing `extends` as a violation would
## fail on its first run.
##
## **File scope only.** The `extends` line is matched with its left
## whitespace intact, the same rule OrphanTestContractTest.declared_class_name
## uses for `class_name`, and for the same reason: only a declaration at
## column 0 counts. An inner class's indented `extends Node`, and the
## one-line `class Foo extends Node:` form, both pass unseen. That is a
## documented limit of a line scanner, not a defect worked around here --
## extending this to a parser is a different task.
##
## **The vacuity guard.** If the walk of res://rules/ yields no .gd file to
## scan, that is reported as a violation rather than passing clean -- a
## scanner that has stopped finding its subject must say so, not go green.
## The defence is the same one OrphanTestContractTest.scan() makes against an
## unparseable `_suites`. The allowlist derivation needs no matching guard in
## the other direction: if it broke, `AttackAction extends TurnAction` would
## start failing, which is loud on its own.
##
## **class_name is parsed locally, not via OrphanTestContractTest.**
## OrphanTestContractTest.declared_class_name lives in res://tests/, which is
## game-side; a rules/ file reaching into it would invert the one-way
## dependency arrow this module exists to keep. declared_class_name_in below
## is a second, small copy of the same line-scanning rule for that reason.
##
## Comments are stripped before matching, via
## ExtractionContractTest.strip_comment(); string literals are not, the same
## rule every scanner here follows. That is what makes the quoted-path form
## `extends "res://rules/state/turn_action.gd"` a violation: it names no
## allowlisted identifier.
##
## It catches the obvious violation, not a determined one. That is the honest
## limit of a lint-style text scanner and the reason it runs on every build
## rather than on request.
class_name BaseClassContractTest

const RULES_DIR := "res://rules/"
const SCANNED_EXTENSION := ".gd"

## The two built-ins permitted regardless of what rules/ declares. Everything
## else in the allowlist is derived by scanning, never hand-listed.
const ALLOWED_BUILTINS: Array[String] = ["RefCounted", "Resource"]

const EXTENDS_PREFIX := "extends "
const CLASS_NAME_PREFIX := "class_name "


static func run() -> bool:
	var violations := scan()

	if violations.is_empty():
		return true

	printerr("\n=== Base Class Contract Violations ===")
	printerr(
		"Files in rules/ must extend RefCounted, Resource, or a class_name declared under rules/."
	)
	printerr("rules/ stays off the scene tree -- see AGENTS.md's second architectural commitment.")
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Scan rules/ and return one "path:line: extends X" string per violation.
## Separated from run() so the scan is callable without the reporting.
static func scan() -> Array[String]:
	return result_for(rules_sources())


## The vacuity-guarded computation scan() performs, given a `{path: source}`
## map instead of the real tree.
##
## Pure so BaseClassScannerTest can pin the empty-scan guard directly, rather
## than depending on res://rules/ itself ever becoming momentarily empty. An
## empty map is the first vacuity hazard this guard defends against: if the
## walk of res://rules/ yields no .gd file, nothing is being checked, and that
## is reported rather than passed clean.
static func result_for(sources: Dictionary) -> Array[String]:
	if sources.is_empty():
		var complaint := (
			"%s: no .gd file found under this path -- the scan has nothing to check" % RULES_DIR
		)
		return [complaint] as Array[String]

	return violations_for(allowed_names_for(sources), sources)


## Every file-scope base class violation, given an allowlist and a
## `{path: source}` map.
##
## Pure and side-effect free -- no DirAccess, no FileAccess -- so
## BaseClassScannerTest can exercise it on synthetic maps rather than by
## planting files in the tree. The source repo took the latter route and left
## four orphaned .uid files behind when its fixtures were deleted
## (EXTRACTION_LOG.md #23).
static func violations_for(allowed_names: Array[String], sources: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	var paths := sources.keys()
	paths.sort()

	for path: String in paths:
		var declaration := _extends_declaration(sources[path])
		if declaration.is_empty():
			continue

		var base_class: String = declaration["base"]
		if base_class not in allowed_names:
			violations.append("%s:%d: extends %s" % [path, declaration["line"], base_class])

	return violations


## The file-scope `extends` target this source declares, or "" when it
## declares none.
##
## File scope only: the line is stripped on the right but not the left, so an
## inner class's indented `extends` does not count, and a file that takes
## GDScript's implicit RefCounted -- declaring no `extends` line at all --
## returns "" rather than being misread as a violation.
static func declared_base_class(source: String) -> String:
	var declaration := _extends_declaration(source)
	return declaration.get("base", "")


## The file-scope `class_name` this source declares, or "" when it declares
## none.
##
## A second, small copy of OrphanTestContractTest.declared_class_name's rule
## rather than a call to it: that helper lives in res://tests/, game-side, and
## rules/ may not reach into game-side test infrastructure without inverting
## the one-way dependency arrow this module exists to keep.
static func declared_class_name_in(source: String) -> String:
	for raw_line in source.split("\n"):
		var line := ExtractionContractTest.strip_comment(raw_line).strip_edges(false, true)
		if not line.begins_with(CLASS_NAME_PREFIX):
			continue

		var rest := line.trim_prefix(CLASS_NAME_PREFIX).strip_edges()
		var space := rest.find(" ")
		return rest if space < 0 else rest.substr(0, space)

	return ""


## The allowlist for a given `{path: source}` map: the two built-ins plus
## every file-scope `class_name` found among the sources.
##
## Pure so the derivation itself is testable on synthetic input, and so
## real_allowed_base_classes() below is nothing more than this applied to the
## real tree.
static func allowed_names_for(sources: Dictionary) -> Array[String]:
	var allowed: Array[String] = ALLOWED_BUILTINS.duplicate()

	var paths := sources.keys()
	paths.sort()

	for path: String in paths:
		var declared := declared_class_name_in(sources[path])
		if not declared.is_empty() and declared not in allowed:
			allowed.append(declared)

	return allowed


## The allowlist derived from the real rules/ tree.
static func real_allowed_base_classes() -> Array[String]:
	return allowed_names_for(rules_sources())


## Every .gd file under rules/, as `{path: source}`.
static func rules_sources() -> Dictionary:
	var sources := {}

	for file_path in ExtractionContractTest.files_recursive(RULES_DIR):
		if file_path.ends_with(SCANNED_EXTENSION):
			sources[file_path] = ExtractionContractTest.read_file(file_path)

	return sources


## The file-scope `extends` declaration in this source, as
## `{"line": int, "base": String}` (1-indexed), or `{}` when none is declared.
##
## Kept private: declared_base_class() and violations_for() are the two
## public shapes callers need, one without the line number and one with.
static func _extends_declaration(source: String) -> Dictionary:
	var lines := source.split("\n")

	for i in range(lines.size()):
		# Stripped on the right but not the left, the same rule
		# OrphanTestContractTest.declared_class_name uses: an indented line
		# fails begins_with() and is silently skipped, which is what confines
		# this to file scope.
		var line := ExtractionContractTest.strip_comment(lines[i]).strip_edges(false, true)
		if not line.begins_with(EXTENDS_PREFIX):
			continue

		var base_class := line.trim_prefix(EXTENDS_PREFIX).strip_edges()
		return {"line": i + 1, "base": base_class}

	return {}

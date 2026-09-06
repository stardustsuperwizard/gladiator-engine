## Gate bypass contract test for the game side.
##
## Fails the build if any file under scripts/ or scenes/ reaches into the rules
## module by path, or resolves an action itself.
##
## This is the executable form of the second architectural commitment in
## `AGENTS.md`: UI gathers intent, the authority validates and resolves, the UI
## renders what comes back. `scripts/action_runner.gd` is the one place
## entitled to resolve, and everything else asks it. If hotseat ever resolves
## directly the calling convention has to be rebuilt for AI, undo, replays and
## networking alike, and the gate becomes decoration.
##
## **This is the reverse arrow, and it is a second test.**
## `rules/tests/extraction_contract_test.gd` enforces that `rules/` never names
## `scripts/`; this one enforces that `scripts/` never bypasses the gate. The
## two are separate files on purpose and neither is an edit to the other. It
## lives here rather than under `rules/tests/` because a test that scans
## `res://scripts/` is game-side code -- putting it in the rules module would
## make it a rules file naming a forbidden prefix, needing an exemption in a
## list that exists for something else entirely.
##
## **The two violation classes.**
##
## 1. Any occurrence of `res://rules/` -- a `preload()`, a `load()`, or an
##    `[ext_resource]` line in a `.tscn`. A scene attaching a script from
##    `res://rules/` is a `Node` subclassing rules code, the violation in its
##    most direct form, which is why scenes are scanned at all.
## 2. Any receiver-qualified call to `resolve(` -- that is, `.resolve(`.
##    Resolving is precisely the operation the gate owns.
##
## **What is explicitly permitted.** Naming a `rules/` type by its global
## `class_name` in order to *construct* a command or *read* a result --
## `PassAction.new("f1")`, `result.success`, `TurnResult` as a return type --
## is legal and is not flagged. A view that could not name an action type could
## not gather intent, and a view that could not name a result could not render
## one. The line drawn here is *who resolves*, not *who may say a type's name*,
## which is also why `scripts/authority.gd` needs no exemption: it names rules
## types throughout and resolves nothing, so it passes on its merits.
##
## **The scanner needs no self-exemption.** `tests/` is not among the scanned
## directories, so this file's own `res://rules/` and `.resolve(` literals are
## never read as violations. That asymmetry with the two contract tests under
## `rules/tests/` -- which do scan their own directory and so do carry
## exemptions -- is deliberate, not an oversight to be "fixed".
##
## Comments are stripped before scanning GDScript, via
## `ExtractionContractTest.strip_comment()`. String literals are not stripped:
## `var s := "res://rules/"` is reported, which is the safe direction to be
## wrong in. Scene files are not comment-stripped at all, since `#` carries no
## comment meaning in `.tscn`.
##
## It catches the obvious violation, not a determined one. A `Callable`
## reference taken without parentheses (`var f := action.resolve`) and a call
## assembled from a string and invoked by reflection both pass unseen;
## detecting those needs a parser, not a line scanner. That is the honest limit
## of a lint-style check and the reason it runs on every build rather than on
## request.
class_name GateBypassContractTest

## The game-side directories. Deliberately not `res://resources/` -- data files
## declare no dependency and call nothing -- and deliberately not `tests/`, per
## the docstring above.
const SCANNED_DIRS := ["res://scripts/", "res://scenes/"]

## Violation class one: any mention of the rules module by path.
const FORBIDDEN_PREFIX := "res://rules/"

## Violation class two, as reported. The receiver is the whole point: a bare
## `resolve(` with nothing before the name is a declaration or a call on
## `self`, and `TurnAction.resolve()` is declared in `rules/`, never here.
const RESOLVE_CALL := ".resolve("

## The receiver-qualified call pattern. The literal "." excludes
## `func resolve(state: GameState) -> TurnResult:`, which has no receiver, and
## requiring "(" immediately after the name (whitespace aside) excludes
## `.resolve_all(` and `.resolved`.
const RESOLVE_PATTERN := "\\.resolve\\s*\\("

## `.gd` for both violation classes, `.tscn` for the path one. `.uid` sidecars
## end in neither and are skipped.
const SCANNED_EXTENSIONS := [".gd", ".tscn"]

## The one file entitled to resolve.
##
## Full paths, not filenames, for the reason the two contract tests under
## `rules/tests/` both give: a suffix match would exempt any future file
## anywhere that happened to take the name, which is a standing invitation to
## park a real bypass in a file named after the runner. Do not exempt a
## directory, and do not add `res://scripts/authority.gd` -- it passes on its
## merits today, and an exemption would hide it later starting not to.
const EXEMPT_FILES := ["res://scripts/action_runner.gd"]

static var _pattern: RegEx = null


static func run() -> bool:
	var violations := scan()

	if violations.is_empty():
		return true

	printerr("\n=== Gate Bypass Contract Violations ===")
	printerr(
		(
			"Files in %s must not reference %s or call %s."
			% [", ".join(SCANNED_DIRS), FORBIDDEN_PREFIX, RESOLVE_CALL]
		)
	)
	printerr("Submit the action through ActionRunner and render the TurnResult it returns.")
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Scan the game-side directories and return one "path:line: what" string per
## violation. Separated from run() so the scan is callable without the
## reporting.
static func scan() -> Array[String]:
	var violations: Array[String] = []

	for scanned_dir in SCANNED_DIRS:
		for file_path in ExtractionContractTest.files_recursive(scanned_dir):
			if file_path in EXEMPT_FILES:
				continue
			if not _is_scanned(file_path):
				continue

			var content := ExtractionContractTest.read_file(file_path)
			if content.is_empty():
				continue

			var is_gdscript := file_path.ends_with(".gd")
			var lines := content.split("\n")
			for line_num in range(lines.size()):
				for what in violations_in_line(lines[line_num], is_gdscript):
					violations.append("%s:%d: %s" % [file_path, line_num + 1, what])

	return violations


## True when this line either names the rules module by path or resolves.
##
## Pure and side-effect free so GateBypassScannerTest can exercise it directly
## on synthetic lines rather than by planting violation files in the tree.
static func line_violates(line: String, is_gdscript: bool) -> bool:
	return not violations_in_line(line, is_gdscript).is_empty()


## Every violation this line commits, as the strings scan() reports.
##
## `is_gdscript` does two jobs, and both follow from the same fact. In GDScript
## a `#` starts a comment, so the line is stripped first; in a `.tscn` it does
## not, so the line is read whole. And a `.resolve(` in a scene file is inert
## text in a serialised property, not a call, so only the path class applies
## there. A scene bypasses the gate by attaching rules code, not by invoking
## it.
##
## Public rather than private because the report wording is a contract worth
## pinning, and scan() cannot demonstrate it while the game side is clean.
static func violations_in_line(line: String, is_gdscript: bool) -> Array[String]:
	var code := ExtractionContractTest.strip_comment(line) if is_gdscript else line
	var found: Array[String] = []

	if FORBIDDEN_PREFIX in code:
		found.append(FORBIDDEN_PREFIX)

	if is_gdscript and _resolve_pattern().search(code) != null:
		found.append(RESOLVE_CALL)

	return found


static func _is_scanned(file_path: String) -> bool:
	for extension in SCANNED_EXTENSIONS:
		if file_path.ends_with(extension):
			return true
	return false


## The compiled pattern, built once and reused.
##
## A const cannot hold a compiled RegEx, and recompiling per line would make
## the scan quadratic in the size of the game side for no benefit.
static func _resolve_pattern() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.create_from_string(RESOLVE_PATTERN)
	return _pattern

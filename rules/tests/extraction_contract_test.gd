## Extraction contract test for the rules module.
##
## Fails the build if any file under rules/ references res://scripts/,
## res://scenes/, or res://resources/.
##
## This enforces the one-way dependency arrow: the game depends on rules/,
## never the reverse. That isolation is what lets the same simulation run
## identically wherever it runs -- hotseat, a client, or a headless server.
##
## GDScript has no module system and `class_name` is global, so nothing
## structural prevents a violation. This scanner is the enforcement. It catches
## the obvious violation, not a determined one; that is the honest limit of a
## lint-style check and the reason it runs on every build rather than on
## request.
##
## Adapted from mikeys_game_bones-rules-moba (EXTRACTION_LOG.md #2). The
## source version stripped comments with `line.split("#")[0]`, which silently
## truncates any line carrying a `#` inside a string literal and lets a real
## violation past. strip_comment() below is quote-aware; ContractScannerTest
## pins that behaviour.
class_name ExtractionContractTest

const RULES_DIR := "res://rules/"
const FORBIDDEN_PREFIXES := ["res://scripts/", "res://scenes/", "res://resources/"]
const SCANNED_EXTENSIONS := [".gd", ".json", ".tres"]

## Contract tests that name a forbidden prefix as scan-target data rather than
## depending on it. A forbidden prefix in a scanner's path list is a string
## opened with DirAccess, not a type called or a scene loaded, so the module
## still runs standalone.
##
## Full paths, not filenames: a suffix match would exempt any future file
## anywhere under rules/ that happened to carry one of these names, which is a
## standing invitation to park a real violation in a file named after a
## contract test. Every entry must be a contract test whose only
## forbidden-prefix occurrences are in that path-list role. Do not add
## ordinary rules code.
const EXEMPT_FILES := [
	"res://rules/tests/extraction_contract_test.gd",
	"res://rules/tests/contract_scanner_test.gd",
]


static func run() -> bool:
	var violations := scan()

	if violations.is_empty():
		return true

	printerr("\n=== Extraction Contract Violations ===")
	printerr("Files in rules/ must not reference %s" % ", ".join(FORBIDDEN_PREFIXES))
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Scan rules/ and return one "path:line: prefix" string per violation.
## Separated from run() so the scan is callable without the reporting.
static func scan() -> Array[String]:
	var violations: Array[String] = []

	for file_path in _get_files_recursive(RULES_DIR):
		if file_path in EXEMPT_FILES:
			continue
		if not _is_scanned(file_path):
			continue

		var content := _read_file(file_path)
		if content.is_empty():
			continue

		var is_gdscript := file_path.ends_with(".gd")
		var lines := content.split("\n")
		for line_num in range(lines.size()):
			for prefix in FORBIDDEN_PREFIXES:
				if line_violates(lines[line_num], prefix, is_gdscript):
					violations.append("%s:%d: %s" % [file_path, line_num + 1, prefix])

	return violations


## True when this line references the forbidden prefix in code.
##
## Pure and side-effect free so ContractScannerTest can exercise it directly on
## synthetic lines rather than by planting violation files in the tree -- the
## source repo took the latter route and left four orphaned .uid files behind
## when the fixtures were deleted.
static func line_violates(line: String, forbidden: String, is_gdscript: bool) -> bool:
	var code := strip_comment(line) if is_gdscript else line
	return forbidden in code


## Return the line with any GDScript comment removed.
##
## Quote-aware: a `#` inside a string literal is content, not a comment, and
## truncating there would hide whatever followed it on the line. Handles both
## quote styles and backslash escapes. Does not handle triple-quoted strings
## spanning lines -- a docstring line containing a forbidden prefix is reported,
## which is the safe direction to be wrong in.
static func strip_comment(line: String) -> String:
	var in_single := false
	var in_double := false
	var i := 0

	while i < line.length():
		var c := line[i]

		if c == "\\" and (in_single or in_double):
			i += 2
			continue

		if c == "\"" and not in_single:
			in_double = not in_double
		elif c == "'" and not in_double:
			in_single = not in_single
		elif c == "#" and not in_single and not in_double:
			return line.substr(0, i)

		i += 1

	return line


static func _is_scanned(file_path: String) -> bool:
	for extension in SCANNED_EXTENSIONS:
		if file_path.ends_with(extension):
			return true
	return false


static func _get_files_recursive(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)

	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not file_name.begins_with("."):
			var full_path := dir_path.path_join(file_name)
			if dir.current_is_dir():
				files.append_array(_get_files_recursive(full_path))
			else:
				files.append(full_path)
		file_name = dir.get_next()

	dir.list_dir_end()
	return files


static func _read_file(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

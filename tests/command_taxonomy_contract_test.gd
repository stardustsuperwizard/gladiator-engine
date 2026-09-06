## Command taxonomy contract test: adding a command needs no edit to the gate.
##
## Two halves, and both are load-bearing.
##
## Behaviourally, this file declares its own `TurnAction` subclass -- one that
## exists nowhere else in the project and that `ActionRunner` and `Authority`
## have never heard of -- and runs it through the gate twice: once as the
## active player who owns the actor, expecting success, and once as a different
## requester, expecting refusal. It works because generality comes from
## subclassing `resolve()`, not from a lookup keyed on a command kind.
##
## Structurally, it scans `res://scripts/action_runner.gd` and
## `res://scripts/authority.gd` for the name of every concrete `TurnAction`
## subclass declared under `res://rules/`, and fails if either file mentions
## one. Discovering the names by scanning rather than listing them means this
## check stays correct as commands are added, instead of pinning today's single
## `PassAction` and quietly missing tomorrow's Attack.
##
## The name matches the source repo's equivalent (`AUDIT_NOTES.md` Q1). It
## lives under `tests/` rather than `rules/tests/` because it names
## `res://scripts/` paths, which `rules/tests/extraction_contract_test.gd`
## fails the build over -- and it is game-side code besides.
class_name CommandTaxonomyContractTest

## The two files that must never name a concrete command.
const GATE_FILES := ["res://scripts/action_runner.gd", "res://scripts/authority.gd"]

const RULES_DIR := "res://rules/"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_unknown_subclass_resolves_when_permitted())
	violations.append_array(_test_unknown_subclass_is_refused_when_not())
	violations.append_array(_test_gate_files_exist())
	violations.append_array(_test_gate_names_no_concrete_command())

	if violations.is_empty():
		return true

	printerr("\n=== Command Taxonomy Contract Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(1))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	return state


## A command that exists only inside this test file, with its own `FAILURE_*`
## block and its own effect on the state. Nothing in `scripts/` names it,
## nothing registered it, and no dispatch table was updated to admit it -- the
## entire cost of adding a command is this declaration.
class _StandInAction:
	extends TurnAction
	const FAILURE_STAND_IN := &"command_taxonomy_test_stand_in"

	var resolve_calls: int = 0

	func resolve(state: GameState) -> TurnResult:
		resolve_calls += 1
		if actor_id() not in state.fighter_ids():
			return TurnResult.failure(FAILURE_STAND_IN)
		state.round_number += 1
		return TurnResult.ok()


## Run one: the active player, acting with a fighter they own.
static func _test_unknown_subclass_resolves_when_permitted() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var runner := ActionRunner.new(Authority.new(state))
	var action := _StandInAction.new("f1")
	var before_round := state.round_number

	var result := runner.run(action, "p1")

	violations.append_array(
		_expect(
			result.success,
			(
				"a TurnAction subclass declared inside this test must resolve successfully through "
				+ "ActionRunner with no gate edit"
			)
		)
	)
	violations.append_array(
		_expect(action.resolve_calls == 1, "the permitted stand-in must have resolved exactly once")
	)
	violations.append_array(
		_expect(
			state.round_number == before_round + 1,
			"the permitted stand-in's own effect on the state must have been applied"
		)
	)

	return violations


## Run two: a different requester, whose turn it is not. Refused with an
## `Authority` constant, and never resolved -- the gate is as blind to this
## subclass on the refusal path as it is on the success path.
static func _test_unknown_subclass_is_refused_when_not() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var runner := ActionRunner.new(Authority.new(state))
	var action := _StandInAction.new("f1")
	var before_digest := state.digest()

	var result := runner.run(action, "p2")

	violations.append_array(
		_expect(
			not result.success,
			"the same stand-in submitted by a player whose turn it is not must be refused"
		)
	)
	violations.append_array(
		_expect(
			result.reason == Authority.REFUSED_NOT_YOUR_TURN,
			"the refusal must carry an Authority constant, not the stand-in's own FAILURE_*"
		)
	)
	violations.append_array(
		_expect(action.resolve_calls == 0, "the refused stand-in must not have been resolved")
	)
	violations.append_array(
		_expect(
			state.digest() == before_digest,
			"the refused stand-in must leave the state digest identical"
		)
	)

	return violations


## A missing gate file would make the scan below pass vacuously.
static func _test_gate_files_exist() -> Array[String]:
	var violations: Array[String] = []

	for path in GATE_FILES:
		violations.append_array(
			_expect(
				not ExtractionContractTest.read_file(path).is_empty(),
				"%s must exist and be readable" % path
			)
		)

	return violations


## No concrete command may be named in the gate. The names are discovered by
## scanning `rules/` for files that both declare a `class_name` and extend
## `TurnAction`, so this stays honest as commands are added.
static func _test_gate_names_no_concrete_command() -> Array[String]:
	var violations: Array[String] = []
	var commands := _concrete_command_names()

	violations.append_array(
		_expect(
			not commands.is_empty(),
			(
				"the scan must find at least one concrete TurnAction subclass under rules/ -- "
				+ "finding none would make this contract pass vacuously"
			)
		)
	)
	violations.append_array(
		_expect(
			"PassAction" in commands, "the scan must find PassAction, the command this task shipped"
		)
	)

	for path in GATE_FILES:
		var content := ExtractionContractTest.read_file(path)
		for command in commands:
			(
				violations
				. append_array(
					_expect(
						command not in content,
						(
							(
								"%s must not name the concrete command %s -- adding a command must need no "
								% [path, command]
							)
							+ "edit to the gate"
						)
					)
				)
			)

	return violations


## Every `class_name` declared by a file under `rules/` that also extends
## `TurnAction` at file scope.
##
## Deliberately file-scope only: `extends TurnAction` indented inside a test's
## inner class is not a shipped command, and the inner class's name is not a
## global one the gate could name anyway.
static func _concrete_command_names() -> Array[String]:
	var names: Array[String] = []

	for file_path in ExtractionContractTest.files_recursive(RULES_DIR):
		if not file_path.ends_with(".gd"):
			continue

		var content := ExtractionContractTest.read_file(file_path)
		if content.is_empty():
			continue

		var declared := ""
		var extends_turn_action := false
		for raw_line in content.split("\n"):
			var line := ExtractionContractTest.strip_comment(raw_line).strip_edges(false, true)
			if line.begins_with("class_name "):
				declared = line.trim_prefix("class_name ").strip_edges()
			elif line == "extends TurnAction":
				extends_turn_action = true

		if extends_turn_action and not declared.is_empty():
			names.append(declared)

	return names

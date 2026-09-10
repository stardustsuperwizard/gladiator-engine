## Tests `FighterTemplates`: registration and its refusals, `template()` and
## `template_for()` and every way each returns `null`, identity (never a
## copy), `templates_by_fighter()`'s shape, `from_directory()` against the real
## authored roster, and that every call above leaves `state.digest()` and
## `state.rng.get_state()` untouched.
##
## Lives under `tests/` rather than `rules/tests/` for the same reason
## `tests/authority_test.gd` and `tests/resource_data_test.gd` do:
## `FighterTemplates` is `res://scripts/` code, and loading
## `res://resources/fighters/` is ordinary game-side code that cannot live
## under `rules/`.
class_name FighterTemplatesTest

const WARRIOR_PATH := "res://resources/fighters/warrior.tres"
const ARCHER_PATH := "res://resources/fighters/archer.tres"
const CONSTRUCTION_BUDGET_PATH := "res://resources/fighters/construction_budget.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_register_refuses_null())
	violations.append_array(_test_register_refuses_empty_template_id())
	violations.append_array(_test_register_refuses_duplicate())
	violations.append_array(_test_template_returns_null_for_unknown_id())
	violations.append_array(_test_template_returns_the_registered_object())
	violations.append_array(_test_template_for_returns_registered_template())
	violations.append_array(_test_template_for_returns_null_for_unknown_fighter())
	violations.append_array(_test_template_for_returns_null_for_missing_template_id())
	violations.append_array(_test_template_for_returns_null_for_non_string_template_id())
	violations.append_array(_test_template_for_returns_null_for_unregistered_template_id())
	violations.append_array(_test_shared_template_is_identical_across_fighters())
	violations.append_array(_test_templates_by_fighter_shape())
	violations.append_array(_test_templates_by_fighter_empty_state())
	violations.append_array(_test_from_directory_finds_warrior_and_archer())
	violations.append_array(_test_from_directory_skips_construction_budget())
	violations.append_array(_test_from_directory_unreadable_path_yields_empty_instance())
	violations.append_array(_test_calls_leave_state_untouched())

	if violations.is_empty():
		return true

	printerr("\n=== Fighter Templates Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## An in-memory template, never loaded from disk, so identity tests cannot be
## satisfied by accident through Resource's load cache.
static func _make_template(id: String) -> FighterTemplate:
	var made := FighterTemplate.new()
	made.template_id = id
	return made


static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(1))
	state.add_player("p1")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1", "template_id": "warrior"})
	state.add_fighter("f2", {"id": "f2", "owner_id": "p1", "template_id": "archer"})
	return state


static func _test_register_refuses_null() -> Array[String]:
	var templates := FighterTemplates.new()

	return _expect(not templates.register(null), "register(null) must return false")


static func _test_register_refuses_empty_template_id() -> Array[String]:
	var templates := FighterTemplates.new()
	var made := _make_template("")

	return _expect(
		not templates.register(made), "register() must refuse a template with an empty template_id"
	)


static func _test_register_refuses_duplicate() -> Array[String]:
	var violations: Array[String] = []
	var templates := FighterTemplates.new()
	var first := _make_template("warrior")
	var second := _make_template("warrior")

	violations.append_array(
		_expect(templates.register(first), "the first register() of a template_id must succeed")
	)
	(
		violations
		. append_array(
			_expect(
				not templates.register(second),
				"register() must refuse a second template registered under an already-registered template_id"
			)
		)
	)
	violations.append_array(
		_expect(
			is_same(templates.template("warrior"), first),
			"a refused duplicate register() must leave the originally registered template in place"
		)
	)

	return violations


static func _test_template_returns_null_for_unknown_id() -> Array[String]:
	var templates := FighterTemplates.new()

	return _expect(
		templates.template("no_such_template") == null,
		"template() must return null for an unregistered template_id"
	)


static func _test_template_returns_the_registered_object() -> Array[String]:
	var templates := FighterTemplates.new()
	var made := _make_template("warrior")
	templates.register(made)

	return _expect(
		is_same(templates.template("warrior"), made),
		"template() must return the identical object that was registered"
	)


static func _test_template_for_returns_registered_template() -> Array[String]:
	var templates := FighterTemplates.new()
	var made := _make_template("warrior")
	templates.register(made)
	var state := _build_state()

	return _expect(
		is_same(templates.template_for(state, "f1"), made),
		"template_for() must return the registered FighterTemplate named by the fighter's template_id"
	)


static func _test_template_for_returns_null_for_unknown_fighter() -> Array[String]:
	var templates := FighterTemplates.new()
	templates.register(_make_template("warrior"))
	var state := _build_state()

	return _expect(
		templates.template_for(state, "no_such_fighter") == null,
		"template_for() must return null for a fighter id the state does not hold"
	)


static func _test_template_for_returns_null_for_missing_template_id() -> Array[String]:
	var templates := FighterTemplates.new()
	templates.register(_make_template("warrior"))
	var state := _build_state()
	state.add_fighter("no_template", {"id": "no_template", "owner_id": "p1"})

	return _expect(
		templates.template_for(state, "no_template") == null,
		'template_for() must return null when the payload has no "template_id" key'
	)


static func _test_template_for_returns_null_for_non_string_template_id() -> Array[String]:
	var templates := FighterTemplates.new()
	templates.register(_make_template("warrior"))
	var state := _build_state()
	state.add_fighter("bad_template", {"id": "bad_template", "owner_id": "p1", "template_id": 7})

	return _expect(
		templates.template_for(state, "bad_template") == null,
		'template_for() must return null when "template_id" is not a String'
	)


static func _test_template_for_returns_null_for_unregistered_template_id() -> Array[String]:
	var templates := FighterTemplates.new()
	var state := _build_state()

	return _expect(
		templates.template_for(state, "f1") == null,
		"template_for() must return null when the named template_id was never registered"
	)


## The parent scenario: two fighters built from one registered template keep
## sharing the identical object.
static func _test_shared_template_is_identical_across_fighters() -> Array[String]:
	var violations: Array[String] = []
	var templates := FighterTemplates.new()
	var made := _make_template("warrior")
	templates.register(made)

	var state := GameState.new(Board.new(), DeterministicRng.new(1))
	state.add_player("p1")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1", "template_id": "warrior"})
	state.add_fighter("f2", {"id": "f2", "owner_id": "p1", "template_id": "warrior"})

	var first := templates.template_for(state, "f1")
	var second := templates.template_for(state, "f2")

	violations.append_array(
		_expect(
			is_same(first, second),
			"two fighters built from one template_id must be handed the identical FighterTemplate"
		)
	)
	violations.append_array(
		_expect(
			is_same(first, made),
			"the shared template must be the identical object that was registered"
		)
	)

	return violations


## A state with two fighters whose templates are known and one whose template
## is not returns exactly two entries, keyed by fighter id.
static func _test_templates_by_fighter_shape() -> Array[String]:
	var violations: Array[String] = []
	var templates := FighterTemplates.new()
	var warrior := _make_template("warrior")
	var archer := _make_template("archer")
	templates.register(warrior)
	templates.register(archer)

	var state := _build_state()
	state.add_fighter("f3", {"id": "f3", "owner_id": "p1", "template_id": "unregistered"})

	var by_fighter := templates.templates_by_fighter(state)

	violations.append_array(
		_expect(
			by_fighter.size() == 2,
			"templates_by_fighter() must hold exactly one entry per fighter with a known template"
		)
	)
	violations.append_array(
		_expect(
			is_same(by_fighter.get("f1"), warrior),
			'templates_by_fighter()["f1"] must be the identical warrior template'
		)
	)
	violations.append_array(
		_expect(
			is_same(by_fighter.get("f2"), archer),
			'templates_by_fighter()["f2"] must be the identical archer template'
		)
	)
	violations.append_array(
		_expect(
			not by_fighter.has("f3"),
			"templates_by_fighter() must omit a fighter whose template_id was never registered"
		)
	)

	return violations


static func _test_templates_by_fighter_empty_state() -> Array[String]:
	var templates := FighterTemplates.new()
	var state := GameState.new(Board.new(), DeterministicRng.new(1))

	return _expect(
		templates.templates_by_fighter(state).is_empty(),
		"templates_by_fighter() on a state with no fighters must return an empty Dictionary"
	)


static func _test_from_directory_finds_warrior_and_archer() -> Array[String]:
	var violations: Array[String] = []
	var templates := FighterTemplates.from_directory()

	var warrior := templates.template("warrior")
	violations.append_array(
		_expect(
			warrior != null,
			'from_directory() over the default path must register a template_id "warrior"'
		)
	)
	if warrior != null:
		(
			violations
			. append_array(
				_expect(
					is_same(warrior, load(WARRIOR_PATH)),
					"the registered warrior template must be the same object load() returns for warrior.tres"
				)
			)
		)

	var archer := templates.template("archer")
	violations.append_array(
		_expect(
			archer != null,
			'from_directory() over the default path must register a template_id "archer"'
		)
	)
	if archer != null:
		(
			violations
			. append_array(
				_expect(
					is_same(archer, load(ARCHER_PATH)),
					"the registered archer template must be the same object load() returns for archer.tres"
				)
			)
		)

	return violations


## construction_budget.tres shares resources/fighters/ with warrior.tres and
## archer.tres and loads as a ConstructionBudget, not a FighterTemplate --
## from_directory()'s `resource is FighterTemplate` filter must skip it rather
## than registering it under some id, or crashing trying to read one.
static func _test_from_directory_skips_construction_budget() -> Array[String]:
	var violations: Array[String] = []

	var budget: Variant = load(CONSTRUCTION_BUDGET_PATH)
	violations.append_array(
		_expect(
			not (budget is FighterTemplate),
			(
				"construction_budget.tres must not load as a FighterTemplate, or this test cannot "
				+ "tell a skip from a registration"
			)
		)
	)

	# from_directory() must not have stumbled over construction_budget.tres:
	# it still finds the two real templates that share its directory.
	var templates := FighterTemplates.from_directory()
	violations.append_array(
		_expect(
			templates.template("warrior") != null and templates.template("archer") != null,
			(
				"from_directory() must still register warrior and archer despite "
				+ "construction_budget.tres sharing their directory"
			)
		)
	)

	return violations


static func _test_from_directory_unreadable_path_yields_empty_instance() -> Array[String]:
	var violations: Array[String] = []
	var templates := FighterTemplates.from_directory("res://no_such_directory_at_all/")

	violations.append_array(
		_expect(
			templates != null,
			"from_directory() over an unreadable path must still return a usable instance, not null"
		)
	)
	violations.append_array(
		_expect(
			templates.template("warrior") == null,
			"from_directory() over an unreadable path must register nothing"
		)
	)

	return violations


## Every read above -- refusal(), template(), template_for(),
## templates_by_fighter() -- must leave the state exactly as it found it.
static func _test_calls_leave_state_untouched() -> Array[String]:
	var violations: Array[String] = []
	var templates := FighterTemplates.from_directory()
	var state := _build_state()

	var before_digest := state.digest()
	var before_rng_state := state.rng.get_state()

	templates.template("warrior")
	templates.template_for(state, "f1")
	templates.template_for(state, "no_such_fighter")
	templates.templates_by_fighter(state)

	violations.append_array(
		_expect(
			state.digest() == before_digest, "FighterTemplates calls must not change state.digest()"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_rng_state,
			"FighterTemplates calls must not change state.rng.get_state()"
		)
	)

	return violations

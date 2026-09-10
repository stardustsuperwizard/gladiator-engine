## A game-side `template_id` -> `FighterTemplate` lookup, and the one place that
## turns a fighter's stored `"template_id"` into the template it names.
##
## This is the mapping every action's constructor needs and that, until now, no
## caller outside a test fixture could produce: `GameState` stores fighters as
## opaque payloads and never resolves one to a template (see its own
## docstring), and `Fighter.from_dict()` takes the template as an argument
## precisely because choosing which template a saved fighter belongs to is a
## game-side decision. This class is that decision, made once, in one place.
##
## **Game-side by architecture, not by convenience.** No `rules/` file may
## depend on this class or do what it does -- `rules/` never reads
## `"template_id"` off a fighter payload, matching the same seam
## `scripts/authority.gd` already keeps for `"owner_id"`. Reading an opaque
## payload key from game-side code is the intended pattern, not a boundary
## violation, and it is not a reason to add a template or ownership accessor to
## `GameState`.
##
## **Templates are shared, never copied.** A registered `Resource` is handed
## back by reference so two fighters built from the same template keep sharing
## the identical object -- see `FighterTemplate`'s and `Fighter`'s own
## docstrings for why a per-fighter copy is wrong. Nothing here ever calls
## `duplicate()` on a template.
##
## **The map handed to rules-side code is keyed by fighter id, not template
## id.** `templates_by_fighter()` is that map's shape; `rules/` still never
## sees a `"template_id"` string, because it never sees this class at all.
##
## **A duplicate `register()` is refused, not replacing the original.** The
## first-registered template for a `template_id` keeps that id for the life of
## this instance. Silently swapping the template out from under a still-live
## `Resource` reference -- for example one a `Fighter` already holds via
## `template()` -- would let two callers disagree about what a `template_id`
## means, which is the exact bug a shared-instance design exists to prevent.
class_name FighterTemplates
extends RefCounted

## Where `from_directory()` looks by default. A `res://resources/` path is
## legal game-side code -- only `rules/` is forbidden from naming one.
const DEFAULT_TEMPLATES_DIR := "res://resources/fighters/"

## The fighter-payload key naming which template a fighter was built from.
## Named here, rather than inlined, for the same reason
## `Authority.OWNER_ID_KEY` is: this is the one place this class reaches into
## an opaque payload, and `Fighter.to_dict()` is what writes it.
const TEMPLATE_ID_KEY := "template_id"

## template_id -> FighterTemplate, held by reference.
var _templates: Dictionary = {}


## Registers `template` under its own `template_id`. Returns `false` and
## changes nothing when `template` is `null`, when its `template_id` is empty,
## or when a template is already registered under that `template_id` -- see
## the class docstring for why a duplicate is refused rather than replacing
## the original.
func register(template: FighterTemplate) -> bool:
	if template == null:
		return false
	if template.template_id.is_empty():
		return false
	if _templates.has(template.template_id):
		return false

	_templates[template.template_id] = template
	return true


## The `FighterTemplate` registered under `template_id`, or `null` when none
## is. Returned by reference -- see the class docstring.
func template(template_id: String) -> FighterTemplate:
	return _templates.get(template_id)


## The `FighterTemplate` that `fighter_id` in `state` was built from.
##
## Returns `null` for a fighter id `state` does not hold, for a payload whose
## `"template_id"` is missing or not a `String`, and for a `template_id` that
## was never registered. Read-only: `state.fighter()` already hands back a
## copy, and nothing here calls into `state` again.
func template_for(state: GameState, fighter_id: String) -> FighterTemplate:
	var payload := state.fighter(fighter_id)
	if payload.is_empty():
		return null

	var template_id_field: Variant = payload.get(TEMPLATE_ID_KEY)
	if typeof(template_id_field) != TYPE_STRING:
		return null

	return template(template_id_field)


## Every fighter in `state` whose template is known, as fighter id ->
## `FighterTemplate`, keyed and ordered by `state.fighter_ids()`. A fighter
## whose template cannot be resolved -- per `template_for()`'s refusals -- is
## omitted rather than mapped to `null`. This is the shape rules-side code is
## handed: keyed by fighter id, never by template id.
func templates_by_fighter(state: GameState) -> Dictionary:
	var result: Dictionary = {}

	for fighter_id in state.fighter_ids():
		var found := template_for(state, fighter_id)
		if found != null:
			result[fighter_id] = found

	return result


## Builds a `FighterTemplates` populated from every `.tres` file directly under
## `directory_path` (default `DEFAULT_TEMPLATES_DIR`) that `load()`s as a
## `FighterTemplate` -- `construction_budget.tres`, which loads as a
## `ConstructionBudget`, is skipped. Not recursive: the authored directory is
## flat.
##
## An unreadable `directory_path` yields an empty, still-usable instance rather
## than `null` -- the same "nothing is repaired, nothing crashes" direction
## `Fighter.from_dict()` and `GameState.from_dict()` take on a bad input.
static func from_directory(directory_path: String = DEFAULT_TEMPLATES_DIR) -> FighterTemplates:
	var instance := FighterTemplates.new()

	var dir := DirAccess.open(directory_path)
	if dir == null:
		return instance

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource: Variant = load(directory_path.path_join(file_name))
			if resource is FighterTemplate:
				instance.register(resource)
		file_name = dir.get_next()
	dir.list_dir_end()

	return instance

## Turns a fighter selection into the affordances a UI can offer, and builds
## the `TurnAction` that carries one.
##
## The view a session builds on top of `RoundDriver`/`HotseatSession` needs to
## answer, for a selected fighter: which of my fighters can even be selected,
## which hexes can this one reach, which enemies can it attack, and which
## hexes could it charge to and against whom. Answering any of those by
## re-deriving range, line of sight, reachability or the Charge lockout here
## would be a second copy of a rule `rules/` already owns -- see the
## Architecture Constraints on the Issue this class implements. So every query
## below asks the rules module's own predicate and reports what it said:
## `Board.reachable_from()`, `AttackAction.refusal_from()`,
## `ChargeLockout.locks_out()` and `Board.occupant_at()`.
##
## **An affordance, not a permission.** A command this class builds still goes
## through `Authority` by way of `ActionRunner`, and still may be refused there
## or fail on its own terms -- this class is not a pre-gate, and nothing here
## resolves anything. `tests/gate_bypass_contract_test.gd` fails the build on a
## receiver-qualified `.resolve(` or a `res://rules/` literal appearing in
## `scripts/`, and this file carries neither.
##
## **Holds no `GameState`.** Every method takes the state it is asked about,
## exactly as `FighterTemplates` and `DefaultActionStep` do -- there is no
## second, possibly stale, reference to drift out of step with the one
## `Authority` holds.
##
## **Templates are looked up, never loaded.** `FighterTemplates.template_for()`
## is the one place a fighter's stored `"template_id"` becomes the template it
## names; this class calls it once per fighter per query and never reaches for
## `load()` or `preload()` itself. A fighter id the state does not hold, or one
## whose template cannot be resolved, answers every query below with an empty
## result and every builder below with `null` -- refusing beats guessing.
##
## **Read-only.** No query or builder here mutates `state`, commits a payload,
## moves a board occupant, or draws from `state.rng`. Building a `TurnAction`
## constructs an object; only `ActionRunner.run()` -- which this class never
## calls -- resolves one.
class_name ActionOptions
extends RefCounted

## The one place a fighter's stored template id becomes its `FighterTemplate`.
## Injected, not owned: two callers sharing one `ActionOptions` share one
## `FighterTemplates` too.
var _templates: FighterTemplates

## The authored combat dials every candidate `AttackAction`/`ChargeAction` this
## class builds is constructed with. Injected, never resolved -- this class
## calls no `load()` and knows no resource path.
var _combat_profile: CombatProfile


func _init(templates: FighterTemplates, combat_profile: CombatProfile) -> void:
	_templates = templates
	_combat_profile = combat_profile


## `player_id`'s fighters, in `state.fighter_ids()` order, that are still the
## board's occupant of their own recorded position -- spec §9's defeat test,
## the same one `ChargeLockout.locks_out()` and `DefaultActionStep.action_for()`
## both read `Board.occupant_at()` for. A fighter whose template cannot be
## resolved, or whose payload will not parse, is omitted rather than guessed
## at.
func actable_fighters(state: GameState, player_id: String) -> Array[String]:
	var result: Array[String] = []

	for fighter_id in state.fighter_ids():
		var fighter := _read_fighter(state, fighter_id)
		if fighter == null:
			continue
		if fighter.owner_id() != player_id:
			continue
		if state.board.occupant_at(fighter.position()) != StringName(fighter_id):
			continue

		result.append(fighter_id)

	return result


## Every hex `fighter_id` could Move to right now:
## `Board.reachable_from(fighter.position(), fighter.move())` -- which already
## excludes the fighter's own hex, per that method's own contract -- or an
## empty array when the fighter is unknown, its template cannot be resolved,
## or `ChargeLockout.locks_out()` refuses it the same way `MoveAction` does.
func move_destinations(state: GameState, fighter_id: String) -> Array[Vector3i]:
	var fighter := _read_fighter(state, fighter_id)
	if fighter == null:
		return []
	if ChargeLockout.locks_out(state, fighter):
		return []

	return state.board.reachable_from(fighter.position(), fighter.move())


## Every fighter id `fighter_id` could Attack right now: every other fighter
## whose candidate `AttackAction` reports `refusal_from(state,
## fighter.position())` empty. `refusal_from()` is `AttackAction`'s own
## pre-check, so this omits a friendly fighter, one out of range, one with no
## line of sight, one already defeated, and -- since `AttackAction._refusal()`
## consults `ChargeLockout.locks_out()` for every target alike -- reports none
## at all for a fighter the Charge lockout holds.
func attack_targets(state: GameState, fighter_id: String) -> Array[String]:
	var attacker_template := _templates.template_for(state, fighter_id)
	if attacker_template == null:
		return []
	var attacker := Fighter.from_dict(state.fighter(fighter_id), attacker_template)
	if attacker == null:
		return []

	var result: Array[String] = []

	for target_id in state.fighter_ids():
		if target_id == fighter_id:
			continue
		var target_template := _templates.template_for(state, target_id)
		if target_template == null:
			continue

		var candidate := AttackAction.new(
			fighter_id, target_id, attacker_template, target_template, _combat_profile
		)
		if candidate.refusal_from(state, attacker.position()).is_empty():
			result.append(target_id)

	return result


## Every hex `fighter_id` could relocate to and then legally Attack `target_id`
## from: the fighter's `move_destinations()` -- so this is already empty for a
## fighter the Charge lockout holds -- filtered to those where a candidate
## attack half's `refusal_from(state, destination)` is empty. That is exactly
## the question `ChargeAction._refusal()` asks once it already knows the
## destination is reachable: its final step is
## `return _attack.refusal_from(state, _destination)`. Returns an empty array
## when either fighter id is unknown or its template cannot be resolved.
func charge_destinations(
	state: GameState, fighter_id: String, target_id: String
) -> Array[Vector3i]:
	var actor_template := _templates.template_for(state, fighter_id)
	var target_template := _templates.template_for(state, target_id)
	if actor_template == null or target_template == null:
		return []

	var destinations := move_destinations(state, fighter_id)
	if destinations.is_empty():
		return []

	var candidate := AttackAction.new(
		fighter_id, target_id, actor_template, target_template, _combat_profile
	)

	var result: Array[Vector3i] = []
	for destination in destinations:
		if candidate.refusal_from(state, destination).is_empty():
			result.append(destination)

	return result


## Every fighter id `fighter_id` could Charge: one with at least one hex in
## `charge_destinations(state, fighter_id, target_id)`.
func charge_targets(state: GameState, fighter_id: String) -> Array[String]:
	var result: Array[String] = []

	for target_id in state.fighter_ids():
		if target_id == fighter_id:
			continue
		if not charge_destinations(state, fighter_id, target_id).is_empty():
			result.append(target_id)

	return result


## A `MoveAction` for `fighter_id` to `destination`, or `null` when
## `fighter_id` is unknown or its template cannot be resolved. Built, not
## resolved: the caller still submits it through `ActionRunner`.
func move(state: GameState, fighter_id: String, destination: Vector3i) -> MoveAction:
	var template := _templates.template_for(state, fighter_id)
	if template == null:
		return null

	return MoveAction.new(fighter_id, destination, template)


## An `AttackAction` of `fighter_id` against `target_id`, or `null` when either
## fighter id is unknown or its template cannot be resolved.
func attack(state: GameState, fighter_id: String, target_id: String) -> AttackAction:
	var attacker_template := _templates.template_for(state, fighter_id)
	var target_template := _templates.template_for(state, target_id)
	if attacker_template == null or target_template == null:
		return null

	return AttackAction.new(
		fighter_id, target_id, attacker_template, target_template, _combat_profile
	)


## A `GuardAction` for `fighter_id`, or `null` when it is unknown or its
## template cannot be resolved.
func guard(state: GameState, fighter_id: String) -> GuardAction:
	var template := _templates.template_for(state, fighter_id)
	if template == null:
		return null

	return GuardAction.new(fighter_id, template)


## A `ChargeAction` moving `fighter_id` to `destination` and attacking
## `target_id`, or `null` when either fighter id is unknown or its template
## cannot be resolved.
func charge(
	state: GameState, fighter_id: String, target_id: String, destination: Vector3i
) -> ChargeAction:
	var actor_template := _templates.template_for(state, fighter_id)
	var target_template := _templates.template_for(state, target_id)
	if actor_template == null or target_template == null:
		return null

	return ChargeAction.new(
		fighter_id, destination, target_id, actor_template, target_template, _combat_profile
	)


## `fighter_id`'s payload as a `Fighter` over its resolved template, or `null`
## when `fighter_id` is unknown, its template cannot be resolved, or the
## payload will not parse.
func _read_fighter(state: GameState, fighter_id: String) -> Fighter:
	var template := _templates.template_for(state, fighter_id)
	if template == null:
		return null

	return Fighter.from_dict(state.fighter(fighter_id), template)

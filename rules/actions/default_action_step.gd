## Names the outcome of an Action Step the active player did not choose: spec
## §6's Guard, on the first of that player's fighters, in deployment order,
## eligible to Guard right now -- or nothing at all when none is.
##
## **Eligible means exactly what `GuardAction.resolve()` already refuses.**
## `action_for()` re-derives the same five checks `GuardAction._refusal()`
## would run for a given fighter -- a template to parse it with, a payload
## that parses, ownership by the deciding player, still the board's occupant
## of its own recorded position (spec §9's defeat test, the same one
## `ChargeLockout.locks_out()` uses), and not held by the Charge lockout -- so
## that a `GuardAction` this rule hands back never disagrees with the action's
## own refusal when it is later resolved. Nothing here calls `resolve()` --
## the caller decides when, and this rule only decides which fighter and
## whether one qualifies at all.
##
## **Walks `state.fighter_ids()`, not `templates.keys()`.** Deployment order is
## the order fighters were added to `GameState`, which is exactly what
## `fighter_ids()` returns; a `Dictionary` has no defined iteration order to
## rely on instead. "First eligible" means first in that order, not
## best-placed by any tactical measure -- a later fighter standing next to an
## enemy is not preferred over an earlier one standing alone.
##
## **A payload that will not parse is skipped**, matching
## `ChargeLockout.locks_out()`'s own handling of an unreadable fighter:
## skipping is the safe direction, since a fighter this rule cannot even read
## cannot be named for an action.
##
## **Returns `null`, not a refused `GuardAction`,** when no fighter qualifies:
## when `player_id` names no player in `state.turn_order()`, when `templates`
## is empty, and when every fighter the player owns is off the board or locked
## out. A `null` from this rule is "there is nothing to default to", never "a
## `GuardAction` that would itself be refused".
##
## **Pure.** `action_for()` mutates nothing, commits nothing, resolves
## nothing, and draws nothing from `state.rng` -- it only reads `state` and
## constructs a `GuardAction`, which is returned unresolved.
##
## `RefCounted`, static methods only, never instantiated -- the same shape
## `ChargeLockout` and the dice-pool module already use in this directory.
class_name DefaultActionStep
extends RefCounted


## The default action for `player_id` in `state`: a `GuardAction` on the first
## fighter, in `state.fighter_ids()` order, that
##
## 1. has a template in `templates` (keyed by fighter id),
## 2. parses via `Fighter.from_dict(state.fighter(fighter_id), template)`,
## 3. has `owner_id()` equal to `player_id`,
## 4. is still the board's occupant of its own recorded position -- spec §9's
##    defeat test, `state.board.occupant_at(fighter.position()) ==
##    StringName(fighter_id)`, and
## 5. is not held by `ChargeLockout.locks_out(state, fighter)`.
##
## Returns `null` when no fighter satisfies all five, when `player_id` names
## no player in `state.turn_order()`, and when `templates` is empty.
static func action_for(
	state: GameState, player_id: String, templates: Dictionary
) -> GuardAction:
	if player_id not in state.turn_order():
		return null

	if templates.is_empty():
		return null

	for fighter_id in state.fighter_ids():
		var template: Variant = templates.get(fighter_id)
		if not (template is FighterTemplate):
			continue

		var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
		if fighter == null:
			continue

		if fighter.owner_id() != player_id:
			continue

		if state.board.occupant_at(fighter.position()) != StringName(fighter_id):
			continue

		if ChargeLockout.locks_out(state, fighter):
			continue

		return GuardAction.new(fighter_id, template)

	return null

## Spec §6's Move: a fighter steps to a reachable destination.
##
## `resolve()` refuses first, changing nothing, then commits the board and the
## payload together: `Relocation.relocate()` for the board and the fighter's
## own position, then its new `"moved"` flag, then the payload back into
## `GameState`.
##
## **The relocation itself lives in `Relocation`, not here.** The place-then-
## free ordering, and why a refused relocation must never leave a fighter
## standing on no hex at all, are documented on that class -- it is the one
## primitive this action and `ChargeAction` both commit their board change
## through, so a second copy of the ordering cannot drift. What stays here is
## everything that is Move's rather than relocation's: the refusal order, the
## reachability check, and the `"moved"` flag.
##
## **Reachability is `Board.reachable_from()`, and only that.** It is a
## breadth-first search that routes *around* `BLOCKED` and occupied hexes,
## unlike `HexCoord.distance()`, which counts straight through them. A
## destination behind a wall, behind another fighter, or reachable only by a
## detour longer than `move()` steps is refused exactly the same way a
## destination that is simply too far is -- `FAILURE_DESTINATION_UNREACHABLE`
## deliberately does not distinguish why the search said no.
##
## **The `"moved"` flag is this class's own vocabulary.** `Fighter` carries the
## flag mechanism -- `set_status_flag()`, `has_status_flag()`,
## `clear_status_flag()` -- and names no flag itself; `FLAG_MOVED` lives here,
## the same way `AttackAction` owns `FAILURE_TARGET_IS_SELF` and `PassAction`
## owns `FAILURE_NO_SUCH_FIGHTER`. It is a plain `String`, not a `StringName`:
## `Fighter.set_status_flag()` takes a `String`, `Fighter.to_dict()` serializes
## flags as plain strings, and `Fighter.from_dict()` rejects a non-`String`
## entry. The `FAILURE_*` constants below stay `StringName` because
## `TurnResult.failure()` takes one; the two differ on purpose.
##
## **The string itself now lives in `StatusFlags`.** `FLAG_MOVED` is retained
## as a re-export so this class keeps naming the flag in its own vocabulary,
## but `StatusFlags.MOVED` is the canonical literal, needed once a clearing
## step must enumerate every round-level flag at once. See that class's
## docstring.
##
## **The flag must be set before the payload is committed.** `set_status_flag()`
## runs on the in-memory `Fighter` before `to_dict()` is read out of it and
## handed to `state.update_fighter()` -- `update_fighter()` replaces the stored
## payload wholesale, so setting the flag after that call would write it to a
## throwaway object the state never sees again.
##
## **The template is injected, never resolved.** It arrives through `_init()`,
## exactly as `AttackAction`'s templates do: nothing here calls `load()` or
## `preload()`, consults a registry, or asks `GameState` for one.
##
## **Neither `turns_taken` nor `round_number` is touched.** Move has three
## observable effects of its own -- position, occupancy, the flag -- so it
## follows `AttackAction`'s precedent: `PassAction` touches neither field
## either, and has no observable effect on `state` at all.
##
## **Draws nothing from `state.rng`.** Move is fully determined by the board
## and the `move()` stat; `rules/tests/ambient_rng_contract_test.gd` and
## `rules/tests/ambient_rng_scanner_test.gd` enforce that no generator call
## appears here.
##
## **Spec §6's Charge lockout.** `ChargeLockout.locks_out()` is consulted right
## after the fighter's identity is settled and before the destination is
## looked at -- the actor's own legality comes before any geometry. See
## `ChargeLockout`'s own docstring for the rule and why it owns `"charged"`
## rather than `ChargeAction`.
class_name MoveAction
extends TurnAction

## Spec §6's `"moved"` flag, set on the acting fighter by a successful Move.
## Re-exported from `StatusFlags`, the canonical home; see the class docstring.
const FLAG_MOVED := StatusFlags.MOVED

## `actor_template` is `null`, or the state holds a payload for `actor_id()`
## that will not parse.
const FAILURE_MISSING_DATA := &"move_missing_data"

## The state holds no fighter with this action's `actor_id()`.
const FAILURE_NO_SUCH_FIGHTER := &"move_no_such_fighter"

## The destination is the hex the fighter already stands on.
const FAILURE_DESTINATION_IS_ORIGIN := &"move_destination_is_origin"

## The destination is absent from `Board.reachable_from(origin, fighter.move())`
## -- too far, blocked, occupied, off the board, or only reachable by a detour
## longer than `move()`. Every one of those reports this single constant; see
## the class docstring.
const FAILURE_DESTINATION_UNREACHABLE := &"move_destination_unreachable"

## Spec §6's Charge lockout refuses this actor -- see `ChargeLockout`.
const FAILURE_CHARGE_LOCKOUT := &"move_charge_lockout"

## Where this action moves the actor. Set once, at construction.
var _destination: Vector3i

## The authored data this resolver needs to read the actor's `move()`
## allowance, injected rather than resolved.
var _template: FighterTemplate


## Both arguments beyond `actor_id` are required and stored exactly as given;
## nothing is validated here. A `null` template is refused by `resolve()` with
## `FAILURE_MISSING_DATA`, which is where it can actually be answered.
func _init(actor_id: String, destination: Vector3i, actor_template: FighterTemplate) -> void:
	super(actor_id)
	_destination = destination
	_template = actor_template


## Resolves this Move against `state`, per spec §6.
##
## Refuses first, changing nothing at all -- `_refusal()` fixes the order the
## reasons are tried in, so a request failing more than one condition always
## reports the same one. Then, in exactly the order the class docstring gives:
## relocates through `Relocation.relocate()`, which secures the destination
## before freeing the origin, then sets `FLAG_MOVED`, then commits the payload.
##
## A `Relocation.relocate()` that returns `false` has changed nothing, and is
## reported as `FAILURE_DESTINATION_UNREACHABLE` -- the same constant
## `_refusal()` gives for a destination the search never reached.
func resolve(state: GameState) -> TurnResult:
	var fighter := _read_fighter(state)

	var reason := _refusal(state, fighter)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	if not Relocation.relocate(state.board, fighter, _destination):
		return TurnResult.failure(FAILURE_DESTINATION_UNREACHABLE)

	fighter.set_status_flag(FLAG_MOVED)
	state.update_fighter(actor_id(), fighter.to_dict())
	return TurnResult.ok()


## Why this Move cannot resolve, or `&""` when it can.
##
## The single implementation of the predicate, in a fixed order: the injected
## data and the fighter's identity first, then spec §6's Charge lockout, then
## whether there is anywhere to go at all, then whether the search can
## actually get there.
func _refusal(state: GameState, fighter: Fighter) -> StringName:
	if _template == null:
		return FAILURE_MISSING_DATA

	if fighter == null:
		var ids := state.fighter_ids()
		return FAILURE_NO_SUCH_FIGHTER if actor_id() not in ids else FAILURE_MISSING_DATA

	if ChargeLockout.locks_out(state, fighter):
		return FAILURE_CHARGE_LOCKOUT

	if _destination == fighter.position():
		return FAILURE_DESTINATION_IS_ORIGIN

	if _destination not in state.board.reachable_from(fighter.position(), fighter.move()):
		return FAILURE_DESTINATION_UNREACHABLE

	return &""


## `actor_id()`'s payload as a `Fighter` over `_template`, or `null` when the
## template is `null` or the payload will not parse. `_refusal()` is what turns
## either case into the right `FAILURE_*` constant.
func _read_fighter(state: GameState) -> Fighter:
	if _template == null:
		return null
	return Fighter.from_dict(state.fighter(actor_id()), _template)

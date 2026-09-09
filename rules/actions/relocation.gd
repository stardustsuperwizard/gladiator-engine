## The one relocation primitive spec §6's Move and Charge both commit through.
##
## `relocate()` calls `Board.place_occupant()` at the destination, then
## `Board.remove_occupant()` at the origin, then `Fighter.move_to()`. That
## order -- secure the destination before freeing the origin -- is what
## `AttackAction._apply_push()` documents as an architecture constraint, and it
## applies here for the identical reason: a refused relocation must never leave
## a fighter standing on no hex at all. A refused `place_occupant()` returns
## `false` having changed nothing at all, so the caller's own refusal path can
## still report as if nothing was attempted.
##
## **It sets no status flag and commits no payload.** Both are the caller's,
## and that is the whole reason this is a seam rather than a method on one
## action: `MoveAction` sets `"moved"` and `ChargeAction` sets `"charged"` over
## one shared relocation. There is deliberately no flag parameter -- that would
## make one action's vocabulary configurable by another. The caller commits the
## moved fighter with `GameState.update_fighter()` itself; nothing here names
## `GameState` at all.
##
## **Reachability is not this class's job.** Each calling action keeps its own
## `Board.reachable_from()` check in its own `_refusal()`, because that is a
## direct call to an existing `Board` API rather than a re-derivation, and
## folding it in would give this class two jobs. `relocate()` refuses only what
## `Board.place_occupant()` refuses.
##
## **Draws nothing from `state.rng`** -- it is handed no generator and no
## state. Relocation is fully determined by the board and the destination.
##
## `RefCounted`, one static method, never instantiated -- the same shape
## `Flanking`, `DicePool` and `ChargeLockout` already use in this module.
class_name Relocation
extends RefCounted


## Moves `fighter` to `destination` on `board`, securing the destination before
## freeing the origin. Returns `false`, having changed nothing, when the
## destination will not take the occupant -- off the board, BLOCKED, or already
## occupied, exactly the three cases `Board.place_occupant()` refuses.
##
## Sets no status flag and commits no payload; see the class docstring.
static func relocate(board: Board, fighter: Fighter, destination: Vector3i) -> bool:
	var origin := fighter.position()

	if not board.place_occupant(destination, StringName(fighter.id())):
		return false

	board.remove_occupant(origin)
	fighter.move_to(destination)
	return true

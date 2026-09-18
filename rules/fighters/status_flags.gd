## One canonical home for spec §6's three round-level status-flag names, plus
## spec §5.2's `activated` flag, and the enumerated set spec §10 step 5 clears.
##
## `MOVED`, `GUARDED` and `CHARGED` are the single string literals; the three
## actions that produce them -- `MoveAction.FLAG_MOVED`,
## `GuardAction.FLAG_GUARDED` and `ChargeLockout.FLAG_CHARGED` -- keep their own
## names as re-exports of these constants, so every call site keeps reading in
## the acting class's own vocabulary and nothing that reads them moves.
## `ACTIVATED` follows the identical re-export convention: `Activation
## .FLAG_ACTIVATED` re-exports it, the same way `ChargeLockout.FLAG_CHARGED`
## already does for `CHARGED`.
##
## **`ACTIVATED` marks once-per-round activation, not a §6 action of its
## own.** Every one of `MoveAction`, `AttackAction`, `GuardAction`,
## `ChargeAction` and `PassAction` records it on a successful resolve, through
## `Activation.record()` -- see that class for the payload-level seam. Nothing
## reads it yet; see `Activation`'s own docstring for what is and is not built
## on top of it.
##
## **Why the set is enumerated rather than "clear everything."** Spec §9
## hedges -- "*Most* per-round status flags ... clear at end of round" -- and
## `enhanced` is the shape of a state that would not: a status that persists
## across rounds rather than resetting with them. `enhanced` names no rule that
## exists yet; it is unbuilt. Enumerating the flags that do clear is the safer
## reading of that hedge, and this class is what makes enumerating cheap for
## the clearing step that reads `round_level()`.
##
## **Why no hazard-triggered flag is listed.** Spec §9 also mentions a
## hazard-triggered flag. No hazard rule exists in this tree, so there is no
## flag name to publish for it; adding one now would be inventing a rule this
## class does not own.
##
## **A plain `String`, not a `StringName`**, for the reason every one of the
## three re-exports already documents: `Fighter.set_status_flag()` takes a
## `String`, `Fighter.to_dict()` serializes flags as plain strings, and
## `Fighter.from_dict()` rejects a `status_flags` entry that is not
## `TYPE_STRING`.
##
## **`round_level()` returns a fresh array on every call**, matching
## `Fighter.status_flags()`, `GameState.turn_order()` and
## `GameState.fighter_ids()`: a caller must not be able to edit the canonical
## set through the value it was handed back. Nothing exposes the array itself
## as a `const`.
##
## **This class is a leaf.** It names nothing else in `rules/` at all -- not
## `Fighter`, not `GameState`, not any action -- which is what keeps the class
## graph acyclic once a clearing step depends on it: `StatusFlags` depends on
## nothing here; `ChargeLockout` and the three actions depend on it.
##
## `RefCounted`, constants and static methods only, never instantiated -- the
## same shape `Flanking`, `DicePool` and `ChargeLockout` already use in this
## tree.
class_name StatusFlags
extends RefCounted

## Spec §6's Move flag.
const MOVED := "moved"

## Spec §6's Guard flag.
const GUARDED := "guarded"

## Spec §6's Charge flag.
const CHARGED := "charged"

## Spec §5.2's once-per-round activation flag. Set by every Action Step
## command on a successful resolve; see `Activation`.
const ACTIVATED := "activated"


## The flags spec §10 step 5 clears at end of round, as a fresh copy. See the
## class docstring for why this set is enumerated rather than "every flag."
static func round_level() -> Array[String]:
	return [MOVED, GUARDED, CHARGED, ACTIVATED] as Array[String]

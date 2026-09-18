## Spec §5.2's once-per-round activation record: which fighters have resolved
## an Action Step command this round.
##
## `record()` is what every one of `MoveAction`, `AttackAction`, `GuardAction`,
## `ChargeAction` and `PassAction` calls on its success path, immediately
## before its existing `PowerStep.note_action(state)` call. `has_activated()`
## is the read side. This is only the record: nothing here refuses a command
## from an already-activated fighter, nothing filters which fighters may be
## chosen, and nothing changes how many Turns a round has. That is the
## remainder of epic #377 (#407, #408), not this task.
##
## **Payload-level, like `EndSegment`'s flag clearing.** `record()` reads the
## stored payload with `GameState.fighter()`, produces the updated payload
## with `Fighter.with_flags()`, and commits it with `GameState.update_fighter()`.
## It takes no `FighterTemplate` and builds no `Fighter` -- the same seam
## `StandardVictory` uses to read `owner_id` and `EndSegment` uses to clear
## flags, and for the identical reason: none of the five actions that call
## this class hold a spare template lying around for an id that is not
## necessarily their own actor's in every caller's context, and none of them
## should have to construct one just to flip a flag.
##
## **`EndSegment` clears this flag for free.** `StatusFlags.ACTIVATED` is in
## `StatusFlags.round_level()`, and `EndSegment.run()`'s step 5 already clears
## every flag in that set from every fighter on the board -- see that class.
## Nothing in this file, and no edit to `end_segment.gd`, does the clearing.
##
## **`record()` is idempotent.** `ChargeAction` composes `AttackAction`, so the
## same actor id reaches `record()` twice in one resolved Charge -- once
## through the composed `AttackAction`, once directly. `Fighter.with_flags()`
## does not add a second copy of a flag already present, so the second call
## commits a payload identical to what is already stored and
## `GameState.digest()` does not move.
##
## **`record()` refuses only an unknown fighter id**, returning `false` and
## writing nothing. There is no other refusal: this class does not ask whether
## the fighter has already acted, whether an Action Step is open, or anything
## else about the request -- that is the calling action's `_refusal()`, not
## this class's.
##
## **`PowerStepPassAction` does not call this class.** Its `actor_id()` is a
## player id, not a fighter id -- spec §5.3's Power Step pass is a player's
## declaration, not a fighter's action -- and a Power Step pass is not an
## Action Step action. See that class's own docstring.
##
## **Pure.** Draws nothing from `state.rng`. `record()` is the only writer
## here; `has_activated()` only reads.
##
## `RefCounted`, static methods only, never instantiated -- the same shape
## `ChargeLockout`, `PowerStep` and `EndSegment` already use.
class_name Activation
extends RefCounted

## Spec §5.2's `"activated"` flag. Re-exported from `StatusFlags`, the
## canonical home for the literal itself -- the same convention
## `ChargeLockout.FLAG_CHARGED` already sets for `StatusFlags.CHARGED`.
const FLAG_ACTIVATED := StatusFlags.ACTIVATED


## Records `fighter_id` as activated this round. Returns `false` and changes
## nothing when `fighter_id` names no fighter in `state`.
##
## Idempotent: a fighter that already carries `FLAG_ACTIVATED` is committed
## again with the identical payload, so `state.digest()` does not move on a
## second call. See the class docstring.
static func record(state: GameState, fighter_id: String) -> bool:
	if fighter_id not in state.fighter_ids():
		return false

	var payload := state.fighter(fighter_id)
	var updated := Fighter.with_flags(payload, [FLAG_ACTIVATED] as Array[String])
	state.update_fighter(fighter_id, updated)
	return true


## True when `fighter_id` has resolved an Action Step command this round.
## `false` for a fighter that has not, and for a fighter id `state` does not
## hold. Reads only; never changes `state.digest()`.
static func has_activated(state: GameState, fighter_id: String) -> bool:
	if fighter_id not in state.fighter_ids():
		return false

	return Fighter.has_flag(state.fighter(fighter_id), FLAG_ACTIVATED)

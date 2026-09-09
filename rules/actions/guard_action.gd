## Spec §6's Guard: a fighter spends its Action Step raising its own defenses.
##
## `resolve()` refuses first, changing nothing, then sets spec §6's
## `"guarded"` flag on the acting fighter and commits the payload back into
## `GameState`. That is the whole effect: no position, no board occupancy, and
## no counter changes.
##
## **This is the first status flag in the tree that resolution actually
## reads.** `MoveAction.FLAG_MOVED` has a writer and no reader; `FLAG_GUARDED`
## below has both -- `AttackAction` reads it twice, once to lower the save
## target per spec §7.3 and once to refuse the push per spec §6. See that
## class's docstring for the two reads.
##
## **The `"guarded"` flag is this class's own vocabulary**, the same
## convention `MoveAction` sets for `FLAG_MOVED`: a constant belongs to the
## class that produces it, and `AttackAction` references
## `GuardAction.FLAG_GUARDED` rather than holding a second copy of the string.
## It is a plain `String`, not a `StringName`, for the identical reason
## `MoveAction`'s own docstring gives: `Fighter.set_status_flag()` takes a
## `String`, `Fighter.to_dict()` serializes flags as plain strings, and
## `Fighter.from_dict()` rejects a non-`String` entry. The `FAILURE_*`
## constants below stay `StringName` because `TurnResult.failure()` takes one.
##
## **The string itself now lives in `StatusFlags`.** `FLAG_GUARDED` is
## retained as a re-export so this class keeps naming the flag in its own
## vocabulary, but `StatusFlags.GUARDED` is the canonical literal, needed once
## a clearing step must enumerate every round-level flag at once. See that
## class's docstring.
##
## **A Guard by an already-guarded fighter is not a refusal.** It resolves,
## returns `TurnResult.ok()`, and is a no-op: `Fighter.set_status_flag()`
## already returns `false` for a flag it holds, and the committed payload is
## identical. No spec rule forbids repeating it.
##
## **The flag must be set before the payload is committed**, for the reason
## `MoveAction` documents: `state.update_fighter()` replaces the stored payload
## wholesale, so setting the flag after that call would write it to a
## throwaway object the state never sees again.
##
## **The template is injected, never resolved.** It arrives through `_init()`,
## exactly as `MoveAction`'s and `AttackAction`'s do: nothing here calls
## `load()` or `preload()`, consults a registry, or asks `GameState` for one.
## Guard reads no stat off it -- the template exists only so
## `Fighter.from_dict()` has one to parse the actor's payload with.
##
## **Neither `turns_taken` nor `round_number` is touched.** Guard has an
## observable effect of its own -- the flag -- so it follows `MoveAction`'s and
## `AttackAction`'s precedent rather than `PassAction`'s.
##
## **Draws nothing from `state.rng`.** Guard is fully determined by the
## request; `rules/tests/ambient_rng_contract_test.gd` and
## `rules/tests/ambient_rng_scanner_test.gd` enforce that no generator call
## appears here.
##
## **Spec §6's Charge lockout.** `ChargeLockout.locks_out()` is consulted
## right after the fighter's identity is settled, the last check in this
## predicate. See `ChargeLockout`'s own docstring for the rule and why it owns
## `"charged"` rather than `ChargeAction`.
class_name GuardAction
extends TurnAction

## Spec §6's `"guarded"` flag, set on the acting fighter by a successful Guard.
## Re-exported from `StatusFlags`, the canonical home; see the class
## docstring.
const FLAG_GUARDED := StatusFlags.GUARDED

## `actor_template` is `null`, or the state holds a payload for `actor_id()`
## that will not parse.
const FAILURE_MISSING_DATA := &"guard_missing_data"

## The state holds no fighter with this action's `actor_id()`.
const FAILURE_NO_SUCH_FIGHTER := &"guard_no_such_fighter"

## Spec §6's Charge lockout refuses this actor -- see `ChargeLockout`.
const FAILURE_CHARGE_LOCKOUT := &"guard_charge_lockout"

## The authored data this resolver needs to parse the actor's payload,
## injected rather than resolved.
var _template: FighterTemplate


## `actor_template` is required and stored exactly as given; nothing is
## validated here. A `null` template is refused by `resolve()` with
## `FAILURE_MISSING_DATA`, which is where it can actually be answered. Guard
## names one fighter -- the actor -- and nothing else: no target parameter, no
## destination.
func _init(actor_id: String, actor_template: FighterTemplate) -> void:
	super(actor_id)
	_template = actor_template


## Resolves this Guard against `state`, per spec §6.
##
## Refuses first, changing nothing at all -- `_refusal()` fixes the order the
## reasons are tried in. Then, in exactly this order: set `FLAG_GUARDED` on the
## in-memory fighter, then commit the payload.
func resolve(state: GameState) -> TurnResult:
	var fighter := _read_fighter(state)

	var reason := _refusal(state, fighter)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	fighter.set_status_flag(FLAG_GUARDED)
	state.update_fighter(actor_id(), fighter.to_dict())
	return TurnResult.ok()


## Why this Guard cannot resolve, or `&""` when it can.
##
## The single implementation of the predicate, in a fixed order: the injected
## data first, then the fighter's identity, then spec §6's Charge lockout.
func _refusal(state: GameState, fighter: Fighter) -> StringName:
	if _template == null:
		return FAILURE_MISSING_DATA

	if fighter == null:
		var ids := state.fighter_ids()
		return FAILURE_NO_SUCH_FIGHTER if actor_id() not in ids else FAILURE_MISSING_DATA

	if ChargeLockout.locks_out(state, fighter):
		return FAILURE_CHARGE_LOCKOUT

	return &""


## `actor_id()`'s payload as a `Fighter` over `_template`, or `null` when the
## template is `null` or the payload will not parse. `_refusal()` is what turns
## either case into the right `FAILURE_*` constant.
func _read_fighter(state: GameState) -> Fighter:
	if _template == null:
		return null
	return Fighter.from_dict(state.fighter(actor_id()), _template)

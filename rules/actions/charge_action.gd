## Spec §6's Charge: one fighter relocates and attacks in a single Action Step.
##
## **It composes Move and Attack; it re-derives neither.** The relocation is
## `Relocation.relocate()`, the same primitive `MoveAction` commits through.
## The reachability search is `Board.reachable_from()`, called directly. The
## attack's legality is `AttackAction.refusal_from()`, and the attack itself is
## `AttackAction.resolve()` -- so spec §7.3's two charts, the engagement bonus,
## the attack-pool-then-save-pool draw order, spec §8's flanking, damage,
## defeat, `defeat_award`, spec §7.6-7.7's push-back and spec §6's Guard row
## and push immunity all arrive here with no second copy of any of them. A
## second copy of any of that is the primary correctness risk in this action,
## and every design decision below exists to make composition possible without
## one.
##
## **One `AttackAction`, built at construction, used twice.** The same instance
## answers the pre-check in `_refusal()` and resolves the attack in
## `resolve()`, so the resolution detail is readable off it afterwards through
## `attack_half()` -- one accessor rather than nine passthroughs. `TurnResult`
## stays the dumb two-field record it is and is not widened.
##
## **The resolution order is load-bearing.** The relocation is committed to
## `GameState` *before* the attack half resolves, because
## `AttackAction.resolve()` re-reads the attacker out of `GameState`: that is
## what makes the attack resolve from the destination, and what makes spec
## §7.3's engagement bonus and spec §8's flanking measure against the board as
## it stands after the move, for free. The `"charged"` flag is committed
## *after* the attack half resolves, because `AttackAction` refuses a fighter
## holding `"charged"` while any friendly fighter lacks it -- setting the flag
## first would make Charge refuse itself on nearly every board.
##
## **`"charged"`, never `"moved"`.** Spec §6 gives Charge a distinct flag
## instead of Move's, and `ChargeLockout.FLAG_CHARGED` is that flag's one home;
## see that class's docstring for why the constant lives there rather than
## here. Nothing below declares a second copy of it, and nothing below clears
## any flag -- spec §10 step 5's round-level clearing does not exist yet, and
## this action must not stand in for it.
##
## **A Miss is a successful Charge**, exactly as it is a successful Attack:
## `TurnResult.success` means the action resolved, not that it hurt anyone, so
## `HIT`, `DRAWN` and `MISS` all set the flag and return `TurnResult.ok()`.
##
## **Draws from `state.rng` only through the attack half**, which draws
## precisely what a standalone `AttackAction` draws, in the same order. The
## move half draws nothing, so a Charge to hex X attacking Y leaves the
## generator exactly where a Move to X followed by an Attack on Y would.
##
## **Neither `turns_taken` nor `round_number` is touched**, following
## `MoveAction`'s and `AttackAction`'s precedent.
##
## **It calls `PowerStep.note_action(state)` on its success path**, as every
## concrete command does, which opens the Turn's Power Step and clears any
## consecutive-pass record. It reaches that call twice on a successful Charge
## -- once through the composed `AttackAction` and once directly -- and
## `note_action()` is idempotent, so the second call leaves exactly what the
## first did. `turns_taken` still rises only when the Power Step ends, in
## `PowerStep.end_on_second_pass()`.
##
## **The templates and the profile are injected, never resolved.** They arrive
## through `_init()` and are handed to the composed `AttackAction`: nothing
## here calls `load()` or `preload()`, consults a registry, or asks `GameState`
## for one.
##
## Adding this action required no edit to `ActionRunner` and none to
## `Authority`: generality comes from subclassing `resolve()`.
class_name ChargeAction
extends TurnAction

## A template or the `CombatProfile` is `null`, or the state holds a payload
## for `actor_id()` that will not parse.
const FAILURE_MISSING_DATA := &"charge_missing_data"

## The state holds no fighter with this action's `actor_id()`.
const FAILURE_NO_SUCH_FIGHTER := &"charge_no_such_fighter"

## Spec §6's precondition: the actor has already moved or already charged this
## round. Charge is not gated by `ChargeLockout` on top of this -- a charged
## fighter is refused another Charge right here, and spec §6's lockout names
## Move, Attack and Guard.
const FAILURE_ALREADY_ACTED := &"charge_already_acted"

## The destination is the hex the fighter already stands on. Inherited from
## Move deliberately: spec §6 defines Charge as a combined Move and Attack, and
## its Move "must end in a different hex than it started". A Charge that does
## not move is an Attack, and `AttackAction` is how you make one.
const FAILURE_DESTINATION_IS_ORIGIN := &"charge_destination_is_origin"

## The destination is absent from `Board.reachable_from(origin, fighter.move())`
## -- too far, blocked, occupied, off the board, or only reachable by a detour
## longer than `move()`. The **full** `move()` allowance: spec §6 states no
## reduction, so none is applied.
const FAILURE_DESTINATION_UNREACHABLE := &"charge_destination_unreachable"

## Where this action relocates the actor before it attacks. Set once, at
## construction.
var _destination: Vector3i

## The authored data this resolver needs, all injected, none resolved. The
## actor's template is read for its `move()` allowance and to parse the actor's
## payload; the target's template and the profile are held only so `_refusal()`
## can answer `FAILURE_MISSING_DATA` for them before anything else is tried.
var _template: FighterTemplate
var _target_template: FighterTemplate
var _combat_profile: CombatProfile

## The attack half, built once from the constructor's arguments. The same
## instance answers `refusal_from()` in `_refusal()` and resolves in
## `resolve()`; see the class docstring.
var _attack: AttackAction


## Every argument beyond `push_back` is required and stored exactly as given;
## nothing is validated here. A `null` template or profile is refused by
## `resolve()` with `FAILURE_MISSING_DATA`, which is where it can actually be
## answered.
##
## `push_back` is passed straight through to the attack half and defaults to
## `false`, exactly as `AttackAction._init()` already does.
func _init(
	actor_id: String,
	destination: Vector3i,
	target_id: String,
	actor_template: FighterTemplate,
	target_template: FighterTemplate,
	combat_profile: CombatProfile,
	push_back: bool = false
) -> void:
	super(actor_id)
	_destination = destination
	_template = actor_template
	_target_template = target_template
	_combat_profile = combat_profile
	_attack = AttackAction.new(
		actor_id, target_id, actor_template, target_template, combat_profile, push_back
	)


## Resolves this Charge against `state`, per spec §6.
##
## Refuses first, changing nothing at all -- `_refusal()` fixes the order the
## reasons are tried in, and asks the attack half whether its own attack is
## legal *from the destination* before anything moves. Then, in this order and
## no other:
##
## 1. relocate through `Relocation.relocate()`;
## 2. commit the relocation -- the relocation only, not the flag;
## 3. resolve the attack half, which re-reads the attacker and so attacks from
##    the destination;
## 4. re-read the actor, set `ChargeLockout.FLAG_CHARGED`, commit again;
## 5. note the action against the Power Step, idempotently -- step 3 already
##    did it once;
## 6. return `TurnResult.ok()`.
##
## The actor is re-read at step 4 rather than reusing the local `Fighter` from
## step 1: it is one parse, and it keeps this action from depending on which
## payloads `AttackAction` chose to commit.
func resolve(state: GameState) -> TurnResult:
	var fighter := _read_fighter(state)

	var reason := _refusal(state, fighter)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	if not Relocation.relocate(state.board, fighter, _destination):
		return TurnResult.failure(FAILURE_DESTINATION_UNREACHABLE)

	state.update_fighter(actor_id(), fighter.to_dict())

	var result := _attack.resolve(state)
	if not result.success:
		# Unreachable. `_refusal()` asked `refusal_from()` the identical
		# predicate at this identical position moments ago and nothing between
		# the two changed a term of it -- see `AttackAction.refusal_from()`'s
		# own docstring for why the pre-check is exact. Returned unchanged
		# rather than repaired: rollback machinery, a retry or a second
		# relocation for a path the invariant excludes would be untested code
		# guarding an impossible case.
		return result

	var charged := _read_fighter(state)
	charged.set_status_flag(ChargeLockout.FLAG_CHARGED)
	state.update_fighter(actor_id(), charged.to_dict())
	PowerStep.note_action(state)
	return TurnResult.ok()


## The attack half, for reading the resolution detail back -- `outcome()`,
## `attack_target()`, `pushed()`, `target_defeated()` and the rest. Meaningless
## until `resolve()` has returned a successful `TurnResult`.
func attack_half() -> AttackAction:
	return _attack


## Why this Charge cannot resolve, or `&""` when it can.
##
## The single implementation of the predicate, in a fixed order: the injected
## data and the fighter's identity first, then spec §6's precondition, then
## whether there is anywhere to go at all, then whether the search can actually
## get there, and finally whether the attack half is legal from the
## destination.
##
## That last step is returned **verbatim, in `AttackAction`'s own vocabulary**
## -- `attack_target_out_of_range`, `attack_no_line_of_sight` and the rest.
## There are deliberately no parallel `charge_*` copies of those: attack
## legality has one home, the caller learns which half refused and why in one
## value, and duplicated constants would be pairs that must agree with nothing
## enforcing it.
##
## The move half uses the full `move()` allowance and is gated on no attack
## type: any fighter may Charge, a Range-8 one included. `range_hexes()` is
## consulted nowhere outside the attack half's own reach check.
func _refusal(state: GameState, fighter: Fighter) -> StringName:
	if _template == null or _target_template == null or _combat_profile == null:
		return FAILURE_MISSING_DATA

	if fighter == null:
		var ids := state.fighter_ids()
		return FAILURE_NO_SUCH_FIGHTER if actor_id() not in ids else FAILURE_MISSING_DATA

	var already_acted := (
		fighter.has_status_flag(MoveAction.FLAG_MOVED)
		or fighter.has_status_flag(ChargeLockout.FLAG_CHARGED)
	)
	if already_acted:
		return FAILURE_ALREADY_ACTED

	if _destination == fighter.position():
		return FAILURE_DESTINATION_IS_ORIGIN

	if _destination not in state.board.reachable_from(fighter.position(), fighter.move()):
		return FAILURE_DESTINATION_UNREACHABLE

	return _attack.refusal_from(state, _destination)


## `actor_id()`'s payload as a `Fighter` over `_template`, or `null` when the
## template is `null` or the payload will not parse. `_refusal()` is what turns
## either case into the right `FAILURE_*` constant.
func _read_fighter(state: GameState) -> Fighter:
	if _template == null:
		return null
	return Fighter.from_dict(state.fighter(actor_id()), _template)

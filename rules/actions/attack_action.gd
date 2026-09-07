## Spec §7: one fighter attacks another. The capstone of Slice 0.
##
## `resolve()` validates the target, rolls both dice pools through the state's
## seeded generator, applies spec §8's flanking and surrounding bonuses,
## compares the two totals into Hit / Drawn / Miss, and on a Hit applies the
## weapon's damage and checks defeat.
##
## **It wires three modules together and reimplements none of them.** The
## dice-pool math lives in `DicePool`, the adjacency bonus in `Flanking`, and
## the fighter payload shape in `Fighter`. A second copy of any of that here is
## the primary correctness risk in this project.
##
## **A resolved Miss is a successful `TurnResult`.** `TurnResult.success` means
## the action resolved, not that the attack hurt someone, so `HIT`, `DRAWN` and
## `MISS` all return `TurnResult.ok()`. `reason` is for refusals only, and the
## resolution detail is read back off the accessors below rather than out of the
## result -- `TurnResult` is deliberately a dumb two-field record and is not
## widened to carry a combat payload for the benefit of one action.
##
## **Draw order is the contract.** The attack pool is drawn *entirely* before
## the save pool, both through `state.rng`, and nothing else in `resolve()`
## touches the generator. That ordering is what makes the hand-worked tests in
## `rules/tests/attack_action_test.gd` reproducible; changing it silently
## invalidates every recorded expectation.
##
## **Templates are injected, never resolved.** The weapon, the target's
## `FighterTemplate` and both `DiceProfile`s arrive through `_init()`. Nothing
## here calls `load()` or `preload()`, consults a registry, or asks `GameState`
## for a template -- `rules/` has no outbound dependency on `res://resources/`.
##
## **The two symbols come from different places, and neither is written here.**
## The attack roll matches `weapon.weapon_type`; the save roll matches
## `save_profile.match_symbol`, because `FighterTemplate` carries `save` as a
## dice count with no save *type*. No balance value, symbol string included,
## may live in GDScript.
##
## **Defeat removes the board occupant, not the payload.** Spec §9 takes a
## defeated fighter off the board, so `resolve()` calls
## `Board.remove_occupant()` and leaves the payload in `GameState` with its
## counter at or above health, where `Fighter.is_defeated()` keeps answering
## true.
##
## Adding this action required no edit to `ActionRunner` and none to
## `Authority`: generality comes from subclassing `resolve()`.
class_name AttackAction
extends TurnAction

## The state holds no fighter with this action's `actor_id()`. Deliberately a
## different constant from `Authority`'s own "no such fighter" refusal -- the
## two vocabularies stay separate, exactly as `PassAction` sets the precedent.
const FAILURE_NO_SUCH_FIGHTER := &"attack_no_such_fighter"

## The state holds no fighter with this action's target id.
const FAILURE_NO_SUCH_TARGET := &"attack_no_such_target"

## The target and the actor are the same fighter.
const FAILURE_TARGET_IS_SELF := &"attack_target_is_self"

## The target shares the actor's `owner_id`.
const FAILURE_TARGET_IS_FRIENDLY := &"attack_target_is_friendly"

## The target stands further than the weapon's `range_hexes`. The boundary is
## inclusive: a target at exactly `range_hexes` is in range.
const FAILURE_TARGET_OUT_OF_RANGE := &"attack_target_out_of_range"

## A BLOCKED hex, or a coordinate with no hex at all, intervenes.
const FAILURE_NO_LINE_OF_SIGHT := &"attack_no_line_of_sight"

## The target's damage counter is already at or above its health.
const FAILURE_TARGET_ALREADY_DEFEATED := &"attack_target_already_defeated"

## One of the four injected objects is `null`, or a fighter payload could not be
## parsed. Refusing beats crashing, and beats resolving against a guess.
const FAILURE_MISSING_DATA := &"attack_missing_data"

## The fighter this action attacks. Set once, at construction.
var _target_id: String

## The authored data this resolver needs, all injected, none resolved.
var _weapon: WeaponTemplate
var _target_template: FighterTemplate
var _attack_profile: DiceProfile
var _save_profile: DiceProfile

## The resolution detail, read back through the accessors below. Every value
## here is meaningless until `resolve()` has returned a successful `TurnResult`;
## `_outcome` starts at `MISS` only because the enum has no "unresolved"
## member and one of the three has to be the initial value.
var _outcome: DicePool.Outcome = DicePool.Outcome.MISS
var _attack_successes: int = 0
var _save_successes: int = 0
var _attack_bonus: int = 0
var _save_bonus: int = 0
var _target_defeated: bool = false


## Every argument is required and every one is stored exactly as given; nothing
## is validated here. A `null` template or profile is refused by `resolve()`
## with `FAILURE_MISSING_DATA`, which is where it can actually be answered.
func _init(
	actor_id: String,
	target_id: String,
	weapon: WeaponTemplate,
	target_template: FighterTemplate,
	attack_profile: DiceProfile,
	save_profile: DiceProfile
) -> void:
	super(actor_id)
	_target_id = target_id
	_weapon = weapon
	_target_template = target_template
	_attack_profile = attack_profile
	_save_profile = save_profile


## Resolves the attack against `state`, per spec §7.
##
## Refuses first, changing nothing at all -- `_refusal()` below fixes the order
## the reasons are tried in, so a request failing more than one condition always
## reports the same one.
##
## Then, in this order and no other: build the flanking candidates, read the
## attack bonus off the target and the save bonus off the attacker, roll the
## attack pool, roll the save pool, count both, compare, and on a `HIT` apply
## damage and check defeat.
##
## Returns `TurnResult.ok()` for `HIT`, `DRAWN` and `MISS` alike.
func resolve(state: GameState) -> TurnResult:
	var attacker := _read_fighter(state.fighter(actor_id()))
	var target := _read_fighter(state.fighter(_target_id))

	var reason := _refusal(state, attacker, target)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	_resolve_attack(state, attacker, target)
	return TurnResult.ok()


## Hit / Drawn / Miss, valid once `resolve()` has returned successfully.
func outcome() -> DicePool.Outcome:
	return _outcome


## Successes counted on the attack roll.
func attack_successes() -> int:
	return _attack_successes


## Successes counted on the save roll.
func save_successes() -> int:
	return _save_successes


## Extra success-symbol types the target's neighbours unlocked on the attack
## roll: `Flanking.NONE`, `FLANKED` or `SURROUNDED`.
func attack_bonus_count() -> int:
	return _attack_bonus


## Extra success-symbol types the attacker's neighbours unlocked on the save
## roll.
func save_bonus_count() -> int:
	return _save_bonus


## True when this attack took the target's counter to or past its health.
## Always false for a `DRAWN` or `MISS`, and false before `resolve()` runs; an
## already-defeated target is refused, so this attack is the only way it becomes
## true.
func target_defeated() -> bool:
	return _target_defeated


## Why this attack cannot resolve, or `&""` when it can.
##
## The single implementation of the predicate, in two halves and one fixed
## order: is there an attack to resolve at all, and then is this a legal target.
## `Authority.refusal()` sets the shape -- one predicate, one order, no second
## copy -- though the two answer entirely separate questions in entirely
## separate vocabularies and neither may be expressed in the other's terms.
##
## `attacker` and `target` are the parsed payloads, either of which may be
## `null` here; `_identity_refusal()` is what guarantees they are not by the
## time `_targeting_refusal()` reads them.
func _refusal(state: GameState, attacker: Fighter, target: Fighter) -> StringName:
	var identity := _identity_refusal(state, attacker, target)
	if not identity.is_empty():
		return identity

	return _targeting_refusal(state, attacker, target)


## Is there an attack to resolve at all: the injected data, both fighters
## existing, both payloads parsing, and the target not being the attacker.
##
## A `null` parse is two different refusals depending on why. A fighter the
## state does not hold is `FAILURE_NO_SUCH_FIGHTER` or `FAILURE_NO_SUCH_TARGET`;
## a fighter it does hold whose payload `Fighter.from_dict()` rejects is
## `FAILURE_MISSING_DATA`, since something is wrong with the data rather than
## with the request.
func _identity_refusal(state: GameState, attacker: Fighter, target: Fighter) -> StringName:
	if _weapon == null or _target_template == null:
		return FAILURE_MISSING_DATA
	if _attack_profile == null or _save_profile == null:
		return FAILURE_MISSING_DATA

	if attacker == null:
		var ids := state.fighter_ids()
		return FAILURE_NO_SUCH_FIGHTER if actor_id() not in ids else FAILURE_MISSING_DATA

	if target == null:
		var ids := state.fighter_ids()
		return FAILURE_NO_SUCH_TARGET if _target_id not in ids else FAILURE_MISSING_DATA

	if _target_id == actor_id():
		return FAILURE_TARGET_IS_SELF

	return &""


## Is this a legal target: not friendly, within the weapon's reach, visible, and
## not already defeated. Both fighters are non-`null` by the time this runs.
##
## Range is inclusive at the boundary -- `distance <= range_hexes` -- and
## visibility is the board's own centre-to-centre line, which already answers
## "off the board" as blocked.
func _targeting_refusal(state: GameState, attacker: Fighter, target: Fighter) -> StringName:
	if target.owner_id() == attacker.owner_id():
		return FAILURE_TARGET_IS_FRIENDLY

	if HexCoord.distance(attacker.position(), target.position()) > _weapon.range_hexes:
		return FAILURE_TARGET_OUT_OF_RANGE

	if not state.board.has_line_of_sight(attacker.position(), target.position()):
		return FAILURE_NO_LINE_OF_SIGHT

	if target.is_defeated():
		return FAILURE_TARGET_ALREADY_DEFEATED

	return &""


## Spec §7 steps 2 to 6, on a request that has already passed `_refusal()`.
##
## The bonuses are read before either pool is rolled, because both are pure
## adjacency and neither touches the generator. Then the attack pool entirely,
## then the save pool entirely; see the class docstring on why that order is the
## contract.
func _resolve_attack(state: GameState, attacker: Fighter, target: Fighter) -> void:
	var candidates := _flanking_candidates(state)
	_attack_bonus = Flanking.bonus_count(
		target.position(), target.owner_id(), actor_id(), candidates
	)
	_save_bonus = Flanking.bonus_count(
		attacker.position(), attacker.owner_id(), _target_id, candidates
	)

	var attack_roll := DicePool.roll(_attack_profile, _weapon.dice_count, state.rng)
	var save_roll := DicePool.roll(_save_profile, _target_template.save, state.rng)

	_attack_successes = DicePool.count_successes(
		attack_roll, DicePool.success_symbols(_attack_profile, _weapon.weapon_type, _attack_bonus)
	)
	_save_successes = DicePool.count_successes(
		save_roll, DicePool.success_symbols(_save_profile, _save_profile.match_symbol, _save_bonus)
	)

	_outcome = DicePool.outcome(_attack_successes, _save_successes)
	if _outcome == DicePool.Outcome.HIT:
		_apply_hit(state, target)


## Applies the weapon's damage to `target`, commits the payload, and takes the
## fighter off the board when the damage defeated it.
##
## The payload stays in `GameState` either way -- spec §9 removes a defeated
## fighter from the *board*, and `Fighter.is_defeated()` has to keep answering
## true for the stored record.
func _apply_hit(state: GameState, target: Fighter) -> void:
	target.apply_damage(_weapon.damage_value)
	state.update_fighter(_target_id, target.to_dict())

	_target_defeated = target.is_defeated()
	if _target_defeated:
		state.board.remove_occupant(target.position())


## `Flanking`'s normalised candidate view -- `{"id", "owner_id", "position"}`
## with the position as a `Vector3i` -- one entry per fighter in
## `state.fighter_ids()` that is still standing on the board.
##
## **"Still standing" is how a defeated fighter is excluded.** Defeat is what
## `_apply_hit()` above expresses by calling `Board.remove_occupant()`, so a
## fighter the board no longer reports at its recorded position is exactly a
## fighter this engine has already defeated, and a fighter off the board flanks
## nobody. Reading each payload's counter against its own health is not
## available here and must not be faked: only the *target's* `FighterTemplate`
## is injected, and measuring another fighter's health against it would be a
## guess dressed as a rule.
##
## A payload that will not parse is skipped rather than refused, matching
## `Flanking`'s own handling of an unreadable candidate: an unreadable fighter
## is not an enemy, and skipping is the safe direction.
func _flanking_candidates(state: GameState) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	for fighter_id in state.fighter_ids():
		var fighter := _read_fighter(state.fighter(fighter_id))
		if fighter == null:
			continue
		if state.board.occupant_at(fighter.position()) != StringName(fighter.id()):
			continue

		var candidate: Dictionary = {
			Flanking.ID_KEY: fighter.id(),
			Flanking.OWNER_ID_KEY: fighter.owner_id(),
			Flanking.POSITION_KEY: fighter.position(),
		}
		candidates.append(candidate)

	return candidates


## `payload` as a `Fighter`, or `null` when it will not parse.
##
## Every payload is parsed over `_target_template`, the one `FighterTemplate`
## this action holds, because `Fighter` owns the payload shape and this file may
## not hand-parse a `position` array. `Fighter.from_dict()` documents that it
## neither reads nor matches the payload's `template_id`, so for any fighter but
## the target this reads back the mutable half only -- id, owner and position,
## which is all the candidate list wants. **Do not read a stat off a `Fighter`
## returned here unless it is the target**: its stats would be the target's.
func _read_fighter(payload: Dictionary) -> Fighter:
	return Fighter.from_dict(payload, _target_template)

## Spec §7: one fighter attacks another. The capstone of Slice 0.
##
## `resolve()` validates the target, resolves spec §7.3's two target numbers,
## rolls both d6 pools through the state's seeded generator, counts each pool
## at or above its own target, compares the two totals into Hit / Drawn / Miss,
## and on a Hit applies the attacker's `damage()` and checks defeat.
##
## **It wires three modules together and reimplements none of them.** The
## dice-pool math lives in `DicePool`, the adjacency bonus in `Flanking`, and
## the fighter payload shape in `Fighter`. A second copy of any of that here is
## the primary correctness risk in this project.
##
## **Every number comes from data.** The two fighters' stats come from their
## `FighterTemplate`s and every target, modifier and range from the
## `CombatProfile`; no balance value may live in GDScript. There is no weapon
## and no symbol-faced die -- spec §3 and §7 as revised 2026-09-08 deleted the
## `Weapon` entity and the symbol-matched dice model alike, and the two
## resource classes that carried them are gone from the tree.
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
## **Templates are injected, never resolved.** Both `FighterTemplate`s and the
## `CombatProfile` arrive through `_init()`. Nothing here calls `load()` or
## `preload()`, consults a registry, or asks `GameState` for a template --
## `rules/` has no outbound dependency on `res://resources/`.
##
## **The two target numbers are separate charts, not one.** Spec §7.3 prices
## the attack roll's conditions and the save roll's from different fields, and
## measures them on different fighters. The attack target starts at
## `attack_target` and takes the *target's* flanking priced from the `attack_*`
## modifiers, plus the engagement bonus; the save target starts at
## `save_target` and takes the *attacker's* flanking priced from the `save_*`
## modifiers. Every row is a bonus -- a subtraction -- and
## `CombatProfile.clamped_target()` does the clamping.
##
## **Engagement is measured on the board, never off the Range stat.** The
## distance actually attacked across is what is compared to
## `engagement_range`, so a Range-4 archer standing in contact is engaged
## exactly as a Range-1 warrior is, and the same archer two hexes out is not.
## Engagement is also *not* adjacency: `engagement_range` is a dial an ability
## may one day raise, while `Flanking` is measured in literal adjacency for
## everyone, always, inside `Flanking.bonus_count()`. The two must not be
## routed through one helper.
##
## **Defeat removes the board occupant, not the payload.** Spec §9 takes a
## defeated fighter off the board, so `resolve()` calls
## `Board.remove_occupant()` and leaves the payload in `GameState` with its
## counter at or above health, where `Fighter.is_defeated()` keeps answering
## true.
##
## **Defeat also awards spec §9's flat point.** `_apply_hit()` credits
## `_combat_profile.defeat_award` to `attacker.owner_id()`'s `PlayerState.score`
## -- a flat, authored value, not anything read off either fighter's stats. A
## missing `PlayerState` is skipped rather than refused, since the defeat
## itself has already happened. This is the only seam that exists for the
## award today; nothing routes it through `Authority` or `ActionRunner`.
##
## **A push is optional, declared, and not a move -- spec §7.6-7.7.**
## `push_back` arrives through `_init()`, because spec §7.6 leaves whether to
## attempt the shove to the attacking player, not to this resolver; defaulting
## it to `false` keeps every call site from before this existed unchanged. It
## applies on a `HIT` or a `DRAWN`, never a `MISS`, and never to a target this
## same attack has just defeated -- spec §9 has already taken that fighter off
## the board. The destination is the neighbour of the target's hex furthest
## from the attacker by `HexCoord.distance()`, ties broken by
## `HexCoord.DIRECTIONS` order; see `_push_destination()`. It draws nothing
## from `state.rng` -- the generator's position after an attack is pinned by
## the tests above, and a push must not shift it. And it sets no status flag
## at all: spec §6's `"moved"` flag belongs to a fighter's own chosen move, not
## a shove it did not choose, and no `"moved"` constant exists yet regardless.
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

## The target stands further than the attacker's `range_hexes()`. The boundary
## is inclusive: a target at exactly `range_hexes()` is in range.
const FAILURE_TARGET_OUT_OF_RANGE := &"attack_target_out_of_range"

## A BLOCKED hex, or a coordinate with no hex at all, intervenes.
const FAILURE_NO_LINE_OF_SIGHT := &"attack_no_line_of_sight"

## The target's damage counter is already at or above its health.
const FAILURE_TARGET_ALREADY_DEFEATED := &"attack_target_already_defeated"

## One of the three injected objects is `null`, or a fighter payload could not
## be parsed. Refusing beats crashing, and beats resolving against a guess.
const FAILURE_MISSING_DATA := &"attack_missing_data"

## The fighter this action attacks. Set once, at construction.
var _target_id: String

## The authored data this resolver needs, all injected, none resolved.
##
## Both templates are required and neither stands in for the other: the
## attacker's stats decide the pool size, the damage and the reach, and the
## target's decide the save pool. Parsing one fighter over the other's template
## resolves the attack with the wrong fighter's numbers -- a wrong answer, not
## a crash.
var _attacker_template: FighterTemplate
var _target_template: FighterTemplate
var _combat_profile: CombatProfile

## Declared intent, set once at construction: whether the attacking player
## wants the target shoved on a Hit or a Drawn. See the class docstring.
var _push_back: bool = false

## The resolution detail, read back through the accessors below. Every value
## here is meaningless until `resolve()` has returned a successful `TurnResult`;
## `_outcome` starts at `MISS` only because the enum has no "unresolved"
## member and one of the three has to be the initial value.
var _outcome: DicePool.Outcome = DicePool.Outcome.MISS
var _attack_successes: int = 0
var _save_successes: int = 0
var _attack_bonus: int = 0
var _save_bonus: int = 0
var _attack_target: int = 0
var _save_target: int = 0
var _target_defeated: bool = false

## Whether `_apply_push()` actually moved the target. False until `resolve()`
## runs, and false forever when `push_back` was never true.
var _pushed: bool = false


## Every argument is required and every one is stored exactly as given; nothing
## is validated here. A `null` template or profile is refused by `resolve()`
## with `FAILURE_MISSING_DATA`, which is where it can actually be answered.
##
## `push_back` defaults to `false`, so every call site and every test written
## before this parameter existed remains valid unchanged.
func _init(
	actor_id: String,
	target_id: String,
	attacker_template: FighterTemplate,
	target_template: FighterTemplate,
	combat_profile: CombatProfile,
	push_back: bool = false
) -> void:
	super(actor_id)
	_target_id = target_id
	_attacker_template = attacker_template
	_target_template = target_template
	_combat_profile = combat_profile
	_push_back = push_back


## Resolves the attack against `state`, per spec §7.
##
## Refuses first, changing nothing at all -- `_refusal()` below fixes the order
## the reasons are tried in, so a request failing more than one condition always
## reports the same one.
##
## Then, in this order and no other: build the flanking candidates, read the
## attack bonus off the target and the save bonus off the attacker, resolve
## both target numbers, roll the attack pool, roll the save pool, count both,
## compare, and on a `HIT` apply damage and check defeat.
##
## Returns `TurnResult.ok()` for `HIT`, `DRAWN` and `MISS` alike.
func resolve(state: GameState) -> TurnResult:
	var attacker := _read_fighter(state.fighter(actor_id()), _attacker_template)
	var target := _read_fighter(state.fighter(_target_id), _target_template)

	var reason := _refusal(state, attacker, target)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	_resolve_attack(state, attacker, target)
	return TurnResult.ok()


## Hit / Drawn / Miss, valid once `resolve()` has returned successfully.
func outcome() -> DicePool.Outcome:
	return _outcome


## Successes counted on the attack roll: dice at or above `attack_target()`.
func attack_successes() -> int:
	return _attack_successes


## Successes counted on the save roll: dice at or above `save_target()`.
func save_successes() -> int:
	return _save_successes


## The effective attack target number this resolution used, after the target's
## flanking, the engagement bonus and the profile's clamp.
func attack_target() -> int:
	return _attack_target


## The effective save target number this resolution used, after the attacker's
## flanking and the profile's clamp.
func save_target() -> int:
	return _save_target


## The tier the target's neighbours reached, and so which `attack_*` modifier
## priced the attack target: `Flanking.NONE`, `FLANKED` or `SURROUNDED`.
func attack_bonus_count() -> int:
	return _attack_bonus


## The tier the *attacker's* neighbours reached, and so which `save_*` modifier
## priced the save target.
func save_bonus_count() -> int:
	return _save_bonus


## True when this attack took the target's counter to or past its health.
## Always false for a `DRAWN` or `MISS`, and false before `resolve()` runs; an
## already-defeated target is refused, so this attack is the only way it becomes
## true.
func target_defeated() -> bool:
	return _target_defeated


## True when spec §7.6-7.7's push actually moved the target. Always false when
## `push_back` was `false`, false on a `MISS`, false for a target this attack
## defeated, and false when the computed destination was refused -- see
## `_apply_push()`.
func pushed() -> bool:
	return _pushed


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
	if _attacker_template == null or _target_template == null:
		return FAILURE_MISSING_DATA
	if _combat_profile == null:
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


## Is this a legal target: not friendly, within the attacker's reach, visible,
## and not already defeated. Both fighters are non-`null` by the time this runs.
##
## Range is the *attacker's* `range_hexes()`, inclusive at the boundary --
## `distance <= range_hexes()` -- and visibility is the board's own
## centre-to-centre line, which already answers "off the board" as blocked.
func _targeting_refusal(state: GameState, attacker: Fighter, target: Fighter) -> StringName:
	if target.owner_id() == attacker.owner_id():
		return FAILURE_TARGET_IS_FRIENDLY

	if HexCoord.distance(attacker.position(), target.position()) > attacker.range_hexes():
		return FAILURE_TARGET_OUT_OF_RANGE

	if not state.board.has_line_of_sight(attacker.position(), target.position()):
		return FAILURE_NO_LINE_OF_SIGHT

	if target.is_defeated():
		return FAILURE_TARGET_ALREADY_DEFEATED

	return &""


## Spec §7 steps 2 to 6, on a request that has already passed `_refusal()`.
##
## The bonuses and both target numbers are resolved before either pool is
## rolled, because all of that is pure adjacency and arithmetic and none of it
## touches the generator. Then the attack pool entirely, then the save pool
## entirely; see the class docstring on why that order is the contract.
func _resolve_attack(state: GameState, attacker: Fighter, target: Fighter) -> void:
	var candidates := _flanking_candidates(state)
	_attack_bonus = Flanking.bonus_count(
		target.position(), target.owner_id(), actor_id(), candidates
	)
	_save_bonus = Flanking.bonus_count(
		attacker.position(), attacker.owner_id(), _target_id, candidates
	)

	_attack_target = _resolved_attack_target(attacker, target)
	_save_target = _resolved_save_target()

	var attack_roll := DicePool.roll_dice(attacker.attack(), _combat_profile.die_sides, state.rng)
	var save_roll := DicePool.roll_dice(target.save(), _combat_profile.die_sides, state.rng)

	_attack_successes = DicePool.count_at_or_above(attack_roll, _attack_target)
	_save_successes = DicePool.count_at_or_above(save_roll, _save_target)

	_outcome = DicePool.outcome(_attack_successes, _save_successes)
	if _outcome == DicePool.Outcome.HIT:
		_apply_hit(state, attacker, target)

	var hit_or_drawn := _outcome == DicePool.Outcome.HIT or _outcome == DicePool.Outcome.DRAWN
	if _push_back and hit_or_drawn and not _target_defeated:
		_apply_push(state, attacker, target)


## Spec §7.3's attack chart: the profile's `attack_target`, less the *target's*
## flanking priced from the `attack_*` modifiers, less the engagement bonus,
## clamped.
##
## `_engagement_bonus()` is passed as `target_modifier()`'s signed `extra`,
## already negative, because every §7.3 row is a bonus.
func _resolved_attack_target(attacker: Fighter, target: Fighter) -> int:
	var modifier := DicePool.target_modifier(
		_attack_bonus,
		_combat_profile.attack_flank_modifier,
		_combat_profile.attack_surround_modifier,
		_engagement_bonus(attacker, target)
	)
	return _combat_profile.clamped_target(_combat_profile.attack_target, modifier)


## Spec §7.3's save chart: the profile's `save_target`, less the *attacker's*
## flanking priced from the `save_*` modifiers -- larger magnitudes than the
## attack chart's, and keyed on the other fighter -- clamped.
##
## `extra` is `0`. Spec §7.3's other save-chart row is Guard, whose
## `guard_modifier` this action deliberately leaves unread: the `guarded` flag
## has no writer until the Guard action exists.
func _resolved_save_target() -> int:
	var modifier := DicePool.target_modifier(
		_save_bonus, _combat_profile.save_flank_modifier, _combat_profile.save_surround_modifier, 0
	)
	return _combat_profile.clamped_target(_combat_profile.save_target, modifier)


## `-engagement_modifier` when the attacker stands at or within
## `engagement_range` of the target, `0` otherwise. Negative because engagement
## is a bonus.
##
## The distance measured is the one actually attacked across, read off the
## board. It is **not** derived from `attacker.range_hexes()`: a long-ranged
## fighter standing in contact is engaged like any other, and a fighter
## shooting from further out is not, whatever its Range stat says.
func _engagement_bonus(attacker: Fighter, target: Fighter) -> int:
	var distance := HexCoord.distance(attacker.position(), target.position())
	if distance <= _combat_profile.engagement_range:
		return -_combat_profile.engagement_modifier

	return 0


## Applies the *attacker's* damage to `target`, commits the payload, takes the
## fighter off the board when the damage defeated it, and on a defeat awards
## spec §9's flat point to the attacker's owner.
##
## `attacker.damage()`, never the target's: the two fighters have different
## stats, and reading the wrong one is a wrong result rather than a crash.
##
## The payload stays in `GameState` either way -- spec §9 removes a defeated
## fighter from the *board*, and `Fighter.is_defeated()` has to keep answering
## true for the stored record.
##
## The award is `_combat_profile.defeat_award`, a flat authored value rather
## than anything read off either fighter -- §3.2 deleted `pointValue`, and this
## is not its replacement in disguise. The recipient is `attacker.owner_id()`;
## a state with no `PlayerState` for that id is skipped, not refused -- the
## defeat itself has already happened by the time the award is reached, so
## there is nothing left to refuse. Draws nothing from `state.rng`.
func _apply_hit(state: GameState, attacker: Fighter, target: Fighter) -> void:
	target.apply_damage(attacker.damage())
	state.update_fighter(_target_id, target.to_dict())

	_target_defeated = target.is_defeated()
	if not _target_defeated:
		return

	state.board.remove_occupant(target.position())

	var scorer := state.player(attacker.owner_id())
	if scorer != null:
		scorer.score += _combat_profile.defeat_award


## Spec §7.6-7.7: shoves `target` one hex directly away from `attacker`, on a
## `HIT` or a `DRAWN`. The caller has already excluded `MISS` and a target this
## same attack defeated; nothing here re-checks either.
##
## Tries `Board.place_occupant()` at the computed destination *before*
## touching the target's current hex, and returns having changed nothing when
## that placement is refused -- the architecture constraint that
## `place_occupant()`'s return is checked before the payload is committed. The
## origin is freed only once the destination is secured, so a refused push
## never leaves the target standing on no hex at all; because the destination
## is always a distinct neighbour of the origin, freeing the origin afterwards
## rather than beforehand changes nothing about which pushes succeed. Draws
## nothing from `state.rng`, and sets no status flag -- see the class
## docstring.
func _apply_push(state: GameState, attacker: Fighter, target: Fighter) -> void:
	var origin := target.position()
	var destination := _push_destination(attacker.position(), origin)

	if not state.board.place_occupant(destination, StringName(_target_id)):
		return

	state.board.remove_occupant(origin)
	target.move_to(destination)
	state.update_fighter(_target_id, target.to_dict())
	_pushed = true


## The neighbour of `origin` furthest from `attacker_position` by
## `HexCoord.distance()`. `HexCoord.neighbours()` returns the six neighbours in
## fixed `HexCoord.DIRECTIONS` order, and only a strictly greater distance ever
## replaces the current pick here, so the first neighbour reaching the maximum
## distance wins any tie -- the lowest `HexCoord.DIRECTIONS` index, exactly as
## the tie-break this class documents.
##
## Not `target + (target - attacker)`: that is a single hex step, correct only
## when `attacker` and `target` are already adjacent, and wrong for a ranged
## attack at distance 2 or more.
func _push_destination(attacker_position: Vector3i, origin: Vector3i) -> Vector3i:
	var neighbours := HexCoord.neighbours(origin)
	var best: Vector3i = neighbours[0]
	var best_distance := HexCoord.distance(attacker_position, best)

	for neighbour in neighbours.slice(1):
		var distance := HexCoord.distance(attacker_position, neighbour)
		if distance > best_distance:
			best = neighbour
			best_distance = distance

	return best


## `Flanking`'s normalised candidate view -- `{"id", "owner_id", "position"}`
## with the position as a `Vector3i` -- one entry per fighter in
## `state.fighter_ids()` that is still standing on the board.
##
## **"Still standing" is how a defeated fighter is excluded.** Defeat is what
## `_apply_hit()` above expresses by calling `Board.remove_occupant()`, so a
## fighter the board no longer reports at its recorded position is exactly a
## fighter this engine has already defeated, and a fighter off the board flanks
## nobody. Reading each payload's counter against its own health is not
## available here and must not be faked: only the two participants' templates
## are injected, and measuring a third fighter's health against either would be
## a guess dressed as a rule.
##
## Every candidate is parsed over `_target_template`, and that is safe for
## exactly the reason `_read_fighter()` gives: a candidate contributes only its
## id, owner and position, none of which come from a template.
##
## A payload that will not parse is skipped rather than refused, matching
## `Flanking`'s own handling of an unreadable candidate: an unreadable fighter
## is not an enemy, and skipping is the safe direction.
func _flanking_candidates(state: GameState) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	for fighter_id in state.fighter_ids():
		var fighter := _read_fighter(state.fighter(fighter_id), _target_template)
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


## `payload` as a `Fighter` over `template`, or `null` when it will not parse.
##
## The template is a parameter rather than a fixed field because this action
## holds two and they are not interchangeable. `resolve()` parses the attacker
## over `_attacker_template` and the target over `_target_template`, so every
## stat either one reads through -- `range_hexes()`, `attack()`, `damage()`,
## `save()` -- is its own.
##
## `_flanking_candidates()` is the one caller that may pass either template,
## because a candidate contributes only its id, owner and position:
## `Fighter.from_dict()` documents that it neither reads nor matches the
## payload's `template_id`, so for a fighter that is neither participant this
## reads back the mutable half only. Do not read a stat off a `Fighter`
## returned to that caller.
func _read_fighter(payload: Dictionary, template: FighterTemplate) -> Fighter:
	return Fighter.from_dict(payload, template)

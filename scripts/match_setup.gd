## The dev-authored starting state a hotseat scene is handed: a board, two
## players, and a small roster each, built from the authored fighter templates
## and the authored round structure.
##
## This is spec §4 Setup's *placeholder*, not §4 Setup itself -- see the class
## docstring's own architecture constraints in the Issue that added this file.
## No roster building against `ConstructionBudget`, no deployment rules, no
## mulligan, no roll-off. It builds a `GameState` and hands it back; it
## constructs no `Authority`, no `RoundDriver`, resolves nothing and submits
## nothing.
##
## **Authored numbers stay authored.** `turns_per_player` and
## `rounds_per_match` come off `res://resources/round/round_profile.tres`, and
## every fighter's stats come off its own authored `.tres` under
## `res://resources/fighters/`. Nothing here restates a stat or a round number
## as a literal. The board radius, the seed and the starting hexes are this
## fixture's own and are named constants below.
##
## **Static methods only, `RefCounted` base** -- the same shape `TurnSequence`,
## `PowerStep`, `EndSegment` and `DefaultActionStep` already use. Never
## instantiated.
##
## **Placements are legal by construction.** Every starting hex named below is
## on the board this class builds, each is empty before its fighter is placed,
## and every distance between a hex on one side and a hex on the other is well
## past `HexCoord.are_adjacent()`'s threshold of 1 -- see the constants'
## docstrings for the actual distances. The opening Turn is therefore a real
## choice, never a forced melee.
##
## **Determinism is a property of the state this returns, not of this class.**
## `build()` seeds `state.rng` from `match_seed` and draws nothing from it --
## the same discipline `RoundDriver`'s own docstring states for itself.
class_name MatchSetup
extends RefCounted

## Where the authored round structure lives. Never named from `rules/`.
const ROUND_PROFILE_PATH := "res://resources/round/round_profile.tres"

## Where the authored combat numbers live.
const COMBAT_PROFILE_PATH := "res://resources/combat/combat_profile.tres"

## The seed `build()` uses when its caller does not supply one. Nothing about
## this value matters beyond its being fixed, the same convention
## `tests/round_driver_test.gd`'s own `SEED` documents for itself.
const DEFAULT_SEED := 20260912

## How many rings of hexes `_board()` builds, centred on the origin.
const BOARD_RADIUS := 3

## The two players, added in this order -- `turn_order()` names `p1` first.
const PLAYER_ONE := "p1"
const PLAYER_TWO := "p2"

## The `template_id`s of this fixture's two authored templates, matching
## `resources/fighters/warrior.tres` and `resources/fighters/archer.tres`.
## Naming which template a fighter is built from is a game-side decision --
## see `FighterTemplates`'s own docstring -- and this is that decision, made
## once, here.
const WARRIOR_TEMPLATE_ID := "warrior"
const ARCHER_TEMPLATE_ID := "archer"

## This fixture's four fighter ids, one per starting hex below.
const P1_WARRIOR_ID := "p1-warrior"
const P1_ARCHER_ID := "p1-archer"
const P2_WARRIOR_ID := "p2-warrior"
const P2_ARCHER_ID := "p2-archer"

## The four starting hexes: `p1`'s pair on one side of the board, `p2`'s pair
## on the opposite side, mirrored through the origin. Every cross-player
## distance among the four is 6, and the two distances within a single
## player's pair are 3 -- both well past the 1 that would make a fighter
## `HexCoord.are_adjacent()` to an enemy.
const P1_WARRIOR_START := Vector3i(-3, 3, 0)
const P1_ARCHER_START := Vector3i(-3, 0, 3)
const P2_WARRIOR_START := Vector3i(3, -3, 0)
const P2_ARCHER_START := Vector3i(3, 0, -3)


## Builds a playable starting `GameState`: a hexagonal board of `BOARD_RADIUS`
## rings, every hex `Board.HexType.NORMAL`; `p1` then `p2` added to the turn
## order; `turns_per_player` and `rounds_per_match` read off the authored
## `RoundProfile`; and two fighters per player -- one `warrior`, one `archer`
## -- placed on the starting hexes above and registered as the board's
## occupant of each.
static func build(match_seed: int = DEFAULT_SEED) -> GameState:
	var state := GameState.new(_board(), DeterministicRng.new(match_seed))
	state.add_player(PLAYER_ONE)
	state.add_player(PLAYER_TWO)

	var profile: RoundProfile = load(ROUND_PROFILE_PATH)
	state.turns_per_player = profile.turns_per_player
	state.rounds_per_match = profile.rounds_per_match

	var fighter_templates := templates()
	_place(
		state, fighter_templates, P1_WARRIOR_ID, PLAYER_ONE, WARRIOR_TEMPLATE_ID, P1_WARRIOR_START
	)
	_place(state, fighter_templates, P1_ARCHER_ID, PLAYER_ONE, ARCHER_TEMPLATE_ID, P1_ARCHER_START)
	_place(
		state, fighter_templates, P2_WARRIOR_ID, PLAYER_TWO, WARRIOR_TEMPLATE_ID, P2_WARRIOR_START
	)
	_place(state, fighter_templates, P2_ARCHER_ID, PLAYER_TWO, ARCHER_TEMPLATE_ID, P2_ARCHER_START)

	return state


## The game-side `template_id` -> `FighterTemplate` lookup, populated from
## every authored `.tres` under `res://resources/fighters/`. The same set
## `build()` itself builds fighters from, so a caller's lookup and the state's
## payloads always name the same templates.
static func templates() -> FighterTemplates:
	return FighterTemplates.from_directory()


## The authored combat numbers, loaded fresh each call -- the same pattern
## `tests/round_driver_test.gd`'s own `_combat_profile()` uses.
static func combat_profile() -> CombatProfile:
	return load(COMBAT_PROFILE_PATH)


## A hexagonal board of `BOARD_RADIUS` rings, every hex `Board.HexType.NORMAL`
## -- the same construction `tests/round_driver_test.gd`'s own `_board()`
## uses.
static func _board() -> Board:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			board.add_hex(Vector3i(x, y, -x - y), Board.HexType.NORMAL)
	return board


## Builds a `Fighter` for `fighter_id`, owned by `owner_id`, from the template
## `template_id` names in `fighter_templates`, standing at `coord` -- then
## records its payload in `state` and registers it as `state.board`'s occupant
## of `coord`, so `Board.occupant_at()` and `GameState.fighter()` agree from
## the moment this fixture is built.
static func _place(
	state: GameState,
	fighter_templates: FighterTemplates,
	fighter_id: String,
	owner_id: String,
	template_id: String,
	coord: Vector3i
) -> void:
	var fighter_template := fighter_templates.template(template_id)
	var fighter := Fighter.new(fighter_id, fighter_template, owner_id, coord)
	state.add_fighter(fighter_id, fighter.to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))

## The whole of a match, serializable to a plain `Dictionary` and back.
##
## Spec §3's `GameState`: the board, the fighters, each player's piles and
## score, the round and turn counters, and the seeded generator's seed *and*
## its current position. A snapshot that omits the generator position cannot
## reproduce the match that follows it, so `rng` is serialized alongside
## everything else rather than reconstructed from a seed.
##
## **Fighters are opaque payloads.** There is no `Fighter` type here and there
## must not be. `add_fighter()` takes a `Dictionary` of JSON-compatible
## values, stores it, and never reads a key of it -- the same seam `Board`
## already keeps for occupant ids, and the same one the card piles keep for
## card ids in `PlayerState`. This class owns the slot and its serialization,
## not the contents.
##
## **The state owns the generator; functions still take it explicitly.**
## Randomness is passed in, never reached for: a resolver receives
## `state.rng` as an argument. That is why there is no `roll_die()`
## passthrough on this class -- a convenience wrapper would hide the
## generator behind the state, which is the ambient-randomness habit under a
## different name. `rng` is the only route to a random number here.
##
## **Ordering is part of the state.** `_turn_order` and `_fighter_order` are
## explicit arrays rather than `Dictionary` key iteration, and `to_dict()`
## builds its keys in a fixed order and populates `players` and `fighters` by
## walking them. Two states built by the same sequence of calls therefore
## stringify identically, character for character, which is what makes
## `digest()` a usable identity.
class_name GameState
extends RefCounted

## The hex board. Public because callers place and move occupants on it
## directly; `to_dict()` nests its `to_dict()`.
var board: Board

## The seeded generator. Public and passed *out* to resolvers, never wrapped.
var rng: DeterministicRng

## Spec §3's round and turn counters. Named `round_number` and `turns_taken`
## rather than `round` and `turn` because `round()` is a GDScript global
## function and a member shadowing it is at best a warning -- the same
## reasoning that forced `get_seed()`/`get_state()` in `DeterministicRng`.
##
## These are fields. What increments them, and what a round or a turn means,
## is a later Feature's business.
var round_number: int = 1
var turns_taken: int = 0

## player id -> PlayerState, for every player added.
var _players: Dictionary = {}

## Player ids in the order they were added. This is the canonical player
## list, not a derived view of `_players`.
var _turn_order: Array[String] = []

## fighter id -> opaque payload Dictionary.
var _fighters: Dictionary = {}

## Fighter ids in the order they were added.
var _fighter_order: Array[String] = []


## Both a board and a generator are required. A state with neither cannot be
## resolved against and cannot be reproduced, so there is no default for
## either.
func _init(state_board: Board, state_rng: DeterministicRng) -> void:
	board = state_board
	rng = state_rng


## The player ids, in the order they were added. Doubles as the canonical
## player list. A copy, so a caller cannot reorder the turn order by mutating
## the returned array.
func turn_order() -> Array[String]:
	return _turn_order.duplicate()


## Adds a player with an empty `PlayerState`. Returns `false` and changes
## nothing when `player_id` is empty or already present.
func add_player(player_id: String) -> bool:
	if player_id.is_empty():
		return false
	if _players.has(player_id):
		return false

	_players[player_id] = PlayerState.new()
	_turn_order.append(player_id)
	return true


## The live `PlayerState` for `player_id`, or `null` when there is no such
## player. Live rather than a copy: mutating a score is how a score changes.
func player(player_id: String) -> PlayerState:
	return _players.get(player_id)


## Records `data` as the payload for `fighter_id`. Returns `false` and changes
## nothing when `fighter_id` is empty or already present.
##
## `data` is stored as a deep copy and never inspected -- no key of it is
## read, validated or interpreted here. The copy is what makes the stored
## payload independent of the caller's dictionary.
func add_fighter(fighter_id: String, data: Dictionary) -> bool:
	if fighter_id.is_empty():
		return false
	if _fighters.has(fighter_id):
		return false

	_fighters[fighter_id] = data.duplicate(true)
	_fighter_order.append(fighter_id)
	return true


## The payload for `fighter_id`, or an empty `Dictionary` when there is no
## such fighter. A deep copy, so the stored payload cannot be edited through
## the value handed back.
func fighter(fighter_id: String) -> Dictionary:
	if not _fighters.has(fighter_id):
		return {}
	return (_fighters[fighter_id] as Dictionary).duplicate(true)


## The fighter ids, in the order they were added. A copy.
func fighter_ids() -> Array[String]:
	return _fighter_order.duplicate()


## Replaces the stored payload for `fighter_id` with `data`. Returns `false`
## and changes nothing when `fighter_id` is empty or names no fighter already
## in the state.
##
## `data` is stored as a deep copy and never inspected -- no key of it is
## read, validated or interpreted here, exactly as `add_fighter()`. Does not
## touch `_fighter_order`: the id is already present, so its position in the
## canonical order is unchanged.
func update_fighter(fighter_id: String, data: Dictionary) -> bool:
	if fighter_id.is_empty():
		return false
	if not _fighters.has(fighter_id):
		return false

	_fighters[fighter_id] = data.duplicate(true)
	return true


## The whole state as JSON-compatible primitives -- `int`, `float`, `String`,
## `Array`, `Dictionary` only, no `Vector3i` and no `StringName`:
##
##   {
##     "board": <Board.to_dict()>,
##     "rng": <DeterministicRng.to_dict()>,
##     "round_number": <int>,
##     "turns_taken": <int>,
##     "turn_order": ["<player id>", ...],
##     "players": {"<player id>": <PlayerState.to_dict()>, ...},
##     "fighter_order": ["<fighter id>", ...],
##     "fighters": {"<fighter id>": <opaque dictionary>, ...}
##   }
##
## Keys are built in exactly that order, and `players` and `fighters` are
## populated by walking `turn_order` and `fighter_order`, so the output of two
## identically built states stringifies to the identical string.
##
## `DeterministicRng` serializes its seed and state as decimal `String`s
## rather than ints, because JSON numbers are doubles and lose precision above
## 2^53. That is deliberate; it is not a shape to clean up.
func to_dict() -> Dictionary:
	var players: Dictionary = {}
	for player_id in _turn_order:
		players[player_id] = (_players[player_id] as PlayerState).to_dict()

	var fighters: Dictionary = {}
	for fighter_id in _fighter_order:
		fighters[fighter_id] = (_fighters[fighter_id] as Dictionary).duplicate(true)

	var turn_order_out: Array = []
	turn_order_out.append_array(_turn_order)

	var fighter_order_out: Array = []
	fighter_order_out.append_array(_fighter_order)

	return {
		"board": board.to_dict(),
		"rng": rng.to_dict(),
		"round_number": round_number,
		"turns_taken": turns_taken,
		"turn_order": turn_order_out,
		"players": players,
		"fighter_order": fighter_order_out,
		"fighters": fighters,
	}


## Rebuilds a `GameState` from `to_dict()`'s shape, producing an entirely
## independent state: the `Board`, the `DeterministicRng` and every
## `PlayerState` are new objects, and every fighter payload is a deep copy, so
## mutating the result cannot reach the state it was serialized from.
##
## Returns `null`, having built nothing usable, on any refusal: a missing or
## non-`Dictionary` `"board"` or `"rng"`; a nested `Board.from_dict()` or
## `DeterministicRng.from_dict()` that itself refuses; a `round_number` or
## `turns_taken` that is not an integer; a `turn_order` or `fighter_order`
## that is not an `Array` of `String`; a `players` or `fighters` that is not a
## `Dictionary`; an id in an order array with no matching entry in its
## dictionary; an entry in a dictionary with no matching id in its order array;
## a duplicate or empty id; or a malformed nested `PlayerState`. Nothing is
## repaired.
static func from_dict(data: Dictionary) -> GameState:
	var board_field: Variant = data.get("board")
	if typeof(board_field) != TYPE_DICTIONARY:
		return null
	var restored_board := Board.from_dict(board_field)
	if restored_board == null:
		return null

	var rng_field: Variant = data.get("rng")
	if typeof(rng_field) != TYPE_DICTIONARY:
		return null
	var restored_rng := DeterministicRng.from_dict(rng_field)
	if restored_rng == null:
		return null

	var round_value: Variant = PlayerState.as_int(data.get("round_number"))
	if round_value == null:
		return null

	var turns_value: Variant = PlayerState.as_int(data.get("turns_taken"))
	if turns_value == null:
		return null

	var turn_order_field: Variant = data.get("turn_order")
	if typeof(turn_order_field) != TYPE_ARRAY:
		return null
	var players_field: Variant = data.get("players")
	if typeof(players_field) != TYPE_DICTIONARY:
		return null

	var fighter_order_field: Variant = data.get("fighter_order")
	if typeof(fighter_order_field) != TYPE_ARRAY:
		return null
	var fighters_field: Variant = data.get("fighters")
	if typeof(fighters_field) != TYPE_DICTIONARY:
		return null

	# Size equality is what catches a `players` or `fighters` entry that no
	# order array names. The per-id loops below catch the other direction, and
	# `add_player()`/`add_fighter()` refuse a duplicate or empty id, so
	# matching sizes plus every id resolving means the two agree exactly.
	if players_field.size() != turn_order_field.size():
		return null
	if fighters_field.size() != fighter_order_field.size():
		return null

	var state := GameState.new(restored_board, restored_rng)
	state.round_number = round_value
	state.turns_taken = turns_value

	for entry in turn_order_field:
		if typeof(entry) != TYPE_STRING:
			return null
		var player_data: Variant = players_field.get(entry)
		if typeof(player_data) != TYPE_DICTIONARY:
			return null
		var player_state := PlayerState.from_dict(player_data)
		if player_state == null:
			return null
		if not state.add_player(entry):
			return null
		state._players[entry] = player_state

	for entry in fighter_order_field:
		if typeof(entry) != TYPE_STRING:
			return null
		var payload: Variant = fighters_field.get(entry)
		if typeof(payload) != TYPE_DICTIONARY:
			return null
		if not state.add_fighter(entry, payload):
			return null

	return state


## The canonical identity of this state: the SHA-256 of
## `JSON.stringify(to_dict())`, as 64 lowercase hex characters.
##
## Two states are equal when their digests are. This is the primitive the
## determinism suite compares runs with, and the reason `to_dict()` fixes its
## key order and refuses non-JSON values -- the hash is taken over the
## stringified form, so anything that varies in that string varies here.
func digest() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(to_dict()).to_utf8_buffer())
	return context.finish().hex_encode()

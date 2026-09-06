## One player's card piles and score, as a serializable data record.
##
## This is a record, not an abstraction: it exists so four typed arrays and a
## score serialize as one unit instead of as a nested untyped `Dictionary`.
## It has no behaviour beyond `to_dict()`/`from_dict()` and must not grow any
## -- "a new abstraction needs a second caller" (AGENTS.md) governs
## behavioural abstractions, and this adds none.
##
## Card ids are opaque `String`s. There is no `Card` type, no deck-type enum
## and no card effect here; the piles are held, and what a card does is later.
## Nothing enforces that an id in `hand` is absent from `deck`, and nothing
## shuffles or draws.
class_name PlayerState
extends RefCounted

## The four card piles, spec §3's per-player state. Each holds opaque card
## ids in the order they were put there; order is preserved by serialization
## because `GameState`'s digest is computed over it.
var hand: Array[String] = []
var deck: Array[String] = []
var discard: Array[String] = []
var scored: Array[String] = []

var score: int = 0


## The four piles and the score as JSON-compatible primitives -- `int`,
## `String`, `Array`, `Dictionary` only. Keys are built in a fixed order so
## two identically built records stringify identically, character for
## character; see `GameState.to_dict()` for why that matters.
func to_dict() -> Dictionary:
	return {
		"hand": _plain(hand),
		"deck": _plain(deck),
		"discard": _plain(discard),
		"scored": _plain(scored),
		"score": score,
	}


## Rebuilds a `PlayerState` from `to_dict()`'s shape.
##
## Returns `null`, having built nothing usable, when any of the five keys is
## missing, when a pile is not an `Array` of `String`, or when `score` is not
## an integer. Nothing is repaired.
static func from_dict(data: Dictionary) -> PlayerState:
	var state := PlayerState.new()

	if not _read_pile(data, "hand", state.hand):
		return null
	if not _read_pile(data, "deck", state.deck):
		return null
	if not _read_pile(data, "discard", state.discard):
		return null
	if not _read_pile(data, "scored", state.scored):
		return null

	var score_value: Variant = as_int(data.get("score"))
	if score_value == null:
		return null
	state.score = score_value

	return state


## An untyped copy of a pile, so the serialized form carries a plain `Array`
## rather than an `Array[String]`. Both stringify identically; the plain one
## is what `JSON.parse_string()` hands back, so a round trip through JSON
## produces a dictionary of exactly the same shape as `to_dict()`.
static func _plain(pile: Array[String]) -> Array:
	var out: Array = []
	out.append_array(pile)
	return out


## Appends `data[key]` into `into`, or returns `false` leaving the caller to
## discard the half-built record.
static func _read_pile(data: Dictionary, key: String, into: Array[String]) -> bool:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_ARRAY:
		return false

	for entry in value:
		if typeof(entry) != TYPE_STRING:
			return false
		into.append(entry)

	return true


## `value` as an `int`, or `null` when it is not an integer.
##
## An integral `float` is accepted because JSON has exactly one number type
## and Godot's `JSON.parse_string()` hands every number back as a `float` --
## `5` in, `5.0` out. A reparsed `5.0` here is an `int` that has been through
## JSON, not a wrong type, and `GameState`'s JSON-compatibility criterion
## requires `from_dict()` to accept it. A fractional `float` is still a
## refusal. Public so `GameState` reads its own integer fields the same way
## rather than keeping a second copy of this rule.
static func as_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) != TYPE_FLOAT:
		return null

	var number: float = value
	if number != floorf(number):
		return null

	return int(number)

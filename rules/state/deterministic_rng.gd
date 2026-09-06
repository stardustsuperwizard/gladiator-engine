## Seeded, serializable random number generator.
##
## Wraps a private RandomNumberGenerator so every draw goes through this
## class's receiver-qualified calls (`_rng.randi_range(...)`), never a bare
## global `randi()`/`randf()` -- see the Ambient RNG contract test and
## .github/instructions/rules.instructions.md. Callers get numbers, never the
## generator itself, so nothing outside this file can advance its position
## behind the state's back.
##
## A snapshot must resume the sequence, not rewind it: to_dict()/from_dict()
## carry both the seed and the current state, and from_dict() is careful to
## assign them in the order that preserves that guarantee. See the comment at
## from_dict() for why the order matters.
class_name DeterministicRng
extends RefCounted

var _rng: RandomNumberGenerator


## The seed is always assigned explicitly. RandomNumberGenerator randomizes
## itself on construction if left alone, which would make a default-built
## generator irreproducible -- the one thing this class exists to prevent.
func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


## The seed this generator was constructed or restored with. Unlike
## get_state(), this never changes as numbers are drawn.
func get_seed() -> int:
	return _rng.seed


## The generator's current position in its sequence. Advances with every
## draw; snapshot this alongside get_seed() to resume rather than rewind.
func get_state() -> int:
	return _rng.state


## The single drawing primitive: an integer in [from, to], inclusive at both
## ends. Every other draw in this class is defined in terms of this one.
##
## Returns `from` without advancing the generator when `to < from` rather than
## raising an error, so a degenerate range has a well-defined answer instead
## of a crash.
func next_int(from: int, to: int) -> int:
	if to < from:
		return from
	return _rng.randi_range(from, to)


## One die numbered 1 through `sides`.
##
## Returns 0 without advancing the generator when `sides < 1` -- there is no
## face to land on.
func roll_die(sides: int) -> int:
	if sides < 1:
		return 0
	return next_int(1, sides)


## Serializes the seed and state as decimal Strings, not ints.
##
## Both are 64-bit values. The canonical serialized-state form (task #23) is
## JSON-compatible primitives, and JSON numbers are IEEE-754 doubles, which
## lose precision above 2^53 -- a generator position past that point would
## silently come back wrong instead of failing loudly. str() and
## String.to_int() round-trip a 64-bit int exactly, so that is the form used
## here instead.
func to_dict() -> Dictionary:
	return {"seed": str(_rng.seed), "state": str(_rng.state)}


## Restores a generator from to_dict()'s output. Returns null when "seed" or
## "state" is missing, or when either value is not a String -- an int would
## already have round-tripped through a lossy double by the time it got here.
static func from_dict(data: Dictionary) -> DeterministicRng:
	if not data.has("seed") or not data.has("state"):
		return null

	var seed_value: Variant = data["seed"]
	var state_value: Variant = data["state"]
	if typeof(seed_value) != TYPE_STRING or typeof(state_value) != TYPE_STRING:
		return null

	var rng := DeterministicRng.new(seed_value.to_int())

	# Assign seed BEFORE state -- the constructor above already has. Writing
	# RandomNumberGenerator.seed resets its state to match that seed, so
	# assigning state first (or letting a later seed write clobber a restored
	# state) would silently rewind the generator to the start of its sequence.
	# State must be the last write.
	rng._rng.state = state_value.to_int()

	return rng

# gdlint:ignore = max-public-methods
#
# That waiver has to be line 1: gdlint reports max-public-methods against the
# class as a whole, at line 1, and an `ignore` covers only the line it sits on
# and the next -- `disable` would start its range below the reported line and
# miss it. Hence a bare directive with its explanation underneath rather than
# above.
#
# The public surface is this task's contract, and every alternative gdlint's
# threshold points at is forbidden by that same contract: the four damage
# predicates may not collapse into one `damage_state()` or a `DamageState`
# enum, and the five stat readers may not move behind a stat-bag object,
# because reading through to the shared template is the design. Twenty-two
# methods, of which twenty are a single-expression read. The waiver is local
# rather than a raised threshold in `.gdlintrc`, so no other file's shape
# changes because of this one's.
##
## What has *happened* to a fighter -- its position, its damage counter, its
## status flags and its owner -- over a shared `FighterTemplate` that says what
## it *is*. Stats are read through to that template and never copied out of it,
## and the template is never written to.
##
## **`RefCounted`, never `Resource`.** This is the whole design. Godot caches
## and shares `Resource` instances: two loads of one `.tres` hand back the
## *same object*, so a runtime fighter that were a `Resource`, or that wrote a
## damage counter onto its template, would corrupt every fighter built from that
## template. See `docs/godot-implementation-guide.md` §3.
##
## The other option §3 offers -- `template.duplicate()` per fighter -- is
## rejected here on purpose: a per-fighter copy makes two fighters disagree
## about their stats once a `.tres` is retuned, and it throws away the "what it
## is" / "what has happened to it" split this class exists to draw. Hold the
## shared reference, and never write through it: not `template.health`, not
## `template.tags`, not an element of `template.weapons`.
##
## `weapons()` and `status_flags()` hand back copies for the same reason.
## `template.weapons` is a shared `Array` on a shared `Resource`, so returning
## the live array would be that same bug with one extra step -- `append()` on
## the value handed back would mutate the template. The weapons copy is
## *shallow*, and deliberately: the `WeaponTemplate` elements stay shared,
## because they are immutable authored data and duplicating them per fighter
## would reintroduce the divergence above.
##
## **Damage -- spec §9.** Four predicates over the damage counter `c` and the
## template's `health` `H`:
##
##   | Predicate         | True when    |
##   | ----------------- | ------------ |
##   | `is_undamaged()`  | `c == 0`     |
##   | `is_damaged()`    | `c > 0`      |
##   | `is_vulnerable()` | `c + 1 >= H` |
##   | `is_defeated()`   | `c >= H`     |
##
## These are four independent descriptions, **not** a four-way partition, and
## two of the overlaps look like bugs and are not:
##
## - A fighter whose template has `health == 1` is **both undamaged and
##   vulnerable** at counter 0. It is untouched, and one point would defeat it.
##   Both are true, and both are correct.
## - A defeated fighter is **also vulnerable**, because `c >= H` implies
##   `c + 1 >= H`.
##
## Do not "correct" either one. A precedence rule, a `DamageState` enum, a
## single `damage_state()` returning one value, or an `is_vulnerable()` that
## excludes the defeated would each invent a rule the spec does not state.
##
## `apply_damage()` is not a healing API: it refuses a non-positive amount
## rather than clamping it, and the counter is not clamped at `health` on the
## way up either, so a counter above health is legitimate state. Nothing here
## removes a defeated fighter from anything -- this class makes defeat
## *queryable*, and what defeat then *does* belongs to attack resolution.
##
## **Status flags are opaque `String`s** kept as an insertion-ordered set. No
## enum of known flags, no clearing at end of round, no rule about which
## combinations are legal.
##
## **Serialization carries the mutable half only.** Stats are not in
## `to_dict()`; they live in the authored template. `from_dict()` therefore
## takes the template as an argument rather than resolving one -- there is no
## path in the serialized form and nothing here reaches for the filesystem,
## because a rules module that did would stop being the self-contained,
## deterministic module the architecture rests on. `template_id` rides along
## purely so a game-side caller can decide which template to pass back in;
## nothing here interprets it.
class_name Fighter
extends RefCounted

## The mutable half, all of it. `_template` is the one reference out, and it is
## read-only from here.
var _id: String
var _template: FighterTemplate
var _owner_id: String
var _position: Vector3i
var _damage_counter: int = 0
var _status_flags: Array[String] = []


## All four arguments are required, and all four are stored exactly as given:
## nothing is validated here. `GameState._init()` sets the precedent -- it takes
## a board and a generator and checks neither. Validation belongs where a value
## can actually be refused, which is `move_to()` and `from_dict()`.
func _init(
	fighter_id: String,
	fighter_template: FighterTemplate,
	owner_id: String,
	start_position: Vector3i
) -> void:
	_id = fighter_id
	_template = fighter_template
	_owner_id = owner_id
	_position = start_position


## This fighter's id. A `String`, not a `StringName`: it is what the serialized
## form and `GameState` use, and a `StringName` is banned from `to_dict()`
## output. A caller converts at the `Board` boundary, which takes a
## `StringName` for occupant ids.
func id() -> String:
	return _id


## The id of the player who owns this fighter.
func owner_id() -> String:
	return _owner_id


## The shared template. Returned by reference, not copied -- two fighters built
## from one template must keep returning the identical object. Read it; never
## write to it.
func template() -> FighterTemplate:
	return _template


## Where this fighter currently stands, as a cube coordinate.
##
## `Board` also records an occupant per hex. Reconciling the two is a movement
## concern with no owner yet, so nothing here touches a `Board` and this class
## holds no reference to one.
func position() -> Vector3i:
	return _position


## Moves this fighter to `coord`. Returns `false` and changes nothing when
## `coord` fails `HexCoord.is_valid()`.
##
## Distance, terrain and the fighter's `move()` allowance are not checked --
## whether a move is *legal* is a later Feature's question. This only refuses a
## coordinate that is not a coordinate.
func move_to(coord: Vector3i) -> bool:
	if not HexCoord.is_valid(coord):
		return false

	_position = coord
	return true


## The template's movement allowance, in hexes.
func move() -> int:
	return _template.move


## The template's save value.
func save() -> int:
	return _template.save


## The template's health -- the damage counter this fighter is defeated at.
func health() -> int:
	return _template.health


## The template's point value.
func point_value() -> int:
	return _template.point_value


## The template's weapons, as a **shallow** copy: a new `Array` holding the
## same `WeaponTemplate` objects. Appending to the value returned here cannot
## reach the template; the elements are shared on purpose. See the class
## docstring.
func weapons() -> Array[WeaponTemplate]:
	return _template.weapons.duplicate()


## Total damage points accumulated. Starts at 0 and only ever rises.
func damage_counter() -> int:
	return _damage_counter


## Adds `points` to the damage counter. Returns `false` and changes nothing
## when `points < 1`.
##
## Not a healing API, and not a clamp in either direction: 0 and negatives are
## refused rather than treated as removal, and the counter is allowed past
## `health()` because `is_defeated()` asks `>=`.
func apply_damage(points: int) -> bool:
	if points < 1:
		return false

	_damage_counter += points
	return true


## True when nothing has damaged this fighter yet. Overlaps `is_vulnerable()`
## when the template's health is 1; see the class docstring.
func is_undamaged() -> bool:
	return _damage_counter == 0


## True once any damage has landed.
func is_damaged() -> bool:
	return _damage_counter > 0


## True when one more damage point would defeat this fighter. Deliberately
## still true once it *is* defeated, and true at counter 0 for a
## one-health fighter; see the class docstring.
func is_vulnerable() -> bool:
	return _damage_counter + 1 >= _template.health


## True when the damage counter has reached the template's health. Nothing here
## acts on that -- removal from the board, scoring and discards are attack
## resolution's business.
func is_defeated() -> bool:
	return _damage_counter >= _template.health


## Adds `flag` to this fighter's status flags. Returns `false` and changes
## nothing when `flag` is empty or already present.
func set_status_flag(flag: String) -> bool:
	if flag.is_empty():
		return false
	if _status_flags.has(flag):
		return false

	_status_flags.append(flag)
	return true


## True when `flag` is currently set, by exact string match.
func has_status_flag(flag: String) -> bool:
	return _status_flags.has(flag)


## Removes `flag`. Returns `false` when it was not set.
func clear_status_flag(flag: String) -> bool:
	var index := _status_flags.find(flag)
	if index == -1:
		return false

	_status_flags.remove_at(index)
	return true


## The status flags, in the order they were set. A copy, so a caller cannot
## add, remove or reorder flags through the returned array -- the same reason
## `GameState.turn_order()` copies.
func status_flags() -> Array[String]:
	return _status_flags.duplicate()


## The mutable half as JSON-compatible primitives -- `int`, `String`, `Array`
## only, no `Vector3i` and no `StringName`:
##
##   {
##     "id": "<string>",
##     "template_id": "<string>",
##     "owner_id": "<string>",
##     "position": [x, y, z],
##     "damage_counter": <int>,
##     "status_flags": ["<flag>", ...]
##   }
##
## Keys are built in exactly that order, so two identically built fighters
## stringify to the identical string. That matters because this dictionary is
## what `GameState.add_fighter()` stores and what `GameState.digest()` hashes
## via `JSON.stringify()`.
##
## `position` is `[x, y, z]`, matching `Board.to_dict()`'s coord convention.
## `template_id` is copied from the template as it stands now; no stat is
## carried, because stats live in the `.tres`.
##
## `status_flags` is a plain `Array`, not an `Array[String]`, so a round trip
## through `JSON.parse_string()` produces a dictionary of exactly this shape --
## the same reason `PlayerState.to_dict()` untypes its piles.
func to_dict() -> Dictionary:
	var flags: Array = []
	flags.append_array(_status_flags)

	return {
		"id": _id,
		"template_id": _template.template_id,
		"owner_id": _owner_id,
		"position": [_position.x, _position.y, _position.z],
		"damage_counter": _damage_counter,
		"status_flags": flags,
	}


## Rebuilds a `Fighter` from `to_dict()`'s shape over `fighter_template`.
##
## The template is an argument, never resolved from the data. `data`'s
## `template_id` is not read, not matched against `fighter_template`, and not
## validated: choosing which template a saved fighter belongs to is a game-side
## decision, and a saved match meeting a retuned `.tres` is a content-version
## question (`docs/godot-implementation-guide.md` §9.3), not this one.
##
## Returns `null`, having built nothing usable, on any refusal: a null
## `fighter_template`; an `"id"` or `"owner_id"` that is missing or not a
## `String`; a `"position"` that is not a three-element `int` array or that
## fails `HexCoord.is_valid()`; a `"damage_counter"` that is not an integer or
## that is negative -- `apply_damage()` cannot produce one, so neither can a
## well-formed record; or a `"status_flags"` that is not an array of `String`,
## or that holds an empty or repeated flag, both of which `set_status_flag()`
## refuses. Nothing is repaired.
static func from_dict(data: Dictionary, fighter_template: FighterTemplate) -> Fighter:
	if fighter_template == null:
		return null

	var id_field: Variant = data.get("id")
	if typeof(id_field) != TYPE_STRING:
		return null

	var owner_field: Variant = data.get("owner_id")
	if typeof(owner_field) != TYPE_STRING:
		return null

	var coord_value: Variant = _coord_from(data.get("position"))
	if coord_value == null:
		return null
	var coord: Vector3i = coord_value

	var counter_value: Variant = PlayerState.as_int(data.get("damage_counter"))
	if counter_value == null:
		return null
	var counter: int = counter_value
	if counter < 0:
		return null

	var flags_field: Variant = data.get("status_flags")
	if typeof(flags_field) != TYPE_ARRAY:
		return null

	var fighter := Fighter.new(id_field, fighter_template, owner_field, coord)
	fighter._damage_counter = counter

	# Through set_status_flag(), so its refusals are this refusal too rather
	# than a second copy of the rule -- the same shape Board.from_dict() uses
	# when it replays entries through add_hex()/place_occupant().
	for entry in flags_field:
		if typeof(entry) != TYPE_STRING:
			return null
		if not fighter.set_status_flag(entry):
			return null

	return fighter


## `value` as a valid cube coordinate, or `null` when it is not a three-element
## array of integers satisfying `HexCoord.is_valid()`.
##
## Components go through `PlayerState.as_int()` for the reason its own
## docstring gives: JSON has one number type, so a reparsed `0` arrives as
## `0.0` and is an integer that has been through JSON, not a wrong type.
static func _coord_from(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return null

	var components: Array = value
	if components.size() != 3:
		return null

	var parsed: Array[int] = []
	for component in components:
		var number: Variant = PlayerState.as_int(component)
		if number == null:
			return null
		parsed.append(number)

	var coord := Vector3i(parsed[0], parsed[1], parsed[2])
	if not HexCoord.is_valid(coord):
		return null

	return coord

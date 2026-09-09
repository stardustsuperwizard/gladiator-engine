## What resolving a rule against a state returns.
##
## A `TurnAction` is the usual producer and was for a while the only one, but
## it is not the only one: `EndSegment.run()` returns one of these too. A
## Segment boundary is not a player command and is not a `TurnAction` -- see
## that class's own docstring for why -- and it still has exactly the two
## things this record carries, so it uses this record rather than a second
## result type. There is deliberately no field naming which rule produced a
## result: a caller already knows what it called.
##
## A dumb, immutable-by-convention record -- the shape `PlayerState` already
## sets, not an abstraction with behaviour. `_init()` stores exactly what it is
## given, validating neither field; `ok()` and `failure()` are the two
## constructors every caller actually uses.
##
## `reason` is a `StringName`, not a `String`: it is a compared-against
## constant, never serialized. There is no `to_dict()`/`from_dict()` here on
## purpose -- a `TurnResult` is not part of `GameState` and nothing hashes it.
class_name TurnResult
extends RefCounted

## Whether the action resolved.
var success: bool

## Empty (`&""`) on success. On failure, one of the acting rule's own
## `FAILURE_*` constants -- a `TurnAction` subclass's, or `EndSegment`'s --
## never an `Authority` refusal, which is a separate vocabulary and never
## reaches a `TurnResult`.
var reason: StringName


func _init(is_success: bool, result_reason: StringName = &"") -> void:
	success = is_success
	reason = result_reason


## A successful result: `success == true`, `reason == &""`.
static func ok() -> TurnResult:
	return TurnResult.new(true, &"")


## A failed result carrying `reason` as given.
static func failure(reason: StringName) -> TurnResult:
	return TurnResult.new(false, reason)

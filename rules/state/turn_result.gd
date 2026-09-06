## What resolving a `TurnAction` returns.
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

## Empty (`&""`) on success. On failure, one of the acting `TurnAction`
## subclass's own `FAILURE_*` constants -- never an `Authority` refusal, which
## is a separate vocabulary and never reaches a `TurnResult`.
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

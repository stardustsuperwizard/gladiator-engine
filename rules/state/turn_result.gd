## What resolving a rule against a state returns.
##
## A `TurnAction` is the usual producer -- `resolve()` returns one -- but it is
## not the only one. `EndSegment.run()` is the other: spec §10's End Segment is
## a rule that resolves against a `GameState` without any player having
## submitted it, and it reports itself in exactly this vocabulary. The record
## does not carry which rule produced it, and must not learn to: a caller
## already holds the thing it called.
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

## Empty (`&""`) on success. On failure, one of the resolving rule's own
## `FAILURE_*` constants -- the acting `TurnAction` subclass's, or
## `EndSegment`'s -- never an `Authority` refusal, which is a separate
## vocabulary and never reaches a `TurnResult`.
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

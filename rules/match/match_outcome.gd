## What a victory condition answers about a match state: spec §11.3's two
## questions, plus the rule that produced the second answer.
##
## Four facts and no behaviour -- whether the match is `over`, which ending
## finished it, who won, and which rule named that winner. A dumb,
## immutable-by-convention record, the shape `TurnResult` and `PlayerState`
## already set, not an abstraction. `_init()` stores exactly what it is given
## and validates neither field; `unended()` and `ended()` are the two
## constructors every caller actually uses.
##
## **There is no `to_dict()`, and there must not be.** Spec §11.3 makes the end
## condition a *derived check over the match state*, never a flag the rules set:
## the same state must always produce the same answer, whoever asks and
## whenever. An outcome is therefore recomputed from a `GameState` whenever one
## is wanted, and is never stored in a state or serialized beside one -- a
## serialized outcome would be a second copy of a fact `GameState` already
## determines, free to drift out of agreement with it.
##
## `ended_by` and `deciding_rule` are `StringName`s for the reason
## `TurnResult.reason` is one: each is a compared-against constant and is never
## serialized. `winner_id` is a plain `String`, because that is what
## `GameState.turn_order()` holds.
class_name MatchOutcome
extends RefCounted

## Spec §11.3's first ending: a side has no fighters remaining on the board.
const ENDING_ELIMINATION := &"elimination"

## Spec §11.3's second ending: §11.1's round limit has been reached.
const ENDING_ROUND_LIMIT := &"round_limit"

## The winner held the most VP outright. No tiebreaker was consulted.
const RULE_VICTORY_POINTS := &"victory_points"

## Tiebreaker 1: exactly one of the tied sides still has fighters on the board.
const RULE_ONLY_SURVIVING_SIDE := &"only_surviving_side"

## Tiebreaker 2: the tied side with the most fighters still on the board.
const RULE_MOST_SURVIVING_FIGHTERS := &"most_surviving_fighters"

## Tiebreaker 3: nothing separated the sides, so nobody won. `winner_id` is
## empty.
const RULE_DRAW := &"draw"

## Whether the match has ended.
var over: bool

## Which ending finished the match -- one of the `ENDING_*` constants -- or
## `&""` while it has not ended.
var ended_by: StringName

## The winning side's player id, as it appears in `GameState.turn_order()`.
## Empty for a draw, and for a match that has not ended.
var winner_id: String

## Which rule named the winner -- one of the `RULE_*` constants -- or `&""`
## while the match has not ended.
var deciding_rule: StringName


func _init(
	is_over: bool, ending: StringName = &"", winner: String = "", rule: StringName = &""
) -> void:
	over = is_over
	ended_by = ending
	winner_id = winner
	deciding_rule = rule


## A match that has not ended: no ending, no winner, no deciding rule.
static func unended() -> MatchOutcome:
	return MatchOutcome.new(false)


## A match that ended by `ending`, won by `winner` under `rule`. `winner` is
## empty for a draw.
static func ended(ending: StringName, winner: String, rule: StringName) -> MatchOutcome:
	return MatchOutcome.new(true, ending, winner, rule)

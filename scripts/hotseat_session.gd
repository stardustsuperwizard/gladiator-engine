## Which step of which Turn a hotseat match is on, and who must act next.
##
## The headless half of the hotseat loop. A view asks this class four
## questions -- `phase()`, `active_player_id()`, `players_to_act()` and
## `player_to_act()` -- and routes every command a player makes back through
## `submit()`, `decline()`, `pass_power_step()` or `advance_segment()`. That is
## the whole surface, and it is enough to play a match without the caller
## counting a Turn or naming a rule.
##
## **It resolves nothing and routes everything through `RoundDriver`.** Each of
## the four commands above is one line delegating to the identically named
## driver method and handing back its `TurnResult` unwrapped and unmodified --
## refusals and failures included. `ActionRunner` stays the one thing entitled
## to resolve, and this class never reaches past the driver to it.
##
## **It is not a second gate.** It refuses nothing on its own and pre-checks no
## entitlement. A command submitted out of turn or out of phase is submitted
## like any other and comes back refused by `Authority` or failed by the action
## itself, and that answer is returned unchanged. `players_to_act()` reports
## whose turn to speak it is; it does not enforce it, and a caller that ignores
## it gets the gate's own answer rather than this class's. Whose question is
## whose stays exactly as `scripts/authority.gd` documents it.
##
## **`active_player_id()` comes from `RoundDriver`, never from
## `Authority.active_player_id()`**, and nothing here calls
## `Authority.set_active_player()`. The driver's own docstring argues that at
## length: the gate's active player is a field the game sets and cannot clear,
## so reading it back would report a stale player for a Turn the round does not
## have. The rule is the answer.
##
## **It never passes on a player's behalf and never supplies the second pass.**
## Spec §5.3 is explicit that passing is a move, not an absence, so
## `pass_power_step()` submits one pass for the player named and nothing more.
## A Power Step that wants two passes gets them from two calls, made by two
## players.
##
## **It counts nothing.** No Turn counter, no round counter, no pass tally of
## its own. `phase()` and `players_to_act()` are derived from `GameState` at
## the moment they are asked, so a state restored by `GameState.from_dict()`
## reports correctly with no extra work -- the same property `TurnSequence`
## gets by deriving the active player rather than storing it.
##
## **It holds no `GameState` of its own.** The state comes off
## `Authority.state()` at the point of use, the precedent `ActionRunner` and
## `RoundDriver` both document: a second reference here could drift out of step
## with the one the gate validated against.
##
## **`MATCH_COMPLETE` reports that the End Segment would refuse, and nothing
## more.** It is not a victory check -- no winner, no score, no §11 branch, not
## even a partial one. `EndSegment` refuses `FAILURE_FINAL_ROUND` on the last
## round's complete Segment, and this phase is that refusal named in advance so
## a view can stop asking for Turns that do not exist. What happens after the
## last round is victory determination, which this class does not do and does
## not approximate.
class_name HotseatSession
extends RefCounted

## Where the match is, as the only four answers a hotseat view needs.
##
## Derived from `GameState` on every call, never stored: these are names for
## states the rules already hold, not a state machine this class runs.
##
## - `ACTION_STEP` -- a Turn is open and its core action has not resolved. The
##   active player alone may act (spec §5.1).
## - `POWER_STEP` -- the Action Step's action has resolved and
##   `state.power_step_open` is true. Both players act, alternating, until two
##   passes in a row end the Step and the Turn with it (§5.3).
## - `SEGMENT_COMPLETE` -- the round has run every Turn it has and is not the
##   final round, so `advance_segment()` is the next thing to happen (§10).
## - `MATCH_COMPLETE` -- the final round's Combat Segment is complete. There is
##   no next round and `advance_segment()` will refuse.
enum Phase { ACTION_STEP, POWER_STEP, SEGMENT_COMPLETE, MATCH_COMPLETE }

## The gate, and the route to the state -- which is deliberately not cached
## here. Read through `_state()` at the point of use.
var _authority: Authority

## The one route to a resolver this class has. Built over `_authority` and
## `templates` when the caller does not supply one, so the session and the
## driver can never be a mismatched pair by accident -- the pattern
## `RoundDriver._init()` already sets for its own optional `ActionRunner`.
var _driver: RoundDriver


## `authority` and `templates` are required; `templates` is stored nowhere and
## is used only to build the driver when one is not given.
##
## `driver` is optional: a caller that already has a `RoundDriver` over the
## same `Authority` hands it in, and a caller that does not gets one built
## here.
func _init(authority: Authority, templates: FighterTemplates, driver: RoundDriver = null) -> void:
	_authority = authority
	_driver = driver if driver != null else RoundDriver.new(authority, templates)


## Which step of which Turn the match is on, derived from the state as it is
## right now.
##
## The order of the tests is the meaning of the answer: a complete Combat
## Segment is reported before anything about a Step, because a Segment with no
## Turns left has no Step to be in, and the final round is distinguished from
## every other complete Segment because only one of the two has a next round to
## begin.
func phase() -> Phase:
	var state := _state()

	if state.combat_segment_complete():
		return Phase.MATCH_COMPLETE if state.is_final_round() else Phase.SEGMENT_COMPLETE

	if state.power_step_open:
		return Phase.POWER_STEP

	return Phase.ACTION_STEP


## The player whose Turn it is, or `""` when the round has none left.
##
## Delegates to `RoundDriver.active_player_id()`, which derives it from
## `TurnSequence`. Never read back off `Authority` -- see the class docstring.
func active_player_id() -> String:
	return _driver.active_player_id()


## Every player entitled to act right now, the one who should act first at the
## front. Empty when nobody is: `SEGMENT_COMPLETE`, `MATCH_COMPLETE`, or a
## state so unconfigured that no rule names an active player.
##
## In `ACTION_STEP` that is the active player alone, which is spec §5.1's
## Action Step. In `POWER_STEP` it is every player in `state.turn_order()`,
## rotated so the active player comes first, minus whoever passed most recently
## -- `PowerStepPassAction` fails `FAILURE_ALREADY_PASSED` on two passes in a
## row by the same player, and this is that rule read forwards instead of
## backwards.
##
## **A report, not a gate.** Nothing here refuses a command, and a player left
## out of this list who submits anyway is answered by `Authority` or by the
## action, not by this class.
func players_to_act() -> Array[String]:
	var active := active_player_id()
	if active.is_empty():
		return [] as Array[String]

	match phase():
		Phase.ACTION_STEP:
			return [active] as Array[String]
		Phase.POWER_STEP:
			return _power_step_players(active)

	return [] as Array[String]


## The one player who should act next, or `""` when nobody should.
##
## The front of `players_to_act()`, which is the whole of it in `ACTION_STEP`
## and the player whose pass the Power Step is waiting on in `POWER_STEP`. A
## hotseat view needs no more than this to know whose device to hand over.
func player_to_act() -> String:
	var players := players_to_act()
	return "" if players.is_empty() else players[0]


## Submits `action` on behalf of `requester_id`, through `RoundDriver`.
##
## Returns the driver's `TurnResult` unwrapped and unmodified: a refusal from
## the gate, a failure from the action, or a success. Nothing is pre-checked
## here, including whether `requester_id` is in `players_to_act()`.
func submit(action: TurnAction, requester_id: String) -> TurnResult:
	return _driver.submit(action, requester_id)


## Spec §5.3's one explicit way not to choose: `player_id` declines their
## Action Step and takes whatever `DefaultActionStep` says it comes to.
##
## Delegates to `RoundDriver.decline()`, result unchanged. The Turn it declines
## still has its Power Step, and still completes only on that Step's two
## passes.
func decline(player_id: String) -> TurnResult:
	return _driver.decline(player_id)


## Submits `player_id`'s Power Step pass, through `RoundDriver`.
##
## One call, one pass, one player. The opponent's pass is their own call and
## nothing here makes it for them.
func pass_power_step(player_id: String) -> TurnResult:
	return _driver.pass_power_step(player_id)


## Runs spec §10's End Segment through `RoundDriver.end_segment()`: the round
## ends, its round-level flags clear, the next one begins.
##
## Returns the driver's `TurnResult` unchanged, refusals included --
## `EndSegment.FAILURE_COMBAT_SEGMENT_INCOMPLETE` while Turns remain, and
## `EndSegment.FAILURE_FINAL_ROUND` on the match's last round, which is the
## refusal `MATCH_COMPLETE` names in advance.
func advance_segment() -> TurnResult:
	return _driver.end_segment()


## The live state, off the gate, at the moment of use. Never cached -- see the
## class docstring.
func _state() -> GameState:
	return _authority.state()


## `state.turn_order()` rotated so `active` is at the front, minus the last
## entry of the consecutive-pass record when that record is non-empty.
##
## The rotation is what makes the active player the one a view hands the device
## to first when a Power Step opens; the removal is what makes it the opponent
## once the active player has passed. An `active` the turn order does not hold
## leaves the order as authored rather than guessing at a rotation.
func _power_step_players(active: String) -> Array[String]:
	var state := _state()
	var order := state.turn_order()
	if order.is_empty():
		return [] as Array[String]

	var start := maxi(order.find(active), 0)
	var ordered: Array[String] = []
	for offset in order.size():
		ordered.append(order[(start + offset) % order.size()])

	var passes := state.power_step_passes()
	if not passes.is_empty():
		ordered.erase(passes[passes.size() - 1])

	return ordered

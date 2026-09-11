## Plays a round of spec §5.2's Combat Segment through the gate.
##
## Composes three pieces that already exist and adds no rule of its own:
## `TurnSequence` says whose Turn it is, `DefaultActionStep` says what an
## un-chosen Action Step comes to, and `ActionRunner` is how every player
## command reaches a resolver. What this class contributes is the *order* --
## report the active player, keep `Authority` in step with the rule that
## derives them, route the command, and run the End Segment at the Segment
## boundary.
##
## **Every player command goes through `ActionRunner`.** The chosen action,
## the default Guard that `decline()` builds, and both Power Step passes: all
## three are submitted, none is resolved here. `EndSegment.run()` and
## `PowerStep.note_action()` are the only two rules-side calls made outside
## the runner, and each has a stated reason that does not generalise:
##
## - `EndSegment`'s own docstring argues the first at length -- a Segment
##   transition is not a player command, names no actor, has no requester, and
##   so supplies neither half of the question `Authority` answers.
## - The second is the empty-Action-Step case in `decline()` and nothing else.
##   Spec §5.3 puts a Power Step after every Action Step, and
##   `PowerStepPassAction` refuses `FAILURE_STEP_NOT_OPEN` while the Step is
##   closed, so a Turn whose Action Step resolved nothing would otherwise have
##   no way to complete. Opening the Step is what lets the two passes land and
##   the Turn end like any other.
##
## Neither precedent extends to anything a player submits, and there is no
## third.
##
## **`active_player_id()` answers from `TurnSequence`, never from
## `Authority`.** The gate's active player is a field the game sets, and it
## has no way to be cleared -- `set_active_player("")` is refused, because an
## empty id is in no turn order. Reading the gate back would therefore report
## a stale player for a Turn the round does not have, and a Combat Segment
## that has run all eight of its Turns would appear to offer a ninth. The rule
## is the answer; the gate is kept in step with it so that a submission the
## rule permits is one the gate permits too, and `submit()` and `decline()`
## refuse on their own -- with `Authority.REFUSED_NO_ACTIVE_PLAYER`, the gate's
## own constant -- when the rule names nobody. `scripts/authority.gd` grows
## nothing for this.
##
## **It holds no `GameState` of its own.** The state comes back off
## `Authority.state()` at the moment it is needed, exactly as `ActionRunner`
## does and for the same reason: a second reference here could drift out of
## step with the one the gate validated against.
##
## **It counts nothing.** `turns_taken` rises in
## `PowerStep.end_on_second_pass()` and nowhere else, `power_step_open` and
## the consecutive-pass record are written by the actions that resolve, and
## this class reads all three and writes none of them -- the single
## `note_action()` call above excepted. A caller that wants to know whether the
## round is over asks `active_player_id()` or
## `GameState.combat_segment_complete()`; neither this class nor its callers
## keep a tally.
##
## **A pass is a player command, one call per player.** `pass_power_step()`
## submits one pass for the player named, and nothing here passes on anybody's
## behalf: spec §5.3 is explicit that passing is a move, not an absence, and
## an engine that supplied the second pass itself would have decided for a
## player who never spoke.
##
## **It draws nothing from `state.rng`.** Only a resolving action may, and
## every resolution here happens inside `ActionRunner`.
##
## **It loads no resource and seeds no counter.** `turns_per_player` and
## `rounds_per_match` arrive on the state its caller built, from the authored
## `RoundProfile`; this class reads neither directly and authors no new dial.
class_name RoundDriver
extends RefCounted

## The gate every command is submitted to, and the route to the state -- which
## is deliberately not cached here.
var _authority: Authority

## The game-side template lookup `decline()` needs, so that
## `DefaultActionStep.action_for()` can be handed the fighter-id-keyed map it
## takes. Nothing else in this class reads it.
var _templates: FighterTemplates

## The one thing entitled to resolve. Built over `_authority` when the caller
## does not supply one, so the runner and the gate can never be a mismatched
## pair by accident.
var _runner: ActionRunner


## `authority` and `templates` are required and stored exactly as given.
##
## `runner` is optional: a caller that already has an `ActionRunner` over the
## same `Authority` hands it in, and a caller that does not gets one built
## here. Either way there is exactly one runner, and it is the only route to a
## resolver this class has.
func _init(authority: Authority, templates: FighterTemplates, runner: ActionRunner = null) -> void:
	_authority = authority
	_templates = templates
	_runner = runner if runner != null else ActionRunner.new(authority)


## The player whose Turn it is, or `""` when the round has none left.
##
## Derived by `TurnSequence.active_player()` from the state, never read back
## off `Authority` -- see the class docstring. An empty answer is the end of
## the Combat Segment, and it is what a caller's loop ends on.
func active_player_id() -> String:
	return TurnSequence.active_player(_authority.state())


## Submits `action` on behalf of `requester_id`.
##
## Syncs the gate to the player `TurnSequence` names and then routes the
## command through `ActionRunner`, returning whatever it returns -- a refusal,
## a failure or a success, unwrapped and unmodified. When the rule names
## nobody, refuses `Authority.REFUSED_NO_ACTIVE_PLAYER` and changes nothing at
## all: the gate is not touched, the action is not submitted, and
## `resolve()` is never reached.
##
## Submitting as somebody other than the active player is not refused here. It
## is routed to the gate like any other command and comes back
## `Authority.REFUSED_NOT_YOUR_TURN`, which is the gate's answer to the gate's
## question.
func submit(action: TurnAction, requester_id: String) -> TurnResult:
	if _sync_active_player().is_empty():
		return TurnResult.failure(Authority.REFUSED_NO_ACTIVE_PLAYER)

	return _runner.run(action, requester_id)


## Spec §5.3's one explicit way not to choose: `player_id` declines their
## Action Step and takes whatever the default comes to.
##
## Asks `DefaultActionStep.action_for()` what an un-chosen Action Step is
## worth -- a `GuardAction` on the first of that player's fighters, in
## `GameState.fighter_ids()` order, eligible to Guard right now -- and submits
## it through `ActionRunner` as `player_id`. That submission is gated exactly
## as a chosen action is: a decline by the non-active player comes back
## `Authority.REFUSED_NOT_YOUR_TURN` and resolves nothing.
##
## **When the rule names no fighter**, every one defeated or held by the
## Charge lockout, there is nothing to submit and the Action Step is empty.
## The Turn still has a Power Step, so this opens it with
## `PowerStep.note_action()` and reports success: an empty Action Step is a
## Turn that resolved nothing, not a Turn that was skipped, and its two passes
## complete it and raise `turns_taken` like any other. Nothing else is written
## -- no flag, no board write, no counter, no `state.rng` draw. That branch
## answers the entitlement question itself, with the gate's own constant,
## because it has no command to put to the gate.
##
## Takes no reason code and no timeout: declining is a decision a player
## makes, and there is no clock in this engine to make it for them.
func decline(player_id: String) -> TurnResult:
	var active := _sync_active_player()
	if active.is_empty():
		return TurnResult.failure(Authority.REFUSED_NO_ACTIVE_PLAYER)

	var state := _authority.state()
	var action := DefaultActionStep.action_for(
		state, player_id, _templates.templates_by_fighter(state)
	)

	if action != null:
		return _runner.run(action, player_id)

	if player_id != active:
		return TurnResult.failure(Authority.REFUSED_NOT_YOUR_TURN)

	PowerStep.note_action(state)
	return TurnResult.ok()


## Submits `player_id`'s Power Step pass.
##
## One call, one pass, one player: the opponent's pass is their own call, and
## nothing here makes it for them. The Step ends on the second pass in a row,
## which is what completes the Turn and raises `turns_taken` -- both inside
## `PowerStep`, neither here -- so the gate is re-synced afterwards and the
## next call to `active_player_id()` names whoever the new Turn belongs to.
func pass_power_step(player_id: String) -> TurnResult:
	var result := _runner.run(PowerStepPassAction.new(player_id), player_id)
	_sync_active_player()
	return result


## Runs spec §10's End Segment: the round ends, its flags clear, the next one
## begins.
##
## Called directly rather than submitted, because it is not a command and has
## no requester -- see the class docstring and `EndSegment`'s own. Returns its
## `TurnResult` unchanged, including its refusals: an incomplete Combat
## Segment and, on the match's final round, `FAILURE_FINAL_ROUND`. The driver
## stops there. What happens after the last round is victory determination,
## which this class does not do and does not approximate.
##
## Re-syncs the gate on the way out, so a successful Segment leaves the front
## of the turn order active for the new round's first Turn.
func end_segment() -> TurnResult:
	var result := EndSegment.run(_authority.state())
	_sync_active_player()
	return result


## Points `Authority` at the player `TurnSequence` names, and returns that
## player -- `""` when the rule names nobody.
##
## An empty answer leaves the gate exactly as it was: `Authority` has no way
## to clear its active player, by design, so the callers above refuse on the
## returned `""` rather than trying to make the gate say it.
func _sync_active_player() -> String:
	var active := TurnSequence.active_player(_authority.state())
	if not active.is_empty():
		_authority.set_active_player(active)

	return active

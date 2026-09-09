## Spec §5.3's Power Step: when it is open, and what ends it.
##
## A Turn is an Action Step followed by a Power Step. The Action Step's core
## action opens the Power Step; the Power Step ends when both players pass in a
## row; and **a Turn is not over until its Power Step has ended**, which is why
## the increment of `GameState.turns_taken` lives here and nowhere else. Spec
## §5.3 settles that anything counting Turns counts *completed* Turns, not
## resolved actions -- with no card system the two are indistinguishable, and
## they stop being indistinguishable the moment cards exist.
##
## **This is the only writer of `state.turns_taken` in the tree.** No action
## increments it: `PassAction`'s increment is gone, and Move, Attack, Guard and
## Charge never had one.
##
## **`GameState` owns the slot; this class owns the rule.** The state holds
## `power_step_open` and the consecutive-pass record and knows nothing about
## what either means. Deciding that two passes in a row end a Step, and that
## ending one completes a Turn, is this class's business -- the same division
## `GameState.add_fighter()` already keeps against the actions.
##
## **`PASSES_TO_END` is a rule, not a dial, so it stays in code rather than in
## a `.tres`.** Spec §12's "numbers are data" governs dice counts, damage,
## targets and costs, every one of which is expected to be tuned. "Both players
## pass in a row" is not a tuned quantity; it is the definition of the Step
## ending, and a `.tres` that could set it to 3 would author a different game.
##
## **It knows nothing about permission.** Who was entitled to submit a pass is
## the game side's question, and nothing in `rules/` may name the gate.
##
## **Neither method draws from `state.rng`.** Opening a Step, recording a pass
## and ending a Step are fully determined by the request.
##
## `RefCounted` with static methods only; never instantiated.
class_name PowerStep
extends RefCounted

## Spec §5.3: the Step ends when both players pass in a row.
const PASSES_TO_END := 2


## Records that a command other than a Power Step pass has resolved: the Turn's
## Power Step is open, and any consecutive passes are no longer consecutive.
##
## Every concrete `TurnAction` calls this on its success path, which does both
## jobs §5.3 needs at once -- it opens the Power Step after the Action Step's
## action resolves, and it resets the count when a command lands between two
## passes, so pass, action, pass leaves the Step open.
##
## **It is idempotent.** Calling it twice in a row leaves exactly the same
## state, which is what makes it safe for `ChargeAction` to reach it both
## directly and through the `AttackAction` half it composes.
static func note_action(state: GameState) -> void:
	state.power_step_open = true
	state.clear_power_step_passes()


## Records `player_id`'s pass. Returns `true` when this pass ended the Step.
##
## On the pass that reaches `PASSES_TO_END` entries: closes the Step, clears
## the record, and increments `state.turns_taken` by exactly one -- the Turn is
## over, and this is the one place in the tree that says so.
##
## Records the pass through `GameState.record_power_step_pass()`, which refuses
## an id naming no player, so an unrecordable pass ends nothing. Whether the
## same player may pass twice in a row is the submitting command's question,
## not this one's.
static func end_on_second_pass(state: GameState, player_id: String) -> bool:
	state.record_power_step_pass(player_id)

	if state.power_step_passes().size() < PASSES_TO_END:
		return false

	state.power_step_open = false
	state.clear_power_step_passes()
	state.turns_taken += 1
	return true

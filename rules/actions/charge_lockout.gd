## Spec §6's Charge lockout: one shared legality predicate, consulted by the
## Move, Attack and Guard actions.
##
## `locks_out()` answers whether spec §6 refuses `actor` an action right now.
## A fighter carrying the `"charged"` flag is refused Move, Attack and Guard
## while any friendly fighter still on the board lacks the flag, and is
## permitted all three again once every one of them carries it. Pass is not
## gated -- it is the action a locked-out fighter still has -- and neither is
## a further Charge: a charged fighter is refused another Charge by spec §6's
## own precondition, which belongs to that action's own resolver, not this
## predicate.
##
## **Why `FLAG_CHARGED` lives here rather than on the action that will set
## it.** The Move action's own flag constant lives on itself, and the Guard
## action's own flag constant lives on itself, because a constant belongs to
## the class that produces it. `"charged"` does not follow them, and the
## reason is a dependency cycle rather than taste:
##
## - The Charge action has to name the Move action's flag constant, because
##   spec §6's Charge precondition refuses a fighter that already holds
##   `"moved"`.
## - The Move action has to name whatever holds `"charged"`, because of the
##   lockout this class adds.
## - So putting the `"charged"` constant on the Charge action would close a
##   loop between it and the Move action. The Attack and Guard actions would
##   close the same loop by the same route.
##
## This class names `GameState`, `Board`, `Fighter`, `StatusFlags` and
## `StringName` conversions and nothing else under `rules/actions/` -- so
## hanging the constant here instead keeps the whole class graph acyclic: this
## file depends on nothing else in this directory, each of the three reading
## actions depends on this file, and the writing action (still to come) will
## depend on this file plus the two actions whose flags it names. `StatusFlags`
## itself stays a leaf -- see its own docstring -- so depending on it adds no
## cycle.
##
## `"charged"` is also the only flag in the game with one writer and three
## readers outside it, so "the rule that reads it owns its name" is a
## defensible home rather than a workaround.
##
## **`StatusFlags` now exists, and this constant is a re-export of it.** The
## trigger that was going to revisit "no shared status-flag holder" -- spec
## §10 step 5's round-level clearing, which needs the whole set at once -- has
## arrived: enumerating `"moved"`, `"guarded"` and `"charged"` across three
## action imports from a non-action class would have been the worse of the two
## options, so `StatusFlags` holds the three literals and `round_level()`
## publishes the set that step clears. This predicate still clears nothing
## itself. The dependency-cycle argument above is unaffected by that and is
## why `FLAG_CHARGED` still resolves through this class rather than through
## `StatusFlags` directly at each of the three call sites: the cycle it avoids
## is between the actions, not between this class and `StatusFlags`, which
## stays a leaf precisely so a class like this one can depend on it.
##
## **A plain `String`, not a `StringName`.** `Fighter.set_status_flag()` takes
## a `String`, `Fighter.to_dict()` serializes flags as plain strings, and
## `Fighter.from_dict()` rejects a `status_flags` entry whose type is not
## `TYPE_STRING`. The `FAILURE_*` constants the three call sites add stay
## `StringName`, because `TurnResult.failure()` takes one.
##
## **Defeat is the board test, not a health test, and for a stated reason.**
## `Fighter.is_defeated()` compares the damage counter against the *template's*
## health, and this predicate holds no template but the actor's -- parsing
## another fighter's payload over the actor's template and then reading a stat
## off it would be the actor's numbers wearing another fighter's name. The
## Attack action's own flanking-candidate helper answers the identical
## question the identical way: spec §9's defeat is what
## `Board.remove_occupant()` expresses, so a fighter the board no longer
## reports at its recorded position is exactly a fighter this engine has
## already defeated.
##
## **A payload that will not parse is skipped**, matching how the flanking
## helper above and the adjacency module handle an unreadable fighter:
## skipping is the safe direction, because it releases the lockout rather than
## trapping a fighter behind one that can never resolve.
##
## **Pure.** `locks_out()` mutates nothing, commits nothing, and draws nothing
## from `state.rng`.
##
## `RefCounted`, static methods only, never instantiated -- the same shape the
## adjacency module and the dice-pool module already use in this directory.
class_name ChargeLockout
extends RefCounted

## Spec §6's `"charged"` flag. Nothing sets it outside a test fixture until
## the action that will own it lands; see the class docstring for why the
## constant lives here rather than there. Re-exported from `StatusFlags`, the
## canonical home for the literal itself.
const FLAG_CHARGED := StatusFlags.CHARGED


## True when spec §6's lockout refuses `actor` an action right now.
##
## `false` for a `null` actor or one that does not hold `FLAG_CHARGED` -- a
## fighter that has not charged is never locked out, which is every fighter in
## the game until the writer of this flag lands. Otherwise walks
## `state.fighter_ids()`: the lockout holds when at least one *other* fighter
## is friendly (its `owner_id()` equals `actor`'s), still on the board (still
## the occupant of its own recorded position), and unflagged. The actor itself
## can never be the blocker -- it holds the flag by definition -- so it is
## skipped explicitly rather than relying on the flag test to exclude it.
static func locks_out(state: GameState, actor: Fighter) -> bool:
	if actor == null or not actor.has_status_flag(FLAG_CHARGED):
		return false

	for fighter_id in state.fighter_ids():
		if fighter_id == actor.id():
			continue

		var fighter := Fighter.from_dict(state.fighter(fighter_id), actor.template())
		if fighter == null:
			continue

		if fighter.owner_id() != actor.owner_id():
			continue

		if state.board.occupant_at(fighter.position()) != StringName(fighter.id()):
			continue

		if fighter.has_status_flag(FLAG_CHARGED):
			continue

		return true

	return false

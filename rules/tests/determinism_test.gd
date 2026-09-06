## The cross-run determinism proof: same starting state plus the same
## sequence of operations reproduces the same match, and a state serialized
## mid-sequence resumes it rather than restarting it.
##
## This is the suite that discharges the parent Feature's (#3) headline claim.
## Everything it exercises already exists -- `GameState`, `Board`,
## `PlayerState`, `DeterministicRng` -- and none of it is modified here; this
## file only proves what those pieces already guarantee when driven together.
##
## **The sequence is scripted here, not built from `TurnAction`s.**
## `TurnAction`/`TurnResult`/`ActionRunner` are Feature #5's deliverable, and
## #5 is *blocked by* this Feature -- reaching for them would invert that
## dependency and deadlock both. "A reproducible sequence of operations" is
## exactly what a scripted series of dice draws plus state mutations is, and
## that is all `_apply_sequence()` is.
##
## A contract test that cannot fail is worse than no contract test (see
## `ContractScannerTest`'s docstring): the negative-control tests below exist
## so this suite would still fail if `DeterministicRng` or `GameState` ever
## regressed to producing a constant, and each case here was confirmed to
## fail once during development before it was made to pass -- see
## `_test_mid_sequence_round_trip_resumes_rather_than_restarts()`'s docstring
## for the specific failure mode demonstrated and reverted.
class_name DeterminismTest

## The seed the golden digest is pinned to. Also used by the two-run-equality
## and mid-sequence-round-trip cases, since nothing about those requires a
## seed distinct from the golden one -- only the negative control does.
const FIXED_SEED := 424242

## A different seed, for the negative control. Nothing about this value
## matters beyond being different from FIXED_SEED.
const OTHER_SEED := FIXED_SEED + 1

## The sequence length used everywhere a full run is needed. At least 30, per
## the parent Feature's acceptance criteria.
const SEQUENCE_STEPS := 40

## Where a mid-sequence snapshot is taken for the round-trip case. Strictly
## less than SEQUENCE_STEPS, so both a first leg and a second leg exist.
const ROUND_TRIP_K := 17

## The inclusive range every draw in this file uses. Wide enough that two
## sequences agreeing on several consecutive values is not coincidence, and
## that _apply_sequence() varying at all is easy to see.
const DRAW_LOW := 1
const DRAW_HIGH := 1000000

## The three fighter ids _build_state() places on the board, and the order
## _apply_sequence() cycles through them for a move step.
const FIGHTER_IDS: Array[String] = ["fighter_a", "fighter_b", "fighter_c"]

## The two player ids _build_state() adds, and the order _apply_sequence()
## cycles through them for a score or card step.
const PLAYER_IDS: Array[String] = ["north", "south"]

## The SHA-256 digest `_build_state(FIXED_SEED)` plus `SEQUENCE_STEPS` steps of
## `_apply_sequence()` must produce.
##
## **This constant is the whole reason this suite covers "a fresh process".**
## The two-run-equality case below compares two runs inside *one* Godot
## process, which alone cannot prove the parent Feature's claim -- both runs
## share a process, an engine build, and a moment in time. This digest was
## computed by a *previous* process, on a previous day, and every subsequent
## run -- including every CI run -- re-derives it in a *new* process and
## compares. That is a genuine cross-process assertion, not a formality.
##
## Godot spawning a second `godot` process via `OS.execute()` was considered
## and rejected: the `TestBootstrap` autoload hijacks every headless run and
## quits it, so a child process would need bespoke handling for no additional
## assurance beyond what this constant already gives for free. This suite
## spawns no process and `.github/scripts/validate-godot.sh` runs no second
## validation pass because of it.
##
## **What legitimately changes this value**, and the only correct response to
## each: a change to `_build_state()` or `_apply_sequence()` in this file: run
## the suite, take the digest reported in the failure message, confirm the
## change was intended, and update this constant. A change to
## `GameState.to_dict()`, `Board.to_dict()`, `PlayerState.to_dict()`, or
## `DeterministicRng.to_dict()`: same response, from whichever file changed.
## An engine upgrade that changes `JSON.stringify()`'s output: same response,
## and worth a note in the PR since nothing in this repository's own diff
## would explain the change.
##
## What is **never** the correct response: loosening this assertion, deleting
## the case, or replacing the equality check with something weaker. A golden
## digest that can be edited to match whatever the suite currently produces,
## without confirming *why* it changed, proves nothing.
const GOLDEN_DIGEST := "296e15cf7ee36929aa99ffe872192ccdee1c9e2f74f9b809b185745b82f438d8"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_two_independent_runs_agree())
	violations.append_array(_test_a_different_seed_diverges())
	violations.append_array(_test_mid_sequence_round_trip_resumes_rather_than_restarts())
	violations.append_array(_test_golden_digest())

	if violations.is_empty():
		return true

	printerr("\n=== Determinism Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## The fixture: a board of 14 hexes -- including one BLOCKED and one HAZARD --
## two players with non-empty piles, three fighters with distinct payloads,
## and a DeterministicRng seeded with `seed_value`. Identical for every call
## with the same seed; two independent calls with the same seed are how
## `_test_two_independent_runs_agree()` demonstrates the claim rather than
## merely asserting it of a single state compared with itself.
static func _build_state(seed_value: int) -> GameState:
	var board := Board.new()
	board.add_hex(Vector3i(0, 0, 0), Board.HexType.STARTING)
	board.add_hex(Vector3i(1, -1, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(2, -2, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(3, -3, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(-1, 1, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(-2, 2, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(-3, 3, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(0, 1, -1), Board.HexType.HAZARD)
	board.add_hex(Vector3i(0, 2, -2), Board.HexType.NORMAL)
	board.add_hex(Vector3i(0, -1, 1), Board.HexType.NORMAL)
	board.add_hex(Vector3i(0, -2, 2), Board.HexType.NORMAL)
	board.add_hex(Vector3i(1, 0, -1), Board.HexType.BLOCKED)
	board.add_hex(Vector3i(-1, 0, 1), Board.HexType.EDGE)
	board.add_hex(Vector3i(1, 1, -2), Board.HexType.NORMAL)

	board.place_occupant(Vector3i(0, 0, 0), &"fighter_a")
	board.place_occupant(Vector3i(1, -1, 0), &"fighter_b")
	board.place_occupant(Vector3i(-1, 1, 0), &"fighter_c")

	var state := GameState.new(board, DeterministicRng.new(seed_value))

	state.add_player("north")
	var north := state.player("north")
	north.hand.append_array(["card_thrust", "card_feint"] as Array[String])
	north.deck.append_array(["card_parry", "card_lunge", "card_riposte"] as Array[String])
	north.discard.append("card_stumble")
	north.scored.append("objective_north")
	north.score = 3

	state.add_player("south")
	var south := state.player("south")
	south.hand.append("card_shove")
	south.deck.append_array(["card_guard", "card_charge"] as Array[String])
	south.discard.append_array(["card_trip", "card_fumble"] as Array[String])
	south.scored.append_array(["objective_south", "objective_centre"] as Array[String])
	south.score = 7

	state.add_fighter("fighter_a", {"template": "murmillo", "weapons": ["gladius", "scutum"]})
	state.add_fighter("fighter_b", {"template": "retiarius", "weapons": ["trident", "net"]})
	state.add_fighter("fighter_c", {"template": "thraex", "weapons": ["sica"]})

	return state


## Applies `steps` scripted steps to `state` and returns the values drawn from
## `state.rng`, in order.
##
## Every step is a pure function of `state` alone -- specifically, of
## `state.rng`'s current position and of `state.turns_taken`, both of which
## are themselves part of the serialized state. There is no separate loop
## counter or other external bookkeeping driving what happens on a given
## step, which is exactly what makes the mid-sequence round trip work: two
## calls -- `_apply_sequence(state, K)` followed later by
## `_apply_sequence(restored_state, N - K)` on a state restored from a
## snapshot taken after the first call -- take the identical path a single
## `_apply_sequence(state, N)` call would, because `restored_state` resumes
## with the same `turns_taken` and the same `rng` position the snapshot was
## taken at. A version of this that chose its actions from a `for i in
## range(steps)` loop variable instead would silently restart that pattern
## at 0 on the second call and diverge from the reference run -- the same
## seed-versus-state trap `GameStateTest` and `DeterministicRngTest` pin,
## one level up.
##
## Each step draws one value from `state.rng` -- exercising the generator --
## and then, depending on `state.turns_taken` modulo 3, uses that drawn value
## to drive one of three mutations -- exercising the state:
##   0: move a fighter to another hex (target chosen by the draw)
##   1: add to a player's score (amount chosen by the draw)
##   2: append a card id, embedding the draw, to a player's discard pile
## `state.turns_taken` itself advances by one on every step regardless of
## which of the three ran, so the round trip also has to preserve that
## counter for the sequence to continue on the right branch after a restore.
## A sequence that drew from `state.rng` and discarded the value, touching
## nothing else, would pass a round-trip check even if `GameState` were not
## serializing the generator at all -- see `GameStateTest`'s "seed-versus-
## state trap" docstring for the same failure one layer down. Draws are used,
## never thrown away, precisely to close that off.
static func _apply_sequence(state: GameState, steps: int) -> Array[int]:
	var draws: Array[int] = []

	for _i in range(steps):
		var draw := state.rng.next_int(DRAW_LOW, DRAW_HIGH)
		draws.append(draw)

		var step_index := state.turns_taken
		match step_index % 3:
			0:
				_apply_move_step(state, step_index, draw)
			1:
				_apply_score_step(state, step_index, draw)
			2:
				_apply_card_step(state, step_index, draw)

		state.turns_taken += 1

	return draws


## Moves one fighter -- chosen by `step_index`, cycling through FIGHTER_IDS --
## to another hex on the board, chosen from the board's own coordinate list by
## `draw`. A target that is unchanged, blocked, or already occupied is a
## deterministic no-op rather than a skipped draw: the draw was still made and
## still returned, only the mutation it would have driven did not apply. Every
## input here -- the board's coordinate order, which hex is occupied by what
## -- is itself part of the serialized state, so this step is reproducible
## across a restore the same way the other two are.
static func _apply_move_step(state: GameState, step_index: int, draw: int) -> void:
	var fighter_id: String = FIGHTER_IDS[step_index % FIGHTER_IDS.size()]
	var current := _fighter_coord(state.board, fighter_id)

	var coords := state.board.coords()
	var target: Vector3i = coords[draw % coords.size()]

	if target == current:
		return
	if state.board.is_blocked(target) or state.board.is_occupied(target):
		return

	state.board.remove_occupant(current)
	state.board.place_occupant(target, StringName(fighter_id))


## Adds an amount derived from `draw` -- always at least 1, so this is never a
## silent no-op -- to the score of the player chosen by `step_index`, cycling
## through PLAYER_IDS.
static func _apply_score_step(state: GameState, step_index: int, draw: int) -> void:
	var player_id: String = PLAYER_IDS[step_index % PLAYER_IDS.size()]
	var delta := (draw % 7) + 1
	state.player(player_id).score += delta


## Appends a card id embedding both `step_index` and `draw` to the discard
## pile of the player chosen by `step_index`, cycling through PLAYER_IDS. The
## id is unique per step by construction, so a round trip that lost or
## duplicated a step would change the pile's contents, not merely its length.
static func _apply_card_step(state: GameState, step_index: int, draw: int) -> void:
	var player_id: String = PLAYER_IDS[step_index % PLAYER_IDS.size()]
	state.player(player_id).discard.append("card_seq_%d_%d" % [step_index, draw])


## The board coordinate currently occupied by `fighter_id`.
##
## Every fighter `_build_state()` places stays on the board for the life of a
## sequence -- `_apply_move_step()` only repositions, never removes -- so this
## always finds one, and the hard stop below is a fixture bug, not a
## reachable outcome of a normal run.
static func _fighter_coord(board: Board, fighter_id: String) -> Vector3i:
	var target := StringName(fighter_id)
	for coord in board.coords():
		if board.occupant_at(coord) == target:
			return coord

	assert(false, "fixture bug: fighter %s has no occupant coordinate on the board" % fighter_id)
	return Vector3i.ZERO


## Two independently constructed states, same seed, same scripted sequence:
## equal digest() and equal recorded draw arrays. This is the headline claim
## itself, demonstrated rather than merely asserted -- two separate
## `_build_state()` calls and two separate `_apply_sequence()` runs, not one
## state compared against itself.
static func _test_two_independent_runs_agree() -> Array[String]:
	var violations: Array[String] = []

	var first := _build_state(FIXED_SEED)
	var first_draws := _apply_sequence(first, SEQUENCE_STEPS)

	var second := _build_state(FIXED_SEED)
	var second_draws := _apply_sequence(second, SEQUENCE_STEPS)

	violations.append_array(
		_expect(
			first.digest() == second.digest(),
			(
				"two independently built states with the same seed, run through the same "
				+ "sequence, must end with an equal digest()"
			)
		)
	)
	violations.append_array(
		_expect(
			first_draws == second_draws,
			(
				"two independently built states with the same seed, run through the same "
				+ "sequence, must record an equal draw array"
			)
		)
	)

	return violations


## The negative control. A suite that would still pass if the generator
## returned a constant proves nothing, so this pins two things a constant
## generator could not produce: a different seed through the same sequence
## must diverge in both digest() and the recorded draws, and a single
## _apply_sequence() run must itself show the generator varying.
static func _test_a_different_seed_diverges() -> Array[String]:
	var violations: Array[String] = []

	var first := _build_state(FIXED_SEED)
	var first_draws := _apply_sequence(first, SEQUENCE_STEPS)

	var second := _build_state(OTHER_SEED)
	var second_draws := _apply_sequence(second, SEQUENCE_STEPS)

	violations.append_array(
		_expect(
			first.digest() != second.digest(),
			"the same sequence run from a different seed must end with a different digest()"
		)
	)
	violations.append_array(
		_expect(
			first_draws != second_draws,
			"the same sequence run from a different seed must record a different draw array"
		)
	)

	var distinct: Dictionary = {}
	for draw in first_draws:
		distinct[draw] = true
	(
		violations
		. append_array(
			_expect(
				distinct.size() >= 2,
				(
					(
						"_apply_sequence() must return at least 2 distinct drawn values -- got %d distinct "
						+ "value(s) across %d draws, which means the generator is not demonstrably varying"
					)
					% [distinct.size(), first_draws.size()]
				)
			)
		)
	)

	return violations


## The mid-sequence round trip. A reference state runs the full sequence
## uninterrupted. A second state, built the same way, runs only the first
## ROUND_TRIP_K steps, is serialized, restored via from_dict(), and then runs
## the remaining SEQUENCE_STEPS - ROUND_TRIP_K steps on the *restored* state.
## The two must agree: equal digest() at the end, and the draws recorded
## after restoration must match the reference's draws from ROUND_TRIP_K
## onward, element for element.
##
## This is the case that was deliberately broken and confirmed to fail during
## development, per the parent Issue's requirement to demonstrate the failure
## mode: `DeterministicRng.from_dict()` was temporarily edited to leave the
## restored generator's state at whatever `DeterministicRng.new()` gives a
## fresh seed assignment -- i.e. to ignore the "state" key of the snapshot
## entirely and only honour "seed" -- which is precisely the seed-versus-state
## bug this Feature exists to prevent. With that change in place, this case
## failed with a mismatch on the very first post-restore draw (the restored
## generator replayed from the seed instead of resuming), reported through
## the same `_expect()` message below naming the expected and actual values,
## and `test_bootstrap.gd` exited non-zero as a result. The edit was reverted
## immediately afterward; DeterministicRng is unmodified in this PR. See the
## PR description for the exact console output observed.
static func _test_mid_sequence_round_trip_resumes_rather_than_restarts() -> Array[String]:
	var violations: Array[String] = []

	var reference := _build_state(FIXED_SEED)
	var reference_draws := _apply_sequence(reference, SEQUENCE_STEPS)
	var reference_digest := reference.digest()

	var partial := _build_state(FIXED_SEED)
	var partial_draws := _apply_sequence(partial, ROUND_TRIP_K)

	var restored := GameState.from_dict(partial.to_dict())
	violations.append_array(
		_expect(restored != null, "from_dict() must accept a snapshot taken mid-sequence")
	)
	if restored == null:
		return violations

	var resumed_draws := _apply_sequence(restored, SEQUENCE_STEPS - ROUND_TRIP_K)

	violations.append_array(
		_expect(
			restored.digest() == reference_digest,
			(
				(
					"a state serialized at step %d, restored, and run to step %d must match the "
					+ "digest() of a reference run that was never serialized -- got %s, expected %s"
				)
				% [ROUND_TRIP_K, SEQUENCE_STEPS, restored.digest(), reference_digest]
			)
		)
	)

	var expected_tail := reference_draws.slice(ROUND_TRIP_K, SEQUENCE_STEPS)
	(
		violations
		. append_array(
			_expect(
				resumed_draws == expected_tail,
				(
					(
						"MID-SEQUENCE ROUND TRIP: draws recorded after restoration must match the "
						+ "reference run's draws from step %d onward, element for element -- got %s, "
						+ "expected %s (a mismatch here means the restored generator rewound instead of "
						+ "resuming)"
					)
					% [ROUND_TRIP_K, resumed_draws, expected_tail]
				)
			)
		)
	)

	# partial_draws itself is exercised here only to keep it a used local
	# rather than a write nobody reads; its content is not otherwise part of
	# the assertion, since the reference's first ROUND_TRIP_K draws already
	# cover that ground via reference_draws.slice(0, ROUND_TRIP_K).
	(
		violations
		. append_array(
			_expect(
				partial_draws == reference_draws.slice(0, ROUND_TRIP_K),
				(
					"the first %d draws of the partial run must match the reference run's first %d draws"
					% [ROUND_TRIP_K, ROUND_TRIP_K]
				)
			)
		)
	)

	return violations


## Cross-process proof: `_build_state(FIXED_SEED)` plus `SEQUENCE_STEPS` steps
## must reproduce GOLDEN_DIGEST, a value computed by an earlier, independent
## process. See GOLDEN_DIGEST's own docstring for what legitimately changes
## it and why this suite spawns no second process to check it a different way.
static func _test_golden_digest() -> Array[String]:
	var state := _build_state(FIXED_SEED)
	_apply_sequence(state, SEQUENCE_STEPS)
	var actual := state.digest()

	return _expect(
		actual == GOLDEN_DIGEST,
		(
			(
				"golden digest mismatch: got %s, expected %s -- see GOLDEN_DIGEST's docstring for "
				+ "what legitimately moves this value before updating the constant"
			)
			% [actual, GOLDEN_DIGEST]
		)
	)

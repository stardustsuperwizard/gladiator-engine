## Tests `MatchSetup`: the dev-authored starting state the hotseat scene is
## handed.
##
## **Authored numbers are read, never restated.** `turns_per_player` and
## `rounds_per_match` are compared against a fresh `load()` of
## `res://resources/round/round_profile.tres`, not against a literal 4 or 3 --
## the same discipline `tests/round_driver_test.gd`'s own docstring states for
## itself.
##
## Lives under `tests/` rather than `rules/tests/` for the reason
## `tests/round_driver_test.gd`'s own docstring gives: this suite names
## `RoundDriver`, `Authority` and `MatchSetup`, all `res://scripts/` code, and
## `rules/tests/extraction_contract_test.gd` fails the build over a `rules/`
## file that names one.
class_name MatchSetupTest

## The authored round structure, read rather than restated.
const ROUND_PROFILE_PATH := "res://resources/round/round_profile.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_turn_order_and_round_structure())
	violations.append_array(_test_every_fighter_is_placed_legally())
	violations.append_array(_test_the_roster_and_its_placements())
	violations.append_array(_test_the_turn_sequence_starts_fresh())
	violations.append_array(_test_determinism())
	violations.append_array(_test_a_full_turn_is_playable_through_round_driver())

	if violations.is_empty():
		return true

	printerr("\n=== Match Setup Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Turn order and round structure -----------------------------------------


static func _test_turn_order_and_round_structure() -> Array[String]:
	var violations: Array[String] = []
	var profile: RoundProfile = load(ROUND_PROFILE_PATH)
	var state := MatchSetup.build()

	violations.append_array(
		_expect(
			state.turn_order() == ["p1", "p2"],
			"turn_order() must be [\"p1\", \"p2\"], got %s" % [state.turn_order()]
		)
	)
	violations.append_array(
		_expect(
			state.turns_per_player == profile.turns_per_player,
			(
				"turns_per_player must equal the authored RoundProfile's, got %d vs %d"
				% [state.turns_per_player, profile.turns_per_player]
			)
		)
	)
	violations.append_array(
		_expect(
			state.rounds_per_match == profile.rounds_per_match,
			(
				"rounds_per_match must equal the authored RoundProfile's, got %d vs %d"
				% [state.rounds_per_match, profile.rounds_per_match]
			)
		)
	)

	return violations


# --- Placement legality -------------------------------------------------


## Every fighter `build()` places sits on a hex the board has, is the board's
## own `occupant_at()` that hex, and parses back through `Fighter.from_dict()`
## against a template `MatchSetup.templates()` registers.
static func _test_every_fighter_is_placed_legally() -> Array[String]:
	var violations: Array[String] = []
	var state := MatchSetup.build()
	var fighter_templates := MatchSetup.templates()

	for fighter_id in state.fighter_ids():
		var payload := state.fighter(fighter_id)
		var template := fighter_templates.template_for(state, fighter_id)
		violations.append_array(
			_expect(
				template != null,
				"%s's template_id must resolve against MatchSetup.templates()" % fighter_id
			)
		)
		if template == null:
			continue

		var fighter := Fighter.from_dict(payload, template)
		violations.append_array(
			_expect(fighter != null, "%s must parse back through Fighter.from_dict()" % fighter_id)
		)
		if fighter == null:
			continue

		var coord := fighter.position()
		violations.append_array(
			_expect(state.board.has_hex(coord), "%s must stand on a hex the board has" % fighter_id)
		)
		violations.append_array(
			_expect(
				state.board.occupant_at(coord) == StringName(fighter_id),
				(
					"the board's occupant at %s must be %s, got %s"
					% [coord, fighter_id, state.board.occupant_at(coord)]
				)
			)
		)

	return violations


# --- Roster composition and no-adjacent-enemy -------------------------------


## Each player owns at least two fighters, at least two authored templates
## appear across the roster, and no fighter starts adjacent to an enemy
## fighter -- an opening Turn is a real choice, not a forced melee.
static func _test_the_roster_and_its_placements() -> Array[String]:
	var violations: Array[String] = []
	var state := MatchSetup.build()
	var fighter_templates := MatchSetup.templates()

	# fighter_id -> {"owner": String, "coord": Vector3i, "template_id": String}
	var by_fighter: Dictionary = {}
	var fighters_by_owner: Dictionary = {}

	for fighter_id in state.fighter_ids():
		var template := fighter_templates.template_for(state, fighter_id)
		if template == null:
			continue

		var fighter := Fighter.from_dict(state.fighter(fighter_id), template)
		if fighter == null:
			continue

		by_fighter[fighter_id] = {
			"owner": fighter.owner_id(),
			"coord": fighter.position(),
			"template_id": template.template_id,
		}

		if not fighters_by_owner.has(fighter.owner_id()):
			fighters_by_owner[fighter.owner_id()] = []
		(fighters_by_owner[fighter.owner_id()] as Array).append(fighter_id)

	for player_id in state.turn_order():
		var owned: Array = fighters_by_owner.get(player_id, [])
		violations.append_array(
			_expect(
				owned.size() >= 2,
				"%s must own at least two fighters, got %d" % [player_id, owned.size()]
			)
		)

	var template_ids_used: Array = []
	for fighter_id in by_fighter:
		var template_id: String = by_fighter[fighter_id]["template_id"]
		if template_id not in template_ids_used:
			template_ids_used.append(template_id)
	violations.append_array(
		_expect(
			template_ids_used.size() >= 2,
			"the roster must be built from more than one authored template, got %s"
			% [template_ids_used]
		)
	)

	var fighter_ids := by_fighter.keys()
	for i in range(fighter_ids.size()):
		for j in range(i + 1, fighter_ids.size()):
			var a: Dictionary = by_fighter[fighter_ids[i]]
			var b: Dictionary = by_fighter[fighter_ids[j]]
			if a["owner"] == b["owner"]:
				continue
			violations.append_array(
				_expect(
					not HexCoord.are_adjacent(a["coord"], b["coord"]),
					(
						"%s (%s) and %s (%s) are enemies and must not start adjacent"
						% [fighter_ids[i], a["owner"], fighter_ids[j], b["owner"]]
					)
				)
			)

	return violations


# --- TurnSequence on a fresh build -------------------------------------------


static func _test_the_turn_sequence_starts_fresh() -> Array[String]:
	var violations: Array[String] = []
	var state := MatchSetup.build()

	violations.append_array(
		_expect(
			TurnSequence.active_player(state) == "p1",
			"the freshly built state's active player must be p1, got %s"
			% [TurnSequence.active_player(state)]
		)
	)
	violations.append_array(
		_expect(not state.power_step_open, "the freshly built state must have the Power Step closed")
	)
	violations.append_array(
		_expect(
			state.turns_taken == 0,
			"the freshly built state must have turns_taken 0, got %d" % state.turns_taken
		)
	)
	violations.append_array(
		_expect(
			state.round_number == 1,
			"the freshly built state must have round_number 1, got %d" % state.round_number
		)
	)

	return violations


# --- Determinism -------------------------------------------------------------


static func _test_determinism() -> Array[String]:
	var violations: Array[String] = []
	var seed_value := 7

	var first := MatchSetup.build(seed_value)
	var second := MatchSetup.build(seed_value)
	violations.append_array(
		_expect(
			first.digest() == second.digest(),
			"two build() calls with the same seed must produce identical digests"
		)
	)

	var different := MatchSetup.build(seed_value + 1)
	violations.append_array(
		_expect(
			first.rng.get_seed() != different.rng.get_seed(),
			"two build() calls with different seeds must produce a state whose rng differs"
		)
	)

	return violations


# --- A full Turn through RoundDriver -----------------------------------------


## Proves the fixture is playable, and that its templates match its payloads:
## one core action submitted by the active player, then both Power Step
## passes, ending the Turn and handing the next one to the other player.
static func _test_a_full_turn_is_playable_through_round_driver() -> Array[String]:
	var violations: Array[String] = []
	var state := MatchSetup.build()
	var fighter_templates := MatchSetup.templates()
	var authority := Authority.new(state)
	var driver := RoundDriver.new(authority, fighter_templates)

	var active := driver.active_player_id()
	violations.append_array(
		_expect(active == "p1", "the first Turn must belong to p1, got %s" % active)
	)

	var actor_id := MatchSetup.P1_WARRIOR_ID
	var actor_template := fighter_templates.template_for(state, actor_id)
	violations.append_array(
		_expect(actor_template != null, "%s must resolve to a registered template" % actor_id)
	)

	var acted := driver.submit(GuardAction.new(actor_id, actor_template), active)
	violations.append_array(
		_expect(acted.success, "the Turn's core action must resolve, got %s" % acted.reason)
	)

	violations.append_array(_play_power_step(driver, active))

	violations.append_array(
		_expect(
			driver.active_player_id() == "p2",
			"the next Turn must belong to p2, got %s" % driver.active_player_id()
		)
	)

	return violations


## Both Power Step passes for the Turn `active` is taking, each submitted
## through the driver as its own player -- the same shape
## `tests/round_driver_test.gd`'s own `_play_power_step()` uses.
static func _play_power_step(driver: RoundDriver, active: String) -> Array[String]:
	var violations: Array[String] = []
	var opponent := "p2" if active == "p1" else "p1"

	var first := driver.pass_power_step(active)
	violations.append_array(
		_expect(first.success, "the active player's pass must resolve, got %s" % first.reason)
	)

	var second := driver.pass_power_step(opponent)
	violations.append_array(
		_expect(second.success, "the opponent's pass must resolve, got %s" % second.reason)
	)

	return violations

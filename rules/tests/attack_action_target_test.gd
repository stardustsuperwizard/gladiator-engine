## Spec §7.3's two target-number charts, worked by hand against `AttackAction`.
##
## **Not a second test suite.** `test_bootstrap.gd`'s `_suites` gains no entry
## for this file, and it defines no independent `run() -> bool` of its own --
## `run()` below returns `Array[String]`, the same shape every private test
## method in `AttackActionTest` already returns. `AttackActionTest.run()` calls
## it directly and folds the result into its own violations, so a failure here
## still reports as "FAIL Attack Action Test", the one suite of record; nothing
## here ever prints its own PASS/FAIL line. `attack_action_push_test.gd` set
## that precedent and gives the full reasoning.
##
## **Why a second file at all.** Adding these tests to `attack_action_test.gd`
## itself pushes that file past gdlint's `max-file-lines` (.gdlintrc). That
## file's own comment prescribes exactly this response: "when a file approaches
## the limit, split it" -- rather than raising the ceiling or thinning the
## acceptance coverage to fit.
##
## **No fixture is redefined.** `_expect()`, `_build_state()`, `_place()` and
## the hex constants are one-line forwards onto `AttackActionTest`'s own, and
## the dials come from its `standard_profile()`, which restates the authored
## `combat_profile.tres` in memory. Nothing here loads a `.tres`:
## `extraction_contract_test.gd` forbids naming a `res://resources/` path under
## `rules/`.
##
## **The chart, worked from those dials** -- `attack_target` 5, `save_target`
## 5, `engagement_range` 1, `engagement_modifier` 1, attack flank/surround 1/2,
## save flank/surround 2/3, clamp [2, 6] -- with a warrior (range 1, attack 3,
## damage 2, save 2) and an archer (range 4, attack 2, damage 1, save 1):
##
##   | Scenario                              | Dist | Attack | Save |
##   | ------------------------------------- | ---- | ------ | ---- |
##   | warrior -> archer, nothing adjacent   |   1  |   4    |  5   |
##   | archer  -> warrior, in contact        |   1  |   4    |  5   |
##   | archer  -> warrior                    |   2  |   5    |  5   |
##   | archer  -> warrior                    |   4  |   5    |  5   |
##   | archer  -> warrior, target flanked    |   4  |   4    |  5   |
##   | archer  -> warrior, target surrounded |   4  |   3    |  5   |
##   | warrior -> archer, attacker flanked   |   1  |   4    |  3   |
##   | warrior -> archer, attacker surrounded|   1  |   4    |  2   |
##
## Three rows carry most of the risk. Row 2 proves **engagement is positional**:
## a Range-4 fighter standing in contact gets the same 4+ as the Range-1
## fighter, so a resolver deriving engagement from the Range stat rather than
## from the board fails there and nowhere else. Row 3 is the only row where
## this model differs from the long-range threshold it replaced. Rows 7 and 8
## use the **save** chart's larger magnitudes (-2 / -3), not the attack
## chart's, and key on the *attacker's* neighbours rather than the target's.
class_name AttackActionTargetTest
extends RefCounted

const ATTACKER_HEX := AttackActionTest.ATTACKER_HEX
const TARGET_HEX := AttackActionTest.TARGET_HEX
const FAR_HEX := AttackActionTest.FAR_HEX
const LONG_HEX := AttackActionTest.LONG_HEX
const LONG_FLANK_A := AttackActionTest.LONG_FLANK_A
const LONG_FLANK_B := AttackActionTest.LONG_FLANK_B
const TARGET_FLANK_A := AttackActionTest.TARGET_FLANK_A
const ATTACKER_FLANK := AttackActionTest.ATTACKER_FLANK
const ATTACKER_FLANK_B := AttackActionTest.ATTACKER_FLANK_B

## One hex beyond the archer's reach, on the same line.
const BEYOND_HEX := Vector3i(5, -5, 0)

## The ids every scenario below places, in the order `_build_scenario()` uses
## them: the attacker, the target, then the target's flankers and the
## attacker's, drawn from these pools in turn.
const ALLY_IDS: Array[String] = ["a2", "a3"]
const ENEMY_IDS: Array[String] = ["b2", "b3"]


static func run() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(_test_every_chart_row())
	violations.append_array(_test_attacker_and_target_flanked_simultaneously())
	violations.append_array(_test_the_attackers_own_stats_resolve_the_attack())
	violations.append_array(_test_a_hit_applies_the_attackers_own_damage())
	violations.append_array(_test_reach_is_the_attackers_own_range())

	return violations


# --- Fixtures, forwarded onto AttackActionTest's own ----------------------


static func _expect(condition: bool, message: String) -> Array[String]:
	return AttackActionTest._expect(condition, message)


static func _build_state(seed_value: int) -> GameState:
	return AttackActionTest._build_state(seed_value)


static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate
) -> void:
	AttackActionTest._place(state, fighter_id, owner_id, coord, template)


static func _stored_damage(state: GameState, fighter_id: String, template: FighterTemplate) -> int:
	return AttackActionTest._stored_damage(state, fighter_id, template)


## The authored dials, restated in memory by the parent suite.
static func _profile() -> CombatProfile:
	return AttackActionTest.standard_profile()


## Range 1, attack 3, damage 2, save 2 -- the authored warrior's combat stats.
static func _warrior() -> FighterTemplate:
	return AttackActionTest.fighter_template(2, 3, 1, 3, 2)


## Range 4, attack 2, damage 1, save 1 -- the authored archer's.
static func _archer() -> FighterTemplate:
	return AttackActionTest.fighter_template(1, 2, 4, 2, 1)


## Attacker `a1` (p1) at `ATTACKER_HEX`, target `b1` (p2) at `target_hex`, one
## p1 ally per hex in `target_flankers` and one p2 enemy per hex in
## `attacker_flankers`.
##
## The two flanker lists are separate because spec §8's check runs on two
## different fighters: an ally standing next to the target raises the *attack*
## bonus, and an enemy standing next to the attacker raises the *save* bonus.
## Every scenario below is one placement of those two lists.
static func _build_scenario(
	attacker_template: FighterTemplate,
	target_template: FighterTemplate,
	target_hex: Vector3i,
	target_flankers: Array,
	attacker_flankers: Array
) -> GameState:
	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", target_hex, target_template)

	for i in range(target_flankers.size()):
		_place(state, ALLY_IDS[i], "p1", target_flankers[i], attacker_template)
	for i in range(attacker_flankers.size()):
		_place(state, ENEMY_IDS[i], "p2", attacker_flankers[i], target_template)

	return state


# --- The chart ------------------------------------------------------------


## Every row of the chart in this file's docstring, one case each, asserted on
## the effective target numbers the action reports.
##
## The dice are irrelevant here and no expectation depends on them: what is
## under test is spec §7.3's arithmetic, which runs before either pool is
## rolled. Each case also asserts the attack resolved at all, so a row that
## silently became a refusal cannot pass by leaving the accessors at 0.
static func _test_every_chart_row() -> Array[String]:
	var violations: Array[String] = []
	var warrior := _warrior()
	var archer := _archer()
	var none: Array = []

	# label, attacker, target, target hex, target flankers, attacker flankers,
	# expected attack target, expected save target
	var cases := [
		["warrior -> archer at 1, nothing adjacent", warrior, archer, TARGET_HEX, none, none, 4, 5],
		["archer -> warrior in contact", archer, warrior, TARGET_HEX, none, none, 4, 5],
		["archer -> warrior at 2", archer, warrior, FAR_HEX, none, none, 5, 5],
		["archer -> warrior at 4", archer, warrior, LONG_HEX, none, none, 5, 5],
		[
			"archer -> warrior at 4, target flanked",
			archer,
			warrior,
			LONG_HEX,
			[LONG_FLANK_A],
			none,
			4,
			5
		],
		[
			"archer -> warrior at 4, target surrounded",
			archer,
			warrior,
			LONG_HEX,
			[LONG_FLANK_A, LONG_FLANK_B],
			none,
			3,
			5
		],
		[
			"warrior -> archer at 1, attacker flanked",
			warrior,
			archer,
			TARGET_HEX,
			none,
			[ATTACKER_FLANK],
			4,
			3
		],
		[
			"warrior -> archer at 1, attacker surrounded",
			warrior,
			archer,
			TARGET_HEX,
			none,
			[ATTACKER_FLANK, ATTACKER_FLANK_B],
			4,
			2
		],
	]

	for entry in cases:
		var label: String = entry[0]
		var attacker_template: FighterTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var target_hex: Vector3i = entry[3]
		var expected_attack: int = entry[6]
		var expected_save: int = entry[7]

		var state := _build_scenario(
			attacker_template, target_template, target_hex, entry[4], entry[5]
		)
		var action := AttackAction.new("a1", "b1", attacker_template, target_template, _profile())
		var result := action.resolve(state)

		violations.append_array(
			_expect(result.success, "%s must resolve, not be refused (%s)" % [label, result.reason])
		)
		violations.append_array(
			_expect(
				action.attack_target() == expected_attack,
				"%s must attack on %d+, got %d+" % [label, expected_attack, action.attack_target()]
			)
		)
		violations.append_array(
			_expect(
				action.save_target() == expected_save,
				"%s must save on %d+, got %d+" % [label, expected_save, action.save_target()]
			)
		)

	return violations


## Both fighters flanked at once, at different tiers, so each roll must take
## its own bonus from its own dials and neither can be reading the other's.
##
## A warrior attacks an adjacent archer. One friendly ally stands next to the
## archer, so the target is FLANKED: the attack target is 5 - 1 (attack flank)
## - 1 (engaged) = 3. Two enemies stand next to the warrior, so the attacker is
## SURROUNDED: the save target is 5 - 3 (save surround) = 2.
##
## The two answers differ, and they differ in a way that swapping the charts
## would break: priced off the attack dials the save target would be 5 - 2 = 3,
## and priced off the save dials the attack target would be 5 - 2 - 1 = 2.
static func _test_attacker_and_target_flanked_simultaneously() -> Array[String]:
	var violations: Array[String] = []
	var warrior := _warrior()
	var archer := _archer()

	var state := _build_scenario(
		warrior, archer, TARGET_HEX, [TARGET_FLANK_A], [ATTACKER_FLANK, ATTACKER_FLANK_B]
	)
	var action := AttackAction.new("a1", "b1", warrior, archer, _profile())
	var result := action.resolve(state)

	violations.append_array(
		_expect(result.success, "the simultaneous-flanking scenario must resolve")
	)
	violations.append_array(
		_expect(
			action.attack_bonus_count() == Flanking.FLANKED,
			"one ally beside the target must read the target as FLANKED"
		)
	)
	violations.append_array(
		_expect(
			action.save_bonus_count() == Flanking.SURROUNDED,
			"two enemies beside the attacker must read the attacker as SURROUNDED"
		)
	)
	violations.append_array(
		_expect(
			action.attack_target() == 3,
			(
				"a flanked target attacked in contact must be hit on 3+, got %d+"
				% action.attack_target()
			)
		)
	)
	violations.append_array(
		_expect(
			action.save_target() == 2,
			(
				"a surrounded attacker must be saved against on 2+ off the save dials, got %d+"
				% action.save_target()
			)
		)
	)

	return violations


## The attacker's own `attack`, `damage` and `range_hexes` decide the attack --
## not the target's, which this scenario makes deliberately different in all
## three.
##
## The attacker reaches 3 hexes, rolls 4 dice and deals 3 damage; the target
## reaches 1, rolls 1 and deals 1, and saves on 2 dice. Resolved with the
## attacker's numbers this is a 4-dice pool at distance 3 applying 3 damage.
## Resolved with the target's it would be refused as out of range before it
## ever rolled, and if it did roll it would roll one die for one damage.
static func _test_the_attackers_own_stats_resolve_the_attack() -> Array[String]:
	var violations: Array[String] = []
	var attacker_template := AttackActionTest.fighter_template(2, 5, 3, 4, 3)
	var target_template := AttackActionTest.fighter_template(2, 9, 1, 1, 1)
	var reach_hex := Vector3i(3, -3, 0)

	violations.append_array(
		_expect(
			(
				attacker_template.attack != target_template.attack
				and attacker_template.damage != target_template.damage
				and attacker_template.range_hexes != target_template.range_hexes
			),
			"this scenario requires the two fighters to differ in all three attacking stats"
		)
	)
	violations.append_array(
		_expect(
			HexCoord.distance(ATTACKER_HEX, reach_hex) > target_template.range_hexes,
			"this scenario must stand the target beyond its own range_hexes"
		)
	)

	var state := _build_state(13)
	_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
	_place(state, "b1", "p2", reach_hex, target_template)

	var profile := AttackActionTest.forced_profile(
		AttackActionTest.ALWAYS_TARGET, AttackActionTest.NEVER_TARGET
	)
	var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
	var result := action.resolve(state)

	violations.append_array(
		_expect(
			result.success,
			"a target within the attacker's range_hexes must resolve, not report %s" % result.reason
		)
	)
	violations.append_array(
		_expect(
			action.attack_successes() == attacker_template.attack,
			(
				"the attack pool must hold the attacker's attack dice (%d), counted %d"
				% [attacker_template.attack, action.attack_successes()]
			)
		)
	)
	violations.append_array(
		_expect(
			_stored_damage(state, "b1", target_template) == attacker_template.damage,
			(
				"a Hit must apply the attacker's damage (%d), applied %d"
				% [attacker_template.damage, _stored_damage(state, "b1", target_template)]
			)
		)
	)

	return violations


## A Hit applies the attacking fighter's own damage: a warrior Hit adds 2 and
## an archer Hit adds 1, off the very same pair of templates in both
## directions.
static func _test_a_hit_applies_the_attackers_own_damage() -> Array[String]:
	var violations: Array[String] = []
	var warrior := _warrior()
	var archer := _archer()
	var profile := AttackActionTest.forced_profile(
		AttackActionTest.ALWAYS_TARGET, AttackActionTest.NEVER_TARGET
	)

	# label, attacker template, target template, expected damage
	var cases := [["warrior", warrior, archer, 2], ["archer", archer, warrior, 1]]

	for entry in cases:
		var label: String = entry[0]
		var attacker_template: FighterTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var expected: int = entry[3]

		var state := _build_state(13)
		_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
		_place(state, "b1", "p2", TARGET_HEX, target_template)

		var action := AttackAction.new("a1", "b1", attacker_template, target_template, profile)
		var result := action.resolve(state)

		violations.append_array(_expect(result.success, "the %s's attack must resolve" % label))
		violations.append_array(
			_expect(action.outcome() == DicePool.Outcome.HIT, "the %s's attack must Hit" % label)
		)
		violations.append_array(
			_expect(
				_stored_damage(state, "b1", target_template) == expected,
				(
					"a %s Hit must add %d damage, added %d"
					% [label, expected, _stored_damage(state, "b1", target_template)]
				)
			)
		)

	return violations


## Reach is read off the attacker, inclusively: the archer resolves at exactly
## 4 hexes and is refused at 5, while the warrior standing in the archer's
## place is refused at 2.
static func _test_reach_is_the_attackers_own_range() -> Array[String]:
	var violations: Array[String] = []
	var warrior := _warrior()
	var archer := _archer()

	# label, attacker, target, target hex, expected reason (&"" for resolves)
	var cases := [
		["the archer at exactly its range of 4", archer, warrior, LONG_HEX, &""],
		[
			"the archer one hex past its range",
			archer,
			warrior,
			BEYOND_HEX,
			AttackAction.FAILURE_TARGET_OUT_OF_RANGE
		],
		[
			"the warrior two hexes out",
			warrior,
			archer,
			FAR_HEX,
			AttackAction.FAILURE_TARGET_OUT_OF_RANGE
		],
	]

	for entry in cases:
		var label: String = entry[0]
		var attacker_template: FighterTemplate = entry[1]
		var target_template: FighterTemplate = entry[2]
		var target_hex: Vector3i = entry[3]
		var expected: StringName = entry[4]

		var state := _build_state(13)
		_place(state, "a1", "p1", ATTACKER_HEX, attacker_template)
		_place(state, "b1", "p2", target_hex, target_template)

		var action := AttackAction.new("a1", "b1", attacker_template, target_template, _profile())
		var result := action.resolve(state)

		violations.append_array(
			_expect(
				result.reason == expected,
				"%s must report %s, got %s" % [label, expected, result.reason]
			)
		)

	return violations

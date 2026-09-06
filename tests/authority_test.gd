## Tests the `Authority` predicate, every branch: the permitted case, all four
## refusals, the fixed order they are checked in, `set_active_player()`, and
## that asking the question never changes the answer's subject.
##
## Also the home of the vocabulary-separation assertion --
## `PassAction.FAILURE_NO_SUCH_FIGHTER` against every `Authority.REFUSED_*`
## constant. That assertion cannot live in `rules/tests/pass_action_test.gd`,
## because `rules/` names no game-side class at all; this suite is game-side
## and may name both sides.
##
## Lives under `tests/` rather than `rules/tests/` for the same reason
## `tests/resource_data_test.gd` does: `Authority` is `res://scripts/` code,
## which `rules/tests/extraction_contract_test.gd` fails the build over.
class_name AuthorityTest

## Every refusal constant, as name/value pairs, so the distinctness and
## vocabulary tests below enumerate one list instead of four literals.
const REFUSALS := [
	["REFUSED_NO_ACTIVE_PLAYER", Authority.REFUSED_NO_ACTIVE_PLAYER],
	["REFUSED_NOT_YOUR_TURN", Authority.REFUSED_NOT_YOUR_TURN],
	["REFUSED_NO_SUCH_FIGHTER", Authority.REFUSED_NO_SUCH_FIGHTER],
	["REFUSED_NOT_YOUR_FIGHTER", Authority.REFUSED_NOT_YOUR_FIGHTER],
]


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_active_player_seeds_from_turn_order())
	violations.append_array(_test_state_is_the_same_object())
	violations.append_array(_test_owner_on_their_turn_is_permitted())
	violations.append_array(_test_wrong_turn_is_refused())
	violations.append_array(_test_wrong_owner_is_refused())
	violations.append_array(_test_unknown_actor_is_refused())
	violations.append_array(_test_malformed_owner_is_refused())
	violations.append_array(_test_no_players_refuses_everything())
	violations.append_array(_test_set_active_player())
	violations.append_array(_test_check_order_is_fixed())
	violations.append_array(_test_can_perform_delegates_to_refusal())
	violations.append_array(_test_asking_changes_nothing())
	violations.append_array(_test_refusal_constants_are_distinct())
	violations.append_array(_test_action_failures_are_a_separate_vocabulary())

	if violations.is_empty():
		return true

	printerr("\n=== Authority Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Two players, "p1" first in the turn order, and one fighter each. The
## payloads carry `"owner_id"` because that is the shape `Fighter.to_dict()`
## produces and the key `Authority` is written to read.
static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(1))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	state.add_fighter("f2", {"id": "f2", "owner_id": "p2"})
	return state


static func _empty_state() -> GameState:
	return GameState.new(Board.new(), DeterministicRng.new(1))


static func _test_active_player_seeds_from_turn_order() -> Array[String]:
	var state := _build_state()
	var authority := Authority.new(state)

	return _expect(
		authority.active_player_id() == state.turn_order()[0],
		"a new Authority must take its active player from the front of turn_order()"
	)


## By reference, never a copy: resolving has to mutate the state everyone else
## is reading.
static func _test_state_is_the_same_object() -> Array[String]:
	var state := _build_state()
	var authority := Authority.new(state)

	return _expect(
		is_same(authority.state(), state), "state() must return the very state Authority was given"
	)


static func _test_owner_on_their_turn_is_permitted() -> Array[String]:
	var violations: Array[String] = []
	var authority := Authority.new(_build_state())
	var action := PassAction.new("f1")

	violations.append_array(
		_expect(
			authority.can_perform(action, "p1"),
			"the active player acting with a fighter they own must be permitted"
		)
	)
	violations.append_array(
		_expect(
			authority.refusal(action, "p1") == &"",
			'a permitted request must produce refusal() == &""'
		)
	)

	return violations


## The parent Feature's worked scenario: "p2" owns "f2" and is still refused,
## because it is not "p2"'s turn.
static func _test_wrong_turn_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var authority := Authority.new(_build_state())
	var action := PassAction.new("f2")

	violations.append_array(
		_expect(
			not authority.can_perform(action, "p2"),
			"a request from a player whose turn it is not must be refused"
		)
	)
	violations.append_array(
		_expect(
			authority.refusal(action, "p2") == Authority.REFUSED_NOT_YOUR_TURN,
			"a request out of turn must be refused with REFUSED_NOT_YOUR_TURN"
		)
	)

	return violations


static func _test_wrong_owner_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var authority := Authority.new(_build_state())
	var action := PassAction.new("f2")

	violations.append_array(
		_expect(
			not authority.can_perform(action, "p1"),
			"the active player acting with someone else's fighter must be refused"
		)
	)
	violations.append_array(
		_expect(
			authority.refusal(action, "p1") == Authority.REFUSED_NOT_YOUR_FIGHTER,
			"acting with a fighter owned by another player must give REFUSED_NOT_YOUR_FIGHTER"
		)
	)

	return violations


static func _test_unknown_actor_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var action := PassAction.new("no_such_fighter")

	violations.append_array(
		_expect(
			"no_such_fighter" not in state.fighter_ids(),
			"the unknown-actor fixture must genuinely be absent from the state"
		)
	)
	violations.append_array(
		_expect(
			authority.refusal(action, "p1") == Authority.REFUSED_NO_SUCH_FIGHTER,
			"an action naming an absent actor must give REFUSED_NO_SUCH_FIGHTER"
		)
	)

	return violations


## A payload with no `"owner_id"`, and one whose `"owner_id"` is not a
## `String`, are both refused as not-yours. An unreadable owner is not an
## owner, and refusing is the safe direction to be wrong in.
static func _test_malformed_owner_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	state.add_fighter("ownerless", {"id": "ownerless"})
	state.add_fighter("wrong_type", {"id": "wrong_type", "owner_id": 7})
	var authority := Authority.new(state)

	violations.append_array(
		_expect(
			(
				authority.refusal(PassAction.new("ownerless"), "p1")
				== Authority.REFUSED_NOT_YOUR_FIGHTER
			),
			'a payload with no "owner_id" must give REFUSED_NOT_YOUR_FIGHTER'
		)
	)
	violations.append_array(
		_expect(
			(
				authority.refusal(PassAction.new("wrong_type"), "p1")
				== Authority.REFUSED_NOT_YOUR_FIGHTER
			),
			'a payload whose "owner_id" is not a String must give REFUSED_NOT_YOUR_FIGHTER'
		)
	)

	return violations


static func _test_no_players_refuses_everything() -> Array[String]:
	var violations: Array[String] = []
	var state := _empty_state()
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	var authority := Authority.new(state)

	violations.append_array(
		_expect(
			authority.active_player_id() == "",
			'an Authority over a state with no players must report "" as the active player'
		)
	)
	(
		violations
		. append_array(
			_expect(
				authority.refusal(PassAction.new("f1"), "p1") == Authority.REFUSED_NO_ACTIVE_PLAYER,
				"with no active player, a request for a known fighter must give REFUSED_NO_ACTIVE_PLAYER"
			)
		)
	)
	violations.append_array(
		_expect(
			(
				authority.refusal(PassAction.new("no_such_fighter"), "")
				== Authority.REFUSED_NO_ACTIVE_PLAYER
			),
			"with no active player, every request must give REFUSED_NO_ACTIVE_PLAYER"
		)
	)
	violations.append_array(
		_expect(
			not authority.can_perform(PassAction.new("f1"), "p1"),
			"with no active player, can_perform() must be false"
		)
	)

	return violations


static func _test_set_active_player() -> Array[String]:
	var violations: Array[String] = []
	var authority := Authority.new(_build_state())

	violations.append_array(
		_expect(
			authority.set_active_player("p2"),
			"set_active_player() must return true for an id in turn_order()"
		)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p2",
			"set_active_player() must change the active player to the id it accepted"
		)
	)

	violations.append_array(
		_expect(
			not authority.set_active_player("p3"),
			"set_active_player() must return false for an id absent from turn_order()"
		)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p2",
			"a refused set_active_player() must leave the active player unchanged"
		)
	)

	violations.append_array(
		_expect(
			not authority.set_active_player(""),
			"set_active_player() must return false for an empty id"
		)
	)
	violations.append_array(
		_expect(
			authority.active_player_id() == "p2",
			'set_active_player("") must leave the active player unchanged'
		)
	)

	# The refusals follow the field, so the gate now reads the other way round.
	violations.append_array(
		_expect(
			authority.refusal(PassAction.new("f2"), "p2") == &"",
			'after set_active_player("p2"), p2 acting with their own fighter must be permitted'
		)
	)
	violations.append_array(
		_expect(
			authority.refusal(PassAction.new("f1"), "p1") == Authority.REFUSED_NOT_YOUR_TURN,
			'after set_active_player("p2"), p1 must be refused with REFUSED_NOT_YOUR_TURN'
		)
	)

	return violations


## A request failing more than one condition reports a deterministic reason:
## no-active-player before wrong-turn, wrong-turn before unknown-actor,
## unknown-actor before wrong-owner.
static func _test_check_order_is_fixed() -> Array[String]:
	var violations: Array[String] = []

	var empty := _empty_state()
	empty.add_fighter("f2", {"id": "f2", "owner_id": "p2"})
	violations.append_array(
		_expect(
			(
				Authority.new(empty).refusal(PassAction.new("f2"), "p1")
				== Authority.REFUSED_NO_ACTIVE_PLAYER
			),
			"no active player must be reported ahead of a wrong-owner failure"
		)
	)

	var authority := Authority.new(_build_state())
	violations.append_array(
		_expect(
			(
				authority.refusal(PassAction.new("no_such_fighter"), "p2")
				== Authority.REFUSED_NOT_YOUR_TURN
			),
			"a wrong turn must be reported ahead of an unknown actor"
		)
	)
	violations.append_array(
		_expect(
			authority.refusal(PassAction.new("f1"), "p2") == Authority.REFUSED_NOT_YOUR_TURN,
			"a wrong turn must be reported ahead of a wrong owner"
		)
	)
	violations.append_array(
		_expect(
			(
				authority.refusal(PassAction.new("no_such_fighter"), "p1")
				== Authority.REFUSED_NO_SUCH_FIGHTER
			),
			"an unknown actor must be reported ahead of a wrong owner"
		)
	)

	return violations


## `can_perform()` is the predicate read as a bool, not a second copy of it.
## Checked across every branch rather than on one happy case.
static func _test_can_perform_delegates_to_refusal() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	state.add_fighter("ownerless", {"id": "ownerless"})
	var authority := Authority.new(state)

	var requests := [
		["f1", "p1"],
		["f2", "p2"],
		["f2", "p1"],
		["ownerless", "p1"],
		["no_such_fighter", "p1"],
	]

	for request in requests:
		var actor: String = request[0]
		var requester: String = request[1]
		var action := PassAction.new(actor)
		(
			violations
			. append_array(
				_expect(
					(
						authority.can_perform(action, requester)
						== authority.refusal(action, requester).is_empty()
					),
					(
						"can_perform() must agree with refusal().is_empty() for actor %s requested by %s"
						% [actor, requester]
					)
				)
			)
		)

	return violations


## Asking the gate a question is not a move. Neither `refusal()` nor
## `can_perform()` may resolve anything, so the state's digest must survive
## every branch untouched.
static func _test_asking_changes_nothing() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var before_turns := state.turns_taken
	var before_digest := state.digest()

	for actor in ["f1", "f2", "no_such_fighter"]:
		for requester in ["p1", "p2", "p3"]:
			authority.refusal(PassAction.new(actor), requester)
			authority.can_perform(PassAction.new(actor), requester)

	violations.append_array(
		_expect(state.turns_taken == before_turns, "asking Authority must not change turns_taken")
	)
	violations.append_array(
		_expect(
			state.digest() == before_digest, "asking Authority must not change the state digest"
		)
	)

	return violations


static func _test_refusal_constants_are_distinct() -> Array[String]:
	var violations: Array[String] = []

	for i in range(REFUSALS.size()):
		var name_i: String = REFUSALS[i][0]
		var value_i: StringName = REFUSALS[i][1]

		violations.append_array(
			_expect(not value_i.is_empty(), "Authority.%s must not be empty" % name_i)
		)

		for j in range(i + 1, REFUSALS.size()):
			var name_j: String = REFUSALS[j][0]
			var value_j: StringName = REFUSALS[j][1]
			violations.append_array(
				_expect(
					value_i != value_j,
					"Authority.%s and Authority.%s must be different values" % [name_i, name_j]
				)
			)

	return violations


## The gate's refusals and an action's failures are two vocabularies, and
## neither may be expressed in the other's terms. `PassAction`'s "no such
## fighter" deliberately overlaps in meaning with the gate's and deliberately
## is not the same constant.
static func _test_action_failures_are_a_separate_vocabulary() -> Array[String]:
	var violations: Array[String] = []

	for entry in REFUSALS:
		var refusal_name: String = entry[0]
		var refusal_value: StringName = entry[1]
		(
			violations
			. append_array(
				_expect(
					PassAction.FAILURE_NO_SUCH_FIGHTER != refusal_value,
					(
						(
							"PassAction.FAILURE_NO_SUCH_FIGHTER must not equal Authority.%s -- an action's "
							% refusal_name
						)
						+ "failures and the gate's refusals are separate vocabularies"
					)
				)
			)
		)

	violations.append_array(
		_expect(
			PassAction.FAILURE_NO_SUCH_FIGHTER != TurnAction.FAILURE_NOT_IMPLEMENTED,
			"PassAction.FAILURE_NO_SUCH_FIGHTER must not equal TurnAction.FAILURE_NOT_IMPLEMENTED"
		)
	)

	return violations

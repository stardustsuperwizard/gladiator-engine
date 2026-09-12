## The hotseat match: two people at one screen, playing a Combat Segment
## through `HotseatSession`.
##
## This is `res://scenes/main.tscn`'s own script. It builds the match once in
## `_ready()` -- `MatchSetup.build()`, an `Authority` over that state, a
## `HotseatSession` over that `Authority`, and an `ActionOptions` over the same
## templates and the authored `CombatProfile` -- and from then on it does three
## things and no more: it turns a tap or a button press into a command, it
## hands that command to `HotseatSession`, and it re-renders whatever comes
## back.
##
## **Every command goes out through `HotseatSession`.** `submit()`, `decline()`,
## `pass_power_step()` and `advance_segment()` are the only four ways anything
## leaves this class, and nothing here calls `Authority`, `ActionRunner` or
## `RoundDriver` to submit. The actions themselves are built by
## `ActionOptions`, never by hand, and this class resolves nothing --
## `tests/gate_bypass_contract_test.gd` fails the build on a receiver-qualified
## `.resolve(` or a `res://rules/` literal appearing here, and this file
## carries neither.
##
## **It holds no rule and no derived tally.** Whose Turn it is, which Step the
## Turn is on, whose pass the Power Step is waiting for and whether the Segment
## is over all come off `HotseatSession`; what a selected fighter may do comes
## off `ActionOptions`. There is no Turn counter here, no pass counter, no
## round counter and no legality check of this class's own, and
## `Authority.set_active_player()` is never called -- `RoundDriver` keeps the
## gate in step with `TurnSequence` underneath the session, and a scene that
## rotated the active player itself would be deciding something the rules
## already decide.
##
## **What it does keep is a selection**, which is not a rule: which fighter the
## player has pointed at, which action button they pressed, and -- mid-Charge
## -- which target they have named so far. Those are the three things a pointer
## cannot say in one tap, and they are cleared the moment a command is
## submitted.
##
## **An offered option is not a promise.** A highlighted hex is what
## `ActionOptions` reported, not a guarantee the gate will agree, and a tap on
## an un-highlighted hex is submitted like any other rather than swallowed
## here. A refusal or a failure is appended to the log carrying its
## `TurnResult.reason` verbatim, the selected fighter survives it, and nothing
## is retried or translated away.
##
## **It mutates no `GameState` and keeps no copy of one.** Every read goes
## through `Authority.state()` at the point of use -- the precedent
## `ActionRunner`, `RoundDriver` and `HotseatSession` all set -- so what the
## board draws is the state the gate validated against.
##
## **It owns its session rather than reaching for a global.** No autoload is
## added and no event bus exists: `docs/godot-implementation-guide.md` §6 puts
## the authority object on the match scene, signals travel up from `BoardView`
## and direct calls travel down to it.
##
## **At `MATCH_COMPLETE` it stops.** The buttons go dead and the HUD says the
## match is over and that working out who won is #173. It names no winner and
## computes no score -- `EndSegment` refusing `FAILURE_FINAL_ROUND` is where
## this scene's job ends.
class_name HotseatMatch
extends Node

## The four core actions an Action Step can choose, as `choose_action()` takes
## them. `StringName` rather than an enum so a `pressed` signal can carry one
## through `Callable.bind()` and a test can name one without an int.
const ACTION_MOVE := &"move"
const ACTION_ATTACK := &"attack"
const ACTION_CHARGE := &"charge"
const ACTION_GUARD := &"guard"

## Display text per `HotseatSession.Phase`, keyed by the enum's own int value
## so a phase looks up directly -- the shape `BoardView.HEX_COLORS` already
## uses for `Board.HexType`.
const PHASE_LABELS := {
	HotseatSession.Phase.ACTION_STEP: "Action Step",
	HotseatSession.Phase.POWER_STEP: "Power Step",
	HotseatSession.Phase.SEGMENT_COMPLETE: "Combat Segment complete",
	HotseatSession.Phase.MATCH_COMPLETE: "Match complete",
}

## What the HUD says once the final round's Combat Segment is complete. It
## names no winner on purpose: victory determination is #173, and a banner
## guessing at it would be a rule this scene does not have.
const MATCH_OVER_TEXT := "The match is over. Working out who won is issue #173."

## Shown where a player id would be when the rules name nobody.
const NOBODY := "--"

## The gate, and this scene's one route to the `GameState` it renders. Never
## submitted to directly -- see the class docstring.
var _authority: Authority

## Which Step of which Turn the match is on, and the only way a command leaves
## this class.
var _session: HotseatSession

## What a selected fighter may do, and the only thing that builds a
## `TurnAction` here.
var _options: ActionOptions

## The game-side template lookup, shared with the session and handed to
## `BoardView` so it can draw a fighter's stats.
var _templates: FighterTemplates

## The fighter the player has pointed at, or `""`. A selection, not an
## entitlement: nothing here checks who owns it, and a command naming a fighter
## the active player does not own comes back refused by the gate.
var _selected_fighter: String = ""

## The action button pressed and not yet completed, or `&""` when the next tap
## is a fighter selection rather than part of a command.
var _pending_action: StringName = &""

## The target named by the first of a Charge's two taps, or `""` when the next
## tap is that first one.
var _charge_target: String = ""

## Every result this scene has submitted, oldest first, as the HUD shows them.
## A transcript of what came back, never a tally derived from it.
var _log: Array[String] = []

@onready var _board_view: BoardView = $BoardView
@onready var _round_label: Label = $Hud/Sidebar/RoundLabel
@onready var _phase_label: Label = $Hud/Sidebar/PhaseLabel
@onready var _player_label: Label = $Hud/Sidebar/PlayerLabel
@onready var _selection_label: Label = $Hud/Sidebar/SelectionLabel
@onready var _move_button: Button = $Hud/Sidebar/ActionButtons/MoveButton
@onready var _attack_button: Button = $Hud/Sidebar/ActionButtons/AttackButton
@onready var _charge_button: Button = $Hud/Sidebar/ActionButtons/ChargeButton
@onready var _guard_button: Button = $Hud/Sidebar/ActionButtons/GuardButton
@onready var _decline_button: Button = $Hud/Sidebar/DeclineButton
@onready var _pass_button: Button = $Hud/Sidebar/PassButton
@onready var _advance_button: Button = $Hud/Sidebar/AdvanceButton
@onready var _status_label: Label = $Hud/Sidebar/StatusLabel
@onready var _log_label: RichTextLabel = $Hud/Sidebar/LogLabel


## Builds the match, wires the HUD and the board to the intent methods below,
## and renders the opening position.
##
## The four objects are built here and nowhere else, in the one order that
## keeps them a matched set: the state first, the gate over that state, the
## session over that gate, and the options over the same templates the session
## was given.
func _ready() -> void:
	_templates = MatchSetup.templates()
	_authority = Authority.new(MatchSetup.build())
	_session = HotseatSession.new(_authority, _templates)
	_options = ActionOptions.new(_templates, MatchSetup.combat_profile())

	_board_view.hex_selected.connect(select_hex)
	_move_button.pressed.connect(choose_action.bind(ACTION_MOVE))
	_attack_button.pressed.connect(choose_action.bind(ACTION_ATTACK))
	_charge_button.pressed.connect(choose_action.bind(ACTION_CHARGE))
	_guard_button.pressed.connect(choose_action.bind(ACTION_GUARD))
	_decline_button.pressed.connect(decline_turn)
	_pass_button.pressed.connect(pass_power_step)
	_advance_button.pressed.connect(advance_segment)

	_render()


## The session this scene routes every command through.
##
## Exposed so a suite can assert against the session's own reports -- the
## phase, the active player, whose pass is next -- rather than against a label
## this class wrote. Read-only by convention: a caller that submits through it
## is submitting through the same object the buttons do.
func session() -> HotseatSession:
	return _session


## The live `GameState`, off the gate, at the moment of asking. The same
## reference `Authority` holds; this scene never mutates it and neither should
## a caller.
func state() -> GameState:
	return _authority.state()


## Points the HUD at `fighter_id` and clears any half-finished command.
##
## A selection and nothing else: no ownership test, no legality test, no
## submission. Selecting an enemy fighter is allowed and produces a refusal
## from the gate if a command is then built from it, which is the gate's
## answer to give.
func select_fighter(fighter_id: String) -> void:
	_selected_fighter = fighter_id
	_pending_action = &""
	_charge_target = ""
	_render()


## Takes the action button `kind` names for the selected fighter.
##
## Guard needs no further input and is submitted at once. Move, Attack and
## Charge each need a hex or a target, so they are held as the pending action
## and the hexes `ActionOptions` reports are highlighted until `select_hex()`
## completes the command.
##
## With no fighter selected there is nothing to build a command from, so this
## says so in the log and submits nothing. That is a missing selection, not a
## rule: Decline is the way to take a Turn without choosing a fighter, and it
## needs no selection at all.
func choose_action(kind: StringName) -> void:
	if _selected_fighter.is_empty():
		_note("select a fighter before choosing %s" % kind)
		return

	_charge_target = ""

	if kind == ACTION_GUARD:
		_pending_action = &""
		_submit(_options.guard(state(), _selected_fighter), "guard %s" % _selected_fighter)
		return

	_pending_action = kind
	_render()


## What a tap on `coord` means, given what is already selected.
##
## Returns `null` when the tap only advanced the selection -- picking a
## fighter, or naming a Charge's target -- and the submitted `TurnResult` when
## it completed a command.
##
## With no pending action the tap selects whichever fighter occupies the hex,
## and does nothing at all on an empty one. With Move pending it submits a
## Move to that hex, highlighted or not: filtering the tap here would make a
## refusal impossible to see, and an offered option was never a promise.
## Attack and Charge read the hex's occupant as the target, and a Charge takes
## its two taps in the order the flow states -- target first, destination
## second.
func select_hex(coord: Vector3i) -> TurnResult:
	var current := state()

	if _pending_action.is_empty():
		var tapped := String(current.board.occupant_at(coord))
		if not tapped.is_empty():
			select_fighter(tapped)
		return null

	if _pending_action == ACTION_MOVE:
		return _submit(
			_options.move(current, _selected_fighter, coord),
			"move %s to %s" % [_selected_fighter, coord]
		)

	if _pending_action == ACTION_ATTACK:
		var target := String(current.board.occupant_at(coord))
		if target.is_empty():
			return null
		return _submit(
			_options.attack(current, _selected_fighter, target),
			"attack %s with %s" % [target, _selected_fighter]
		)

	if _pending_action == ACTION_CHARGE:
		return _charge_tap(current, coord)

	return null


## Spec §5.3's one explicit way not to choose, for the player
## `HotseatSession.player_to_act()` names.
##
## Reachable with nothing selected and never disabled while a Turn is open,
## because declining is a decision about the Turn rather than about a fighter.
## What it comes to is `DefaultActionStep`'s answer, reached through
## `HotseatSession.decline()`, and this class does not anticipate it.
func decline_turn() -> TurnResult:
	var player := _session.player_to_act()
	return _record("%s declines" % _named(player), _session.decline(player))


## Submits one Power Step pass, for the player
## `HotseatSession.player_to_act()` names.
##
## One press, one pass, one player: the opponent's pass is their own press, and
## nothing here supplies it for them. A press outside an open Power Step is
## submitted anyway and comes back
## `PowerStepPassAction.FAILURE_STEP_NOT_OPEN`.
func pass_power_step() -> TurnResult:
	var player := _session.player_to_act()
	return _record("%s passes" % _named(player), _session.pass_power_step(player))


## Runs spec §10's End Segment through `HotseatSession.advance_segment()`: the
## round ends, its flags clear, the next one begins.
##
## Offered by a button rather than taken automatically, so the Segment boundary
## is something the two players cross when they have both looked at the board.
## Its refusals -- an incomplete Segment, and the final round's
## `EndSegment.FAILURE_FINAL_ROUND` -- reach the log like any other result.
func advance_segment() -> TurnResult:
	return _record("begin next round", _session.advance_segment())


## Every line the result log holds, oldest first. A copy: the log is this
## scene's transcript and a caller editing it would be editing the HUD.
func log_lines() -> Array[String]:
	return _log.duplicate()


## The second half of a Charge: the first tap names the target, the second
## names the destination and submits.
func _charge_tap(current: GameState, coord: Vector3i) -> TurnResult:
	if _charge_target.is_empty():
		var target := String(current.board.occupant_at(coord))
		if target.is_empty():
			return null
		_charge_target = target
		_render()
		return null

	return _submit(
		_options.charge(current, _selected_fighter, _charge_target, coord),
		"charge %s at %s with %s" % [_charge_target, coord, _selected_fighter]
	)


## Submits `action` on behalf of `HotseatSession.player_to_act()` and records
## what came back.
##
## A `null` action is one `ActionOptions` would not build -- an unknown fighter
## id, or a template that will not resolve -- and there is nothing to submit,
## so it is noted rather than invented.
func _submit(action: TurnAction, label: String) -> TurnResult:
	if action == null:
		_note("%s: no command could be built" % label)
		return null

	var player := _session.player_to_act()
	return _record("%s: %s" % [_named(player), label], _session.submit(action, player))


## Appends `result` to the log under `label`, clears the half-finished command,
## and re-renders from the state the gate now holds.
##
## A failure is recorded by its `TurnResult.reason` verbatim -- not translated,
## not softened, not swallowed -- and the selected fighter survives it, so the
## player can try something else without re-selecting.
func _record(label: String, result: TurnResult) -> TurnResult:
	_log.append("%s -- %s" % [label, "ok" if result.success else String(result.reason)])
	_pending_action = &""
	_charge_target = ""
	_render()
	return result


## Appends a line about the HUD itself -- a missing selection, a tap with
## nothing behind it. Never used for anything a rule said.
func _note(message: String) -> void:
	_log.append("(%s)" % message)
	_render()


## Re-reads the state off the gate and redraws everything from it.
##
## Called after every submission and after every selection change. Nothing here
## is cached between calls: the phase, the players and the affordances are all
## asked for again, so the HUD cannot drift from what the rules say.
func _render() -> void:
	var current := state()
	var phase := _session.phase()
	var to_act := _session.player_to_act()
	var match_over: bool = phase == HotseatSession.Phase.MATCH_COMPLETE

	_board_view.render(current, _templates)
	_board_view.set_highlights(_highlight_coords(current))

	_round_label.text = "Round %d of %d" % [current.round_number, current.rounds_per_match]
	_phase_label.text = "Phase: %s" % PHASE_LABELS.get(phase, "")
	_player_label.text = (
		"Turn: %s    To act: %s" % [_named(_session.active_player_id()), _named(to_act)]
	)
	_selection_label.text = "Selected: %s%s" % [_named(_selected_fighter), _pending_text()]

	for button in [_move_button, _attack_button, _charge_button, _guard_button, _decline_button]:
		button.disabled = match_over

	_pass_button.visible = phase == HotseatSession.Phase.POWER_STEP
	_pass_button.text = "Pass (%s)" % _named(to_act)
	_advance_button.visible = phase == HotseatSession.Phase.SEGMENT_COMPLETE
	_status_label.text = MATCH_OVER_TEXT if match_over else ""
	_log_label.text = "\n".join(_log)


## The hexes to highlight for the pending action, as `ActionOptions` reports
## them -- reachable hexes for a Move, the targets' own hexes for an Attack or
## a Charge's first tap, the legal destinations for its second. Empty when no
## action is pending, since a highlight would then be promising something no
## tap is about to do.
func _highlight_coords(current: GameState) -> Array[Vector3i]:
	if _selected_fighter.is_empty() or _pending_action.is_empty():
		return [] as Array[Vector3i]

	if _pending_action == ACTION_MOVE:
		return _options.move_destinations(current, _selected_fighter)

	if _pending_action == ACTION_ATTACK:
		return _coords_of(current, _options.attack_targets(current, _selected_fighter))

	if _pending_action == ACTION_CHARGE:
		if _charge_target.is_empty():
			return _coords_of(current, _options.charge_targets(current, _selected_fighter))
		return _options.charge_destinations(current, _selected_fighter, _charge_target)

	return [] as Array[Vector3i]


## Where each of `fighter_ids` stands, skipping any whose template will not
## resolve or whose payload will not parse -- the same two guards
## `BoardView._draw_fighter_marker()` applies before drawing one.
func _coords_of(current: GameState, fighter_ids: Array[String]) -> Array[Vector3i]:
	var coords: Array[Vector3i] = []

	for fighter_id in fighter_ids:
		var template := _templates.template_for(current, fighter_id)
		if template == null:
			continue
		var fighter := Fighter.from_dict(current.fighter(fighter_id), template)
		if fighter == null:
			continue
		coords.append(fighter.position())

	return coords


## What the selection line says about a half-finished command.
func _pending_text() -> String:
	if _pending_action.is_empty():
		return ""
	if _pending_action == ACTION_CHARGE and not _charge_target.is_empty():
		return "    charging %s -- pick a destination" % _charge_target
	return "    %s -- pick a hex" % _pending_action


## `id`, or `NOBODY` when the rules named nobody.
func _named(id: String) -> String:
	return NOBODY if id.is_empty() else id

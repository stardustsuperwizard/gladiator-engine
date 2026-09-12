## Draws a `GameState` and reports the hex a player pointed at. Decides
## nothing.
##
## `render()` stores what it needs and calls `queue_redraw()`; `_draw()` paints
## every hex `state.board.coords()` reports plus a marker for every fighter
## that is the board's own occupant of its own recorded position, and
## `_unhandled_input()` turns a pressed pointer position into a cube coordinate
## through `HexLayout.from_pixel()` and emits `hex_selected` -- and only that.
## This class builds no `TurnAction`, submits nothing, calls nothing on
## `Authority`, `ActionRunner`, `RoundDriver` or a session, and mutates no
## `GameState`. What a selected hex *means* is the match scene's question, per
## `docs/godot-implementation-guide.md` §6: the view observes and reports a
## pointer, the authority chokepoint decides.
##
## **`HexLayout` is the only conversion boundary.** No pixel or hex arithmetic
## is inlined here; every coordinate this class touches goes through
## `HexLayout.to_pixel()` or `HexLayout.from_pixel()`.
##
## **The centring offset lives on this node's own `Node2D` transform** --
## position this node in the scene tree or set its `position`/`transform` from
## the caller, rather than folding an offset into `HexLayout`, which knows
## nothing about where a board sits on screen.
##
## **A fighter is drawn only when the board still reports it at its own
## recorded position.** Spec §9's defeated fighter is removed from the board
## but may still be present in `state.fighter_ids()` as a payload; comparing
## `state.board.occupant_at(fighter.position())` against the fighter's own id
## is what tells the two apart, and a defeated fighter is not drawn.
##
## **No animation, no frame loop.** No `_process`, no `_physics_process`, no
## tweens -- a redraw happens because `render()` was called, per this task's
## Architecture Constraints.
class_name BoardView
extends Node2D

## Emitted once per qualifying pointer press, naming the hex pointed at.
## Never emitted for a press outside the board.
signal hex_selected(coord: Vector3i)

## Hex circumradius in pixels, passed to every `HexLayout` call this class
## makes. Not authored or configurable: sizing the board view is out of this
## task's scope, and a fixed constant is the smallest thing that satisfies it.
const HEX_SIZE := 32.0

## Fill colour per `Board.HexType`, keyed by the enum's own int value so a
## `Board.HexType` key looks up directly with no translation table.
const HEX_COLORS := {
	Board.HexType.NORMAL: Color(0.82, 0.82, 0.82),
	Board.HexType.STARTING: Color(0.62, 0.82, 1.0),
	Board.HexType.EDGE: Color(0.72, 0.68, 0.5),
	Board.HexType.BLOCKED: Color(0.28, 0.28, 0.28),
	Board.HexType.HAZARD: Color(0.9, 0.42, 0.32),
}

## Overlaid on a highlighted hex's own terrain fill, semi-transparent so the
## terrain underneath stays visible -- "tints the highlight set differently,"
## not "replaces what the hex is."
const HIGHLIGHT_TINT := Color(1.0, 1.0, 0.2, 0.45)

## Hex outline and marker outline/text colour.
const INK_COLOR := Color(0.1, 0.1, 0.1)

## Fighter marker fill, by the index of the fighter's owner in
## `state.turn_order()`. An owner past the palette's end, or one
## `turn_order()` does not name, falls back to `DEFAULT_OWNER_COLOR`.
const OWNER_COLORS := [
	Color(0.82, 0.18, 0.18),
	Color(0.18, 0.42, 0.82),
	Color(0.2, 0.68, 0.32),
	Color(0.78, 0.6, 0.1),
]

const DEFAULT_OWNER_COLOR := Color(0.6, 0.6, 0.6)

## Fighter marker radius as a fraction of `HEX_SIZE`, small enough to leave
## the hex's own outline visible around it.
const MARKER_RADIUS_RATIO := 0.55

const LABEL_FONT_SIZE := 12

var _state: GameState = null
var _templates: FighterTemplates = null
var _highlights: Array[Vector3i] = []


## Stores `state` and `templates` for the next `_draw()` and requests one.
## Neither is copied -- `state` is read-only from here, exactly as
## `GameState`'s own accessors already hand back copies where mutation would
## matter.
func render(state: GameState, templates: FighterTemplates) -> void:
	_state = state
	_templates = templates
	queue_redraw()


## Replaces the highlighted set and requests a redraw. Does not touch
## `_state`: highlighting is presentation only, per this task's Architecture
## Constraints.
func set_highlights(coords: Array[Vector3i]) -> void:
	_highlights = coords.duplicate()
	queue_redraw()


## Empties the highlighted set and requests a redraw.
func clear_highlights() -> void:
	_highlights.clear()
	queue_redraw()


func _draw() -> void:
	if _state == null:
		return

	var highlighted: Dictionary = {}
	for coord in _highlights:
		highlighted[coord] = true

	for coord in _state.board.coords():
		_draw_hex(coord, highlighted.has(coord))

	for fighter_id in _state.fighter_ids():
		_draw_fighter_marker(fighter_id)


func _draw_hex(coord: Vector3i, is_highlighted: bool) -> void:
	var center := HexLayout.to_pixel(coord, HEX_SIZE)
	var offsets := HexLayout.corners(HEX_SIZE)

	var points := PackedVector2Array()
	for offset in offsets:
		points.append(center + offset)

	var hex_type := _state.board.hex_type(coord)
	var fill_color: Color = HEX_COLORS.get(hex_type, HEX_COLORS[Board.HexType.NORMAL])
	draw_colored_polygon(points, fill_color)

	if is_highlighted:
		draw_colored_polygon(points, HIGHLIGHT_TINT)

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, INK_COLOR, 1.0, true)


## Draws `fighter_id`'s marker, or nothing when its template is unknown, its
## payload fails `Fighter.from_dict()`, or the board no longer reports it at
## its own recorded position -- spec §9's defeated fighter, per the class
## docstring.
func _draw_fighter_marker(fighter_id: String) -> void:
	if _templates == null:
		return

	var template := _templates.template_for(_state, fighter_id)
	if template == null:
		return

	var fighter := Fighter.from_dict(_state.fighter(fighter_id), template)
	if fighter == null:
		return

	var fighter_position := fighter.position()
	if _state.board.occupant_at(fighter_position) != StringName(fighter.id()):
		return

	var center := HexLayout.to_pixel(fighter_position, HEX_SIZE)
	var radius := HEX_SIZE * MARKER_RADIUS_RATIO

	draw_circle(center, radius, _owner_color(fighter.owner_id()))
	draw_arc(center, radius, 0.0, TAU, 32, INK_COLOR, 1.5, true)

	var label := "%s\n%d/%d" % [fighter.id(), fighter.damage_counter(), fighter.health()]
	var flags := fighter.status_flags()
	if not flags.is_empty():
		label += "\n" + ",".join(flags)

	draw_multiline_string(
		ThemeDB.fallback_font,
		center + Vector2(-radius, -radius - LABEL_FONT_SIZE),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0,
		LABEL_FONT_SIZE,
		-1,
		INK_COLOR
	)


func _owner_color(owner_id: String) -> Color:
	var index := _state.turn_order().find(owner_id)
	if index == -1:
		return DEFAULT_OWNER_COLOR
	return OWNER_COLORS[index % OWNER_COLORS.size()]


## Converts a pressed mouse click or touch into a cube coordinate through
## `HexLayout.from_pixel()` and emits `hex_selected` only when
## `state.board.has_hex()` is true for it. Reads the input event's own
## position directly -- no Input Map action, no hover state, no cursor: touch
## has neither.
func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return

	var screen_position: Vector2

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not (mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT):
			return
		if mouse_event.device == InputEvent.DEVICE_ID_EMULATION:
			# Godot's default `emulate_mouse_from_touch` re-delivers every
			# touch as an emulated mouse press; the `InputEventScreenTouch`
			# branch below already handles the real touch, so acting on
			# this one too would emit `hex_selected` twice per tap.
			return
		screen_position = mouse_event.position
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if not touch_event.pressed:
			return
		screen_position = touch_event.position
	else:
		return

	var local_position := to_local(screen_position)
	var coord := HexLayout.from_pixel(local_position, HEX_SIZE)

	if _state.board.has_hex(coord):
		hex_selected.emit(coord)

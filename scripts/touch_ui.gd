extends Control
## On-screen controls for touch devices.
##   Left side, lower part: virtual joystick. It appears where the finger lands.
##   Right side: jump, mine (hold) and place buttons.
##   Anywhere else: drag to look. Dragging from the mine button also looks,
##   so the player can aim while mining.
## Appears on touchscreen devices, or after the first touch event.
## Other scripts read `move`, `jump`, `mine`, `place` and call `take_look()`.

const STICK_RADIUS := 90.0
const KNOB_RADIUS := 38.0
const BUTTON_RADIUS := 54.0

var hotbar: Control
var active := false
var move := Vector2.ZERO
var jump := false
var mine := false
var place := false

var _look := Vector2.ZERO
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _look_id := -1
var _button_ids := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	active = DisplayServer.is_touchscreen_available()
	resized.connect(queue_redraw)


## Look movement in pixels since the last call.
func take_look() -> Vector2:
	var d := _look
	_look = Vector2.ZERO
	return d


func button_pos(button: String) -> Vector2:
	match button:
		"jump":
			return Vector2(size.x - 110.0, size.y - 120.0)
		"mine":
			return Vector2(size.x - 260.0, size.y - 95.0)
		_:
			return Vector2(size.x - 110.0, size.y - 270.0)


func stick_home() -> Vector2:
	return Vector2(150.0, size.y - 150.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		active = true
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			move = ((event.position - _stick_origin) / STICK_RADIUS).limit_length(1.0)
			queue_redraw()
		elif event.index == _look_id or _button_ids.get(event.index, "") == "mine":
			_look += event.relative


func _touch_down(index: int, pos: Vector2) -> void:
	if hotbar != null:
		var slot: int = hotbar.slot_at(pos)
		if slot >= 0:
			hotbar.select(slot)
			return
	for button: String in ["jump", "mine", "place"]:
		if pos.distance_to(button_pos(button)) <= BUTTON_RADIUS * 1.15:
			_button_ids[index] = button
			_set_button(button, true)
			return
	if _stick_id == -1 and pos.x < size.x * 0.4 and pos.y > size.y * 0.35:
		_stick_id = index
		_stick_origin = pos
		move = Vector2.ZERO
	elif _look_id == -1:
		_look_id = index


func _touch_up(index: int) -> void:
	if index == _stick_id:
		_stick_id = -1
		move = Vector2.ZERO
	elif index == _look_id:
		_look_id = -1
	elif _button_ids.has(index):
		_set_button(_button_ids[index], false)
		_button_ids.erase(index)


func _set_button(button: String, down: bool) -> void:
	match button:
		"jump":
			jump = down
		"mine":
			mine = down
		"place":
			place = down


func _draw() -> void:
	if not active:
		return
	var center := _stick_origin if _stick_id != -1 else stick_home()
	draw_circle(center, STICK_RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(center, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
	draw_circle(center + move * STICK_RADIUS, KNOB_RADIUS, Color(1, 1, 1, 0.38))

	_draw_button("jump", jump)
	_draw_button("mine", mine)
	_draw_button("place", place)


func _draw_button(button: String, down: bool) -> void:
	var c := button_pos(button)
	var ink := Color(1, 1, 1, 0.9)
	draw_circle(c, BUTTON_RADIUS, Color(1, 1, 1, 0.42 if down else 0.14))
	draw_arc(c, BUTTON_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0, true)
	match button:
		"jump":
			# Arrow up.
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -24), c + Vector2(22, 4), c + Vector2(-22, 4)]), ink)
			draw_rect(Rect2(c + Vector2(-8, 4), Vector2(16, 20)), ink)
		"mine":
			# Pickaxe: handle and curved head.
			draw_line(c + Vector2(-20, 22), c + Vector2(12, -10), ink, 6.0, true)
			draw_arc(c + Vector2(-6, 8), 30.0, -PI * 0.5 - 0.75, -PI * 0.5 + 1.25 + 0.75, 14, ink, 7.0, true)
		"place":
			# Block with a plus.
			draw_rect(Rect2(c - Vector2(20, 20), Vector2(40, 40)), ink, false, 5.0)
			draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), ink, 5.0)
			draw_line(c + Vector2(0, -10), c + Vector2(0, 10), ink, 5.0)

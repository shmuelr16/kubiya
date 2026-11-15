extends Control
## Inventory, crafting and furnace screen. One screen serves the 2x2 grid (opened
## from anywhere), the 3x3 grid (opened by using a workbench) and the furnace.
##
## Works the same with a mouse and with a finger:
##   Tap a slot with an empty hand: pick up the stack.
##   Tap a slot while holding a stack: put it down, merge, or swap.
##   Tap a crafting cell while holding a stack: put down one item.
##   Right-click: put down one item, or pick up half a stack.
##   Tap the result: craft once, straight into the inventory.
##   Furnace: the top slot takes what to smelt, the bottom slot takes fuel.

const Items := preload("res://scripts/items.gd")
const Crafting := preload("res://scripts/crafting.gd")
const Furnaces := preload("res://scripts/furnaces.gd")

signal closed

enum { HIT_NONE, HIT_INV, HIT_CRAFT, HIT_RESULT, HIT_CLOSE, HIT_F_IN, HIT_F_FUEL, HIT_F_OUT }

const SLOT := 56.0
const STEP := 62.0
const PAD := 22.0
const TITLE := 36.0
const PANEL := Vector2(9 * 62.0 - 6.0 + 2 * 22.0, 22.0 + 36.0 + 186.0 + 20.0 + 186.0 + 14.0 + 56.0 + 22.0)

var inventory: RefCounted
var atlas: Texture2D
var audio: Node
var drops: Node3D
var player: Node3D
var input_enabled := true

## 2 or 3 for a crafting grid, 0 for the furnace screen.
var grid_n := 2
## State of the open furnace (see furnaces.gd).
var furnace := {}
## Crafting cells, 3 per row. Only the first grid_n x grid_n are used.
var g_ids := PackedInt32Array()
var g_counts := PackedInt32Array()
var g_durs := PackedInt32Array()
## Stack held by the pointer.
var held_id := 0
var held_count := 0
var held_dur := 0
## [item id, count] of the current recipe, or [].
var result := []

var _pointer := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	g_ids.resize(9)
	g_counts.resize(9)
	g_durs.resize(9)
	resized.connect(queue_redraw)
	inventory.changed.connect(queue_redraw)


func open(n: int) -> void:
	grid_n = n
	visible = true
	_recalc()


func open_furnace(state: Dictionary) -> void:
	furnace = state
	grid_n = 0
	result = []
	visible = true
	queue_redraw()


func _process(_delta: float) -> void:
	if visible and grid_n == 0:
		queue_redraw()


## Puts everything on the grid and in the hand back into the inventory.
## What does not fit drops at the player's feet.
func close() -> void:
	if not visible:
		return
	for i in 9:
		_give_back(g_ids[i], g_counts[i], g_durs[i])
		g_ids[i] = 0
		g_counts[i] = 0
	_give_back(held_id, held_count, held_dur)
	held_id = 0
	held_count = 0
	result = []
	visible = false
	closed.emit()


func _give_back(id: int, count: int, dur: int) -> void:
	if id == 0 or count <= 0:
		return
	var left: int = inventory.add(id, count, dur)
	if left > 0 and drops != null:
		drops.spawn(player.position + Vector3(0, 1.0, 0), id, left, dur)


# --- Layout ---

func _origin() -> Vector2:
	return ((size - PANEL) * 0.5).floor()


func inv_rect(i: int) -> Rect2:
	var o := _origin()
	var main_y := o.y + PAD + TITLE + 186.0 + 20.0
	if i < 9:
		return Rect2(o.x + PAD + i * STEP, main_y + 186.0 + 14.0, SLOT, SLOT)
	var j := i - 9
	@warning_ignore("integer_division")
	return Rect2(o.x + PAD + (j % 9) * STEP, main_y + (j / 9) * STEP, SLOT, SLOT)


## Rectangle of crafting cell (x, y) of the current grid.
func craft_rect(x: int, y: int) -> Rect2:
	var o := _origin()
	var inset := (3 - grid_n) * STEP * 0.5
	return Rect2(o.x + PAD + STEP * 1.5 + inset + x * STEP, o.y + PAD + TITLE + inset + y * STEP, SLOT, SLOT)


## Furnace slots: "in" above the fire, "fuel" below it, "out" on the right.
func furnace_rect(slot: String) -> Rect2:
	if slot == "out":
		return result_rect()
	var o := _origin()
	var y := o.y + PAD + TITLE + (0.0 if slot == "in" else STEP * 2.0)
	return Rect2(o.x + PAD + STEP * 2.5, y, SLOT, SLOT)


func result_rect() -> Rect2:
	var o := _origin()
	return Rect2(o.x + PAD + STEP * 6.3, o.y + PAD + TITLE + STEP, SLOT, SLOT)


func close_rect() -> Rect2:
	var o := _origin()
	return Rect2(o.x + PANEL.x - 52.0, o.y + 10.0, 42.0, 42.0)


## Returns [kind, index]. For crafting cells the index is y * 3 + x.
func _hit(pos: Vector2) -> Array:
	if close_rect().has_point(pos):
		return [HIT_CLOSE, 0]
	if grid_n == 0:
		if furnace_rect("in").grow(3.0).has_point(pos):
			return [HIT_F_IN, 0]
		if furnace_rect("fuel").grow(3.0).has_point(pos):
			return [HIT_F_FUEL, 0]
		if furnace_rect("out").grow(3.0).has_point(pos):
			return [HIT_F_OUT, 0]
	elif result_rect().grow(3.0).has_point(pos):
		return [HIT_RESULT, 0]
	for y in grid_n:
		for x in grid_n:
			if craft_rect(x, y).grow(3.0).has_point(pos):
				return [HIT_CRAFT, y * 3 + x]
	for i in inventory.SIZE:
		if inv_rect(i).grow(3.0).has_point(pos):
			return [HIT_INV, i]
	return [HIT_NONE, 0]


# --- Input ---

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer = event.position
			_click(event.position, false)
	elif event is InputEventScreenDrag:
		pass
	elif not input_enabled:
		return
	elif event is InputEventMouseMotion:
		_pointer = event.position
		if held_count > 0:
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position, false)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_click(event.position, true)
	elif event is InputEventKey:
		if event.pressed and not event.echo and event.physical_keycode in [KEY_E, KEY_ESCAPE]:
			close()
	get_viewport().set_input_as_handled()


func _click(pos: Vector2, secondary: bool) -> void:
	var hit := _hit(pos)
	match hit[0]:
		HIT_CLOSE:
			close()
			return
		HIT_RESULT:
			_craft()
		HIT_INV:
			var i: int = hit[1]
			var s := _swap_logic(inventory.ids[i], inventory.counts[i], inventory.durs[i], secondary, secondary)
			inventory.set_slot(i, s[0], s[1], s[2])
		HIT_F_IN:
			if held_count == 0 or Items.smelt(held_id) != 0:
				_furnace_slot("in", secondary)
		HIT_F_FUEL:
			if held_count == 0 or Items.fuel_time(held_id) > 0.0:
				_furnace_slot("fuel", secondary)
		HIT_F_OUT:
			if furnace["out_n"] > 0:
				furnace["out_n"] = inventory.add(furnace["out_id"], furnace["out_n"])
				if audio != null:
					audio.play("pop", 0.8, -4.0)
		HIT_CRAFT:
			var i: int = hit[1]
			var s := _swap_logic(g_ids[i], g_counts[i], g_durs[i], true, false)
			g_ids[i] = s[0] if s[1] > 0 else 0
			g_counts[i] = s[1]
			g_durs[i] = s[2]
			_recalc()
	queue_redraw()


func _furnace_slot(slot: String, secondary: bool) -> void:
	var s := _swap_logic(furnace[slot + "_id"], furnace[slot + "_n"], 0, secondary, secondary)
	furnace[slot + "_id"] = s[0] if s[1] > 0 else 0
	furnace[slot + "_n"] = s[1]


## Applies one click to a slot holding (id, count, dur). Changes the held stack
## and returns the new slot content. `one` puts down a single item; `half`
## picks up half a stack instead of all of it.
func _swap_logic(id: int, count: int, dur: int, one: bool, half: bool) -> Array:
	if held_count == 0:
		if count == 0:
			return [0, 0, 0]
		@warning_ignore("integer_division")
		var n := (count + 1) / 2 if half else count
		held_id = id
		held_count = n
		held_dur = dur
		return [id, count - n, dur]
	var cap := Items.max_stack(held_id)
	var n := 1 if one else held_count
	if count == 0:
		var out := [held_id, n, held_dur]
		held_count -= n
		return out
	if id == held_id and cap > 1:
		n = mini(n, cap - count)
		held_count -= n
		return [id, count + n, dur]
	if one:
		return [id, count, dur]
	var out := [held_id, held_count, held_dur]
	held_id = id
	held_count = count
	held_dur = dur
	return out


func _recalc() -> void:
	result = Crafting.find(g_ids, grid_n)
	queue_redraw()


func _craft() -> void:
	if result.is_empty() or not inventory.can_add(result[0]):
		return
	for i in 9:
		if g_counts[i] > 0:
			g_counts[i] -= 1
			if g_counts[i] == 0:
				g_ids[i] = 0
	inventory.add(result[0], result[1])
	if audio != null:
		audio.play("pop", 0.8, -4.0)
	_recalc()


# --- Drawing ---

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var o := _origin()
	draw_rect(Rect2(o, PANEL), Color(0.16, 0.17, 0.21, 0.97))
	draw_rect(Rect2(o, PANEL), Color(1, 1, 1, 0.5), false, 3.0)
	var font := ThemeDB.fallback_font
	var title := "Inventory"
	if grid_n == 3:
		title = "Workbench"
	elif grid_n == 0:
		title = "Furnace"
	draw_string(font, o + Vector2(PAD, PAD + 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color.WHITE)

	if grid_n == 0:
		_draw_furnace()
	for y in grid_n:
		for x in grid_n:
			var i := y * 3 + x
			_draw_slot(craft_rect(x, y), g_ids[i], g_counts[i], g_durs[i])
	var rr := result_rect()
	var arrow := Vector2(o.x + PAD + STEP * 5.0, rr.get_center().y)
	draw_line(arrow, arrow + Vector2(50, 0), Color.WHITE, 5.0)
	draw_colored_polygon(PackedVector2Array([
		arrow + Vector2(50, -12), arrow + Vector2(68, 0), arrow + Vector2(50, 12)]), Color.WHITE)
	if grid_n == 0:
		# The arrow fills up while an item cooks.
		var k: float = clampf(furnace["cook"] / Furnaces.COOK_TIME, 0.0, 1.0)
		if k > 0.0:
			draw_line(arrow, arrow + Vector2(50.0 * k, 0), Color(1.0, 0.62, 0.15), 5.0)
	else:
		_draw_slot(rr, 0, 0, 0)
	if not result.is_empty():
		Items.draw_stack(self, atlas, rr, result[0], result[1], Items.max_durability(result[0]))
		draw_rect(rr.grow(2.0), Color(0.5, 1.0, 0.5), false, 3.0)

	for i in inventory.SIZE:
		_draw_slot(inv_rect(i), inventory.ids[i], inventory.counts[i], inventory.durs[i])

	var cr := close_rect()
	draw_rect(cr, Color(0.75, 0.25, 0.22))
	draw_line(cr.position + Vector2(11, 11), cr.end - Vector2(11, 11), Color.WHITE, 4.0)
	draw_line(cr.position + Vector2(cr.size.x - 11, 11), cr.position + Vector2(11, cr.size.y - 11), Color.WHITE, 4.0)

	if held_count > 0:
		var hr := Rect2(_pointer - Vector2(SLOT, SLOT) * 0.5 + Vector2(14, -14), Vector2(SLOT, SLOT))
		Items.draw_stack(self, atlas, hr, held_id, held_count, held_dur)


func _draw_furnace() -> void:
	_draw_slot(furnace_rect("in"), furnace["in_id"], furnace["in_n"], 0)
	_draw_slot(furnace_rect("fuel"), furnace["fuel_id"], furnace["fuel_n"], 0)
	_draw_slot(furnace_rect("out"), furnace["out_id"], furnace["out_n"], 0)
	# Fire between the two slots: its height shows how much of the fuel is left.
	var c := furnace_rect("in").get_center() + Vector2(0, STEP)
	var left: float = furnace["burn"] / maxf(furnace["burn_total"], 0.001) if furnace["burn"] > 0.0 else 0.0
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-16, 18), c + Vector2(16, 18), c + Vector2(0, -20)]), Color(0, 0, 0, 0.45))
	if left > 0.0:
		var h := 38.0 * left
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-16.0 * left, 18), c + Vector2(16.0 * left, 18), c + Vector2(0, 18.0 - h)]),
			Color(1.0, 0.55, 0.12))


func _draw_slot(r: Rect2, id: int, count: int, dur: int) -> void:
	draw_rect(r, Color(0, 0, 0, 0.4))
	draw_rect(r, Color(1, 1, 1, 0.3), false, 2.0)
	Items.draw_stack(self, atlas, r, id, count, dur)

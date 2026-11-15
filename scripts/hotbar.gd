extends Control
## The first 9 inventory slots, shown at the bottom of the screen.
## Select with keys 1-9, the mouse wheel, or a tap.

const Items := preload("res://scripts/items.gd")

const SLOTS := 9
const SLOT := 52.0
const GAP := 6.0
const MARGIN := 14.0

var atlas: Texture2D
var inventory: RefCounted
var selected := 0
var input_enabled := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	inventory.changed.connect(queue_redraw)


## Item id in the selected slot, or 0 when it is empty.
func selected_id() -> int:
	return inventory.ids[selected] if inventory.counts[selected] > 0 else 0


func select(i: int) -> void:
	selected = posmod(i, SLOTS)
	queue_redraw()


func slot_rect(i: int) -> Rect2:
	var total := SLOTS * SLOT + (SLOTS - 1) * GAP
	var x := (size.x - total) * 0.5 + i * (SLOT + GAP)
	return Rect2(x, size.y - SLOT - MARGIN, SLOT, SLOT)


## Slot under a screen position, or -1.
func slot_at(pos: Vector2) -> int:
	for i in SLOTS:
		if slot_rect(i).grow(GAP * 0.5).has_point(pos):
			return i
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < SLOTS:
			select(n)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(selected + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(selected - 1)


func _draw() -> void:
	for i in SLOTS:
		var r := slot_rect(i)
		draw_rect(r, Color(0, 0, 0, 0.45))
		Items.draw_stack(self, atlas, r, inventory.ids[i], inventory.counts[i], inventory.durs[i])
		if i == selected:
			draw_rect(r.grow(2.0), Color.WHITE, false, 4.0)
		else:
			draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)

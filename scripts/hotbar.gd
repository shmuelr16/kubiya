extends Control
## Row of block slots at the bottom of the screen.
## Select with keys 1-9, the mouse wheel, or a tap.

const Blocks := preload("res://scripts/blocks.gd")

const SLOT := 52.0
const GAP := 6.0
const MARGIN := 14.0
const ITEMS: PackedInt32Array = [
	Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND, Blocks.WOOD,
	Blocks.LEAVES, Blocks.PLANKS, Blocks.BRICKS, Blocks.GOLD,
]

var atlas: Texture2D
var selected := 0
var input_enabled := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func selected_id() -> int:
	return ITEMS[selected]


func select(i: int) -> void:
	selected = posmod(i, ITEMS.size())
	queue_redraw()


func slot_rect(i: int) -> Rect2:
	var total := ITEMS.size() * SLOT + (ITEMS.size() - 1) * GAP
	var x := (size.x - total) * 0.5 + i * (SLOT + GAP)
	return Rect2(x, size.y - SLOT - MARGIN, SLOT, SLOT)


## Slot under a screen position, or -1.
func slot_at(pos: Vector2) -> int:
	for i in ITEMS.size():
		if slot_rect(i).grow(GAP * 0.5).has_point(pos):
			return i
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < ITEMS.size():
			select(n)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(selected + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(selected - 1)


func _draw() -> void:
	var inv := 1.0 / Blocks.ATLAS_TILES
	for i in ITEMS.size():
		var r := slot_rect(i)
		draw_rect(r, Color(0, 0, 0, 0.45))
		if atlas != null:
			var tile := Blocks.TILE_OF[ITEMS[i] * 3 + 1]
			var src := Rect2((tile & 3) * inv, (tile >> 2) * inv, inv, inv)
			var px := Vector2(atlas.get_size())
			draw_texture_rect_region(atlas, r.grow(-7.0), Rect2(src.position * px, src.size * px))
		if i == selected:
			draw_rect(r.grow(2.0), Color.WHITE, false, 4.0)
		else:
			draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)

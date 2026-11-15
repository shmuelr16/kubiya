extends Control
## Health and hunger rows above the hotbar, a red flash on damage, and the
## message shown after dying.

const Items := preload("res://scripts/items.gd")

const ICON := 20.0
const STEP := 22.0

var player: Node3D
var hotbar: Control
var atlas: Texture2D

var _flash := 0.0
var _message := 0.0
var _last_health := -1.0
var _last_hunger := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.hurt_taken.connect(func() -> void: _flash = 0.45)
	player.died.connect(func() -> void: _message = 3.0)


func _process(delta: float) -> void:
	var dirty := _flash > 0.0 or _message > 0.0
	_flash = maxf(_flash - delta, 0.0)
	_message = maxf(_message - delta, 0.0)
	if player.health != _last_health or player.hunger != _last_hunger:
		_last_health = player.health
		_last_hunger = player.hunger
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.05, 0.05, _flash * 0.7))
	var left: Vector2 = hotbar.slot_rect(0).position
	var right: float = hotbar.slot_rect(8).end.x
	var y := left.y - ICON - 8.0
	var hp := ceili(player.health)
	var food := ceili(player.hunger)
	for i in 10:
		_heart(Vector2(left.x + i * STEP + ICON * 0.5, y + ICON * 0.5), clampi(hp - i * 2, 0, 2))
		_food(Rect2(right - (i + 1) * STEP, y, ICON, ICON), clampi(food - i * 2, 0, 2))
	if _message > 0.0:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, size.y * 0.4), "You were defeated. Back at the start.",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(1, 1, 1, minf(_message, 1.0)))


## level: 0 empty, 1 half, 2 full.
func _heart(c: Vector2, level: int) -> void:
	_heart_shape(c, 1.0, Color(0, 0, 0, 0.55))
	if level == 2:
		_heart_shape(c, 0.78, Color(0.92, 0.16, 0.20))
	elif level == 1:
		_heart_shape(c, 0.5, Color(0.92, 0.16, 0.20))


func _heart_shape(c: Vector2, k: float, color: Color) -> void:
	var r := ICON * 0.27 * k
	draw_circle(c + Vector2(-r * 0.95, -r * 0.5), r, color)
	draw_circle(c + Vector2(r * 0.95, -r * 0.5), r, color)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 1.9, -r * 0.2), c + Vector2(r * 1.9, -r * 0.2), c + Vector2(0, r * 2.1)]), color)


func _food(r: Rect2, level: int) -> void:
	if atlas == null:
		return
	var region := Items.icon_region(Items.MEAT)
	draw_texture_rect_region(atlas, r, region, Color(0, 0, 0, 0.5))
	if level == 2:
		draw_texture_rect_region(atlas, r, region)
	elif level == 1:
		draw_texture_rect_region(atlas, r.grow(-3.5), region)

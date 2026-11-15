extends Node3D
## Block targeting, mining and placing.
## Casts a ray from the camera through the block grid, outlines the block it
## hits, breaks it after a long press with a growing crack, and places the
## selected hotbar block against the face that was hit.

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")

## The player used the place action on a workbench.
signal workbench_used

const REACH := 5.0
const CRACK_STAGES := 8
const DIG_TICK := 0.22
const PLACE_REPEAT := 0.28
const CAPTURE_GRACE := 0.25

const CRACK_SHADER := "
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform sampler2D cracks : filter_nearest, repeat_disable;
uniform float stage = 0.0;
uniform float stages = 8.0;
varying vec3 lp;
varying vec3 ln;
void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}
void fragment() {
	vec2 uv = abs(ln.x) > 0.5 ? lp.zy : (abs(ln.y) > 0.5 ? lp.xz : lp.xy);
	uv = clamp(uv / 1.006 + 0.5, 0.0, 0.999);
	vec4 c = texture(cracks, vec2((uv.x + stage) / stages, uv.y));
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"

var world: Node3D
var player: Node3D
var hotbar: Control
var touch: Control
var audio: Node
var inventory: RefCounted
var drops: Node3D

var has_target := false
var target := Vector3i.ZERO
## Empty cell in front of the targeted face: where a new block goes.
var place_cell := Vector3i.ZERO
## Current crack stage, 0 to CRACK_STAGES - 1, or -1 when not mining.
var crack_stage := -1

var _progress := 0.0
var _mining_cell := Vector3i.ZERO
var _tick := 0.0
var _place_timer := 0.0
var _grace := CAPTURE_GRACE
var _highlight: Node3D
var _crack: MeshInstance3D
var _crack_mat: ShaderMaterial


func _ready() -> void:
	_build_highlight()
	_build_crack()


func _process(delta: float) -> void:
	var cam: Camera3D = player.cam
	_raycast(cam.global_position, -cam.global_basis.z)
	_highlight.visible = has_target
	if has_target:
		_highlight.position = Vector3(target) + Vector3(0.5, 0.5, 0.5)

	# The click that captures the mouse must not also mine or place.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_grace = maxf(_grace - delta, 0.0) if captured else CAPTURE_GRACE
	var mouse_ok: bool = captured and _grace <= 0.0 and player.input_enabled
	var mine := mouse_ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var place := mouse_ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if touch != null and touch.active:
		mine = mine or touch.mine
		place = place or touch.place
	if player.frozen or player.ui_open:
		mine = false
		place = false
	_update_mining(delta, mine)
	_update_placing(delta, place)


func _update_mining(delta: float, held: bool) -> void:
	if not held or not has_target:
		_stop_mining()
		return
	if target != _mining_cell or crack_stage < 0:
		_mining_cell = target
		_progress = 0.0
		_tick = 0.0
	var id: int = world.get_block(target.x, target.y, target.z)
	var tool_id: int = hotbar.selected_id()
	var time := Items.mine_time(id, tool_id)
	if time < 0.0:
		_stop_mining()
		return
	_progress += delta / maxf(time, 0.05)
	_tick -= delta
	if _tick <= 0.0:
		_tick = DIG_TICK
		audio.play("dig", Blocks.PITCH[id] * randf_range(0.95, 1.05), -7.0)
	if _progress >= 1.0:
		_break_block(target, id, tool_id)
		_stop_mining()
		return
	crack_stage = mini(int(_progress * CRACK_STAGES), CRACK_STAGES - 1)
	_crack.position = Vector3(target) + Vector3(0.5, 0.5, 0.5)
	_crack_mat.set_shader_parameter("stage", float(crack_stage))
	_crack.visible = true


## Removes the block, drops its item, and wears the held tool.
func _break_block(cell: Vector3i, id: int, held: int) -> void:
	world.set_block(cell.x, cell.y, cell.z, Blocks.AIR)
	audio.play("break", Blocks.PITCH[id], -2.0)
	var centre := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var drop := Items.drop_for(id, held)
	if not drop.is_empty():
		drops.spawn(centre, drop[0], drop[1])
	# A torch cannot stand on nothing.
	if world.get_block(cell.x, cell.y + 1, cell.z) == Blocks.TORCH:
		world.set_block(cell.x, cell.y + 1, cell.z, Blocks.AIR)
		drops.spawn(centre + Vector3(0, 1, 0), Blocks.TORCH, 1)
	if Items.is_tool_item(held) and inventory.damage(hotbar.selected):
		audio.play("break", 1.8, -4.0)


func _stop_mining() -> void:
	_progress = 0.0
	crack_stage = -1
	_crack.visible = false


func _update_placing(delta: float, held: bool) -> void:
	if not held:
		_place_timer = 0.0
		return
	_place_timer -= delta
	if _place_timer > 0.0:
		return
	_place_timer = PLACE_REPEAT
	if not has_target:
		return
	if world.get_block(target.x, target.y, target.z) == Blocks.WORKBENCH:
		_place_timer = 0.6
		workbench_used.emit()
		return
	var id: int = hotbar.selected_id()
	if not Items.is_block(id):
		return
	var c := place_cell
	var current: int = world.get_block(c.x, c.y, c.z)
	if current != Blocks.AIR and current != Blocks.WATER:
		return
	if player.intersects_cell(c):
		return
	if world.set_block(c.x, c.y, c.z, id):
		inventory.take(hotbar.selected, 1)
		audio.play("place", Blocks.PITCH[id], -3.0)


## Walks the block grid along the ray (Amanatides-Woo). Water is passed through.
func _raycast(origin: Vector3, dir: Vector3) -> void:
	has_target = false
	var p := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z))))
	var t_delta := Vector3(INF, INF, INF)
	var t_max := Vector3(INF, INF, INF)
	for a in 3:
		if dir[a] != 0.0:
			t_delta[a] = absf(1.0 / dir[a])
			var edge := p[a] + (1.0 if step[a] > 0 else 0.0)
			t_max[a] = (edge - origin[a]) / dir[a]
	var prev := p
	var t := 0.0
	while t <= REACH:
		var id: int = world.get_block(p.x, p.y, p.z)
		if id > 0 and id != Blocks.WATER:
			has_target = true
			target = p
			place_cell = prev
			return
		prev = p
		var a := 0
		if t_max.y < t_max.x and t_max.y <= t_max.z:
			a = 1
		elif t_max.z < t_max.x and t_max.z < t_max.y:
			a = 2
		t = t_max[a]
		p[a] += step[a]
		t_max[a] += t_delta[a]


func _build_highlight() -> void:
	_highlight = Node3D.new()
	_highlight.visible = false
	add_child(_highlight)

	var h := 0.503
	var corners := [
		Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(-h, -h, h),
		Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h),
	]
	var edges := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	var verts := PackedVector3Array()
	for e: int in edges:
		verts.append(corners[e])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var lines := ArrayMesh.new()
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.05, 0.05, 0.05)
	lines.surface_set_material(0, line_mat)
	var outline := MeshInstance3D.new()
	outline.mesh = lines
	_highlight.add_child(outline)

	# A faint white wash keeps the target visible on small screens.
	var box := BoxMesh.new()
	box.size = Vector3(1.004, 1.004, 1.004)
	var wash_mat := StandardMaterial3D.new()
	wash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wash_mat.albedo_color = Color(1, 1, 1, 0.13)
	box.material = wash_mat
	var wash := MeshInstance3D.new()
	wash.mesh = box
	_highlight.add_child(wash)


func _build_crack() -> void:
	var shader := Shader.new()
	shader.code = CRACK_SHADER
	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = shader
	_crack_mat.set_shader_parameter("cracks", _make_crack_texture())
	_crack_mat.set_shader_parameter("stages", float(CRACK_STAGES))
	var box := BoxMesh.new()
	box.size = Vector3(1.006, 1.006, 1.006)
	box.material = _crack_mat
	_crack = MeshInstance3D.new()
	_crack.mesh = box
	_crack.visible = false
	add_child(_crack)


## One row of CRACK_STAGES tiles. Each stage shows a longer part of the same
## random-walk cracks, so the damage grows instead of jumping around.
func _make_crack_texture() -> ImageTexture:
	var tile := Blocks.TILE
	var img := Image.create_empty(tile * CRACK_STAGES, tile, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pixels: Array[Vector2i] = []
	var branches := 7
	var length := 11
	var heads: Array[Vector2] = []
	var dirs: Array[Vector2] = []
	for b in branches:
		heads.append(Vector2(7.5, 7.5))
		dirs.append(Vector2.RIGHT.rotated(TAU * b / branches + rng.randf_range(-0.3, 0.3)))
	for i in length:
		for b in branches:
			dirs[b] = dirs[b].rotated(rng.randf_range(-0.6, 0.6))
			heads[b] += dirs[b]
			var px := Vector2i(clampi(int(heads[b].x), 0, tile - 1), clampi(int(heads[b].y), 0, tile - 1))
			pixels.append(px)
	for s in CRACK_STAGES:
		@warning_ignore("integer_division")
		var count := pixels.size() * (s + 1) / CRACK_STAGES
		for i in count:
			img.set_pixel(s * tile + pixels[i].x, pixels[i].y, Color(0.03, 0.03, 0.03, 0.82))
	return ImageTexture.create_from_image(img)

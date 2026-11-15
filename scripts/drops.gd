extends Node3D
## Items lying in the world. A mined block spawns one; it falls, spins, flies to
## the player when close, and goes into the inventory.

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")
const Mesher := preload("res://scripts/mesher.gd")

const MAX_DROPS := 200
const LIFETIME := 300.0
const PICKUP_DELAY := 0.5
const MAGNET_RANGE := 2.4
const PICKUP_RANGE := 1.0
const REST := 0.16

const SHADER := "
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
global uniform float daylight;
void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb * COLOR.rgb * clamp(daylight, 0.25, 1.0);
}
"


class Drop:
	var node: MeshInstance3D
	var id := 0
	var count := 0
	var dur := 0
	var vel := Vector3.ZERO
	var age := 0.0


var world: Node3D
var player: Node3D
var inventory: RefCounted
var audio: Node
var atlas: Texture2D
var list: Array[Drop] = []

var _material: ShaderMaterial
var _meshes := {}


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("atlas", atlas)


func spawn(pos: Vector3, id: int, count: int, dur := -1) -> void:
	if id == 0 or count <= 0:
		return
	if list.size() >= MAX_DROPS:
		_remove(0)
	var d := Drop.new()
	d.id = id
	d.count = count
	d.dur = Items.max_durability(id) if dur < 0 else dur
	d.vel = Vector3(randf_range(-1.0, 1.0), 3.0, randf_range(-1.0, 1.0))
	d.node = MeshInstance3D.new()
	d.node.mesh = _mesh_for(id)
	d.node.position = pos
	add_child(d.node)
	list.append(d)


func _physics_process(delta: float) -> void:
	if player == null or list.is_empty():
		return
	delta = minf(delta, 0.05)
	var chest := player.position + Vector3(0, 0.9, 0)
	for i in range(list.size() - 1, -1, -1):
		var d := list[i]
		d.age += delta
		if d.age > LIFETIME:
			_remove(i)
			continue
		var p := d.node.position
		var to := chest - p
		var dist := to.length()
		if d.age > PICKUP_DELAY and dist < MAGNET_RANGE and not player.frozen and inventory.can_add(d.id):
			if dist < PICKUP_RANGE:
				var left: int = inventory.add(d.id, d.count, d.dur)
				if left < d.count and audio != null:
					audio.play("pop", randf_range(0.95, 1.2), -6.0)
				if left == 0:
					_remove(i)
					continue
				d.count = left
			else:
				p += to / dist * 7.0 * delta
		else:
			d.vel.y = maxf(d.vel.y - 20.0 * delta, -30.0)
			d.vel.x *= 0.92
			d.vel.z *= 0.92
			var np := p + d.vel * delta
			if world.is_solid(floori(np.x), floori(p.y), floori(np.z)):
				np.x = p.x
				np.z = p.z
			var below := floori(np.y - REST)
			if d.vel.y <= 0.0 and world.is_solid(floori(np.x), below, floori(np.z)):
				np.y = below + 1.0 + REST
				d.vel = Vector3.ZERO
			p = np
		d.node.position = p
		d.node.rotate_y(delta * 2.0)


func _remove(i: int) -> void:
	list[i].node.queue_free()
	list.remove_at(i)


## Blocks are small cubes; other items are flat double-sided icons.
func _mesh_for(id: int) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var inv := 1.0 / Blocks.ATLAS_TILES
	if Items.is_block(id) and id != Blocks.TORCH:
		var m := Mesher.new()
		for f in 6:
			var t := Blocks.TILE_OF[id * 3 + Mesher.SLOT[f]]
			var tb := Vector2(t % Blocks.ATLAS_TILES, floori(t * inv)) * inv
			var n := verts.size()
			for c in 4:
				verts.append((m.cv[f * 4 + c] - Vector3(0.5, 0.5, 0.5)) * 0.3)
				uvs.append(tb + m.cuv[f * 4 + c])
				colors.append(m.shade[f])
			indices.append_array([n, n + 1, n + 2, n, n + 2, n + 3])
	else:
		var t := Items.icon_tile(id)
		var tb := Vector2(t % Blocks.ATLAS_TILES, floori(t * inv)) * inv
		var h := 0.22
		var corners := [Vector3(-h, h, 0), Vector3(h, h, 0), Vector3(h, -h, 0), Vector3(-h, -h, 0)]
		var st := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for c in 4:
			verts.append(corners[c])
			uvs.append(tb + (st[c] as Vector2).clamp(Vector2(0.002, 0.002), Vector2(0.998, 0.998)) * inv)
			colors.append(Color.WHITE)
		indices.append_array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	_meshes[id] = mesh
	return mesh

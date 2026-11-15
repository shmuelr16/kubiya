extends StaticBody3D
## Fixed-size block world, meshed per 16x16 column chunk.

const Blocks := preload("res://scripts/blocks.gd")

const CHUNK := 16
const CHUNKS := 4
const SX := CHUNK * CHUNKS
const SZ := CHUNK * CHUNKS
const SY := 48
const UV_PAD := 0.002

## normal, origin, u, v (u x v = normal), which axis is Y (0 none, 1 u, 2 v),
## tile slot (0 top, 1 side, 2 bottom), shade.
const FACE_DEFS := [
	[Vector3i(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), 1, 1, 0.80],
	[Vector3i(-1, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 2, 1, 0.80],
	[Vector3i(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), 0, 0, 1.00],
	[Vector3i(0, -1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), 0, 2, 0.50],
	[Vector3i(0, 0, 1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), 2, 1, 0.66],
	[Vector3i(0, 0, -1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0), 1, 1, 0.66],
]
## Quad corners as (u, v) multipliers; clockwise seen from outside.
const CORNERS := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]

var data := PackedByteArray()
var material: StandardMaterial3D
var world_seed := 1337


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.albedo_texture = Blocks.make_atlas()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	generate()
	for cz in CHUNKS:
		for cx in CHUNKS:
			_build_chunk(cx, cz)


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.STONE
	if x < 0 or z < 0 or x >= SX or z >= SZ or y >= SY:
		return Blocks.AIR
	return data[x + SX * (z + SZ * y)]


func set_block(x: int, y: int, z: int, id: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= SX or y >= SY or z >= SZ:
		return
	data[x + SX * (z + SZ * y)] = id


func surface_y(x: int, z: int) -> int:
	for y in range(SY - 1, -1, -1):
		if get_block(x, y, z) != Blocks.AIR:
			return y
	return 0


func generate() -> void:
	data.resize(SX * SY * SZ)
	data.fill(Blocks.AIR)
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3

	for z in SZ:
		for x in SX:
			var h := clampi(int(16.0 + noise.get_noise_2d(x, z) * 10.0), 2, SY - 12)
			var top := Blocks.SAND if h <= 12 else Blocks.GRASS
			for y in h + 1:
				var id := Blocks.STONE
				if y == h:
					id = top
				elif y >= h - 3:
					id = Blocks.SAND if top == Blocks.SAND else Blocks.DIRT
				set_block(x, y, z, id)

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for i in 22:
		var tx := rng.randi_range(3, SX - 4)
		var tz := rng.randi_range(3, SZ - 4)
		var ty := surface_y(tx, tz)
		if get_block(tx, ty, tz) == Blocks.GRASS:
			_plant_tree(tx, ty + 1, tz, rng.randi_range(4, 6))


func _plant_tree(x: int, y: int, z: int, height: int) -> void:
	for dy in range(height - 2, height + 2):
		var r := 2 if dy < height else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and r == 2:
					continue
				if get_block(x + dx, y + dy, z + dz) == Blocks.AIR:
					set_block(x + dx, y + dy, z + dz, Blocks.LEAVES)
	for dy in height:
		set_block(x, y + dy, z, Blocks.WOOD)


func _build_chunk(cx: int, cz: int) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var inv := 1.0 / Blocks.ATLAS_TILES

	for y in SY:
		for z in range(cz * CHUNK, (cz + 1) * CHUNK):
			for x in range(cx * CHUNK, (cx + 1) * CHUNK):
				var id := get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var tiles: Array = Blocks.FACES[id]
				var base := Vector3(x, y, z)
				for f: Array in FACE_DEFS:
					var n: Vector3i = f[0]
					if get_block(x + n.x, y + n.y, z + n.z) != Blocks.AIR:
						continue
					var origin: Vector3 = f[1]
					var u: Vector3 = f[2]
					var v: Vector3 = f[3]
					var y_axis: int = f[4]
					var tile: int = tiles[f[5]]
					var shade: float = f[6]
					var tile_uv := Vector2(tile % Blocks.ATLAS_TILES, floori(tile * inv))
					var start := verts.size()
					for c: Vector2 in CORNERS:
						verts.append(base + origin + u * c.x + v * c.y)
						normals.append(Vector3(n))
						colors.append(Color(shade, shade, shade))
						var st := c
						if y_axis == 1:
							st = Vector2(c.y, 1.0 - c.x)
						elif y_axis == 2:
							st = Vector2(c.x, 1.0 - c.y)
						st = st.clamp(Vector2(UV_PAD, UV_PAD), Vector2(1.0 - UV_PAD, 1.0 - UV_PAD))
						uvs.append((tile_uv + st) * inv)
					indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [cx, cz]
	mi.mesh = mesh
	add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	add_child(col)

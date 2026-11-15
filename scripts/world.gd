extends Node3D
## Chunk manager. Streams 16x16x128 chunks around a focus point: generates and
## meshes them on worker threads, uploads meshes on the main thread within a
## time budget, and frees chunks that fall out of range.
##
## Uses its own threads, not WorkerThreadPool: the engine shares that pool, and
## long jobs in it stall the main thread for hundreds of milliseconds.

const Blocks := preload("res://scripts/blocks.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Mesher := preload("res://scripts/mesher.gd")

const CS := 16
const SY := 128
const UPLOAD_BUDGET_USEC := 3000
## How far from a chunk border a sky-light change still re-meshes the neighbour.
const LIGHT_REACH := 4
## Same, for an edit near torches. Less than the torch range, to limit re-meshing.
const TORCH_EDIT_REACH := 6

enum { S_GENERATING, S_DATA, S_MESHING, S_READY }

const SOLID_SHADER := "
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
global uniform float daylight;
void fragment() {
	// COLOR: r = face shade, g = sky light, b = block light.
	float light = max(max(COLOR.g * daylight, COLOR.b), 0.07);
	ALBEDO = texture(atlas, UV).rgb * COLOR.r * light;
}
"

const WATER_SHADER := "
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec3 tint : source_color = vec3(0.16, 0.42, 0.78);
global uniform float daylight;
void fragment() {
	ALBEDO = tint * max(max(COLOR.g * daylight, COLOR.b), 0.07);
	ALPHA = 0.68;
}
"


class Chunk:
	var data: PackedByteArray
	var max_y := 0
	var state := S_GENERATING
	var node: MeshInstance3D
	var quads := 0
	## An edit arrived after the last mesh job started.
	var dirty := false
	## A re-mesh job is running for an already visible chunk.
	var meshing := false


var world_seed := 1337
var view_dist := 8
var focus := Vector3.ZERO
var terrain: Terrain
var chunks := {}
var total_quads := 0
var atlas: ImageTexture
var use_threads := true
var max_tasks := 2

var _mat_solid: ShaderMaterial
var _mat_water: ShaderMaterial
var _offsets: Array[Vector2i] = []
var _center := Vector2i(1 << 30, 1 << 30)
var _pending := true
var _active := 0
var _threads: Array[Thread] = []
var _jobs: Array[Callable] = []
var _sem := Semaphore.new()
var _quit := false
var _results := []
var _uploads := []
var _dirty: Array[Vector2i] = []
## Edited chunks, kept after unload: Vector2i -> [data, max_y].
var _modified := {}
## Torch cells per chunk, as chunk-layout indices: Vector2i -> PackedInt32Array.
var _torches := {}
var _mutex := Mutex.new()


func _ready() -> void:
	terrain = Terrain.new(world_seed)
	use_threads = OS.has_feature("threads") and OS.get_processor_count() > 1
	max_tasks = clampi(OS.get_processor_count() - 2, 1, 4) if use_threads else 1
	if use_threads:
		for i in max_tasks:
			var t := Thread.new()
			t.start(_worker)
			_threads.append(t)

	var solid := Shader.new()
	solid.code = SOLID_SHADER
	_mat_solid = ShaderMaterial.new()
	_mat_solid.shader = solid
	atlas = Blocks.make_atlas()
	_mat_solid.set_shader_parameter("atlas", atlas)
	var water := Shader.new()
	water.code = WATER_SHADER
	_mat_water = ShaderMaterial.new()
	_mat_water.shader = water

	set_view_distance(view_dist)


func set_view_distance(d: int) -> void:
	view_dist = d
	_offsets.clear()
	var r := d + 1
	for z in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + z * z <= r * r:
				_offsets.append(Vector2i(x, z))
	_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared())
	_pending = true


func _exit_tree() -> void:
	_mutex.lock()
	_quit = true
	_jobs.clear()
	_mutex.unlock()
	for t in _threads:
		_sem.post()
	for t in _threads:
		t.wait_to_finish()
	_threads.clear()


func _process(_delta: float) -> void:
	_drain()
	_upload()
	var pc := Vector2i(floori(focus.x) >> 4, floori(focus.z) >> 4)
	if pc != _center:
		_center = pc
		_unload_far()
		_pending = true
	if not _dirty.is_empty():
		_remesh()
	if _pending:
		_schedule()


func is_idle() -> bool:
	return not _pending and _active == 0 and _uploads.is_empty() and _dirty.is_empty()


## Changes one block and re-meshes the chunks that show it.
## Returns false when the position is outside the loaded world.
func set_block(x: int, y: int, z: int, id: int) -> bool:
	if y < 0 or y >= SY:
		return false
	var pos := Vector2i(x >> 4, z >> 4)
	var c: Chunk = chunks.get(pos)
	if c == null or c.state == S_GENERATING:
		return false
	var lx := x & 15
	var lz := z & 15
	# Copy on edit: a worker thread may still be reading the old array.
	var d := c.data.duplicate()
	var index := ((lx + lz * CS) << 7) + y
	var old := d[index]
	d[index] = id
	c.data = d
	c.max_y = maxi(c.max_y, y)
	_modified[pos] = [d, c.max_y]

	var torch_changed := id == Blocks.TORCH or old == Blocks.TORCH
	if torch_changed:
		var list: PackedInt32Array = _torches.get(pos, PackedInt32Array())
		var at := list.find(index)
		if id == Blocks.TORCH and at == -1:
			list.append(index)
		elif id != Blocks.TORCH and at != -1:
			list.remove_at(at)
		_torches[pos] = list

	# Re-mesh every chunk the change can reach: geometry reaches 1 block,
	# sky light a few blocks, torch light its full range.
	var reach := 1
	if torch_changed:
		reach = Mesher.TORCH_LIGHT
	elif _torch_near(pos):
		reach = TORCH_EDIT_REACH
	elif Blocks.SEE_THROUGH[id] != Blocks.SEE_THROUGH[old]:
		reach = LIGHT_REACH
	var x0 := -1 if lx < reach else 0
	var x1 := 1 if lx > 15 - reach else 0
	var z0 := -1 if lz < reach else 0
	var z1 := 1 if lz > 15 - reach else 0
	for dz in range(z0, z1 + 1):
		for dx in range(x0, x1 + 1):
			_mark_dirty(pos + Vector2i(dx, dz))
	return true


func _torch_near(pos: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var list: PackedInt32Array = _torches.get(pos + Vector2i(dx, dz), PackedInt32Array())
			if not list.is_empty():
				return true
	return false


## Torches of a chunk and its 8 neighbours, as x, y, z triples local to the chunk.
func _torches_for(pos: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _torches.is_empty():
		return out
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var list: PackedInt32Array = _torches.get(pos + Vector2i(dx, dz), PackedInt32Array())
			for index in list:
				out.append(((index >> 7) & 15) + dx * CS)
				out.append(index & 127)
				out.append((index >> 11) + dz * CS)
	return out


func _mark_dirty(pos: Vector2i) -> void:
	var c: Chunk = chunks.get(pos)
	if c == null or c.state == S_GENERATING or c.state == S_DATA:
		return
	c.dirty = true
	if not _dirty.has(pos):
		_dirty.append(pos)


## Starts priority mesh jobs for edited chunks. The old mesh stays until the new one is ready.
func _remesh() -> void:
	for pos: Vector2i in _dirty.duplicate():
		var c: Chunk = chunks.get(pos)
		if c == null or not c.dirty:
			_dirty.erase(pos)
			continue
		if c.meshing or c.state != S_READY:
			continue
		var nx: Chunk = chunks.get(pos + Vector2i(-1, 0))
		var px: Chunk = chunks.get(pos + Vector2i(1, 0))
		var nz: Chunk = chunks.get(pos + Vector2i(0, -1))
		var pz: Chunk = chunks.get(pos + Vector2i(0, 1))
		if nx == null or px == null or nz == null or pz == null:
			continue
		if nx.state == S_GENERATING or px.state == S_GENERATING \
				or nz.state == S_GENERATING or pz.state == S_GENERATING:
			continue
		c.dirty = false
		c.meshing = true
		_dirty.erase(pos)
		_start(_job_mesh.bind(pos, c.data, nx.data, px.data, nz.data, pz.data, c.max_y, _torches_for(pos)), true)


## Block id at a world position, or -1 when the chunk is not loaded yet.
func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= SY:
		return Blocks.AIR
	var c: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if c == null or c.state == S_GENERATING:
		return -1
	return c.data[(((x & 15) + (z & 15) * CS) << 7) + y]


## Unloaded chunks count as solid, so nothing falls through missing terrain.
func is_solid(x: int, y: int, z: int) -> bool:
	var id := get_block(x, y, z)
	return id < 0 or Blocks.SOLID[id] == 1


func _schedule() -> void:
	var all_done := true
	var r2 := view_dist * view_dist
	for off in _offsets:
		var pos := _center + off
		var c: Chunk = chunks.get(pos)
		if c == null:
			all_done = false
			if _active >= max_tasks:
				break
			c = Chunk.new()
			chunks[pos] = c
			if _modified.has(pos):
				c.data = _modified[pos][0]
				c.max_y = _modified[pos][1]
				c.state = S_DATA
				continue
			_start(_job_gen.bind(pos))
		elif c.state == S_DATA:
			if off.length_squared() > r2:
				continue
			all_done = false
			var nx: Chunk = chunks.get(pos + Vector2i(-1, 0))
			var px: Chunk = chunks.get(pos + Vector2i(1, 0))
			var nz: Chunk = chunks.get(pos + Vector2i(0, -1))
			var pz: Chunk = chunks.get(pos + Vector2i(0, 1))
			if nx == null or px == null or nz == null or pz == null:
				continue
			if nx.state == S_GENERATING or px.state == S_GENERATING \
					or nz.state == S_GENERATING or pz.state == S_GENERATING:
				continue
			if _active >= max_tasks:
				break
			c.state = S_MESHING
			_start(_job_mesh.bind(pos, c.data, nx.data, px.data, nz.data, pz.data, c.max_y, _torches_for(pos)))
		elif c.state != S_READY:
			all_done = false
	_pending = not all_done


func _start(job: Callable, urgent := false) -> void:
	_active += 1
	if use_threads and not _threads.is_empty():
		_mutex.lock()
		if urgent:
			_jobs.push_front(job)
		else:
			_jobs.append(job)
		_mutex.unlock()
		_sem.post()
	else:
		job.call()


func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _quit:
			_mutex.unlock()
			return
		var job: Callable = _jobs.pop_front()
		_mutex.unlock()
		job.call()


func _job_gen(pos: Vector2i) -> void:
	var r := terrain.generate(pos.x, pos.y)
	_mutex.lock()
	_results.append([0, pos, r])
	_mutex.unlock()


func _job_mesh(pos: Vector2i, d: PackedByteArray, nx: PackedByteArray,
		px: PackedByteArray, nz: PackedByteArray, pz: PackedByteArray, max_y: int,
		torches: PackedInt32Array) -> void:
	var r := Mesher.new().build(d, nx, px, nz, pz, max_y, torches)
	_mutex.lock()
	_results.append([1, pos, r])
	_mutex.unlock()


func _drain() -> void:
	_mutex.lock()
	var done := _results
	_results = []
	_mutex.unlock()
	for r: Array in done:
		_active -= 1
		var c: Chunk = chunks.get(r[1])
		if c == null:
			continue
		if r[0] == 0:
			if c.state == S_GENERATING:
				c.data = r[2]["data"]
				c.max_y = r[2]["max_y"]
				c.state = S_DATA
		elif c.state == S_MESHING:
			_uploads.append(r)
		elif c.meshing:
			_uploads.push_front(r)


func _upload() -> void:
	var t0 := Time.get_ticks_usec()
	while not _uploads.is_empty():
		var r: Array = _uploads.pop_front()
		var pos: Vector2i = r[1]
		var c: Chunk = chunks.get(pos)
		if c == null or (c.state != S_MESHING and not c.meshing):
			continue
		_build_node(c, pos, r[2])
		c.state = S_READY
		c.meshing = false
		if c.dirty and not _dirty.has(pos):
			_dirty.append(pos)
		if Time.get_ticks_usec() - t0 > UPLOAD_BUDGET_USEC:
			break


func _build_node(c: Chunk, pos: Vector2i, m: Dictionary) -> void:
	if c.node != null:
		c.node.queue_free()
		c.node = null
	total_quads -= c.quads
	c.quads = 0
	var sv: PackedVector3Array = m["sv"]
	var wv: PackedVector3Array = m["wv"]
	if sv.is_empty() and wv.is_empty():
		return
	var mesh := ArrayMesh.new()
	if not sv.is_empty():
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = sv
		a[Mesh.ARRAY_TEX_UV] = m["su"]
		a[Mesh.ARRAY_COLOR] = m["sc"]
		a[Mesh.ARRAY_INDEX] = m["si"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_solid)
	if not wv.is_empty():
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = wv
		a[Mesh.ARRAY_COLOR] = m["wc"]
		a[Mesh.ARRAY_INDEX] = m["wi"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_water)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(pos.x * CS, 0, pos.y * CS)
	add_child(mi)
	c.node = mi
	@warning_ignore("integer_division")
	c.quads = (sv.size() + wv.size()) / 4
	total_quads += c.quads


func _unload_far() -> void:
	var limit := (view_dist + 3) * (view_dist + 3)
	for pos: Vector2i in chunks.keys():
		if (pos - _center).length_squared() > limit:
			var c: Chunk = chunks[pos]
			if c.node != null:
				c.node.queue_free()
			total_quads -= c.quads
			chunks.erase(pos)

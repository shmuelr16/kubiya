extends Node3D
## Creatures. All four are original designs, built from coloured boxes in code.
##
##   Mokki    passive  small cream hopper with two tall ears. Moves by hopping.
##   Dundle   passive  wide slow grazer with teal back plates. Drops meat.
##   Gloomer  hostile  dark floating cube with one glowing eye. Appears at night.
##   Skitter  hostile  flat fast crawler with orange eyes. Appears at night.
##
## Hostile creatures chase the player and strike at close range. They dissolve
## at sunrise. Passive creatures wander, and run away after being hit.
## Movement uses the same box-versus-blocks collision as the player.

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")
const Mesher := preload("res://scripts/mesher.gd")

enum { MOKKI, DUNDLE, GLOOMER, SKITTER }

const NAMES := ["Mokki", "Dundle", "Gloomer", "Skitter"]
const HOSTILE := [false, false, true, true]
const HEALTH := [6, 10, 16, 8]
const SPEED := [2.6, 1.5, 3.3, 4.6]
## Half width and height of the collision box.
const HALF := [0.28, 0.42, 0.36, 0.36]
const HEIGHT := [0.6, 0.95, 1.5, 0.4]
const DAMAGE := [0, 0, 4, 2]
## Item dropped on death: [id, count], or [].
const LOOT := [[Items.MEAT, 1], [Items.MEAT, 2], [Items.COAL_LUMP, 1], []]

const MAX_PASSIVE := 6
const MAX_HOSTILE := 8
const SPAWN_PERIOD := 1.5
const SPAWN_MIN := 16.0
const SPAWN_MAX := 30.0
const DESPAWN_RANGE := 72.0
const SIGHT := 18.0
const STRIKE_RANGE := 1.5
const STRIKE_COOLDOWN := 1.0
const GRAVITY := 26.0
const SKIN := 0.001

const SHADER := "
shader_type spatial;
render_mode unshaded;
global uniform float daylight;
uniform float sky = 1.0;
uniform float flash = 0.0;
void fragment() {
	// Alpha 0 marks glowing parts such as eyes: they ignore the light level.
	float light = max(max(sky * daylight, 0.10), 1.0 - COLOR.a);
	ALBEDO = mix(COLOR.rgb * light, vec3(1.0, 0.25, 0.2), flash);
}
"


class Mob:
	var type := 0
	var node: MeshInstance3D
	var mat: ShaderMaterial
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var knock := Vector3.ZERO
	var yaw := 0.0
	var hp := 0.0
	var on_floor := false
	var blocked := false
	var dir := Vector3.ZERO
	var think := 0.0
	var strike := 0.0
	var flash := 0.0
	var flee := 0.0
	var light_t := 0.0
	var age := 0.0
	var chasing := false


var world: Node3D
var player: Node3D
var drops: Node3D
var audio: Node
var daynight: Node3D
var list: Array[Mob] = []
## Tests switch natural spawning off.
var auto_spawn := true

var _shader: Shader
var _meshes := {}
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = SHADER
	_rng.randomize()


func count(hostile: bool) -> int:
	var n := 0
	for m in list:
		if HOSTILE[m.type] == hostile:
			n += 1
	return n


func spawn(type: int, pos: Vector3) -> Mob:
	var m := Mob.new()
	m.type = type
	m.pos = pos
	m.hp = HEALTH[type]
	m.yaw = _rng.randf() * TAU
	m.mat = ShaderMaterial.new()
	m.mat.shader = _shader
	m.node = MeshInstance3D.new()
	m.node.mesh = _mesh_for(type)
	m.node.material_override = m.mat
	m.node.position = pos
	add_child(m.node)
	list.append(m)
	return m


## Damages a creature. `from` is the direction of the blow.
func hurt(m: Mob, amount: float, from: Vector3) -> void:
	m.hp -= amount
	m.flash = 0.25
	m.knock = Vector3(from.x, 0.0, from.z).normalized() * 7.0
	if m.on_floor:
		m.vel.y = 5.0
	if not HOSTILE[m.type]:
		m.flee = 5.0
	audio.play("hit", 1.2, -3.0)
	if m.hp <= 0.0:
		var loot: Array = LOOT[m.type]
		if not loot.is_empty():
			drops.spawn(m.pos + Vector3(0, 0.4, 0), loot[0], loot[1])
		_remove(m)


## Nearest creature hit by a ray: [mob, distance], or [].
func pick(origin: Vector3, dir: Vector3, reach: float) -> Array:
	var best := []
	var best_t := reach
	for m in list:
		var h: float = HALF[m.type] + 0.1
		var lo := m.pos - Vector3(h, 0.0, h)
		var hi := m.pos + Vector3(h, HEIGHT[m.type] + 0.1, h)
		var t0 := 0.0
		var t1 := best_t
		for a in 3:
			if absf(dir[a]) < 0.00001:
				if origin[a] < lo[a] or origin[a] > hi[a]:
					t1 = -1.0
				continue
			var ta := (lo[a] - origin[a]) / dir[a]
			var tb := (hi[a] - origin[a]) / dir[a]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		if t0 <= t1:
			best_t = t0
			best = [m, t0]
	return best


func _physics_process(delta: float) -> void:
	if player == null:
		return
	delta = minf(delta, 0.05)
	if auto_spawn:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = SPAWN_PERIOD
			spawn_tick()
	for i in range(list.size() - 1, -1, -1):
		_step(list[i], delta)


## One round of natural spawning and despawning.
func spawn_tick() -> void:
	var night: bool = daynight != null and daynight.is_night()
	for i in range(list.size() - 1, -1, -1):
		var m := list[i]
		var far := m.pos.distance_to(player.position) > DESPAWN_RANGE
		# Night creatures dissolve in daylight, a few at a time.
		if far or (HOSTILE[m.type] and not night and _rng.randf() < 0.5):
			_remove(m)
	if player.frozen:
		return
	if night and count(true) < MAX_HOSTILE:
		_try_spawn(GLOOMER if _rng.randf() < 0.6 else SKITTER)
	if not night and count(false) < MAX_PASSIVE and _rng.randf() < 0.5:
		_try_spawn(MOKKI if _rng.randf() < 0.55 else DUNDLE)


func _try_spawn(type: int) -> void:
	var angle := _rng.randf() * TAU
	var r := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var x := floori(player.position.x + cos(angle) * r)
	var z := floori(player.position.z + sin(angle) * r)
	if world.get_block(x, 0, z) == -1:
		return
	var y := 126
	while y > 1 and world.get_block(x, y, z) == Blocks.AIR:
		y -= 1
	var ground: int = world.get_block(x, y, z)
	if Blocks.SOLID[ground] == 0 or ground == Blocks.LEAVES:
		return
	if not HOSTILE[type] and ground != Blocks.GRASS:
		return
	if world.get_block(x, y + 2, z) != Blocks.AIR:
		return
	spawn(type, Vector3(x + 0.5, y + 1.0, z + 0.5))


func _remove(m: Mob) -> void:
	m.node.queue_free()
	list.erase(m)


func _step(m: Mob, delta: float) -> void:
	var type := m.type
	m.age += delta
	m.strike = maxf(m.strike - delta, 0.0)
	m.flash = maxf(m.flash - delta, 0.0)
	m.flee = maxf(m.flee - delta, 0.0)

	var to: Vector3 = player.position - m.pos
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	var speed: float = SPEED[type]
	var was_chasing := m.chasing
	m.chasing = false
	if HOSTILE[type] and dist < SIGHT and not player.frozen:
		m.chasing = true
		m.dir = flat / maxf(dist, 0.001) if dist > 0.7 else Vector3.ZERO
		if not was_chasing and audio != null:
			audio.play("growl", 1.0 if type == GLOOMER else 1.7, -8.0)
		if dist < STRIKE_RANGE and absf(to.y) < 1.8 and m.strike <= 0.0:
			m.strike = STRIKE_COOLDOWN
			var push := flat / maxf(dist, 0.001) * 6.0
			player.hurt(DAMAGE[type], Vector3(push.x, 5.0, push.z))
	elif m.flee > 0.0:
		m.dir = -flat / maxf(dist, 0.001)
		speed *= 1.7
	else:
		m.think -= delta
		if m.think <= 0.0:
			m.think = _rng.randf_range(2.0, 5.0)
			if _rng.randf() < 0.4:
				m.dir = Vector3.ZERO
			else:
				m.dir = Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU)

	var in_water: bool = world.get_block(floori(m.pos.x), floori(m.pos.y + 0.3), floori(m.pos.z)) == Blocks.WATER
	if in_water:
		m.vel.y = move_toward(m.vel.y, 2.0, 20.0 * delta)
		speed *= 0.6
	else:
		m.vel.y = maxf(m.vel.y - GRAVITY * delta, -40.0)
		if m.on_floor and m.dir != Vector3.ZERO:
			if m.blocked:
				m.vel.y = 7.6
			elif type == MOKKI:
				m.vel.y = 4.6
	m.vel.x = m.dir.x * speed + m.knock.x
	m.vel.z = m.dir.z * speed + m.knock.z
	m.knock = m.knock.move_toward(Vector3.ZERO, 22.0 * delta)
	_move(m, delta)
	if m.pos.y < -10.0:
		_remove(m)
		return

	# Visuals.
	if m.dir != Vector3.ZERO:
		m.yaw = lerp_angle(m.yaw, atan2(-m.dir.x, -m.dir.z), minf(delta * 8.0, 1.0))
	var lift := 0.0
	if type == GLOOMER:
		lift = 0.12 * sin(m.age * 3.0)
	m.node.position = m.pos + Vector3(0, lift, 0)
	m.node.rotation.y = m.yaw
	m.mat.set_shader_parameter("flash", minf(m.flash * 4.0, 1.0) * 0.7)
	m.light_t -= delta
	if m.light_t <= 0.0:
		m.light_t = 0.5 + _rng.randf() * 0.2
		m.mat.set_shader_parameter("sky", 1.0 if _sees_sky(m.pos) else 0.3)


func _sees_sky(p: Vector3) -> bool:
	var x := floori(p.x)
	var z := floori(p.z)
	for y in range(floori(p.y) + 1, floori(p.y) + 24):
		var id: int = world.get_block(x, y, z)
		if id > 0 and Blocks.SEE_THROUGH[id] == 0:
			return false
	return true


func _move(m: Mob, delta: float) -> void:
	var h: float = HALF[m.type]
	var height: float = HEIGHT[m.type]
	var p := m.pos
	m.on_floor = false
	m.blocked = false

	var nx := p.x + m.vel.x * delta
	if m.vel.x != 0.0 and _hits(nx, p.y, p.z, h, height):
		nx = (floorf(nx + h) - h - SKIN) if m.vel.x > 0.0 else (floorf(nx - h) + 1.0 + h + SKIN)
		m.vel.x = 0.0
		m.blocked = true
	p.x = nx

	var nz := p.z + m.vel.z * delta
	if m.vel.z != 0.0 and _hits(p.x, p.y, nz, h, height):
		nz = (floorf(nz + h) - h - SKIN) if m.vel.z > 0.0 else (floorf(nz - h) + 1.0 + h + SKIN)
		m.vel.z = 0.0
		m.blocked = true
	p.z = nz

	var ny := p.y + m.vel.y * delta
	if _hits(p.x, ny, p.z, h, height):
		if m.vel.y <= 0.0:
			ny = floorf(ny) + 1.0
			m.on_floor = true
		else:
			ny = floorf(ny + height) - height - SKIN
		m.vel.y = 0.0
	p.y = ny
	m.pos = p


func _hits(px: float, py: float, pz: float, h: float, height: float) -> bool:
	for y in range(floori(py), floori(py + height) + 1):
		for z in range(floori(pz - h), floori(pz + h) + 1):
			for x in range(floori(px - h), floori(px + h) + 1):
				if world.is_solid(x, y, z):
					return true
	return false


# --- Models. Front is -Z. Feet at y = 0. ---

func _mesh_for(type: int) -> ArrayMesh:
	if _meshes.has(type):
		return _meshes[type]
	var b := _Builder.new()
	match type:
		MOKKI:
			var fur := Color(0.94, 0.87, 0.70)
			var ear := Color(0.93, 0.66, 0.62)
			b.box(Vector3(0, 0.26, 0), Vector3(0.46, 0.42, 0.56), fur)
			b.box(Vector3(-0.13, 0.68, 0.02), Vector3(0.10, 0.44, 0.08), ear)
			b.box(Vector3(0.13, 0.68, 0.02), Vector3(0.10, 0.44, 0.08), ear)
			b.box(Vector3(0, 0.30, 0.32), Vector3(0.16, 0.16, 0.10), Color.WHITE)
			b.box(Vector3(-0.12, 0.36, -0.285), Vector3(0.07, 0.08, 0.02), Color(0.10, 0.08, 0.08))
			b.box(Vector3(0.12, 0.36, -0.285), Vector3(0.07, 0.08, 0.02), Color(0.10, 0.08, 0.08))
			b.box(Vector3(0, 0.24, -0.29), Vector3(0.08, 0.05, 0.02), ear)
		DUNDLE:
			var hide := Color(0.63, 0.43, 0.26)
			var plate := Color(0.20, 0.62, 0.56)
			b.box(Vector3(0, 0.56, 0.05), Vector3(0.80, 0.56, 1.15), hide)
			b.box(Vector3(0, 0.58, -0.72), Vector3(0.50, 0.44, 0.40), Color(0.74, 0.55, 0.36))
			for sx: float in [-0.27, 0.27]:
				for sz: float in [-0.32, 0.42]:
					b.box(Vector3(sx, 0.14, sz), Vector3(0.18, 0.28, 0.18), Color(0.36, 0.24, 0.15))
				b.box(Vector3(sx * 0.5, 0.66, -0.925), Vector3(0.07, 0.08, 0.02), Color(0.08, 0.07, 0.07))
			for i in 3:
				b.box(Vector3(0, 0.90, -0.28 + i * 0.36), Vector3(0.30, 0.14, 0.22), plate)
		GLOOMER:
			var core := Color(0.17, 0.09, 0.26)
			b.box(Vector3(0, 1.0, 0), Vector3(0.70, 0.70, 0.70), core)
			b.box(Vector3(0, 1.04, -0.36), Vector3(0.36, 0.20, 0.03), Color(0.30, 0.95, 1.0), true)
			b.box(Vector3(0, 1.04, -0.375), Vector3(0.10, 0.20, 0.02), Color(0.02, 0.10, 0.14), true)
			for sx: float in [-0.28, 0.28]:
				for sz: float in [-0.28, 0.28]:
					b.box(Vector3(sx, 0.42 + absf(sx + sz) * 0.2, sz), Vector3(0.16, 0.16, 0.16), Color(0.36, 0.20, 0.52))
			b.box(Vector3(0, 0.16, 0), Vector3(0.12, 0.12, 0.12), Color(0.36, 0.20, 0.52))
		SKITTER:
			var shell := Color(0.52, 0.21, 0.12)
			b.box(Vector3(0, 0.20, 0), Vector3(0.70, 0.20, 0.86), shell)
			b.box(Vector3(0, 0.32, 0.08), Vector3(0.44, 0.08, 0.50), Color(0.66, 0.30, 0.16))
			for sx: float in [-0.16, 0.16]:
				b.box(Vector3(sx, 0.22, -0.44), Vector3(0.12, 0.09, 0.03), Color(1.0, 0.62, 0.10), true)
			for sx: float in [-0.40, 0.40]:
				for i in 3:
					b.box(Vector3(sx, 0.07, -0.28 + i * 0.28), Vector3(0.10, 0.14, 0.08), Color(0.25, 0.10, 0.07))
	var mesh := b.finish()
	_meshes[type] = mesh
	return mesh


## Collects coloured boxes into one mesh. Face shading is baked into the colour.
class _Builder:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var tables := Mesher.new()

	func box(centre: Vector3, size: Vector3, color: Color, glow := false) -> void:
		for f in 6:
			var k: float = 1.0 if glow else Mesher.SHADE[f]
			var n := verts.size()
			for c in 4:
				verts.append(centre + (tables.cv[f * 4 + c] - Vector3(0.5, 0.5, 0.5)) * size)
				colors.append(Color(color.r * k, color.g * k, color.b * k, 0.0 if glow else 1.0))
			indices.append_array([n, n + 1, n + 2, n, n + 2, n + 3])

	func finish() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

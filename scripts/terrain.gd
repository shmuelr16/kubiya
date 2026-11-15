extends RefCounted
## Terrain generator. Pure function of (seed, chunk position), so it is safe to
## call from worker threads and every chunk border lines up without neighbours.
##
## Chunk data layout: index = ((x + z * 16) << 7) + y, one byte per block.

const Blocks := preload("res://scripts/blocks.gd")

const CS := 16
const SY := 128
const SEA := 62
const TREE_MARGIN := 2
const HM := CS + TREE_MARGIN * 2
const CAVE_R2 := 0.011
const CAVE_BAND := 0.105 # sqrt(CAVE_R2), early-out for the first noise

var world_seed: int
var n_cont := FastNoiseLite.new()
var n_hill := FastNoiseLite.new()
var n_rough := FastNoiseLite.new()
var n_cave_a := FastNoiseLite.new()
var n_cave_b := FastNoiseLite.new()


func _init(p_seed: int) -> void:
	world_seed = p_seed
	_setup(n_cont, p_seed, 0.0025, 2)
	_setup(n_hill, p_seed + 1, 0.011, 3)
	_setup(n_rough, p_seed + 2, 0.0018, 1)
	_setup(n_cave_a, p_seed + 3, 0.03, 1)
	_setup(n_cave_b, p_seed + 4, 0.03, 1)


func _setup(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE


## Surface height of a world column (y of the top ground block).
func height(wx: int, wz: int) -> int:
	var rough := clampf(n_rough.get_noise_2d(wx, wz) * 0.9 + 0.5, 0.0, 1.0)
	var h := SEA + 4.0 + n_cont.get_noise_2d(wx, wz) * 24.0 \
			+ n_hill.get_noise_2d(wx, wz) * (5.0 + 20.0 * rough)
	return clampi(int(h), 8, SY - 16)


func carved(wx: int, y: int, wz: int) -> bool:
	var a := n_cave_a.get_noise_3d(wx, y * 1.6, wz)
	if a > CAVE_BAND or a < -CAVE_BAND:
		return false
	var b := n_cave_b.get_noise_3d(wx, y * 1.6, wz)
	return a * a + b * b < CAVE_R2


## Highest y that caves may carve in a column of height h.
## Columns at or near sea level keep a solid cap so that water never meets a cave.
static func carve_top(h: int) -> int:
	return h if h > SEA + 4 else h - 5


static func hash2(x: int, z: int, s: int) -> int:
	var h := (x * 374761393 + z * 668265263 + s * 982451653) & 0x7fffffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffffffff
	return (h ^ (h >> 16)) & 0x7fffffff


## Returns { "data": PackedByteArray, "max_y": int }.
func generate(cx: int, cz: int) -> Dictionary:
	var d := PackedByteArray()
	d.resize(CS * CS * SY)
	var ox := cx * CS
	var oz := cz * CS

	# Height map with a margin, so trees rooted in neighbour chunks can spill in.
	var hm := PackedInt32Array()
	hm.resize(HM * HM)
	for z in HM:
		for x in HM:
			hm[x + z * HM] = height(ox + x - TREE_MARGIN, oz + z - TREE_MARGIN)

	var max_y := SEA
	for z in CS:
		for x in CS:
			var wx := ox + x
			var wz := oz + z
			var h := hm[(x + TREE_MARGIN) + (z + TREE_MARGIN) * HM]
			var col := (x + z * CS) << 7
			var beach := h <= SEA + 1
			var ctop := carve_top(h)
			d[col] = Blocks.BEDROCK
			for y in range(1, h + 1):
				if y > 1 and y <= ctop and carved(wx, y, wz):
					continue
				var id := Blocks.STONE
				if y > h - 4:
					if beach:
						id = Blocks.SAND
					elif y == h:
						id = Blocks.GRASS
					else:
						id = Blocks.DIRT
				d[col + y] = id
			for y in range(h + 1, SEA + 1):
				d[col + y] = Blocks.WATER
			if h > max_y:
				max_y = h

	_ores(d, cx, cz)
	max_y = _trees(d, hm, ox, oz, max_y)
	return {"data": d, "max_y": max_y}


func _ores(d: PackedByteArray, cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash2(cx, cz, world_seed + 11)
	_veins(d, rng, Blocks.COAL, 10, 100, 9)
	_veins(d, rng, Blocks.IRON, 8, 64, 6)
	_veins(d, rng, Blocks.GOLD, 3, 32, 5)
	_veins(d, rng, Blocks.CRYSTAL, 2, 16, 4)


## Random-walk veins that only replace stone. Veins stay inside the chunk.
func _veins(d: PackedByteArray, rng: RandomNumberGenerator, id: int, count: int, top: int, size: int) -> void:
	for i in count:
		var x := rng.randi_range(0, CS - 1)
		var y := rng.randi_range(2, top)
		var z := rng.randi_range(0, CS - 1)
		for s in size:
			var idx := ((x + z * CS) << 7) + y
			if d[idx] == Blocks.STONE:
				d[idx] = id
			match rng.randi() % 6:
				0: x = mini(x + 1, CS - 1)
				1: x = maxi(x - 1, 0)
				2: y = mini(y + 1, top)
				3: y = maxi(y - 1, 2)
				4: z = mini(z + 1, CS - 1)
				5: z = maxi(z - 1, 0)


func _trees(d: PackedByteArray, hm: PackedInt32Array, ox: int, oz: int, max_y: int) -> int:
	for tz in range(-TREE_MARGIN, CS + TREE_MARGIN):
		for tx in range(-TREE_MARGIN, CS + TREE_MARGIN):
			var wx := ox + tx
			var wz := oz + tz
			var hv := hash2(wx, wz, world_seed + 7)
			if hv % 64 != 0:
				continue
			var h := hm[(tx + TREE_MARGIN) + (tz + TREE_MARGIN) * HM]
			if h <= SEA + 1:
				continue
			if h <= carve_top(h) and carved(wx, h, wz):
				continue
			var th := 4 + (hv >> 8) % 3
			for dy in range(th - 2, th + 2):
				var r := 2 if dy < th else 1
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if r == 2 and absi(dx) == 2 and absi(dz) == 2:
							continue
						_put(d, tx + dx, h + 1 + dy, tz + dz, Blocks.LEAVES, true)
			for dy in th:
				_put(d, tx, h + 1 + dy, tz, Blocks.WOOD, false)
			max_y = maxi(max_y, h + th + 2)
	return mini(max_y, SY - 1)


func _put(d: PackedByteArray, x: int, y: int, z: int, id: int, only_air: bool) -> void:
	if x < 0 or z < 0 or x >= CS or z >= CS or y < 0 or y >= SY:
		return
	var idx := ((x + z * CS) << 7) + y
	if only_air and d[idx] != Blocks.AIR:
		return
	d[idx] = id

extends RefCounted
## Builds render arrays for one chunk. Only faces that touch air (or water, for
## solid blocks) are emitted. Runs on worker threads: touches no scene objects.
##
## Face order: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z.

const Blocks := preload("res://scripts/blocks.gd")

const AIR := Blocks.AIR
const WATER := Blocks.WATER
const TORCH := Blocks.TORCH
const INV := 1.0 / Blocks.ATLAS_TILES
const UV_PAD := 0.002
const WATER_DROP := 0.12

## origin, u, v with u x v = normal. Corners o, o+v, o+u+v, o+u are clockwise
## from outside, which Godot treats as the front face.
const FACE_DEFS := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), 1],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 2],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), 0],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), 0],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), 2],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0), 1],
]
const CORNERS := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
## Tile slot per face: 0 top, 1 side, 2 bottom.
const SLOT: PackedInt32Array = [1, 1, 0, 2, 1, 1]
const SHADE: PackedFloat32Array = [0.80, 0.80, 1.00, 0.50, 0.66, 0.66]

var cv := PackedVector3Array()
var cuv := PackedVector2Array()
var shade := PackedColorArray()
var tiles := Blocks.TILE_OF
var see := Blocks.SEE_THROUGH

var sv := PackedVector3Array()
var su := PackedVector2Array()
var sc := PackedColorArray()
var si := PackedInt32Array()
var wv := PackedVector3Array()
var wi := PackedInt32Array()


func _init() -> void:
	var inv := 1.0 / Blocks.ATLAS_TILES
	var lo := Vector2(UV_PAD, UV_PAD)
	var hi := Vector2(1.0 - UV_PAD, 1.0 - UV_PAD)
	for f in 6:
		var def: Array = FACE_DEFS[f]
		var origin: Vector3 = def[0]
		var u: Vector3 = def[1]
		var v: Vector3 = def[2]
		var y_axis: int = def[3]
		for c: Vector2 in CORNERS:
			cv.append(origin + u * c.x + v * c.y)
			var st := c
			if y_axis == 1:
				st = Vector2(c.y, 1.0 - c.x)
			elif y_axis == 2:
				st = Vector2(c.x, 1.0 - c.y)
			cuv.append(st.clamp(lo, hi) * inv)
		shade.append(Color(SHADE[f], SHADE[f], SHADE[f]))


## d is the chunk; nx/px/nz/pz are the -X/+X/-Z/+Z neighbour chunks.
func build(d: PackedByteArray, nx: PackedByteArray, px: PackedByteArray,
		nz: PackedByteArray, pz: PackedByteArray, max_y: int) -> Dictionary:
	var top := mini(max_y, 127)
	for z in 16:
		for x in 16:
			var col := (x + z * 16) << 7
			for y in top + 1:
				var i := col + y
				var id := d[i]
				if id == AIR:
					continue
				if id == TORCH:
					_emit_torch(x, y, z)
					continue
				var nb := d[i + 1] if y < 127 else AIR
				if see[nb] == 1 and nb != id:
					_emit(2, x, y, z, id)
				nb = d[i - 1] if y > 0 else id
				if see[nb] == 1 and nb != id:
					_emit(3, x, y, z, id)
				nb = d[i + 128] if x < 15 else px[i - 1920]
				if see[nb] == 1 and nb != id:
					_emit(0, x, y, z, id)
				nb = d[i - 128] if x > 0 else nx[i + 1920]
				if see[nb] == 1 and nb != id:
					_emit(1, x, y, z, id)
				nb = d[i + 2048] if z < 15 else pz[i - 30720]
				if see[nb] == 1 and nb != id:
					_emit(4, x, y, z, id)
				nb = d[i - 2048] if z > 0 else nz[i + 30720]
				if see[nb] == 1 and nb != id:
					_emit(5, x, y, z, id)
	return {"sv": sv, "su": su, "sc": sc, "si": si, "wv": wv, "wi": wi}


func _emit(f: int, x: int, y: int, z: int, id: int) -> void:
	var k := f * 4
	var b := Vector3(x, y, z)
	if id == WATER:
		if f == 2:
			b.y -= WATER_DROP
		var s := wv.size()
		wv.append(b + cv[k])
		wv.append(b + cv[k + 1])
		wv.append(b + cv[k + 2])
		wv.append(b + cv[k + 3])
		wi.append(s)
		wi.append(s + 1)
		wi.append(s + 2)
		wi.append(s)
		wi.append(s + 2)
		wi.append(s + 3)
		return
	var t := tiles[id * 3 + SLOT[f]]
	var tb := Vector2((t & 7) * INV, (t >> 3) * INV)
	var col := shade[f]
	var n := sv.size()
	sv.append(b + cv[k])
	sv.append(b + cv[k + 1])
	sv.append(b + cv[k + 2])
	sv.append(b + cv[k + 3])
	su.append(tb + cuv[k])
	su.append(tb + cuv[k + 1])
	su.append(tb + cuv[k + 2])
	su.append(tb + cuv[k + 3])
	sc.append(col)
	sc.append(col)
	sc.append(col)
	sc.append(col)
	si.append(n)
	si.append(n + 1)
	si.append(n + 2)
	si.append(n)
	si.append(n + 2)
	si.append(n + 3)


## A torch is a thin post, 2 x 10 x 2 pixels, in the middle of its cell.
## Its UVs cover only the stick-and-flame pixels of the torch tile.
func _emit_torch(x: int, y: int, z: int) -> void:
	var t := tiles[TORCH * 3]
	var tile := Vector2(t & 7, t >> 3)
	var base := Vector3(x + 7.0 / 16.0, y, z + 7.0 / 16.0)
	var size := Vector3(2.0 / 16.0, 10.0 / 16.0, 2.0 / 16.0)
	for f in 6:
		var k := f * 4
		var cap := f == 2 or f == 3
		var n := sv.size()
		for c in 4:
			sv.append(base + cv[k + c] * size)
			var st := cuv[k + c] * float(Blocks.ATLAS_TILES)
			var v := 6.0 / 16.0 + st.y * (2.0 if cap else 10.0) / 16.0
			su.append((tile + Vector2(7.0 / 16.0 + st.x * 2.0 / 16.0, v)) * INV)
			sc.append(shade[f])
		si.append(n)
		si.append(n + 1)
		si.append(n + 2)
		si.append(n)
		si.append(n + 2)
		si.append(n + 3)

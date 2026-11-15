extends RefCounted
## Builds render arrays for one chunk, with baked light. Only faces that touch a
## see-through block are emitted. Runs on worker threads: touches no scene objects.
##
## Face order: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z.
##
## Light: every face stores the light of the cell in front of it in its vertex
## colour. R = face shade, G = sky light, B = block light (torches). The shader
## combines them as max(G * daylight, B), so day and night need no re-mesh.
##   Sky light: 15 in every cell that sees the sky, then flood-filled sideways and
##   down with a loss of 1 per block, inside this chunk. Neighbour chunks feed
##   light in through their open-sky cells only.
##   Block light: flood-filled from torches on a grid padded by the torch range,
##   reading the 4 side neighbours. Diagonal neighbours count as solid.

const Blocks := preload("res://scripts/blocks.gd")

const AIR := Blocks.AIR
const WATER := Blocks.WATER
const TORCH := Blocks.TORCH
const INV := 1.0 / Blocks.ATLAS_TILES
const UV_PAD := 0.002
const WATER_DROP := 0.12
const TORCH_LIGHT := 13
## Padding of the block-light grid on each side, in blocks.
const PAD := TORCH_LIGHT
const PW := 16 + 2 * PAD
## Brightness of light level 0-15: each step down keeps 80%.
const FALLOFF := 0.8

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
var sky_lut := PackedFloat32Array()
var block_lut := PackedFloat32Array()

var sv := PackedVector3Array()
var su := PackedVector2Array()
var sc := PackedColorArray()
var si := PackedInt32Array()
var wv := PackedVector3Array()
var wc := PackedColorArray()
var wi := PackedInt32Array()

## Sky light per cell, chunk layout. Valid up to y = _ytop.
var sl := PackedByteArray()
## Block light per cell on the padded grid. Empty when no torch is in range.
var bl := PackedByteArray()
var has_bl := false

var _d: PackedByteArray
var _nx: PackedByteArray
var _px: PackedByteArray
var _nz: PackedByteArray
var _pz: PackedByteArray
var _ytop := 0
## Top solid y of the neighbour column across each border, per border cell.
var _top_nx := PackedInt32Array()
var _top_px := PackedInt32Array()
var _top_nz := PackedInt32Array()
var _top_pz := PackedInt32Array()


func _init() -> void:
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
			cuv.append(st.clamp(lo, hi) * INV)
		shade.append(Color(SHADE[f], SHADE[f], SHADE[f]))
	for l in 16:
		sky_lut.append(pow(FALLOFF, 15 - l))
		block_lut.append(pow(FALLOFF, 15 - l) if l > 0 else 0.0)


## d is the chunk; nx/px/nz/pz are the -X/+X/-Z/+Z neighbour chunks.
## torches holds x, y, z triples in this chunk's local coordinates; x and z may
## lie outside 0-15 for torches in neighbour chunks.
func build(d: PackedByteArray, nx: PackedByteArray, px: PackedByteArray,
		nz: PackedByteArray, pz: PackedByteArray, max_y: int,
		torches := PackedInt32Array()) -> Dictionary:
	_d = d
	_nx = nx
	_px = px
	_nz = nz
	_pz = pz
	var top := mini(max_y, 127)
	_ytop = mini(top + 1, 127)
	_sky_light(top)
	if not torches.is_empty():
		_block_light(torches)
	var ytop := _ytop
	var zstep := PW << 7

	for z in 16:
		for x in 16:
			var col := (x + z * 16) << 7
			var pcol := ((x + PAD) + (z + PAD) * PW) << 7
			for y in top + 1:
				var i := col + y
				var id := d[i]
				if id == AIR:
					continue
				if id == TORCH:
					_emit_torch(x, y, z)
					continue
				var pb := pcol + y
				var nb := d[i + 1] if y < 127 else AIR
				if see[nb] == 1 and nb != id:
					_emit(2, x, y, z, id, sl[i + 1] if y < ytop else 15,
							bl[pb + 1] if has_bl and y < 127 else 0)
				nb = d[i - 1] if y > 0 else id
				if see[nb] == 1 and nb != id:
					_emit(3, x, y, z, id, sl[i - 1], bl[pb - 1] if has_bl else 0)
				if x < 15:
					nb = d[i + 128]
					if see[nb] == 1 and nb != id:
						_emit(0, x, y, z, id, sl[i + 128], bl[pb + 128] if has_bl else 0)
				else:
					nb = px[i - 1920]
					if see[nb] == 1 and nb != id:
						_emit(0, x, y, z, id, _edge_sky(i, y, 2048, z, _top_px[z]), bl[pb + 128] if has_bl else 0)
				if x > 0:
					nb = d[i - 128]
					if see[nb] == 1 and nb != id:
						_emit(1, x, y, z, id, sl[i - 128], bl[pb - 128] if has_bl else 0)
				else:
					nb = nx[i + 1920]
					if see[nb] == 1 and nb != id:
						_emit(1, x, y, z, id, _edge_sky(i, y, 2048, z, _top_nx[z]), bl[pb - 128] if has_bl else 0)
				if z < 15:
					nb = d[i + 2048]
					if see[nb] == 1 and nb != id:
						_emit(4, x, y, z, id, sl[i + 2048], bl[pb + zstep] if has_bl else 0)
				else:
					nb = pz[i - 30720]
					if see[nb] == 1 and nb != id:
						_emit(4, x, y, z, id, _edge_sky(i, y, 128, x, _top_pz[x]), bl[pb + zstep] if has_bl else 0)
				if z > 0:
					nb = d[i - 2048]
					if see[nb] == 1 and nb != id:
						_emit(5, x, y, z, id, sl[i - 2048], bl[pb - zstep] if has_bl else 0)
				else:
					nb = nz[i + 30720]
					if see[nb] == 1 and nb != id:
						_emit(5, x, y, z, id, _edge_sky(i, y, 128, x, _top_nz[x]), bl[pb - zstep] if has_bl else 0)
	return {"sv": sv, "su": su, "sc": sc, "si": si, "wv": wv, "wc": wc, "wi": wi}


## Sky light of a cell in a neighbour chunk, in front of border cell i.
## Full when that cell sees the sky. Otherwise estimated from the cells of this
## chunk that touch it diagonally: above, below, and both sides along the border.
func _edge_sky(i: int, y: int, along: int, a: int, nb_top: int) -> int:
	if y > nb_top:
		return 15
	var best := 0
	if y < _ytop:
		best = sl[i + 1]
	if y > 0:
		best = maxi(best, sl[i - 1])
	if a < 15:
		best = maxi(best, sl[i + along])
	if a > 0:
		best = maxi(best, sl[i - along])
	return maxi(best - 1, 0)


func _sky_light(top: int) -> void:
	var d := _d
	var ytop := _ytop
	sl.resize(32768)
	var tops := PackedInt32Array()
	tops.resize(256)
	# Straight down from the sky. Water dims the light by 2 per block.
	for c in 256:
		var col := c << 7
		var l := 15
		var y := ytop
		var t := -1
		while y >= 0:
			var id := d[col + y]
			if see[id] == 0:
				t = y
				break
			if id == WATER:
				l = maxi(l - 2, 0)
			sl[col + y] = l
			y -= 1
		tops[c] = t

	_top_nx = _border_tops(_nx, 15, true)
	_top_px = _border_tops(_px, 0, true)
	_top_nz = _border_tops(_nz, 15, false)
	_top_pz = _border_tops(_pz, 0, false)

	# Seeds: lit cells next to a column whose top is higher. Light has to turn
	# a corner there to reach overhangs and cave mouths.
	var q := PackedInt32Array()
	for z in 16:
		for x in 16:
			var c := x + z * 16
			var t := tops[c]
			var hi := t
			if x < 15:
				hi = maxi(hi, tops[c + 1])
			if x > 0:
				hi = maxi(hi, tops[c - 1])
			if z < 15:
				hi = maxi(hi, tops[c + 16])
			if z > 0:
				hi = maxi(hi, tops[c - 16])
			hi = mini(hi, ytop)
			var col := c << 7
			for y in range(t + 1, hi + 1):
				if sl[col + y] > 1:
					q.append(col + y)
			# Border cells below this column's top, next to open sky in the neighbour.
			var nt := 999
			if x == 0:
				nt = _top_nx[z]
			elif x == 15:
				nt = _top_px[z]
			if z == 0:
				nt = mini(nt, _top_nz[x])
			elif z == 15:
				nt = mini(nt, _top_pz[x])
			for y in range(maxi(nt + 1, 0), mini(t, top + 1)):
				var i := col + y
				if see[d[i]] == 1 and sl[i] < 14:
					sl[i] = 14
					q.append(i)

	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var l := sl[i] - 1
		if l <= 0:
			continue
		var y := i & 127
		var x := (i >> 7) & 15
		var z := i >> 11
		var n := i + 1
		if y < ytop and sl[n] < l and see[d[n]] == 1:
			sl[n] = l
			q.append(n)
		n = i - 1
		if y > 0 and sl[n] < l and see[d[n]] == 1:
			sl[n] = l
			q.append(n)
		n = i + 128
		if x < 15 and sl[n] < l and see[d[n]] == 1:
			sl[n] = l
			q.append(n)
		n = i - 128
		if x > 0 and sl[n] < l and see[d[n]] == 1:
			sl[n] = l
			q.append(n)
		n = i + 2048
		if z < 15 and sl[n] < l and see[d[n]] == 1:
			sl[n] = l
			q.append(n)
		n = i - 2048
		if z > 0 and sl[n] < l and see[d[n]] == 1:
			sl[n] = l
			q.append(n)


## Top solid y of the 16 columns of a neighbour that touch this chunk.
## `fixed` is the neighbour-local x (for X borders) or z (for Z borders).
func _border_tops(nb: PackedByteArray, fixed: int, x_border: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(16)
	for a in 16:
		var col := ((fixed + a * 16) << 7) if x_border else ((a + fixed * 16) << 7)
		var y := 127
		while y >= 0 and see[nb[col + y]] == 1:
			y -= 1
		out[a] = y
	return out


## Block id at local coordinates that may lie in a side neighbour. Solid elsewhere.
func _id_at(x: int, y: int, z: int) -> int:
	if x >= 0 and x < 16:
		if z >= 0 and z < 16:
			return _d[((x + z * 16) << 7) + y]
		if z < 0:
			return _nz[((x + (z + 16) * 16) << 7) + y]
		return _pz[((x + (z - 16) * 16) << 7) + y]
	if z >= 0 and z < 16:
		if x < 0:
			return _nx[((x + 16 + z * 16) << 7) + y]
		return _px[((x - 16 + z * 16) << 7) + y]
	return Blocks.STONE


func _block_light(torches: PackedInt32Array) -> void:
	bl.resize(PW * PW * 128)
	var zstep := PW << 7
	var q := PackedInt32Array()
	for t in range(0, torches.size(), 3):
		var gx := torches[t] + PAD
		var gz := torches[t + 2] + PAD
		var y := torches[t + 1]
		if gx < 0 or gz < 0 or gx >= PW or gz >= PW or y < 0 or y > 127:
			continue
		var i := ((gx + gz * PW) << 7) + y
		bl[i] = TORCH_LIGHT
		q.append(i)
		has_bl = true
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var l := bl[i] - 1
		if l <= 0:
			continue
		var y := i & 127
		var c := i >> 7
		var gx := c % PW
		@warning_ignore("integer_division")
		var gz := c / PW
		var x := gx - PAD
		var z := gz - PAD
		if y < 127 and bl[i + 1] < l and see[_id_at(x, y + 1, z)] == 1:
			bl[i + 1] = l
			q.append(i + 1)
		if y > 0 and bl[i - 1] < l and see[_id_at(x, y - 1, z)] == 1:
			bl[i - 1] = l
			q.append(i - 1)
		if gx < PW - 1 and bl[i + 128] < l and see[_id_at(x + 1, y, z)] == 1:
			bl[i + 128] = l
			q.append(i + 128)
		if gx > 0 and bl[i - 128] < l and see[_id_at(x - 1, y, z)] == 1:
			bl[i - 128] = l
			q.append(i - 128)
		if gz < PW - 1 and bl[i + zstep] < l and see[_id_at(x, y, z + 1)] == 1:
			bl[i + zstep] = l
			q.append(i + zstep)
		if gz > 0 and bl[i - zstep] < l and see[_id_at(x, y, z - 1)] == 1:
			bl[i - zstep] = l
			q.append(i - zstep)


func _emit(f: int, x: int, y: int, z: int, id: int, sky: int, block: int) -> void:
	var k := f * 4
	var b := Vector3(x, y, z)
	if id == WATER:
		if f == 2:
			b.y -= WATER_DROP
		var s := wv.size()
		var wcol := Color(1.0, sky_lut[sky], block_lut[block])
		wv.append(b + cv[k])
		wv.append(b + cv[k + 1])
		wv.append(b + cv[k + 2])
		wv.append(b + cv[k + 3])
		wc.append(wcol)
		wc.append(wcol)
		wc.append(wcol)
		wc.append(wcol)
		wi.append(s)
		wi.append(s + 1)
		wi.append(s + 2)
		wi.append(s)
		wi.append(s + 2)
		wi.append(s + 3)
		return
	var t := tiles[id * 3 + SLOT[f]]
	var tb := Vector2((t & 7) * INV, (t >> 3) * INV)
	var col := Color(SHADE[f], sky_lut[sky], block_lut[block])
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
## Its UVs cover only the stick-and-flame pixels of the torch tile. Always fully lit.
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
			sc.append(Color(SHADE[f], 0.0, 1.0))
		si.append(n)
		si.append(n + 1)
		si.append(n + 2)
		si.append(n)
		si.append(n + 2)
		si.append(n + 3)

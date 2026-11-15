extends RefCounted
## Block registry and procedural texture atlas.
## Every texture is generated in code, so the game ships no third-party art.
##
## The atlas is 8 x 8 tiles of 16 pixels. Tiles 0-31 are block faces,
## tiles 32 and up are item icons (see items.gd).

enum {
	AIR, GRASS, DIRT, STONE, SAND, WOOD, LEAVES, WATER, COAL, IRON, GOLD, CRYSTAL,
	BEDROCK, PLANKS, BRICKS, WORKBENCH, TORCH, FURNACE,
}

const TILE := 16
const ATLAS_TILES := 8
const ICON_BASE := 32

## Atlas tile per block id, 3 entries each: top, side, bottom.
const TILE_OF: PackedInt32Array = [
	0, 0, 0, # AIR
	0, 1, 2, # GRASS
	2, 2, 2, # DIRT
	3, 3, 3, # STONE
	4, 4, 4, # SAND
	6, 5, 6, # WOOD
	7, 7, 7, # LEAVES
	0, 0, 0, # WATER (own material, no tile)
	8, 8, 8, # COAL
	9, 9, 9, # IRON
	10, 10, 10, # GOLD
	11, 11, 11, # CRYSTAL
	12, 12, 12, # BEDROCK
	13, 13, 13, # PLANKS
	14, 14, 14, # BRICKS
	15, 16, 13, # WORKBENCH
	19, 19, 19, # TORCH (own shape in mesher.gd)
	18, 17, 18, # FURNACE
]

## Seconds of mining by hand. Negative: cannot be broken.
const HARDNESS: PackedFloat32Array = [
	0.0, 0.7, 0.6, 4.0, 0.6, 2.0, 0.3, 0.0, 5.0, 6.0, 6.0, 7.0, -1.0, 1.8, 4.5, 1.8, 0.05, 4.5,
]

## Tool that mines the block faster: 0 none, 1 pickaxe, 2 axe, 3 shovel.
const TOOL: PackedInt32Array = [0, 3, 3, 1, 3, 2, 0, 0, 1, 1, 1, 1, 0, 2, 1, 2, 0, 1]

## Lowest pickaxe tier that makes the block drop an item: 0 hand, 1 wood, 2 stone.
const MIN_TIER: PackedInt32Array = [0, 0, 0, 1, 0, 0, 0, 0, 1, 2, 2, 2, 0, 0, 1, 0, 0, 1]

## 1 when the block stops movement.
const SOLID: PackedByteArray = [0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1]

## 1 when faces of neighbours stay visible through the block.
const SEE_THROUGH: PackedByteArray = [1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]

## Sound pitch per block: soft materials low, hard materials high.
const PITCH: PackedFloat32Array = [
	1.0, 0.85, 0.8, 1.25, 1.0, 1.05, 1.5, 1.0, 1.3, 1.35, 1.4, 1.6, 1.2, 1.1, 1.3, 1.1, 1.5, 1.25,
]

const C_GRASS := Color(0.36, 0.68, 0.25)
const C_DIRT := Color(0.50, 0.34, 0.20)
const C_STONE := Color(0.52, 0.53, 0.56)
const C_SAND := Color(0.87, 0.80, 0.56)
const C_WOOD := Color(0.45, 0.31, 0.17)
const C_LEAVES := Color(0.20, 0.48, 0.18)
const C_BEDROCK := Color(0.20, 0.20, 0.23)
const C_COAL := Color(0.10, 0.10, 0.11)
const C_IRON := Color(0.80, 0.56, 0.42)
const C_GOLD := Color(0.98, 0.82, 0.20)
const C_CRYSTAL := Color(0.35, 0.90, 0.95)
const C_PLANKS := Color(0.74, 0.58, 0.36)
const C_BRICK := Color(0.66, 0.30, 0.24)
const C_MORTAR := Color(0.80, 0.78, 0.74)
const C_FLAME := Color(1.0, 0.78, 0.18)

## 16 x 16 pixel icons. '.' is transparent, 's' handle, 'h' head, 'c' / 'C' coal.
const ICON_STICK := [
	"", "............ss", "...........sss", "..........sss", ".........sss", "........sss",
	".......sss", "......sss", ".....sss", "....sss", "...sss", "..sss", "..ss",
]
const ICON_COAL := [
	"", "", "", ".....cccc", "....cccccc", "...ccCcccccc", "...cccccCccc", "..ccccccccccc",
	"..ccCcccccccc", "..cccccccCcc", "...ccccccccc", "....cccccc", ".....ccc",
]
const ICON_PICK := [
	"", "....hhhhhhh", "...hhhhhhhhhh", "..hh.....shhhh", ".........sshhh", "........sss.hh",
	".......sss..hh", "......sss...hh", ".....sss....hh", "....sss......h", "...sss", "..sss",
	".sss", ".ss",
]
const ICON_AXE := [
	"", ".........hh", "........hhhh", ".......hhhhhh", "......hhhhhsh", ".....hhhhhssh",
	".....hhhhsss", "......hhsss", ".......sss", "......sss", ".....sss", "....sss",
	"...sss", "..sss", "..ss",
]
const ICON_SHOVEL := [
	"", "...........hhh", "..........hhhhh", ".........hhhhhh", ".........hhhhhh",
	".........hhhhh", "........sshhh", ".......sss", "......sss", ".....sss", "....sss",
	"...sss", "..sss", ".sss", ".ss",
]
const ICON_MEAT := [
	"", "", ".......mmmm", "......mmmmmm", ".....mmmMMmmm", ".....mmmMmmmm", ".....mmmmmmm",
	"......mmmmm", ".....bbmm", "....bb", "...bb", "..bbb", "..bb",
]
const ICON_FRUIT := [
	"", "", ".......g", "......gg", ".....ffff", "....ffffff", "...ffFFffff", "...ffFfffff",
	"...ffffffff", "...ffffffff", "....ffffff", ".....ffff",
]
const ICON_SWORD := [
	"", ".............hh", "............hhh", "...........hhh", "..........hhh",
	".........hhh", "........hhh", ".......hhh", "..s...hhh", "..ss.hhh", "...sshh",
	"....ss", "...ssss", "..ss..ss", ".ss",
]


static func make_atlas() -> ImageTexture:
	var size := TILE * ATLAS_TILES
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115

	_fill(img, 0, C_GRASS, 0.12, rng)
	_fill(img, 2, C_DIRT, 0.14, rng)
	_fill(img, 3, C_STONE, 0.10, rng)
	_fill(img, 4, C_SAND, 0.06, rng)
	_fill(img, 7, C_LEAVES, 0.22, rng)
	_fill(img, 12, C_BEDROCK, 0.35, rng)
	_ore(img, 8, C_COAL, rng)
	_ore(img, 9, C_IRON, rng)
	_ore(img, 10, C_GOLD, rng)
	_ore(img, 11, C_CRYSTAL, rng)
	_planks(img, 13, rng)

	# Bricks: rows of 4 pixels, every second row shifted by half a brick.
	var o := _origin(14)
	for py in TILE:
		for px in TILE:
			@warning_ignore("integer_division")
			var row := py / 4
			var shift := 4 if row % 2 == 1 else 0
			var mortar := py % 4 == 3 or (px + shift) % 8 == 7
			var c := C_MORTAR if mortar else C_BRICK
			img.set_pixel(o.x + px, o.y + py, _shade(c, rng.randf_range(0.90, 1.08)))

	# Grass side: dirt with a ragged green cap.
	_fill(img, 1, C_DIRT, 0.14, rng)
	o = _origin(1)
	for px in TILE:
		var depth := 3 + rng.randi() % 3
		for py in depth:
			img.set_pixel(o.x + px, o.y + py, _shade(C_GRASS, rng.randf_range(0.88, 1.12)))

	# Wood side: vertical bark stripes.
	o = _origin(5)
	for px in TILE:
		var stripe := 0.78 if px % 4 == 0 else 1.0
		for py in TILE:
			img.set_pixel(o.x + px, o.y + py, _shade(C_WOOD, stripe * rng.randf_range(0.92, 1.08)))

	# Wood top: growth rings.
	o = _origin(6)
	for py in TILE:
		for px in TILE:
			var d := Vector2(px - 7.5, py - 7.5).length()
			var ring := 0.8 if int(d) % 3 == 0 else 1.15
			img.set_pixel(o.x + px, o.y + py, _shade(C_WOOD, ring))

	# Workbench top: planks with a dark frame and a cross, like a work grid.
	_planks(img, 15, rng)
	o = _origin(15)
	for i in TILE:
		for edge: int in [0, 15, 7, 8]:
			img.set_pixel(o.x + i, o.y + edge, _shade(C_WOOD, 0.8))
			img.set_pixel(o.x + edge, o.y + i, _shade(C_WOOD, 0.8))

	# Workbench side: planks with a dark top band and legs.
	_planks(img, 16, rng)
	o = _origin(16)
	for px in TILE:
		for py in 3:
			img.set_pixel(o.x + px, o.y + py, _shade(C_WOOD, 0.85))
	for py in range(3, TILE):
		for px: int in [0, 1, 14, 15]:
			img.set_pixel(o.x + px, o.y + py, _shade(C_WOOD, 0.7))

	# Furnace side: stone with a dark mouth and a glowing bed.
	_fill(img, 17, C_STONE, 0.10, rng)
	o = _origin(17)
	for px in range(4, 12):
		for py in range(3, 6):
			img.set_pixel(o.x + px, o.y + py, Color(0.12, 0.12, 0.13))
		for py in range(8, 14):
			var glow := py >= 12
			img.set_pixel(o.x + px, o.y + py, _shade(C_FLAME, rng.randf_range(0.7, 1.0)) if glow else Color(0.10, 0.09, 0.09))

	# Furnace top: dark stone with a frame.
	_fill(img, 18, _shade(C_STONE, 0.8), 0.10, rng)
	o = _origin(18)
	for i in TILE:
		for edge: int in [0, 15]:
			img.set_pixel(o.x + i, o.y + edge, _shade(C_STONE, 0.55))
			img.set_pixel(o.x + edge, o.y + i, _shade(C_STONE, 0.55))

	# Torch: a 2-pixel stick with a flame. The mesher maps only these pixels.
	o = _origin(19)
	for py in range(6, TILE):
		for px in range(7, 9):
			var c := C_FLAME if py < 8 else C_WOOD
			img.set_pixel(o.x + px, o.y + py, _shade(c, rng.randf_range(0.9, 1.1)))

	# Item icons, in the order of the ids in items.gd.
	var handle := {"s": C_WOOD}
	_icon(img, ICON_BASE, ICON_STICK, {"s": _shade(C_WOOD, 1.25)})
	_icon(img, ICON_BASE + 1, ICON_COAL, {"c": C_COAL, "C": Color(0.30, 0.30, 0.33)})
	var heads := [C_PLANKS, C_STONE]
	for tier in 2:
		var colors := handle.duplicate()
		colors["h"] = heads[tier]
		var base := ICON_BASE + 2 + tier * 4
		_icon(img, base, ICON_PICK, colors)
		_icon(img, base + 1, ICON_AXE, colors)
		_icon(img, base + 2, ICON_SHOVEL, colors)
		_icon(img, base + 3, ICON_SWORD, colors)

	_icon(img, ICON_BASE + 10, ICON_MEAT, {
		"m": Color(0.76, 0.30, 0.26), "M": Color(0.93, 0.52, 0.45), "b": Color(0.93, 0.91, 0.83)})
	_icon(img, ICON_BASE + 11, ICON_FRUIT, {
		"f": Color(0.80, 0.22, 0.48), "F": Color(0.97, 0.60, 0.76), "g": Color(0.30, 0.62, 0.25)})

	return ImageTexture.create_from_image(img)


static func _origin(idx: int) -> Vector2i:
	return Vector2i((idx % ATLAS_TILES) * TILE, floori(idx / float(ATLAS_TILES)) * TILE)


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0))


static func _fill(img: Image, idx: int, base: Color, jitter: float, rng: RandomNumberGenerator) -> void:
	var o := _origin(idx)
	for py in TILE:
		for px in TILE:
			img.set_pixel(o.x + px, o.y + py, _shade(base, 1.0 + rng.randf_range(-jitter, jitter)))


## Stone tile with small clusters of ore-colored pixels.
static func _ore(img: Image, idx: int, ore: Color, rng: RandomNumberGenerator) -> void:
	_fill(img, idx, C_STONE, 0.10, rng)
	var o := _origin(idx)
	for i in 7:
		var cx := rng.randi_range(1, TILE - 3)
		var cy := rng.randi_range(1, TILE - 3)
		for j in 4:
			var px := cx + rng.randi_range(0, 1)
			var py := cy + rng.randi_range(0, 1)
			img.set_pixel(o.x + px, o.y + py, _shade(ore, rng.randf_range(0.85, 1.1)))


## Boards with a dark seam every 4 pixels and staggered joints.
static func _planks(img: Image, idx: int, rng: RandomNumberGenerator) -> void:
	var o := _origin(idx)
	for py in TILE:
		for px in TILE:
			var k := rng.randf_range(0.94, 1.06)
			@warning_ignore("integer_division")
			var board := py / 4
			if py % 4 == 3 or px == (board * 5 + 3) % TILE:
				k *= 0.72
			img.set_pixel(o.x + px, o.y + py, _shade(C_PLANKS, k))


## Paints a character map. Pixels on the lower-right edge of a shape get a darker shade.
static func _icon(img: Image, idx: int, rows: Array, colors: Dictionary) -> void:
	var o := _origin(idx)
	for py in mini(rows.size(), TILE):
		var row: String = rows[py]
		for px in mini(row.length(), TILE):
			var ch := row[px]
			if not colors.has(ch):
				continue
			var below_empty := py + 1 >= rows.size() or px >= (rows[py + 1] as String).length() \
					or not colors.has((rows[py + 1] as String)[px])
			img.set_pixel(o.x + px, o.y + py, _shade(colors[ch], 0.72 if below_empty else 1.0))

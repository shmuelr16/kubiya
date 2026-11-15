extends RefCounted
## Block registry and procedural texture atlas.
## Every texture is generated in code, so the game ships no third-party art.

enum { AIR, GRASS, DIRT, STONE, SAND, WOOD, LEAVES }

const TILE := 16
const ATLAS_TILES := 4

## Atlas tile per face: [top, side, bottom].
const FACES := {
	GRASS: [0, 1, 2],
	DIRT: [2, 2, 2],
	STONE: [3, 3, 3],
	SAND: [4, 4, 4],
	WOOD: [6, 5, 6],
	LEAVES: [7, 7, 7],
}

const C_GRASS := Color(0.36, 0.68, 0.25)
const C_DIRT := Color(0.50, 0.34, 0.20)
const C_STONE := Color(0.52, 0.53, 0.56)
const C_SAND := Color(0.87, 0.80, 0.56)
const C_WOOD := Color(0.45, 0.31, 0.17)
const C_LEAVES := Color(0.20, 0.48, 0.18)


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

	# Grass side: dirt with a ragged green cap.
	_fill(img, 1, C_DIRT, 0.14, rng)
	var o := _origin(1)
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

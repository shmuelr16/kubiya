extends RefCounted
## Item registry. Ids below 100 are blocks (same id as in blocks.gd).
## Ids from 100 are items that cannot be placed.

const Blocks := preload("res://scripts/blocks.gd")

const STICK := 100
const COAL_LUMP := 101
const WOOD_PICK := 102
const WOOD_AXE := 103
const WOOD_SHOVEL := 104
const WOOD_SWORD := 105
const STONE_PICK := 106
const STONE_AXE := 107
const STONE_SHOVEL := 108
const STONE_SWORD := 109
const MEAT := 110
const FRUIT := 111

const STACK := 64
const DURABILITY: PackedInt32Array = [0, 60, 132]
const SPEED: PackedFloat32Array = [1.0, 3.0, 5.0]


static func is_block(id: int) -> bool:
	return id > 0 and id < 100


static func is_tool_item(id: int) -> bool:
	return id >= WOOD_PICK and id <= STONE_SWORD


## 0 none, 1 pickaxe, 2 axe, 3 shovel, 4 sword.
static func tool_type(id: int) -> int:
	return (id - WOOD_PICK) % 4 + 1 if is_tool_item(id) else 0


## 0 none, 1 wood, 2 stone.
static func tool_tier(id: int) -> int:
	@warning_ignore("integer_division")
	return (id - WOOD_PICK) / 4 + 1 if is_tool_item(id) else 0


## Hunger points restored by eating the item. 0: not food.
static func food_points(id: int) -> int:
	match id:
		MEAT:
			return 6
		FRUIT:
			return 3
	return 0


## Damage of one hit on a creature with the item in hand.
static func attack_damage(id: int) -> int:
	match tool_type(id):
		0:
			return 1
		4:
			return 3 + tool_tier(id)
	return 2


static func max_durability(id: int) -> int:
	return DURABILITY[tool_tier(id)]


static func max_stack(id: int) -> int:
	return 1 if is_tool_item(id) else STACK


## Seconds to mine a block with the held item. Negative: cannot be broken.
static func mine_time(block: int, held: int) -> float:
	var h := Blocks.HARDNESS[block]
	if h < 0.0:
		return -1.0
	var type := tool_type(held)
	if type != 0 and type == Blocks.TOOL[block]:
		return h / SPEED[tool_tier(held)]
	return h


## What a mined block drops: [item id, count], or [] for nothing.
static func drop_for(block: int, held: int) -> Array:
	var tier := tool_tier(held) if tool_type(held) == 1 else 0
	if Blocks.MIN_TIER[block] > tier:
		return []
	match block:
		Blocks.AIR, Blocks.WATER, Blocks.BEDROCK:
			return []
		Blocks.GRASS:
			return [Blocks.DIRT, 1]
		Blocks.COAL:
			return [COAL_LUMP, 1]
		Blocks.LEAVES:
			var roll := randf()
			if roll < 0.2:
				return [STICK, 1]
			return [FRUIT, 1] if roll < 0.32 else []
	return [block, 1]


static func icon_tile(id: int) -> int:
	if is_block(id):
		return Blocks.TILE_OF[id * 3 + 1]
	return Blocks.ICON_BASE + id - STICK


## Atlas region of the item icon, in pixels.
static func icon_region(id: int) -> Rect2:
	var t := icon_tile(id)
	@warning_ignore("integer_division")
	return Rect2((t % Blocks.ATLAS_TILES) * Blocks.TILE, (t / Blocks.ATLAS_TILES) * Blocks.TILE,
			Blocks.TILE, Blocks.TILE)


## Draws an item stack inside a slot rectangle: icon, count, durability bar.
static func draw_stack(ci: CanvasItem, atlas: Texture2D, rect: Rect2, id: int, count: int, dur: int) -> void:
	if id == 0 or count <= 0 or atlas == null:
		return
	ci.draw_texture_rect_region(atlas, rect.grow(-rect.size.x * 0.14), icon_region(id))
	if count > 1:
		var font := ThemeDB.fallback_font
		var text := str(count)
		var fs := int(rect.size.x * 0.34)
		var pos := Vector2(rect.position.x, rect.end.y - 5.0)
		ci.draw_string(font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 5.0, fs, Color(0, 0, 0, 0.85))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 5.0, fs, Color.WHITE)
	var full := max_durability(id)
	if full > 0 and dur < full:
		var k := clampf(float(dur) / full, 0.0, 1.0)
		var bar := Rect2(rect.position.x + 6.0, rect.end.y - 9.0, rect.size.x - 12.0, 4.0)
		ci.draw_rect(bar, Color(0, 0, 0, 0.8))
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(1.0 - k, k, 0.1))

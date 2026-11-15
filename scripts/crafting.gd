extends RefCounted
## Shaped crafting recipes for the 2x2 and 3x3 grids.
## A recipe matches anywhere in the grid, and also mirrored left to right.

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")

static var _recipes: Array = []


static func recipes() -> Array:
	if not _recipes.is_empty():
		return _recipes
	var s := Items.STICK
	_add(["W"], {"W": Blocks.WOOD}, Blocks.PLANKS, 4)
	_add(["P", "P"], {"P": Blocks.PLANKS}, s, 4)
	_add(["PP", "PP"], {"P": Blocks.PLANKS}, Blocks.WORKBENCH, 1)
	_add(["C", "S"], {"C": Items.COAL_LUMP, "S": s}, Blocks.TORCH, 4)
	_add(["XXX", "X X", "XXX"], {"X": Blocks.STONE}, Blocks.FURNACE, 1)
	for pair: Array in [[Blocks.PLANKS, Items.WOOD_PICK], [Blocks.STONE, Items.STONE_PICK],
			[Items.IRON_INGOT, Items.IRON_PICK]]:
		var key := {"M": pair[0], "S": s}
		var base: int = pair[1]
		_add(["MMM", " S ", " S "], key, base, 1)
		_add(["MM", "MS", " S"], key, base + 1, 1)
		_add(["M", "S", "S"], key, base + 2, 1)
		_add(["M", "M", "S"], key, base + 3, 1)
	return _recipes


static func _add(rows: Array, key: Dictionary, out: int, count: int) -> void:
	var w := (rows[0] as String).length()
	var cells := PackedInt32Array()
	var mirror := PackedInt32Array()
	for row: String in rows:
		for x in w:
			cells.append(key.get(row[x], 0))
			mirror.append(key.get(row[w - 1 - x], 0))
	_recipes.append({"w": w, "h": rows.size(), "cells": cells, "mirror": mirror, "out": out, "count": count})


## grid holds item ids row by row, 3 per row (only the first n x n cells are used).
## Returns [item id, count], or [] when nothing matches.
static func find(grid: PackedInt32Array, n: int) -> Array:
	var x0 := n
	var y0 := n
	var x1 := -1
	var y1 := -1
	for y in n:
		for x in n:
			if grid[y * 3 + x] != 0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return []
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var cells := PackedInt32Array()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells.append(grid[y * 3 + x])
	for r: Dictionary in recipes():
		if r["w"] == w and r["h"] == h and (cells == r["cells"] or cells == r["mirror"]):
			return [r["out"], r["count"]]
	return []

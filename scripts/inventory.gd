extends RefCounted
## Player inventory: 36 slots. Slots 0-8 are the hotbar.
## Each slot holds an item id, a count, and a durability value for tools.

const Items := preload("res://scripts/items.gd")

signal changed

const SIZE := 36
const HOTBAR := 9

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var durs := PackedInt32Array()


func _init() -> void:
	ids.resize(SIZE)
	counts.resize(SIZE)
	durs.resize(SIZE)


## Adds items: tops up matching stacks first, then fills empty slots.
## Returns how many did not fit.
func add(id: int, count: int, dur := -1) -> int:
	if id == 0 or count <= 0:
		return 0
	var cap := Items.max_stack(id)
	if dur < 0:
		dur = Items.max_durability(id)
	if cap > 1:
		for i in SIZE:
			if count > 0 and ids[i] == id and counts[i] < cap:
				var n := mini(count, cap - counts[i])
				counts[i] += n
				count -= n
	for i in SIZE:
		if count > 0 and counts[i] == 0:
			var n := mini(count, cap)
			ids[i] = id
			counts[i] = n
			durs[i] = dur
			count -= n
	changed.emit()
	return count


func can_add(id: int) -> bool:
	var cap := Items.max_stack(id)
	for i in SIZE:
		if counts[i] == 0 or (ids[i] == id and counts[i] < cap):
			return true
	return false


func set_slot(i: int, id: int, count: int, dur: int) -> void:
	if count <= 0:
		id = 0
		count = 0
		dur = 0
	ids[i] = id
	counts[i] = count
	durs[i] = dur
	changed.emit()


## Removes n items from a slot.
func take(i: int, n: int) -> void:
	set_slot(i, ids[i], counts[i] - n, durs[i])


## Wears the tool in a slot by one use. Returns true when it breaks.
func damage(i: int) -> bool:
	if not Items.is_tool_item(ids[i]):
		return false
	durs[i] -= 1
	if durs[i] <= 0:
		set_slot(i, 0, 0, 0)
		return true
	changed.emit()
	return false


func count_of(id: int) -> int:
	var total := 0
	for i in SIZE:
		if ids[i] == id:
			total += counts[i]
	return total


func find(id: int) -> int:
	for i in SIZE:
		if ids[i] == id and counts[i] > 0:
			return i
	return -1

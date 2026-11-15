extends Node
## Every furnace in the world. A furnace keeps working with its screen closed.
## State per furnace cell: input, fuel and output stacks, the fire, the progress.

const Items := preload("res://scripts/items.gd")

const COOK_TIME := 6.0

var drops: Node3D
## Vector3i -> state Dictionary.
var states := {}


static func new_state() -> Dictionary:
	return {
		"in_id": 0, "in_n": 0, "fuel_id": 0, "fuel_n": 0, "out_id": 0, "out_n": 0,
		"burn": 0.0, "burn_total": 0.0, "cook": 0.0,
	}


func state_at(cell: Vector3i) -> Dictionary:
	if not states.has(cell):
		states[cell] = new_state()
	return states[cell]


func _physics_process(delta: float) -> void:
	for s: Dictionary in states.values():
		step(s, delta)


## True when the input can be smelted and the result fits in the output slot.
static func can_smelt(s: Dictionary) -> bool:
	if s["in_n"] <= 0:
		return false
	var result := Items.smelt(s["in_id"])
	if result == 0:
		return false
	return s["out_n"] == 0 or (s["out_id"] == result and s["out_n"] < Items.max_stack(result))


static func step(s: Dictionary, delta: float) -> void:
	var ready := can_smelt(s)
	if s["burn"] <= 0.0 and ready and s["fuel_n"] > 0:
		s["burn_total"] = Items.fuel_time(s["fuel_id"])
		s["burn"] = s["burn_total"]
		s["fuel_n"] -= 1
	if s["burn"] <= 0.0:
		s["cook"] = 0.0
		return
	s["burn"] = maxf(s["burn"] - delta, 0.0)
	if not ready:
		s["cook"] = 0.0
		return
	s["cook"] += delta
	if s["cook"] >= COOK_TIME:
		s["cook"] = 0.0
		s["out_id"] = Items.smelt(s["in_id"])
		s["out_n"] += 1
		s["in_n"] -= 1


## The furnace block was mined: its contents fall out.
func remove(cell: Vector3i) -> void:
	if not states.has(cell):
		return
	var s: Dictionary = states[cell]
	var at := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	for slot: String in ["in", "fuel", "out"]:
		if s[slot + "_n"] > 0 and drops != null:
			drops.spawn(at, s[slot + "_id"], s[slot + "_n"])
	states.erase(cell)


func to_save() -> Array:
	var out := []
	for cell: Vector3i in states:
		var s: Dictionary = states[cell].duplicate()
		s["cell"] = [cell.x, cell.y, cell.z]
		out.append(s)
	return out


func from_save(list: Array) -> void:
	states.clear()
	for entry: Dictionary in list:
		var c: Array = entry["cell"]
		var s := new_state()
		for key: String in s:
			var v: Variant = entry.get(key, s[key])
			s[key] = float(v) if s[key] is float else int(v)
		states[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = s

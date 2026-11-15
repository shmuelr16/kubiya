extends Node
## Automated play test. Drives the game through real touch events, so it covers
## the touch UI, the player, mining, item drops, the inventory and crafting
## screens, tools, placing, re-meshing, swimming and audio.
## Run: godot --path . -- --selftest=/tmp/kubiya   (writes /tmp/kubiya_*.png)

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")
const Crafting := preload("res://scripts/crafting.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Mesher := preload("res://scripts/mesher.gd")
const Mobs := preload("res://scripts/mobs.gd")
const Furnaces := preload("res://scripts/furnaces.gd")
const SaveGame := preload("res://scripts/savegame.gd")
const Menu := preload("res://scripts/menu.gd")

var main: Node3D
var path := ""
var failed := 0
var _xf: Transform2D
var _finger := 10


func _ready() -> void:
	_run()


func _run() -> void:
	main.set_input_enabled(false)
	var w: Node3D = main.world
	var p: Node3D = main.player
	var it: Node3D = main.interaction
	var t: Control = main.touch
	var hb: Control = main.hotbar
	var inv: RefCounted = main.inventory
	var ui: Control = main.inventory_ui
	var drops: Node3D = main.drops
	var dn: Node3D = main.daynight
	var mobs: Node3D = main.mobs
	_xf = get_viewport().get_final_transform()
	# Fixed noon and no wild creatures, until the sections that test them.
	mobs.auto_spawn = false
	dn.paused = true
	dn.set_time(0.25)

	_rules()
	_light_rules()

	await _until(func() -> bool: return w.is_idle() and not p.frozen, 90.0)
	await _wait(0.6)
	_check("spawn_on_floor", p.on_floor, "pos=%s" % p.position)
	_check("audio_synthesised", main.audio.streams.size() == 10, "streams=%d" % main.audio.streams.size())
	_check("inventory_starts_empty", inv.count_of(Blocks.DIRT) == 0 and hb.selected_id() == 0)

	# Joystick: push forward for a second.
	var start: Vector3 = p.position
	var home: Vector2 = t.stick_home()
	_touch(0, home, true)
	for i in 10:
		_drag(0, home + Vector2(0, -9.0 * (i + 1)), Vector2(0, -9))
		await _frame()
	await _wait(1.2)
	_touch(0, home + Vector2(0, -90), false)
	await _frame()
	var moved := Vector2(p.position.x - start.x, p.position.z - start.z).length()
	_check("touch_joystick_moves", moved > 1.0 and t.active, "moved=%.2f" % moved)
	_check("joystick_releases", t.move == Vector2.ZERO)

	# Look: drag on the right side.
	var pitch0: float = p.cam.rotation.x
	var yaw0: float = p.rotation.y
	var look_at := Vector2(t.size.x * 0.6, t.size.y * 0.3)
	_touch(1, look_at, true)
	for i in 10:
		_drag(1, look_at + Vector2(12, 8) * (i + 1), Vector2(12, 8))
		await _frame()
	_touch(1, look_at + Vector2(120, 80), false)
	await _frame()
	_check("touch_look", p.cam.rotation.x < pitch0 - 0.2 and absf(p.rotation.y - yaw0) > 0.3,
			"pitch %.2f -> %.2f, yaw %.2f -> %.2f" % [pitch0, p.cam.rotation.x, yaw0, p.rotation.y])

	# Jump button.
	await _until(func() -> bool: return p.on_floor, 4.0)
	var y0: float = p.position.y
	var top := y0
	_touch(2, t.button_pos("jump"), true)
	for i in 30:
		await _frame()
		top = maxf(top, p.position.y)
	_touch(2, t.button_pos("jump"), false)
	_check("touch_jump", top > y0 + 1.0, "rise=%.2f" % (top - y0))
	await _until(func() -> bool: return p.on_floor, 4.0)
	_check("gravity_lands", p.on_floor and absf(p.position.y - roundf(p.position.y)) < 0.01, "y=%.3f" % p.position.y)

	# Mine the block under the feet with a long press.
	# Stand on the middle of a block first, so that exactly one block holds the player up.
	var fy := floori(p.position.y) - 1
	for dz: int in [0, -1, 1]:
		for dx: int in [0, -1, 1]:
			var bx := floori(p.position.x) + dx
			var bz := floori(p.position.z) + dz
			if w.is_solid(bx, fy, bz) and not w.is_solid(bx, fy + 1, bz) and not w.is_solid(bx, fy + 2, bz):
				p.position.x = bx + 0.5
				p.position.z = bz + 0.5
	y0 = p.position.y
	p.cam.rotation.x = -1.5
	await _frames(3)
	var cell: Vector3i = it.target
	var before: int = w.get_block(cell.x, cell.y, cell.z)
	_check("highlight_on_target", it.has_target and it._highlight.visible, "target=%s block=%d" % [cell, before])
	_touch(3, t.button_pos("mine"), true)
	var max_stage := -1
	var shot_done := false
	var max_drops := 0
	var t0 := Time.get_ticks_msec()
	while w.get_block(cell.x, cell.y, cell.z) != Blocks.AIR and Time.get_ticks_msec() - t0 < 8000:
		await _frame()
		max_stage = maxi(max_stage, it.crack_stage)
		if it.crack_stage >= 5 and not shot_done:
			shot_done = true
			main.save_png_now(path + "_crack.png")
	var mine_ms := Time.get_ticks_msec() - t0
	_touch(3, t.button_pos("mine"), false)
	max_drops = drops.list.size()
	_check("mine_long_press", w.get_block(cell.x, cell.y, cell.z) == Blocks.AIR, "took %d ms" % mine_ms)
	_check("mine_is_not_instant", mine_ms > 300, "took %d ms" % mine_ms)
	_check("crack_grows", max_stage >= 5 and it.crack_stage == -1, "max stage=%d" % max_stage)
	_check("block_drops_item", max_drops == 1 and drops.list[0].id == Blocks.DIRT, "drops=%d" % max_drops)
	await _until(func() -> bool: return w.is_idle(), 5.0)
	_check("remesh_after_edit", w.is_idle())
	await _until(func() -> bool: return p.on_floor, 4.0)
	_check("falls_into_hole", p.position.y < y0 - 0.5, "y %.1f -> %.1f" % [y0, p.position.y])
	await _until(func() -> bool: return drops.list.is_empty(), 4.0)
	_check("item_collected", drops.list.is_empty() and inv.count_of(Blocks.DIRT) == 1 and inv.ids[0] == Blocks.DIRT,
			"dirt=%d" % inv.count_of(Blocks.DIRT))

	# Standing in the hole and looking down: the only free cell overlaps the player.
	var feet: Vector3i = it.place_cell
	await _hold("place", 3)
	_check("no_place_inside_player", w.get_block(feet.x, feet.y, feet.z) == Blocks.AIR and inv.count_of(Blocks.DIRT) == 1)

	# Place the dirt against the wall of the hole. It leaves the inventory.
	var spot := await _aim_at_free_cell()
	await _hold("place", 3)
	_check("place_block", w.get_block(spot.x, spot.y, spot.z) == Blocks.DIRT)
	_check("placing_uses_item", inv.count_of(Blocks.DIRT) == 0)
	await _hold("place", 3)
	await _frames(20)
	_check("no_place_with_empty_hand", inv.count_of(Blocks.DIRT) == 0 and hb.selected_id() == 0)

	# Inventory screen, 2x2: wood -> planks -> workbench.
	inv.add(Blocks.WOOD, 3)
	await _tap(t.bag_pos())
	_check("bag_button_opens_2x2", ui.visible and ui.grid_n == 2 and p.ui_open and not t.enabled)
	await _tap(ui.inv_rect(0).get_center())
	_check("pick_up_stack", ui.held_id == Blocks.WOOD and ui.held_count == 3 and inv.counts[0] == 0)
	await _tap(ui.craft_rect(0, 0).get_center())
	_check("craft_cell_takes_one", ui.g_counts[0] == 1 and ui.held_count == 2)
	_check("recipe_planks", ui.result == [Blocks.PLANKS, 4], str(ui.result))
	await _tap(ui.result_rect().get_center())
	_check("craft_planks", inv.count_of(Blocks.PLANKS) == 4 and ui.g_counts[0] == 0 and ui.result.is_empty())
	await _tap(ui.inv_rect(20).get_center())
	_check("put_down_stack", inv.ids[20] == Blocks.WOOD and inv.counts[20] == 2 and ui.held_count == 0)
	await _tap(ui.inv_rect(inv.find(Blocks.PLANKS)).get_center())
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		await _tap(ui.craft_rect(c.x, c.y).get_center())
	_check("recipe_workbench", ui.result == [Blocks.WORKBENCH, 1] and ui.held_count == 0, str(ui.result))
	await main.save_png(path + "_inventory.png")
	await _tap(ui.result_rect().get_center())
	await _tap(ui.close_rect().get_center())
	_check("close_button", not ui.visible and not p.ui_open and t.enabled)
	_check("craft_workbench", inv.count_of(Blocks.WORKBENCH) == 1 and inv.count_of(Blocks.PLANKS) == 0
			and inv.count_of(Blocks.WOOD) == 2)

	# Close with items on the grid and in the hand: they return to the inventory.
	await _tap(t.bag_pos())
	await _tap(ui.inv_rect(20).get_center())
	await _tap(ui.craft_rect(1, 1).get_center())
	await _tap(ui.close_rect().get_center())
	_check("close_returns_items", inv.count_of(Blocks.WOOD) == 2 and ui.held_count == 0, "wood=%d" % inv.count_of(Blocks.WOOD))

	# Place the workbench, then use it: the 3x3 grid opens.
	var bench_slot: int = inv.find(Blocks.WORKBENCH)
	await _tap(hb.slot_rect(bench_slot).get_center())
	_check("hotbar_tap_selects", hb.selected == bench_slot and hb.selected_id() == Blocks.WORKBENCH)
	spot = await _aim_at_free_cell()
	await _hold("place", 3)
	_check("place_workbench", w.get_block(spot.x, spot.y, spot.z) == Blocks.WORKBENCH and inv.count_of(Blocks.WORKBENCH) == 0)
	await _frames(25)
	_check("aiming_at_workbench", it.has_target and it.target == spot, "target=%s spot=%s" % [it.target, spot])
	await _hold("place", 3)
	_check("workbench_opens_3x3", ui.visible and ui.grid_n == 3)

	# 3x3: craft sticks and a wooden pickaxe by taps.
	inv.add(Blocks.PLANKS, 5)
	var planks: int = inv.find(Blocks.PLANKS)
	await _tap(ui.inv_rect(planks).get_center())
	await _tap(ui.craft_rect(1, 0).get_center())
	await _tap(ui.craft_rect(1, 1).get_center())
	_check("recipe_sticks", ui.result == [Items.STICK, 4], str(ui.result))
	await _tap(ui.result_rect().get_center())
	for x in 3:
		await _tap(ui.craft_rect(x, 0).get_center())
	_check("planks_all_used", ui.held_count == 0, "held=%d" % ui.held_count)
	await _tap(ui.inv_rect(inv.find(Items.STICK)).get_center())
	await _tap(ui.craft_rect(1, 1).get_center())
	await _tap(ui.craft_rect(1, 2).get_center())
	_check("recipe_wood_pick", ui.result == [Items.WOOD_PICK, 1], str(ui.result))
	await main.save_png(path + "_workbench.png")
	await _tap(ui.result_rect().get_center())
	await _tap(ui.close_rect().get_center())
	_check("craft_wood_pick", inv.count_of(Items.WOOD_PICK) == 1 and inv.count_of(Items.STICK) == 2,
			"pick=%d sticks=%d" % [inv.count_of(Items.WOOD_PICK), inv.count_of(Items.STICK)])

	# Mine the workbench with the pickaxe in hand: the tool wears, the block comes back as an item.
	var pick: int = inv.find(Items.WOOD_PICK)
	_check("pick_in_hotbar", pick >= 0 and pick < 9, "slot=%d" % pick)
	await _tap(hb.slot_rect(pick).get_center())
	await _frames(3)
	_touch(3, t.button_pos("mine"), true)
	await _until(func() -> bool: return w.get_block(spot.x, spot.y, spot.z) == Blocks.AIR, 8.0)
	_touch(3, t.button_pos("mine"), false)
	_check("tool_wears", inv.durs[pick] == Items.max_durability(Items.WOOD_PICK) - 1, "dur=%d" % inv.durs[pick])
	# The block may lie out of pickup range: either a drop exists or it was collected.
	await _frames(5)
	var lying: int = drops.list.filter(func(d: Object) -> bool: return d.id == Blocks.WORKBENCH).size()
	_check("mined_block_drops_itself", lying + inv.count_of(Blocks.WORKBENCH) == 1,
			"lying=%d held=%d" % [lying, inv.count_of(Blocks.WORKBENCH)])

	# A tool cannot be placed as a block.
	await _hold("place", 3)
	_check("tool_is_not_placed", inv.count_of(Items.WOOD_PICK) == 1)

	# Torch: not solid, has its own mesh, falls when its support is mined.
	inv.add(Blocks.TORCH, 1)
	await _tap(hb.slot_rect(inv.find(Blocks.TORCH)).get_center())
	spot = await _aim_at_free_cell()
	await _hold("place", 3)
	_check("place_torch", w.get_block(spot.x, spot.y, spot.z) == Blocks.TORCH and not w.is_solid(spot.x, spot.y, spot.z))
	var torch_view := [p.position, p.rotation.y, p.cam.rotation.x]
	await _until(func() -> bool: return w.is_idle(), 5.0)
	await _frames(3)
	await main.save_png(path + "_torch.png")

	# Swimming: drop into the sea.
	var sea := _find_sea(floori(p.position.x), floori(p.position.z))
	p.frozen = true
	p.position = Vector3(sea.x + 0.5, Terrain.SEA + 1.2, sea.y + 0.5)
	p.vel = Vector3.ZERO
	await _until(func() -> bool: return w.get_block(sea.x, 0, sea.y) != -1, 60.0)
	p.frozen = false
	await _wait(1.5)
	_check("sinks_slowly_in_water", p.in_water and p.vel.y >= -p.SINK - 0.01,
			"y=%.2f vel=%.2f" % [p.position.y, p.vel.y])
	var deep: float = p.position.y
	_touch(6, t.button_pos("jump"), true)
	await _wait(1.2)
	_touch(6, t.button_pos("jump"), false)
	_check("swims_up", p.position.y > deep + 1.0, "y %.2f -> %.2f" % [deep, p.position.y])

	await _wait(2.0)
	_check("music_plays", main.audio.notes_played >= 3, "notes=%d" % main.audio.notes_played)

	# --- Day and night ---
	p.position = p.spawn_point
	p.vel = Vector3.ZERO
	await _until(func() -> bool: return p.on_floor, 4.0)
	dn.set_time(0.25)
	_check("noon_is_bright", dn.daylight > 0.95 and not dn.is_night(), "daylight=%.2f" % dn.daylight)
	dn.set_time(0.75)
	_check("midnight_is_dark", dn.daylight < 0.2 and dn.is_night(), "daylight=%.2f" % dn.daylight)
	dn.paused = false
	var clock: float = dn.time
	await _wait(0.5)
	_check("clock_runs", dn.time > clock, "%.5f -> %.5f" % [clock, dn.time])
	dn.paused = true
	# Midnight: look up at the moon and stars.
	dn.set_time(0.75)
	var moon: Vector3 = -Vector3(1, 0, 0).rotated(dn.AXIS, dn.time * TAU)
	p.rotation.y = atan2(-moon.x, -moon.z)
	p.cam.rotation.x = asin(moon.y) - 0.25
	await _frames(4)
	await main.save_png(path + "_night.png")
	# Still midnight: the torch placed earlier lights the ground around it.
	p.frozen = true
	p.position = torch_view[0]
	p.rotation.y = torch_view[1]
	p.cam.rotation.x = torch_view[2]
	await _frames(4)
	await main.save_png(path + "_torchlight.png")
	p.frozen = false
	p.position = p.spawn_point
	await _until(func() -> bool: return p.on_floor, 4.0)
	# Just after sunrise: look east.
	dn.set_time(0.035)
	p.rotation.y = -PI / 2.0
	p.cam.rotation.x = 0.12
	await _frames(4)
	await main.save_png(path + "_sunrise.png")
	dn.set_time(0.25)

	# --- Health and hunger ---
	p.health = p.MAX_HEALTH
	p.position.y += 12.0
	await _wait(0.3)
	await _until(func() -> bool: return p.on_floor, 5.0)
	_check("fall_damage", is_equal_approx(p.health, 11.0), "health=%.1f after a 12 block fall" % p.health)
	p.hunger = p.MAX_HUNGER
	for i in 600:
		p.stats_step(0.1)
	_check("hunger_drains", p.hunger < 19.0, "hunger=%.2f after 60 s" % p.hunger)
	_check("full_stomach_heals", p.health > 11.0, "health=%.1f" % p.health)
	p.hunger = 0.0
	p.health = 5.0
	for i in 100:
		p.stats_step(0.1)
	_check("starving_hurts", is_equal_approx(p.health, 3.0), "health=%.1f after 10 s" % p.health)
	for i in 400:
		p.stats_step(0.1)
	_check("starving_stops_at_one", is_equal_approx(p.health, 1.0) and p.deaths == 0, "health=%.1f" % p.health)

	inv.add(Items.MEAT, 2)
	await _tap(hb.slot_rect(inv.find(Items.MEAT)).get_center())
	p.hunger = 10.0
	await _hold("place", 3)
	_check("eating_feeds", absf(p.hunger - 16.0) < 0.1 and inv.count_of(Items.MEAT) == 1, "hunger=%.1f" % p.hunger)
	p.hunger = p.MAX_HUNGER
	await _frames(20)
	await _hold("place", 3)
	_check("no_eating_when_full", inv.count_of(Items.MEAT) == 1)

	p.position += Vector3(3, 0, 0)
	p.hurt(100.0)
	_check("death_respawns", p.deaths == 1 and p.health == p.MAX_HEALTH and p.position.distance_to(p.spawn_point) < 0.01)
	await _until(func() -> bool: return p.on_floor, 4.0)

	# --- Creatures ---
	var ahead := _flat_direction()
	p.rotation.y = atan2(-ahead.x, -ahead.z)
	p.cam.rotation.x = 0.0
	var dundle: Object = mobs.spawn(Mobs.DUNDLE, p.position + ahead * 2.2 + Vector3(0, 0.2, 0))
	dundle.think = 30.0
	await _wait(0.8)
	await _until(func() -> bool: return dundle.on_floor, 4.0)
	_check("creature_stands_on_ground", dundle.on_floor and mobs.list.size() == 1, "pos=%s" % dundle.pos)
	inv.add(Items.STONE_SWORD, 1)
	var sword: int = inv.find(Items.STONE_SWORD)
	await _tap(hb.slot_rect(sword).get_center())
	_aim(dundle.pos + Vector3(0, 0.5, 0))
	await _frames(2)
	_touch(3, t.button_pos("mine"), true)
	await _frames(4)
	_touch(3, t.button_pos("mine"), false)
	_check("sword_hits_creature", is_equal_approx(dundle.hp, 5.0), "hp=%.0f" % dundle.hp)
	_check("passive_flees_when_hit", dundle.flee > 0.0 and dundle.flash > 0.0)
	_check("sword_wears", inv.durs[sword] == Items.max_durability(Items.STONE_SWORD) - 1)
	var before_drops: int = drops.list.size()
	mobs.hurt(dundle, 99.0, Vector3.FORWARD)
	_check("creature_dies_and_drops", mobs.list.is_empty() and drops.list.size() == before_drops + 1
			and drops.list[-1].id == Items.MEAT and drops.list[-1].count == 2)

	# One of each, for a picture.
	for i in 4:
		mobs.spawn(i, p.position + Vector3(-2.4 + i * 1.6, 1.2, -3.2))
	p.cam.rotation.x = -0.22
	p.frozen = true
	await _wait(0.5)
	await main.save_png(path + "_creatures.png")
	p.frozen = false
	for m: Object in mobs.list.duplicate():
		mobs._remove(m)

	# A night creature chases and strikes.
	dn.set_time(0.75)
	p.health = p.MAX_HEALTH
	var gloomer: Object = mobs.spawn(Mobs.GLOOMER, p.position + Vector3(0, 1.5, -6.0))
	var far := 6.0
	await _wait(1.2)
	var near: float = Vector2(gloomer.pos.x - p.position.x, gloomer.pos.z - p.position.z).length()
	_check("hostile_chases", gloomer.chasing and near < far - 1.5, "distance %.1f -> %.1f" % [far, near])
	await _until(func() -> bool: return p.health < p.MAX_HEALTH, 10.0)
	_check("hostile_strikes", is_equal_approx(p.health, p.MAX_HEALTH - Mobs.DAMAGE[Mobs.GLOOMER]), "health=%.0f" % p.health)
	mobs._remove(gloomer)

	# Natural spawning: night creatures at night, gone by day; grazers by day.
	p.frozen = true
	for i in 60:
		mobs.spawn_tick()
	p.frozen = false
	_check("frozen_player_spawns_nothing", mobs.list.is_empty())
	var chasers := 0
	for i in 60:
		mobs.spawn_tick()
	chasers = mobs.count(true)
	_check("night_spawns_hostiles", chasers > 0 and chasers <= Mobs.MAX_HOSTILE and mobs.count(false) == 0, "hostile=%d" % chasers)
	dn.set_time(0.25)
	for i in 60:
		mobs.spawn_tick()
	_check("hostiles_dissolve_by_day", mobs.count(true) == 0, "hostile=%d" % mobs.count(true))
	_check("day_spawns_passives", mobs.count(false) > 0 and mobs.count(false) <= Mobs.MAX_PASSIVE, "passive=%d" % mobs.count(false))
	for m: Object in mobs.list.duplicate():
		mobs._remove(m)

	# --- Furnace screen ---
	var fcell := Vector3i(3, 200, 3)
	var fs: Dictionary = main.furnaces.state_at(fcell)
	inv.add(Blocks.IRON, 2)
	inv.add(Items.COAL_LUMP, 1)
	main.open_furnace(fcell)
	_check("furnace_screen_opens", ui.visible and ui.grid_n == 0)
	await _tap(ui.inv_rect(inv.find(Blocks.WOOD)).get_center())
	await _tap(ui.furnace_rect("fuel").get_center())
	_check("wood_is_fuel", fs["fuel_id"] == Blocks.WOOD and fs["fuel_n"] == 2 and ui.held_count == 0)
	await _tap(ui.furnace_rect("fuel").get_center())
	await _tap(ui.inv_rect(30).get_center())
	await _tap(ui.inv_rect(inv.find(Items.STICK)).get_center())
	await _tap(ui.furnace_rect("in").get_center())
	_check("furnace_rejects_unsmeltable", fs["in_n"] == 0 and ui.held_id == Items.STICK)
	await _tap(ui.inv_rect(31).get_center())
	await _tap(ui.inv_rect(inv.find(Blocks.IRON)).get_center())
	await _tap(ui.furnace_rect("in").get_center())
	await _tap(ui.inv_rect(inv.find(Items.COAL_LUMP)).get_center())
	await _tap(ui.furnace_rect("fuel").get_center())
	# The fire may already have taken the coal.
	_check("furnace_loaded", fs["in_id"] == Blocks.IRON and fs["in_n"] == 2 and fs["fuel_id"] == Items.COAL_LUMP
			and (fs["fuel_n"] == 1 or fs["burn"] > 0.0))
	for i in 40:
		Furnaces.step(fs, 0.1)
	await _frames(2)
	await main.save_png(path + "_furnace.png")
	_check("furnace_burns", fs["burn"] > 0.0 and fs["fuel_n"] == 0 and fs["cook"] > 3.0, "burn=%.1f cook=%.1f" % [fs["burn"], fs["cook"]])
	for i in 90:
		Furnaces.step(fs, 0.1)
	_check("furnace_smelts", fs["out_id"] == Items.IRON_INGOT and fs["out_n"] == 2 and fs["in_n"] == 0, "out=%d" % fs["out_n"])
	await _tap(ui.furnace_rect("out").get_center())
	_check("take_from_furnace", inv.count_of(Items.IRON_INGOT) == 2 and fs["out_n"] == 0)
	await _tap(ui.close_rect().get_center())
	fs["in_id"] = Blocks.IRON
	fs["in_n"] = 3
	var lying_before: int = drops.list.size()
	main.furnaces.remove(fcell)
	_check("mined_furnace_spills", drops.list.size() == lying_before + 1 and not main.furnaces.states.has(fcell))

	# --- Pause menu ---
	main.pause_game()
	_check("pause_stops_the_game", get_tree().paused and main.menu.mode == Menu.PAUSE and main.menu.visible)
	await _frames(3)
	await main.save_png(path + "_pause.png")
	main.resume_game()
	_check("resume_continues", not get_tree().paused and main.menu.mode == Menu.HIDDEN)

	# --- Save and load ---
	var dir := "user://selftest_world"
	SaveGame.erase(dir)
	_check("no_save_yet", not SaveGame.exists(dir) and SaveGame.read(dir).is_empty())
	_check("saving_off_in_tests", not main.save_game())
	main.save_dir = dir
	main.save_enabled = true
	main.furnaces.state_at(Vector3i(1, 2, 3))["fuel_n"] = 5
	_check("save_writes", main.save_game() and SaveGame.exists(dir))
	main.save_enabled = false
	var loaded := SaveGame.read(dir)
	var meta: Dictionary = loaded.get("meta", {})
	_check("save_keeps_seed_and_clock", int(meta.get("seed", -1)) == w.world_seed and is_equal_approx(meta["time"], dn.time))
	var saved_pos: Array = meta["player"]["pos"]
	_check("save_keeps_player", Vector3(saved_pos[0], saved_pos[1], saved_pos[2]).distance_to(p.position) < 0.001
			and is_equal_approx(meta["player"]["health"], p.health) and int(meta["player"]["deaths"]) == 1)
	var same_items := true
	for i in inv.SIZE:
		same_items = same_items and int(meta["inventory"]["ids"][i]) == inv.ids[i] \
				and int(meta["inventory"]["counts"][i]) == inv.counts[i] and int(meta["inventory"]["durs"][i]) == inv.durs[i]
	_check("save_keeps_inventory", same_items and inv.count_of(Items.IRON_INGOT) == 2)
	var edits: Dictionary = w.edits()
	var same_chunks: bool = loaded["modified"].size() == edits.size() and edits.size() > 0
	for pos: Vector2i in edits:
		same_chunks = same_chunks and loaded["modified"].has(pos) and loaded["modified"][pos][0] == edits[pos][0] \
				and loaded["modified"][pos][1] == edits[pos][1]
	_check("save_keeps_edited_chunks", same_chunks, "chunks=%d" % edits.size())
	var fresh: Node3D = load("res://scripts/world.gd").new()
	fresh.load_edits(loaded["modified"])
	_check("load_finds_torches", fresh._torches.size() == w._torches.size() and w._torches.size() > 0, "chunks with torches=%d" % fresh._torches.size())
	fresh.free()
	var fresh_furnaces: Node = Furnaces.new()
	fresh_furnaces.from_save(meta["furnaces"])
	_check("save_keeps_furnaces", fresh_furnaces.states.has(Vector3i(1, 2, 3)) and fresh_furnaces.states[Vector3i(1, 2, 3)]["fuel_n"] == 5)
	fresh_furnaces.free()
	var broken := FileAccess.open(dir + "/meta.json", FileAccess.WRITE)
	broken.store_string("{ not json")
	broken.close()
	_check("broken_save_is_ignored", SaveGame.read(dir).is_empty())
	SaveGame.erase(dir)
	_check("erase_removes_save", not SaveGame.exists(dir))

	print("SELFTEST %s" % ("ALL PASS" if failed == 0 else "%d FAILED" % failed))
	get_tree().quit(1 if failed > 0 else 0)


## Checks that need no world: recipes, drops, tool speed.
func _rules() -> void:
	var s := Items.STICK
	var pl := Blocks.PLANKS
	var st := Blocks.STONE
	_recipe("recipe_table_planks", [Blocks.WOOD], 3, [pl, 4])
	_recipe("recipe_anywhere_in_grid", [0, 0, 0, 0, 0, 0, 0, 0, Blocks.WOOD], 3, [pl, 4])
	_recipe("recipe_table_sticks", [pl, 0, pl], 3, [s, 4])
	_recipe("recipe_table_workbench", [pl, pl, pl, pl], 3, [Blocks.WORKBENCH, 1])
	_recipe("recipe_table_torch", [Items.COAL_LUMP, 0, s], 3, [Blocks.TORCH, 4])
	_recipe("recipe_table_furnace", [st, st, st, st, 0, st, st, st, st], 3, [Blocks.FURNACE, 1])
	_recipe("recipe_wood_axe", [pl, pl, 0, pl, s, 0, 0, s, 0], 3, [Items.WOOD_AXE, 1])
	_recipe("recipe_axe_mirrored", [pl, pl, 0, s, pl, 0, s, 0, 0], 3, [Items.WOOD_AXE, 1])
	_recipe("recipe_wood_shovel", [pl, 0, 0, s, 0, 0, s, 0, 0], 3, [Items.WOOD_SHOVEL, 1])
	_recipe("recipe_wood_sword", [0, pl, 0, 0, pl, 0, 0, s, 0], 3, [Items.WOOD_SWORD, 1])
	_recipe("recipe_stone_pick", [st, st, st, 0, s, 0, 0, s, 0], 3, [Items.STONE_PICK, 1])
	_recipe("recipe_stone_axe", [st, st, 0, st, s, 0, 0, s, 0], 3, [Items.STONE_AXE, 1])
	_recipe("recipe_stone_shovel", [0, 0, st, 0, 0, s, 0, 0, s], 3, [Items.STONE_SHOVEL, 1])
	_recipe("recipe_stone_sword", [st, 0, 0, st, 0, 0, s, 0, 0], 3, [Items.STONE_SWORD, 1])
	_recipe("recipe_wrong_shape", [pl, 0, 0, pl], 3, [])
	_recipe("recipe_mixed_materials", [pl, st, pl, 0, s, 0, 0, s, 0], 3, [])
	_recipe("recipe_3x3_not_in_2x2", [st, st, st, st, 0, st, st, st, st], 2, [])

	_check("stone_needs_pickaxe", Items.drop_for(st, 0).is_empty() and Items.drop_for(st, Items.WOOD_AXE).is_empty()
			and Items.drop_for(st, Items.WOOD_PICK) == [st, 1])
	_check("iron_needs_stone_pick", Items.drop_for(Blocks.IRON, Items.WOOD_PICK).is_empty()
			and Items.drop_for(Blocks.IRON, Items.STONE_PICK) == [Blocks.IRON, 1])
	_check("grass_drops_dirt", Items.drop_for(Blocks.GRASS, 0) == [Blocks.DIRT, 1])
	_check("coal_drops_lump", Items.drop_for(Blocks.COAL, Items.WOOD_PICK) == [Items.COAL_LUMP, 1])
	var hand := Items.mine_time(st, 0)
	var wood := Items.mine_time(st, Items.WOOD_PICK)
	var stone := Items.mine_time(st, Items.STONE_PICK)
	_check("better_tool_is_faster", stone < wood and wood < hand, "%.2f < %.2f < %.2f" % [stone, wood, hand])
	_check("wrong_tool_no_bonus", Items.mine_time(st, Items.STONE_AXE) == hand
			and Items.mine_time(Blocks.WOOD, Items.STONE_AXE) < Items.mine_time(Blocks.WOOD, 0))
	_check("bedrock_unbreakable", Items.mine_time(Blocks.BEDROCK, Items.STONE_PICK) < 0.0)

	var ig := Items.IRON_INGOT
	_recipe("recipe_iron_pick", [ig, ig, ig, 0, s, 0, 0, s, 0], 3, [Items.IRON_PICK, 1])
	_recipe("recipe_iron_sword", [ig, 0, 0, ig, 0, 0, s, 0, 0], 3, [Items.IRON_SWORD, 1])
	_check("iron_tool_rules", Items.tool_tier(Items.IRON_PICK) == 3 and Items.tool_type(Items.IRON_SWORD) == 4
			and Items.tool_type(Items.IRON_AXE) == 2 and Items.max_durability(Items.IRON_SHOVEL) == 251
			and Items.tool_tier(Items.MEAT) == 0 and not Items.is_tool_item(Items.IRON_INGOT)
			and Items.mine_time(st, Items.IRON_PICK) < stone)
	_check("crystal_needs_iron_pick", Items.drop_for(Blocks.CRYSTAL, Items.STONE_PICK).is_empty()
			and Items.drop_for(Blocks.CRYSTAL, Items.IRON_PICK) == [Blocks.CRYSTAL, 1])
	_check("smelting_table", Items.smelt(Blocks.IRON) == ig and Items.smelt(Items.MEAT) == Items.COOKED_MEAT
			and Items.smelt(Blocks.WOOD) == Items.COAL_LUMP and Items.smelt(Blocks.DIRT) == 0
			and Items.food_points(Items.COOKED_MEAT) > Items.food_points(Items.MEAT))

	var f := Furnaces.new_state()
	f["in_id"] = Blocks.IRON
	f["in_n"] = 2
	for i in 200:
		Furnaces.step(f, 0.1)
	_check("furnace_needs_fuel", f["out_n"] == 0 and f["in_n"] == 2)
	f["fuel_id"] = Items.STICK
	f["fuel_n"] = 1
	for i in 200:
		Furnaces.step(f, 0.1)
	_check("fuel_runs_out", f["out_n"] == 1 and f["in_n"] == 1 and f["burn"] == 0.0 and f["cook"] == 0.0,
			"out=%d after one stick" % f["out_n"])
	f["out_id"] = Items.COAL_LUMP
	f["fuel_n"] = 3
	for i in 200:
		Furnaces.step(f, 0.1)
	_check("furnace_waits_for_free_output", f["out_n"] == 1 and f["fuel_n"] == 3)

	var inv: RefCounted = load("res://scripts/inventory.gd").new()
	var left: int = inv.add(Blocks.DIRT, 70)
	_check("stacks_cap_at_64", left == 0 and inv.counts[0] == 64 and inv.counts[1] == 6)
	inv.add(Items.WOOD_PICK, 2)
	_check("tools_do_not_stack", inv.counts[2] == 1 and inv.counts[3] == 1 and inv.durs[2] == 60)
	left = inv.add(Blocks.STONE, 64 * 40)
	_check("full_inventory_rejects", left == 64 * 40 - 64 * 32 and not inv.can_add(Blocks.STONE) and inv.can_add(Blocks.DIRT),
			"left=%d" % left)


## Light is computed in the mesher. Checked here on small hand-built chunks.
func _light_rules() -> void:
	var open := _slab(false, false)
	var roofed := _slab(true, false)
	var holed := _slab(true, true)
	var m := Mesher.new()
	m.build(open, open, open, open, open, 15)
	_check("open_sky_is_full_light", m.sl[_ci(8, 12, 8)] == 15 and m.sl[_ci(0, 11, 0)] == 15)

	m = Mesher.new()
	m.build(roofed, roofed, roofed, roofed, roofed, 15)
	_check("sealed_room_is_dark", m.sl[_ci(8, 12, 8)] == 0 and not m.has_bl)

	m = Mesher.new()
	m.build(holed, roofed, roofed, roofed, roofed, 15)
	_check("light_falls_through_a_hole", m.sl[_ci(8, 12, 8)] == 15, "under hole=%d" % m.sl[_ci(8, 12, 8)])
	_check("light_fades_sideways", m.sl[_ci(10, 12, 8)] == 13 and m.sl[_ci(8, 12, 13)] == 10 and m.sl[_ci(8, 11, 8)] == 15,
			"2 away=%d, 5 away=%d" % [m.sl[_ci(10, 12, 8)], m.sl[_ci(8, 12, 13)]])

	m = Mesher.new()
	m.build(roofed, open, open, open, open, 15)
	_check("light_enters_from_neighbour", m.sl[_ci(0, 12, 8)] == 14 and m.sl[_ci(5, 12, 8)] == 9,
			"edge=%d, 5 in=%d" % [m.sl[_ci(0, 12, 8)], m.sl[_ci(5, 12, 8)]])

	var lit := roofed.duplicate()
	lit[_ci(8, 11, 8)] = Blocks.TORCH
	m = Mesher.new()
	m.build(lit, roofed, roofed, roofed, roofed, 15, PackedInt32Array([8, 11, 8]))
	_check("torch_lights_a_dark_room", m.has_bl and m.bl[_pi(8, 11, 8)] == Mesher.TORCH_LIGHT
			and m.bl[_pi(10, 11, 8)] == Mesher.TORCH_LIGHT - 2 and m.sl[_ci(8, 12, 8)] == 0,
			"at torch=%d, 2 away=%d" % [m.bl[_pi(8, 11, 8)], m.bl[_pi(10, 11, 8)]])
	_check("torch_light_stops_at_walls", m.bl[_pi(8, 5, 8)] == 0 and m.bl[_pi(8, 15, 8)] == 0)

	var neighbour := roofed.duplicate()
	neighbour[_ci(14, 11, 8)] = Blocks.TORCH
	m = Mesher.new()
	m.build(roofed, neighbour, roofed, roofed, roofed, 15, PackedInt32Array([-2, 11, 8]))
	_check("torch_light_crosses_chunks", m.bl[_pi(0, 11, 8)] == Mesher.TORCH_LIGHT - 2, "edge=%d" % m.bl[_pi(0, 11, 8)])
	_check("light_levels_fade_smoothly", m.sky_lut[15] == 1.0 and m.sky_lut[14] < 1.0 and m.sky_lut[0] > 0.0 and m.block_lut[0] == 0.0)


## Test chunk: stone up to y 10, optional stone roof at y 15, optional 1-block hole at (8, 8).
func _slab(roof: bool, hole: bool) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(16 * 16 * 128)
	for c in 256:
		for y in 11:
			d[(c << 7) + y] = Blocks.STONE
		if roof and not (hole and c == 8 + 8 * 16):
			d[(c << 7) + 15] = Blocks.STONE
	return d


func _ci(x: int, y: int, z: int) -> int:
	return ((x + z * 16) << 7) + y


func _pi(x: int, y: int, z: int) -> int:
	return (((x + Mesher.PAD) + (z + Mesher.PAD) * Mesher.PW) << 7) + y


## A direction in which the ground stays level for 3 blocks, for close-range tests.
func _flat_direction() -> Vector3:
	var p: Node3D = main.player
	var w: Node3D = main.world
	var y := floori(p.position.y)
	for i in 8:
		var d := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 4.0)
		var level := true
		for step in range(1, 4):
			var x := floori(p.position.x + d.x * step)
			var z := floori(p.position.z + d.z * step)
			level = level and w.is_solid(x, y - 1, z) and not w.is_solid(x, y, z) and not w.is_solid(x, y + 1, z)
		if level:
			return d
	return Vector3.FORWARD


## Points the camera at a world position.
func _aim(target: Vector3) -> void:
	var p: Node3D = main.player
	var d: Vector3 = (target - p.cam.global_position).normalized()
	p.rotation.y = atan2(-d.x, -d.z)
	p.cam.rotation.x = asin(d.y)


func _recipe(test: String, cells: Array, n: int, expect: Array) -> void:
	var grid := PackedInt32Array()
	grid.resize(9)
	# cells are given for an n-wide grid when shorter than 9, else as the full 3x3.
	if cells.size() == 9:
		for i in 9:
			grid[i] = cells[i]
	else:
		for i in cells.size():
			@warning_ignore("integer_division")
			grid[(i / 2) * 3 + i % 2] = cells[i]
	var got := Crafting.find(grid, n)
	_check(test, got == expect, "got %s" % str(got))


## Turns the view until the targeted face has a free cell the player does not stand in.
func _aim_at_free_cell() -> Vector3i:
	var p: Node3D = main.player
	var it: Node3D = main.interaction
	p.cam.rotation.x = -0.9
	for attempt in 16:
		await _frames(3)
		if it.has_target and not p.intersects_cell(it.place_cell) \
				and main.world.get_block(it.place_cell.x, it.place_cell.y, it.place_cell.z) == Blocks.AIR:
			return it.place_cell
		p.rotate_y(PI / 4.0)
		if attempt % 8 == 7:
			p.cam.rotation.x += 0.25
	return it.place_cell


func _find_sea(x0: int, z0: int) -> Vector2i:
	var terrain: Terrain = main.world.terrain
	for r in range(1, 300):
		for d: Vector2i in [Vector2i(r * 4, 0), Vector2i(-r * 4, 0), Vector2i(0, r * 4), Vector2i(0, -r * 4)]:
			if terrain.height(x0 + d.x, z0 + d.y) < Terrain.SEA - 5:
				return Vector2i(x0 + d.x, z0 + d.y)
	return Vector2i(x0, z0)


func _check(test: String, ok: bool, detail := "") -> void:
	if not ok:
		failed += 1
	print("SELFTEST %-26s %s  %s" % [test, "PASS" if ok else "FAIL", detail])


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _xf * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _xf * pos
	e.relative = _xf.basis_xform(relative)
	Input.parse_input_event(e)


func _tap(pos: Vector2) -> void:
	_finger += 1
	_touch(_finger, pos, true)
	await _frames(2)
	_touch(_finger, pos, false)
	await _frames(2)


## Holds a touch button for a number of frames.
func _hold(button: String, frames: int) -> void:
	var pos: Vector2 = main.touch.button_pos(button)
	_finger += 1
	_touch(_finger, pos, true)
	await _frames(frames)
	_touch(_finger, pos, false)
	await _frames(2)


func _frame() -> void:
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(done: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame

extends Node
## Automated play test. Drives the game through real touch events, so it covers
## the touch UI, the player, mining, placing, re-meshing, swimming and audio.
## Run: godot --path . -- --selftest=/tmp/kubiya   (writes /tmp/kubiya_*.png)

const Blocks := preload("res://scripts/blocks.gd")
const Terrain := preload("res://scripts/terrain.gd")

var main: Node3D
var path := ""
var failed := 0
var _xf: Transform2D


func _ready() -> void:
	_run()


func _run() -> void:
	main.set_input_enabled(false)
	var w: Node3D = main.world
	var p: Node3D = main.player
	var it: Node3D = main.interaction
	var t: Control = main.touch
	var hb: Control = main.hotbar
	_xf = get_viewport().get_final_transform()

	await _until(func() -> bool: return w.is_idle() and not p.frozen, 90.0)
	await _wait(0.6)
	_check("spawn_on_floor", p.on_floor, "pos=%s" % p.position)
	_check("audio_synthesised", main.audio.streams.size() == 7, "streams=%d" % main.audio.streams.size())

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
	var t0 := Time.get_ticks_msec()
	while w.get_block(cell.x, cell.y, cell.z) != Blocks.AIR and Time.get_ticks_msec() - t0 < 8000:
		await _frame()
		max_stage = maxi(max_stage, it.crack_stage)
		if it.crack_stage >= 5 and not shot_done:
			shot_done = true
			await main.save_png(path + "_crack.png")
	var mine_ms := Time.get_ticks_msec() - t0
	_touch(3, t.button_pos("mine"), false)
	_check("mine_long_press", w.get_block(cell.x, cell.y, cell.z) == Blocks.AIR, "took %d ms" % mine_ms)
	_check("mine_is_not_instant", mine_ms > 300, "took %d ms" % mine_ms)
	_check("crack_grows", max_stage >= 5 and it.crack_stage == -1, "max stage=%d" % max_stage)
	await _until(func() -> bool: return w.is_idle(), 5.0)
	_check("remesh_after_edit", w.is_idle())
	await _until(func() -> bool: return p.on_floor, 4.0)
	_check("falls_into_hole", p.position.y < y0 - 0.5, "y %.1f -> %.1f" % [y0, p.position.y])

	# Hotbar: tap the bricks slot.
	var slot := 7
	var tap: Vector2 = hb.slot_rect(slot).get_center()
	_touch(4, tap, true)
	await _frame()
	_touch(4, tap, false)
	await _frame()
	_check("hotbar_tap_selects", hb.selected == slot and hb.selected_id() == Blocks.BRICKS)

	# Standing in the hole and looking down: the only free cell overlaps the player.
	var feet: Vector3i = it.place_cell
	_touch(5, t.button_pos("place"), true)
	await _frames(3)
	_touch(5, t.button_pos("place"), false)
	await _frames(2)
	_check("no_place_inside_player", w.get_block(feet.x, feet.y, feet.z) == Blocks.AIR)

	# Place against the wall of the hole.
	p.cam.rotation.x = -0.9
	var placed := false
	for attempt in 8:
		await _frames(3)
		if it.has_target and not p.intersects_cell(it.place_cell):
			var c: Vector3i = it.place_cell
			_touch(5, t.button_pos("place"), true)
			await _frames(3)
			_touch(5, t.button_pos("place"), false)
			await _frames(2)
			placed = w.get_block(c.x, c.y, c.z) == Blocks.BRICKS
			break
		p.rotate_y(PI / 4.0)
		p.cam.rotation.x += 0.12
	_check("place_block", placed)
	await _until(func() -> bool: return w.is_idle(), 5.0)
	await _frames(3)
	await main.save_png(path + "_placed.png")

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

	await _wait(3.0)
	_check("music_plays", main.audio.notes_played >= 3, "notes=%d" % main.audio.notes_played)

	print("SELFTEST %s" % ("ALL PASS" if failed == 0 else "%d FAILED" % failed))
	get_tree().quit(1 if failed > 0 else 0)


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
	print("SELFTEST %-24s %s  %s" % [test, "PASS" if ok else "FAIL", detail])


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

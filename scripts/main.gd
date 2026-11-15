extends Node3D
## Entry point. Builds the world, player, creatures, audio and screens in code,
## loads and saves the game, and runs the title and pause menus.
##
## Test arguments, passed after `--`. Any of the first six turns saving off.
##   --shot=PATH        wait for the world to load, measure FPS, save a PNG, quit
##   --selftest=PATH    drive the game with simulated touches, print PASS/FAIL, quit
##   --titleshot=PATH   save a PNG of the title screen, quit
##   --e2e=write|read   with --savedir: change the world and save, or load and report
##   --pos=X,Y,Z        hold the camera at a fixed position (no physics)
##   --cave             put the fixed camera inside the nearest cave
##   --savedir=DIR      use another save folder (res:// or user:// path)
##   --look=PITCH,YAW   camera angles in degrees
##   --dist=N           view distance in chunks
##   --fly=SPEED        with --pos: move the camera along +X (blocks per second)
##   --nothreads        force the single-threaded loader (as on web)
##   --time=T           freeze the clock: 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight
##   --nomobs           no natural creature spawning

const Blocks := preload("res://scripts/blocks.gd")
const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Interaction := preload("res://scripts/interaction.gd")
const Hotbar := preload("res://scripts/hotbar.gd")
const TouchUI := preload("res://scripts/touch_ui.gd")
const GameAudio := preload("res://scripts/audio.gd")
const Inventory := preload("res://scripts/inventory.gd")
const InventoryUI := preload("res://scripts/inventory_ui.gd")
const Drops := preload("res://scripts/drops.gd")
const DayNight := preload("res://scripts/daynight.gd")
const Mobs := preload("res://scripts/mobs.gd")
const StatusHUD := preload("res://scripts/status_hud.gd")
const Furnaces := preload("res://scripts/furnaces.gd")
const Menu := preload("res://scripts/menu.gd")
const SaveGame := preload("res://scripts/savegame.gd")
const SelfTest := preload("res://scripts/selftest.gd")

const TEST_SEED := 1337
const AUTOSAVE_PERIOD := 60.0
const HELP := "WASD: move  |  Space: jump / swim  |  Shift: run  |  E: inventory  |  Esc: menu\n" \
		+ "Hold left: mine / hit  |  Right: place / use / eat  |  1-9 / wheel: slot  |  M: music"

## Set before reloading the scene: start a fresh world, and skip the title screen.
static var boot_new_world := false
static var boot_skip_title := false
static var _daylight_registered := false

var world: Node3D
var player: Node3D
var interaction: Node3D
var audio: Node
var hotbar: Control
var inventory: RefCounted
var inventory_ui: Control
var drops: Node3D
var daynight: Node3D
var mobs: Node3D
var furnaces: Node
var status: Control
var menu: Control
var environment: Environment
var touch: Control
var hud: Label
var help: Label
var underwater: ColorRect
var fixed_camera := false
var spawn_xz := Vector2i.ZERO
var fly_speed := 0.0
## False while the title screen is up: the world loads but the game waits.
var started := false
var save_enabled := true
var save_dir := SaveGame.DIR
var saves_written := 0

var _was_captured := false
var _loaded_player := false
var _autosave := AUTOSAVE_PERIOD


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var test_mode := false
	for key: String in ["shot", "selftest", "titleshot", "pos", "cave", "e2e"]:
		test_mode = test_mode or args.has(key)
	if args.has("savedir"):
		save_dir = args["savedir"]
	save_enabled = not test_mode or args.has("savedir")
	get_tree().auto_accept_quit = false

	# Shaders read this global value, so it must exist before any of them compiles.
	# It outlives a scene reload, so it is registered once per run.
	if not _daylight_registered:
		_daylight_registered = true
		RenderingServer.global_shader_parameter_add("daylight", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)

	# Saved game, or a new world.
	var saved := {}
	if save_enabled:
		if boot_new_world:
			SaveGame.erase(save_dir)
		else:
			saved = SaveGame.read(save_dir)
	boot_new_world = false
	var meta: Dictionary = saved.get("meta", {})

	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	inventory = Inventory.new()

	world = World.new()
	world.name = "World"
	if not meta.is_empty():
		world.world_seed = int(meta["seed"])
		world.load_edits(saved["modified"])
	elif test_mode:
		world.world_seed = TEST_SEED
	else:
		world.world_seed = randi() & 0x7fffffff
	if OS.has_feature("web"):
		world.view_dist = 5
	if args.has("dist"):
		world.view_dist = int(args["dist"])
	add_child(world)
	if args.has("nothreads"):
		world.use_threads = false
		world.max_tasks = 1

	player = Player.new()
	player.name = "Player"
	player.world = world
	player.audio = audio
	add_child(player)
	player.cam.far = (world.view_dist + 2) * 16.0

	drops = Drops.new()
	drops.name = "Drops"
	drops.world = world
	drops.player = player
	drops.inventory = inventory
	drops.audio = audio
	drops.atlas = world.atlas
	add_child(drops)

	furnaces = Furnaces.new()
	furnaces.name = "Furnaces"
	furnaces.drops = drops
	add_child(furnaces)

	_build_sky()
	if args.has("time"):
		daynight.set_time(float(args["time"]))
		daynight.paused = true

	mobs = Mobs.new()
	mobs.name = "Mobs"
	mobs.world = world
	mobs.player = player
	mobs.drops = drops
	mobs.audio = audio
	mobs.daynight = daynight
	mobs.auto_spawn = not args.has("nomobs")
	add_child(mobs)

	_build_hud()
	player.touch = touch

	interaction = Interaction.new()
	interaction.name = "Interaction"
	interaction.world = world
	interaction.player = player
	interaction.hotbar = hotbar
	interaction.touch = touch
	interaction.audio = audio
	interaction.inventory = inventory
	interaction.drops = drops
	interaction.mobs = mobs
	interaction.furnaces = furnaces
	interaction.workbench_used.connect(open_inventory.bind(3))
	interaction.furnace_used.connect(open_furnace)
	add_child(interaction)

	if args.has("pos"):
		var p: PackedStringArray = args["pos"].split(",")
		player.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		fixed_camera = true
		fly_speed = float(args.get("fly", "0"))
	elif args.has("cave"):
		player.position = _find_cave()
		fixed_camera = true
	elif not meta.is_empty():
		_apply_save(meta)
	else:
		spawn_xz = _find_land()
		player.position = Vector3(spawn_xz.x + 0.5, 100.0, spawn_xz.y + 0.5)
	if args.has("look"):
		var l: PackedStringArray = args["look"].split(",")
		player.cam.rotation_degrees.x = float(l[0])
		player.rotation_degrees.y = float(l[1])
	world.focus = player.position

	if args.has("selftest"):
		started = true
		var test := SelfTest.new()
		test.main = self
		test.path = args["selftest"]
		add_child(test)
	elif args.has("shot"):
		started = true
		set_input_enabled(false)
		_screenshot(args["shot"])
	elif args.has("e2e"):
		started = true
		set_input_enabled(false)
		mobs.auto_spawn = false
		_e2e(args["e2e"])
	elif args.has("titleshot"):
		_show_title(not meta.is_empty())
		_title_shot(args["titleshot"])
	elif test_mode or boot_skip_title:
		boot_skip_title = false
		started = true
	else:
		_show_title(not meta.is_empty())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()


func set_input_enabled(on: bool) -> void:
	player.input_enabled = on
	hotbar.input_enabled = on
	inventory_ui.input_enabled = on


# --- Title and pause ---

func _show_title(has_save: bool) -> void:
	started = false
	daynight.paused = true
	touch.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.show_title(has_save)


func _on_play() -> void:
	menu.hide_menu()
	started = true
	daynight.paused = false
	touch.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_new_world() -> void:
	boot_new_world = true
	boot_skip_title = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func pause_game() -> void:
	if not started or menu.mode != Menu.HIDDEN or inventory_ui.visible:
		return
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.music_on = audio.music_on
	menu.show_pause()
	get_tree().paused = true


func resume_game() -> void:
	get_tree().paused = false
	menu.hide_menu()
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_music() -> void:
	audio.toggle_music()
	menu.music_on = audio.music_on


func _on_to_title() -> void:
	save_game()
	boot_new_world = false
	boot_skip_title = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit() -> void:
	save_game()
	get_tree().quit()


# --- Save and load ---

## Writes the game to the save folder. Returns false when saving is off or fails.
func save_game() -> bool:
	if not save_enabled or not started or player.frozen:
		return false
	inventory_ui.close()
	var p := player.position
	var meta := {
		"seed": world.world_seed,
		"time": daynight.time,
		"music": audio.music_on,
		"selected": hotbar.selected,
		"player": {
			"pos": [p.x, p.y, p.z],
			"yaw": player.rotation.y,
			"pitch": player.cam.rotation.x,
			"health": player.health,
			"hunger": player.hunger,
			"deaths": player.deaths,
			"spawn": [player.spawn_point.x, player.spawn_point.y, player.spawn_point.z],
		},
		"inventory": {
			"ids": Array(inventory.ids), "counts": Array(inventory.counts), "durs": Array(inventory.durs),
		},
		"furnaces": furnaces.to_save(),
	}
	var ok := SaveGame.write(save_dir, meta, world.edits())
	if ok:
		saves_written += 1
	return ok


func _apply_save(meta: Dictionary) -> void:
	var pl: Dictionary = meta["player"]
	var pos: Array = pl["pos"]
	var spawn: Array = pl["spawn"]
	player.position = Vector3(pos[0], pos[1], pos[2])
	player.rotation.y = pl["yaw"]
	player.cam.rotation.x = pl["pitch"]
	player.health = pl["health"]
	player.hunger = pl["hunger"]
	player.deaths = int(pl["deaths"])
	player.spawn_point = Vector3(spawn[0], spawn[1], spawn[2])
	_loaded_player = true
	var inv: Dictionary = meta["inventory"]
	for i in inventory.SIZE:
		inventory.set_slot(i, int(inv["ids"][i]), int(inv["counts"][i]), int(inv["durs"][i]))
	hotbar.select(int(meta.get("selected", 0)))
	daynight.set_time(float(meta["time"]))
	furnaces.from_save(meta.get("furnaces", []))
	if not bool(meta.get("music", true)):
		audio.toggle_music()


# --- Screens ---

func open_inventory(grid: int) -> void:
	if not _can_open():
		return
	_before_screen()
	inventory_ui.open(grid)


func open_furnace(cell: Vector3i) -> void:
	if not _can_open():
		return
	_before_screen()
	inventory_ui.open_furnace(furnaces.state_at(cell))


func _can_open() -> bool:
	return started and not inventory_ui.visible and not player.frozen and menu.mode == Menu.HIDDEN


func _before_screen() -> void:
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.ui_open = true
	touch.enabled = false


func _on_inventory_closed() -> void:
	player.ui_open = false
	touch.enabled = true
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not player.input_enabled or not started:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				audio.toggle_music()
			KEY_E:
				open_inventory(2)
			KEY_ESCAPE:
				pause_game()


func _process(delta: float) -> void:
	player.position.x += fly_speed * delta
	world.focus = player.position
	if player.frozen and not fixed_camera and started:
		_try_spawn()
	if save_enabled and started:
		_autosave -= delta
		if _autosave <= 0.0:
			_autosave = AUTOSAVE_PERIOD
			save_game()
	var p := player.position
	var eye: Vector3 = player.cam.global_position
	underwater.visible = world.get_block(floori(eye.x), floori(eye.y), floori(eye.z)) == Blocks.WATER
	help.visible = not touch.active and started
	hotbar.visible = started
	status.visible = started
	if touch.bag_pressed:
		touch.bag_pressed = false
		open_inventory(2)
	var hours := fposmod(daynight.time * 24.0 + 6.0, 24.0)
	hud.text = "Kubiya 0.6  |  %d FPS  |  %d chunks  |  %dk quads  |  %d, %d, %d  |  %02d:%02d" % [
		Engine.get_frames_per_second(), world.chunks.size(), world.total_quads / 1000.0,
		floori(p.x), floori(p.y), floori(p.z), int(hours), int(fposmod(hours, 1.0) * 60.0)]


## First dry column east of the origin.
func _find_land() -> Vector2i:
	for i in 400:
		if world.terrain.height(i * 4, 0) > Terrain.SEA + 2:
			return Vector2i(i * 4, 0)
	return Vector2i.ZERO


## Test helper: an open cave cell with headroom, facing down the tunnel.
func _find_cave() -> Vector3:
	var t: Terrain = world.terrain
	for x in range(0, 400):
		for y in range(20, 40):
			if t.carved(x, y, 0) and t.carved(x, y + 1, 0) and t.carved(x + 2, y, 0) \
					and t.height(x, 0) > y + 8:
				return Vector3(x + 0.5, y - 0.6, 0.5)
	return Vector3(0.5, 30.0, 0.5)


## Releases the player once the chunk under them has data.
## A new player lands on open ground near the spawn column, not on a tree.
func _try_spawn() -> void:
	var x := floori(player.position.x)
	var z := floori(player.position.z)
	if world.get_block(x, 0, z) == -1:
		return
	if _loaded_player:
		player.frozen = false
		return
	var best := Vector3i(x, _top_solid(x, z), z)
	for r in range(0, 9):
		var found := false
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if found or maxi(absi(dx), absi(dz)) != r:
					continue
				if world.get_block(x + dx, 0, z + dz) == -1:
					continue
				var y := _top_solid(x + dx, z + dz)
				var ground: int = world.get_block(x + dx, y, z + dz)
				if ground == Blocks.GRASS or ground == Blocks.SAND or ground == Blocks.DIRT:
					best = Vector3i(x + dx, y, z + dz)
					found = true
		if found:
			break
	player.position = Vector3(best.x + 0.5, best.y + 1.0, best.z + 0.5)
	player.spawn_point = player.position
	player.frozen = false


func _top_solid(x: int, z: int) -> int:
	var y := Terrain.SY - 1
	while y > 0 and not world.is_solid(x, y, z):
		y -= 1
	return y


func _build_sky() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	# Fog hides the edge of the loaded area. The sky dome sets its colour.
	var far: float = world.view_dist * 16.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = far * 0.6
	environment.fog_depth_end = far - 8.0
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	daynight = DayNight.new()
	daynight.name = "DayNight"
	daynight.environment = environment
	daynight.camera = player.cam
	add_child(daynight)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	underwater = ColorRect.new()
	underwater.color = Color(0.10, 0.30, 0.65, 0.45)
	underwater.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater.visible = false
	layer.add_child(underwater)

	hud = Label.new()
	hud.position = Vector2(12, 8)
	layer.add_child(hud)

	help = Label.new()
	help.text = HELP
	help.position = Vector2(12, 32)
	help.modulate = Color(1, 1, 1, 0.75)
	layer.add_child(help)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(cross)

	hotbar = Hotbar.new()
	hotbar.atlas = world.atlas
	hotbar.inventory = inventory
	layer.add_child(hotbar)

	status = StatusHUD.new()
	status.player = player
	status.hotbar = hotbar
	status.atlas = world.atlas
	layer.add_child(status)

	touch = TouchUI.new()
	touch.hotbar = hotbar
	layer.add_child(touch)

	inventory_ui = InventoryUI.new()
	inventory_ui.inventory = inventory
	inventory_ui.atlas = world.atlas
	inventory_ui.audio = audio
	inventory_ui.drops = drops
	inventory_ui.player = player
	inventory_ui.closed.connect(_on_inventory_closed)
	layer.add_child(inventory_ui)

	menu = Menu.new()
	menu.play_pressed.connect(_on_play)
	menu.new_world_pressed.connect(_on_new_world)
	menu.resume_pressed.connect(resume_game)
	menu.music_pressed.connect(_on_music)
	menu.title_pressed.connect(_on_to_title)
	menu.quit_pressed.connect(_on_quit)
	layer.add_child(menu)


func _screenshot(path: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var saved_fly := fly_speed
	fly_speed = 0.0
	for i in 10:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var load_stats := await measure(func() -> bool:
		return world.is_idle() or Time.get_ticks_msec() - t0 > 120000)
	var load_ms := Time.get_ticks_msec() - t0
	fly_speed = saved_fly
	var t1 := Time.get_ticks_msec()
	var run_stats := await measure(func() -> bool:
		return Time.get_ticks_msec() - t1 > 5000)
	fly_speed = 0.0
	var err := await save_png(path)
	print("SHOT err=%d threads=%s dist=%d chunks=%d quads=%d | load %d ms, worst frame %.1f ms | run fps avg %.0f, worst frame %.1f ms | pos=%s floor=%s" % [
		err, world.use_threads, world.view_dist, world.chunks.size(), world.total_quads,
		load_ms, load_stats[1], run_stats[0], run_stats[1], player.position, player.on_floor])
	get_tree().quit()


func _title_shot(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	while not world.is_idle() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	for i in 5:
		await get_tree().process_frame
	var err := await save_png(path)
	print("TITLESHOT err=%d menu=%d started=%s" % [err, menu.mode, started])
	get_tree().quit()


## Two-run save test. "write" changes the world and saves; "read" is run in a
## new process and reports what it loaded. Both print one comparable line.
func _e2e(phase: String) -> void:
	var t0 := Time.get_ticks_msec()
	while (player.frozen or not world.is_idle()) and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	if phase == "write":
		var c := Vector3i(floori(player.position.x) + 2, floori(player.position.y) + 1, floori(player.position.z))
		world.set_block(c.x, c.y, c.z, Blocks.BRICKS)
		world.set_block(c.x, c.y + 1, c.z, Blocks.TORCH)
		inventory.add(Blocks.BRICKS, 7)
		daynight.set_time(0.6)
		player.health = 13.0
		furnaces.state_at(c)["in_n"] = 3
		furnaces.state_at(c)["in_id"] = Blocks.IRON
		for i in 30:
			await get_tree().process_frame
		print("E2E saved=%s" % save_game())
	var q := Vector3i(floori(player.position.x) + 2, floori(player.position.y) + 1, floori(player.position.z))
	print("E2E %s seed=%d pos=%s block=%d torch=%d bricks=%d time=%.2f health=%.0f furnace_in=%d edits=%d torches=%d" % [
		phase, world.world_seed, player.position.snappedf(0.01), world.get_block(q.x, q.y, q.z),
		world.get_block(q.x, q.y + 1, q.z), inventory.count_of(Blocks.BRICKS), daynight.time, player.health,
		furnaces.state_at(q)["in_n"], world.edits().size(), world._torches.size()])
	save_enabled = false
	get_tree().quit()


func save_png(path: String) -> int:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(path)


## Saves the frame that is already on screen. Does not wait, so game time does not advance.
func save_png_now(path: String) -> int:
	return get_viewport().get_texture().get_image().save_png(path)


## Runs frames until `done` returns true. Returns [average fps, worst frame ms].
func measure(done: Callable) -> Array:
	var start := Time.get_ticks_usec()
	var last := start
	var worst := 0
	var frames := 0
	while not done.call():
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
	return [frames * 1000000.0 / maxf(last - start, 1.0), worst / 1000.0]

extends Node3D
## Entry point. Builds sky, world, player, interaction, audio and HUD in code.
##
## Test arguments, passed after `--`:
##   --shot=PATH        wait for the world to load, measure FPS, save a PNG, quit
##   --selftest=PATH    drive the game with simulated touches, print PASS/FAIL, quit
##   --pos=X,Y,Z        hold the camera at a fixed position (no physics)
##   --look=PITCH,YAW   camera angles in degrees
##   --dist=N           view distance in chunks
##   --fly=SPEED        with --pos: move the camera along +X (blocks per second)
##   --cave             put the fixed camera inside the nearest cave
##   --nothreads        force the single-threaded loader (as on web)

const Blocks := preload("res://scripts/blocks.gd")
const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Interaction := preload("res://scripts/interaction.gd")
const Hotbar := preload("res://scripts/hotbar.gd")
const TouchUI := preload("res://scripts/touch_ui.gd")
const GameAudio := preload("res://scripts/audio.gd")
const SelfTest := preload("res://scripts/selftest.gd")

const FOG_COLOR := Color(0.70, 0.84, 0.96)
const HELP := "Click: capture mouse  |  WASD: move  |  Space: jump / swim  |  Shift: run  |  " \
		+ "Hold left: mine  |  Right: place  |  1-9 / wheel: block  |  M: music  |  Esc: release"

var world: Node3D
var player: Node3D
var interaction: Node3D
var audio: Node
var hotbar: Control
var touch: Control
var hud: Label
var help: Label
var underwater: ColorRect
var fixed_camera := false
var spawn_xz := Vector2i.ZERO
var fly_speed := 0.0


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""

	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)

	world = World.new()
	world.name = "World"
	if OS.has_feature("mobile") or OS.has_feature("web"):
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

	_build_sky()
	_build_hud()
	player.touch = touch

	interaction = Interaction.new()
	interaction.name = "Interaction"
	interaction.world = world
	interaction.player = player
	interaction.hotbar = hotbar
	interaction.touch = touch
	interaction.audio = audio
	add_child(interaction)

	if args.has("pos"):
		var p: PackedStringArray = args["pos"].split(",")
		player.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		fixed_camera = true
		fly_speed = float(args.get("fly", "0"))
	elif args.has("cave"):
		player.position = _find_cave()
		fixed_camera = true
	else:
		spawn_xz = _find_land()
		player.position = Vector3(spawn_xz.x + 0.5, 100.0, spawn_xz.y + 0.5)
	if args.has("look"):
		var l: PackedStringArray = args["look"].split(",")
		player.cam.rotation_degrees.x = float(l[0])
		player.rotation_degrees.y = float(l[1])
	world.focus = player.position

	if args.has("selftest"):
		var test := SelfTest.new()
		test.main = self
		test.path = args["selftest"]
		add_child(test)
	elif args.has("shot"):
		set_input_enabled(false)
		_screenshot(args["shot"])


func set_input_enabled(on: bool) -> void:
	player.input_enabled = on
	hotbar.input_enabled = on


func _unhandled_input(event: InputEvent) -> void:
	if not player.input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		audio.toggle_music()


func _process(delta: float) -> void:
	player.position.x += fly_speed * delta
	world.focus = player.position
	if player.frozen and not fixed_camera:
		_try_spawn()
	var p := player.position
	var eye: Vector3 = player.cam.global_position
	underwater.visible = world.get_block(floori(eye.x), floori(eye.y), floori(eye.z)) == Blocks.WATER
	help.visible = not touch.active
	hud.text = "Kubiya 0.3  |  %d FPS  |  %d chunks  |  %dk quads  |  %d, %d, %d" % [
		Engine.get_frames_per_second(), world.chunks.size(), world.total_quads / 1000.0,
		floori(p.x), floori(p.y), floori(p.z)]


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


## Drops the player on top of the spawn column once its chunk has data.
func _try_spawn() -> void:
	var x := spawn_xz.x
	var z := spawn_xz.y
	if world.get_block(x, 0, z) == -1:
		return
	var y := Terrain.SY - 1
	while y > 0 and not world.is_solid(x, y, z):
		y -= 1
	player.position.y = y + 1.0
	player.frozen = false


func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.50, 0.90)
	sky_mat.sky_horizon_color = FOG_COLOR
	sky_mat.ground_horizon_color = FOG_COLOR
	sky_mat.ground_bottom_color = FOG_COLOR
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	# Fog hides the edge of the loaded area.
	var far: float = world.view_dist * 16.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = FOG_COLOR
	env.fog_depth_begin = far * 0.6
	env.fog_depth_end = far - 8.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


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
	layer.add_child(hotbar)

	touch = TouchUI.new()
	touch.hotbar = hotbar
	layer.add_child(touch)


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


func save_png(path: String) -> int:
	await RenderingServer.frame_post_draw
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

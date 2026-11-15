extends Node3D
## Entry point. Builds sky, sun, world, player and HUD in code.
##
## Test hook: `godot --path . -- --shot=/tmp/out.png` saves one screenshot and quits.

const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")

var world: StaticBody3D
var player: CharacterBody3D
var fps_label: Label


func _ready() -> void:
	_build_sky()

	world = World.new()
	world.name = "World"
	add_child(world)

	@warning_ignore("integer_division")
	var cx: int = World.SX / 2
	@warning_ignore("integer_division")
	var cz: int = World.SZ / 2
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(cx + 0.5, world.surface_y(cx, cz) + 3.0, cz + 0.5)
	add_child(player)

	_build_hud()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_screenshot(arg.trim_prefix("--shot="))


func _process(_delta: float) -> void:
	fps_label.text = "Kubiya 0.1  |  %d FPS" % Engine.get_frames_per_second()


func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.50, 0.90)
	sky_mat.sky_horizon_color = Color(0.70, 0.84, 0.96)
	sky_mat.ground_horizon_color = Color(0.70, 0.84, 0.96)
	sky_mat.ground_bottom_color = Color(0.30, 0.36, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.90)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	fps_label = Label.new()
	fps_label.position = Vector2(12, 8)
	layer.add_child(fps_label)

	var help := Label.new()
	help.text = "Click: capture mouse  |  WASD: move  |  Space: jump  |  Shift: run  |  Esc: release"
	help.position = Vector2(12, 32)
	help.modulate = Color(1, 1, 1, 0.75)
	layer.add_child(help)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(cross)


func _screenshot(path: String) -> void:
	player.cam.rotation.x = -0.35
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SHOT ", path, " err=", err, " player_y=", player.position.y, " on_floor=", player.is_on_floor())
	get_tree().quit()

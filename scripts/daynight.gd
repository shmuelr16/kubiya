extends Node3D
## Day and night. Owns the clock and the sky: one dome mesh around the camera
## whose shader paints the gradient, sun, crescent moon and stars. Also drives
## the global `daylight` shader value, the fog and the background colour.
##
## time: 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight.

const DAY_LENGTH := 600.0
const MIN_DAYLIGHT := 0.18
const AXIS := Vector3(0.0, 0.33, 0.944)

const DAY_TOP := Color(0.25, 0.50, 0.90)
const DAY_HORIZON := Color(0.70, 0.84, 0.96)
const NIGHT_TOP := Color(0.010, 0.015, 0.045)
const NIGHT_HORIZON := Color(0.030, 0.045, 0.090)
const DUSK := Color(0.96, 0.55, 0.30)

const SHADER := "
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;
uniform vec3 top_color;
uniform vec3 horizon_color;
uniform vec3 glow_color;
uniform vec3 sun_dir;
uniform mat3 star_rot;
uniform float night;
uniform float glow;
varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 col = mix(horizon_color, top_color, pow(clamp(d.y, 0.0, 1.0), 0.45));

	float sd = dot(d, sun_dir);
	col += glow_color * pow(max(sd, 0.0), 5.0) * glow * (1.0 - clamp(d.y * 1.6, 0.0, 1.0));

	// Stars: a cube grid on the sky sphere gives small square stars.
	if (night > 0.01) {
		vec3 s = star_rot * d;
		vec3 cell = floor(s * 95.0);
		float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float twinkle = 0.75 + 0.25 * sin(TIME * (1.0 + h * 5.0) + h * 40.0);
		col += vec3(0.95, 0.95, 1.0) * step(0.9972, h) * night * twinkle * smoothstep(0.0, 0.12, d.y);
	}

	// Sun: bright disc with a soft rim.
	col = mix(col, vec3(1.0, 0.93, 0.62), smoothstep(0.9972, 0.9984, sd));

	// Moon: disc with a bite taken out of it.
	float md = dot(d, -sun_dir);
	float moon = smoothstep(0.9981, 0.9989, md);
	vec3 bite = normalize(-sun_dir + vec3(0.022, 0.016, 0.0));
	moon *= 1.0 - smoothstep(0.9982, 0.9990, dot(d, bite));
	col = mix(col, vec3(0.86, 0.90, 1.0), moon);

	ALBEDO = col;
}
"

var time := 0.08
var paused := false
var environment: Environment
var camera: Camera3D

## 0.12 at night to 1.0 by day. Mirrors the global shader value.
var daylight := 1.0
var sun_height := 0.0

var _dome: MeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.material = _mat
	_dome = MeshInstance3D.new()
	_dome.mesh = sphere
	_dome.extra_cull_margin = 16384.0
	add_child(_dome)
	apply()


func _process(delta: float) -> void:
	if not paused:
		time = fposmod(time + delta / DAY_LENGTH, 1.0)
	apply()


func set_time(t: float) -> void:
	time = fposmod(t, 1.0)
	apply()


func is_night() -> bool:
	return sun_height < -0.08


## Recomputes colours and light from the clock and pushes them to the renderer.
func apply() -> void:
	var angle := time * TAU
	var sun := Vector3(1, 0, 0).rotated(AXIS, angle)
	sun_height = sun.y
	var day := smoothstep(-0.14, 0.24, sun.y)
	daylight = lerpf(MIN_DAYLIGHT, 1.0, day)
	var dusk := clampf(1.0 - absf(sun.y) / 0.32, 0.0, 1.0)
	var top := NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK, dusk * 0.45)

	RenderingServer.global_shader_parameter_set("daylight", daylight)
	_mat.set_shader_parameter("top_color", Vector3(top.r, top.g, top.b))
	_mat.set_shader_parameter("horizon_color", Vector3(horizon.r, horizon.g, horizon.b))
	_mat.set_shader_parameter("glow_color", Vector3(DUSK.r, DUSK.g, DUSK.b))
	_mat.set_shader_parameter("sun_dir", sun)
	_mat.set_shader_parameter("star_rot", Basis(AXIS, -angle))
	_mat.set_shader_parameter("night", 1.0 - smoothstep(-0.16, 0.06, sun.y))
	_mat.set_shader_parameter("glow", dusk)
	if environment != null:
		environment.background_color = horizon
		environment.fog_light_color = horizon
	if camera != null:
		_dome.global_position = camera.global_position
		_dome.scale = Vector3.ONE * camera.far * 0.9

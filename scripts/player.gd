extends Node3D
## First-person walker with its own box-versus-blocks collision.
## No physics engine shapes: terrain needs no collision meshes, which keeps
## chunk loading cheap on phones.
##
## `position` is the centre of the feet.

const Blocks := preload("res://scripts/blocks.gd")

const HALF := 0.3
const HEIGHT := 1.8
const EYE := 1.62
const SPEED := 4.5
const SPRINT := 7.0
const JUMP := 8.2
const GRAVITY := 26.0
const MAX_FALL := 50.0
const SWIM_UP := 3.2
const SINK := 2.5
const SENSITIVITY := 0.0025
const SKIN := 0.001

var world: Node3D
var cam: Camera3D
var vel := Vector3.ZERO
var on_floor := false
var in_water := false
## While frozen the player does not move. Used until the spawn chunk loads.
var frozen := true
## Tests switch this off so that stray key presses cannot move the player.
var input_enabled := true


func _ready() -> void:
	cam = Camera3D.new()
	cam.position.y = EYE
	cam.fov = 75.0
	cam.near = 0.08
	add_child(cam)
	cam.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSITIVITY)
		cam.rotation.x = clampf(cam.rotation.x - event.relative.y * SENSITIVITY, -1.5, 1.5)


func _physics_process(delta: float) -> void:
	if frozen or world == null:
		return
	delta = minf(delta, 0.05)

	var input := Vector2.ZERO
	if _down(KEY_W) or _down(KEY_UP):
		input.y -= 1.0
	if _down(KEY_S) or _down(KEY_DOWN):
		input.y += 1.0
	if _down(KEY_A) or _down(KEY_LEFT):
		input.x -= 1.0
	if _down(KEY_D) or _down(KEY_RIGHT):
		input.x += 1.0
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	var p := position
	in_water = world.get_block(floori(p.x), floori(p.y + 0.4), floori(p.z)) == Blocks.WATER
	var speed := SPRINT if _down(KEY_SHIFT) else SPEED
	if in_water:
		speed *= 0.6
		vel.y = move_toward(vel.y, -SINK, 14.0 * delta)
		if _down(KEY_SPACE):
			vel.y = SWIM_UP
	else:
		vel.y = maxf(vel.y - GRAVITY * delta, -MAX_FALL)
		if on_floor and _down(KEY_SPACE):
			vel.y = JUMP
	vel.x = dir.x * speed
	vel.z = dir.z * speed
	_move(delta)


## Moves one axis at a time and snaps to the block boundary on contact.
func _move(delta: float) -> void:
	var p := position
	on_floor = false

	var nx := p.x + vel.x * delta
	if vel.x != 0.0 and _hits(nx, p.y, p.z):
		nx = (floorf(nx + HALF) - HALF - SKIN) if vel.x > 0.0 else (floorf(nx - HALF) + 1.0 + HALF + SKIN)
		vel.x = 0.0
	p.x = nx

	var nz := p.z + vel.z * delta
	if vel.z != 0.0 and _hits(p.x, p.y, nz):
		nz = (floorf(nz + HALF) - HALF - SKIN) if vel.z > 0.0 else (floorf(nz - HALF) + 1.0 + HALF + SKIN)
		vel.z = 0.0
	p.z = nz

	var ny := p.y + vel.y * delta
	if _hits(p.x, ny, p.z):
		if vel.y <= 0.0:
			ny = floorf(ny) + 1.0
			on_floor = true
		else:
			ny = floorf(ny + HEIGHT) - HEIGHT - SKIN
		vel.y = 0.0
	p.y = ny

	position = p


func _hits(px: float, py: float, pz: float) -> bool:
	var x1 := floori(px + HALF)
	var y1 := floori(py + HEIGHT)
	var z1 := floori(pz + HALF)
	for y in range(floori(py), y1 + 1):
		for z in range(floori(pz - HALF), z1 + 1):
			for x in range(floori(px - HALF), x1 + 1):
				if world.is_solid(x, y, z):
					return true
	return false


func _down(key: Key) -> bool:
	return input_enabled and Input.is_physical_key_pressed(key)

extends Node3D
## First-person player: walking, jumping, gravity, swimming, and its own
## box-versus-blocks collision. No physics engine shapes are used, so terrain
## needs no collision meshes.
##
## `position` is the centre of the feet. Input comes from keyboard and mouse,
## and from the touch UI when one is attached.

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
const SWIM_HOP := 6.5
const SINK := 2.5
const SENSITIVITY := 0.0025
const TOUCH_SENSITIVITY := 0.006
const SKIN := 0.001
const STEP_LENGTH := 2.2

var world: Node3D
var touch: Control
var audio: Node
var cam: Camera3D
var vel := Vector3.ZERO
var on_floor := false
var in_water := false
## A wall stopped horizontal movement in the last step.
var blocked := false
## While frozen the player does not move. Used until the spawn chunk loads.
var frozen := true
## Tests switch this off so that stray key presses and clicks cannot interfere.
var input_enabled := true
## A menu is open: the player stands still and ignores input.
var ui_open := false

var _step_acc := 0.0
var _fall_speed := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.position.y = EYE
	cam.fov = 75.0
	cam.near = 0.08
	add_child(cam)
	cam.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or ui_open:
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * SENSITIVITY)


func _process(_delta: float) -> void:
	if touch != null:
		var d: Vector2 = touch.take_look()
		if d != Vector2.ZERO:
			_look(d * TOUCH_SENSITIVITY)


func _look(d: Vector2) -> void:
	rotate_y(-d.x)
	cam.rotation.x = clampf(cam.rotation.x - d.y, -1.5, 1.5)


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
	var jump := _down(KEY_SPACE)
	var using_touch := false
	if touch != null and touch.active:
		if touch.move != Vector2.ZERO:
			input += touch.move
			using_touch = true
		jump = jump or touch.jump
	input = input.limit_length(1.0)
	var dir := transform.basis * Vector3(input.x, 0.0, input.y)

	var p := position
	var was_in_water := in_water
	in_water = world.get_block(floori(p.x), floori(p.y + 0.4), floori(p.z)) == Blocks.WATER
	if in_water and not was_in_water and vel.y < -4.0:
		_sound("splash", randf_range(0.9, 1.1), -4.0)

	var speed := SPRINT if _down(KEY_SHIFT) else SPEED
	if in_water:
		speed *= 0.6
		vel.y = move_toward(vel.y, -SINK, 14.0 * delta)
		if jump:
			# A stronger kick against a wall lets the player climb out onto a bank.
			vel.y = SWIM_HOP if blocked else SWIM_UP
	else:
		vel.y = maxf(vel.y - GRAVITY * delta, -MAX_FALL)
		# Touch has no spare finger for jumping while walking: hop up steps automatically.
		if on_floor and (jump or (using_touch and blocked)):
			vel.y = JUMP
	vel.x = dir.x * speed
	vel.z = dir.z * speed

	var was_on_floor := on_floor
	_fall_speed = -vel.y
	_move(delta)

	if on_floor:
		var below := world.get_block(floori(position.x), floori(position.y - 0.5), floori(position.z)) as int
		var pitch: float = Blocks.PITCH[below] if below > 0 else 1.0
		if not was_on_floor and _fall_speed > 7.0:
			_sound("step", pitch * 0.8, -3.0)
			_step_acc = 0.0
		_step_acc += Vector2(vel.x, vel.z).length() * delta
		if _step_acc > STEP_LENGTH:
			_step_acc = 0.0
			_sound("step", pitch * randf_range(0.9, 1.1), -10.0)


## True when the player's box overlaps the given block cell.
func intersects_cell(c: Vector3i) -> bool:
	var p := position
	return c.x + 1.0 > p.x - HALF and c.x < p.x + HALF \
			and c.y + 1.0 > p.y and c.y < p.y + HEIGHT \
			and c.z + 1.0 > p.z - HALF and c.z < p.z + HALF


## Moves one axis at a time and snaps to the block boundary on contact.
func _move(delta: float) -> void:
	var p := position
	on_floor = false
	blocked = false

	var nx := p.x + vel.x * delta
	if vel.x != 0.0 and _hits(nx, p.y, p.z):
		nx = (floorf(nx + HALF) - HALF - SKIN) if vel.x > 0.0 else (floorf(nx - HALF) + 1.0 + HALF + SKIN)
		vel.x = 0.0
		blocked = true
	p.x = nx

	var nz := p.z + vel.z * delta
	if vel.z != 0.0 and _hits(p.x, p.y, nz):
		nz = (floorf(nz + HALF) - HALF - SKIN) if vel.z > 0.0 else (floorf(nz - HALF) + 1.0 + HALF + SKIN)
		vel.z = 0.0
		blocked = true
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


func _sound(sound: String, pitch: float, db: float) -> void:
	if audio != null:
		audio.play(sound, pitch, db)


func _down(key: Key) -> bool:
	return input_enabled and not ui_open and Input.is_physical_key_pressed(key)

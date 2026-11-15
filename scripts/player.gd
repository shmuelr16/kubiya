extends CharacterBody3D
## First-person walker: WASD / arrows, mouse look, Space to jump, Shift to run.

const SPEED := 5.0
const SPRINT := 8.0
const JUMP := 7.5
const GRAVITY := 22.0
const SENSITIVITY := 0.0025

var cam: Camera3D
var spawn := Vector3.ZERO


func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	col.shape = capsule
	add_child(col)

	cam = Camera3D.new()
	cam.position.y = 0.7
	cam.fov = 75.0
	cam.far = 300.0
	add_child(cam)
	cam.make_current()
	spawn = position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSITIVITY)
		cam.rotation.x = clampf(cam.rotation.x - event.relative.y * SENSITIVITY, -1.5, 1.5)


func _physics_process(delta: float) -> void:
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
	var speed := SPRINT if _down(KEY_SHIFT) else SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if is_on_floor():
		if _down(KEY_SPACE):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	if position.y < -30.0:
		position = spawn
		velocity = Vector3.ZERO


func _down(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)

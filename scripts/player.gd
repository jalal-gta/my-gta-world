extends CharacterBody3D
## Player controller: capsule walker + orbit follow camera + car enter/exit.
##
## Controls:
##   * WASD / arrows — move (registered in the Settings autoload)
##   * Mouse (click to capture) or touch-drag — orbit camera
##   * Touch joystick (bottom-left, on touchscreens) — move
##   * Space — jump, Shift — sprint, E — enter/exit the drivable car
##
## The CharacterBody itself never yaws: the mesh pivot and the camera rig
## rotate independently, which keeps movement maths simple and stable.

const SPEED := 5.5
const SPRINT_SPEED := 10.0
const JUMP_VELOCITY := 8.0
const GRAVITY := 22.0

var _yaw := 0.0
var _pitch := -0.32
var _car: Node = null

@onready var _rig: Node3D = $CameraRig
@onready var _spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var _cam: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _mesh_pivot: Node3D = $MeshPivot
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_apply_camera_far()
	if not Settings.changed.is_connected(_apply_camera_far):
		Settings.changed.connect(_apply_camera_far)


func _apply_camera_far() -> void:
	if _cam != null:
		_cam.far = Settings.view_distance + 80.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _car != null:
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera((event as InputEventMouseMotion).relative)
	if event is InputEventScreenDrag:
		_rotate_camera((event as InputEventScreenDrag).relative * 1.6)


func _rotate_camera(rel: Vector2) -> void:
	_yaw -= rel.x * 0.0032
	_pitch = clampf(_pitch - rel.y * 0.0032, -1.1, 0.6)


func _physics_process(delta: float) -> void:
	if _car != null:
		# Ride along hidden inside the car; E gets out.
		global_position = _car.global_position + Vector3(0.0, 0.4, 0.0)
		velocity = Vector3.ZERO
		if Input.is_action_just_pressed("interact"):
			_exit_car()
		return

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var joy := get_tree().get_first_node_in_group("joystick")
	if joy != null:
		var jout: Vector2 = joy.get("output")
		if jout.length() > 0.15:
			input_dir = jout

	var dir := Basis(Vector3.UP, _yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
	else:
		dir = Vector3.ZERO

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	if dir.length() > 0.05:
		var target_yaw := atan2(-dir.x, -dir.z)
		_mesh_pivot.rotation.y = lerp_angle(_mesh_pivot.rotation.y, target_yaw, 12.0 * delta)

	_rig.rotation.y = _yaw
	_spring.rotation.x = _pitch

	if Input.is_action_just_pressed("interact"):
		_try_enter_car()


func _try_enter_car() -> void:
	for node in get_tree().get_nodes_in_group("drivable"):
		var car := node as Node3D
		if car != null and global_position.distance_to(car.global_position) < 4.0:
			_car = car
			car.call("set_driven", true)
			visible = false
			_shape.set_deferred("disabled", true)
			velocity = Vector3.ZERO
			return


func _exit_car() -> void:
	if _car == null:
		return
	_car.call("set_driven", false)
	var car3d := _car as Node3D
	global_position = car3d.global_position + car3d.global_transform.basis.x * 2.4 + Vector3(0, 0.3, 0)
	_car = null
	visible = true
	_shape.set_deferred("disabled", false)
	_cam.current = true

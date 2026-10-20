extends CharacterBody3D
## The player's car: dead-simple arcade driving on a CharacterBody3D.
##
## One physics body for the hero car is affordable; the *ambient* traffic
## (traffic_car.gd) is kinematic on purpose. Steering scales with speed so
## the car feels stable at 90 FPS and at 30 FPS alike (all motion here is
## delta-based, never per-frame constants).

const MAX_FORWARD := 24.0 # m/s  (~86 km/h)
const MAX_REVERSE := 9.0
const ACCEL := 16.0
const DRAG := 6.0
const BRAKE := 30.0
const TURN_RATE := 1.7 # rad/s at speed
const GRAVITY := 22.0

var driven := false

var _speed := 0.0
var _vy := 0.0


func _ready() -> void:
	add_to_group("drivable")
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.1, 4.5)
	shape.shape = box
	shape.position.y = 0.65
	add_child(shape)

	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.72, 0.14, 0.1)
	paint.roughness = 0.26
	paint.metallic = 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 0.6, 4.4)
	bm.material = paint
	body.mesh = bm
	body.position.y = 0.6
	add_child(body)

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.13, 0.17)
	glass.roughness = 0.12
	glass.metallic = 0.6
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.7, 0.55, 2.1)
	cm.material = glass
	cabin.mesh = cm
	cabin.position = Vector3(0, 1.15, -0.25)
	add_child(cabin)

	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color(0.08, 0.08, 0.09)
	tyre.roughness = 0.9
	for p in [Vector2(-0.95, -1.45), Vector2(0.95, -1.45), Vector2(-0.95, 1.45), Vector2(0.95, 1.45)]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.36
		cyl.bottom_radius = 0.36
		cyl.height = 0.3
		cyl.material = tyre
		wheel.mesh = cyl
		wheel.rotation_degrees.z = 90.0
		wheel.position = Vector3(p.x, 0.36, p.y)
		add_child(wheel)

	_add_lights()

	var cam := Camera3D.new()
	cam.name = "CarCamera"
	cam.position = Vector3(0, 2.9, 8.2)
	cam.rotation_degrees.x = -13.0
	cam.fov = 72.0
	cam.current = false
	add_child(cam)


## Tiny emissive light strips (warm front / red rear), same cheap trick as
## the traffic cars: material emission only, no real light nodes.
func _add_lights() -> void:
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1.0, 0.95, 0.8)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.93, 0.75)
	head.emission_energy_multiplier = 1.6
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.6, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(0.9, 0.08, 0.08)
	tail.emission_energy_multiplier = 1.2
	for spec in [
		[Vector3(-0.6, 0.68, -2.21), head], [Vector3(0.6, 0.68, -2.21), head],
		[Vector3(-0.6, 0.68, 2.21), tail], [Vector3(0.6, 0.68, 2.21), tail],
	]:
		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.45, 0.15, 0.05)
		lm.material = spec[1]
		lamp.mesh = lm
		lamp.position = spec[0]
		add_child(lamp)


func set_driven(v: bool) -> void:
	driven = v
	var cam := get_node_or_null("CarCamera") as Camera3D
	if cam != null:
		cam.current = v


func _physics_process(delta: float) -> void:
	if is_on_floor():
		_vy = -0.5
	else:
		_vy -= GRAVITY * delta

	if driven:
		var throttle := Input.get_axis("move_back", "move_forward")
		var steer := Input.get_axis("move_left", "move_right")
		if throttle != 0.0:
			_speed = clampf(_speed + ACCEL * throttle * delta, -MAX_REVERSE, MAX_FORWARD)
		else:
			_speed = move_toward(_speed, 0.0, DRAG * delta)
		if absf(_speed) > 0.2:
			var grip := clampf(absf(_speed) / 8.0, 0.25, 1.0)
			rotate_y(-steer * TURN_RATE * grip * signf(_speed) * delta)
	else:
		_speed = move_toward(_speed, 0.0, BRAKE * delta)

	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	velocity = forward * _speed
	velocity.y = _vy
	move_and_slide()

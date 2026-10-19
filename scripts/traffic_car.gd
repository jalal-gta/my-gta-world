extends Node3D
## Ambient traffic car: a kinematic waypoint follower.
##
## Deliberately NOT a physics body — a dozen RigidBody/CharacterBody vehicles
## would cost far more CPU than this does, and ambient traffic only needs to
## *look* alive. Movement happens in _process with plain vector maths.
## The car also distance-culls itself against Settings.view_distance (and
## pauses while culled — cheap, and invisible to the player).

var waypoints: Array[Vector3] = []
var speed := 10.0
var body_color := Color(0.8, 0.3, 0.2)
var start_index := 0

var _idx := 0
var _player: Node3D = null


func _ready() -> void:
	_build_visuals()
	_idx = start_index
	if waypoints.size() > 0:
		global_position = waypoints[_idx]
		_idx = (_idx + 1) % waypoints.size()


func _build_visuals() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.55
	mat.metallic = 0.25
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.55, 4.2)
	bm.material = mat
	body.mesh = bm
	body.position.y = 0.55
	add_child(body)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.15, 0.19)
	glass.roughness = 0.25
	glass.metallic = 0.4
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.6, 0.5, 2.0)
	cm.material = glass
	cabin.mesh = cm
	cabin.position = Vector3(0, 1.05, -0.2)
	add_child(cabin)


func _process(delta: float) -> void:
	if waypoints.is_empty():
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null:
		var d := global_position.distance_to(_player.global_position)
		visible = d < Settings.view_distance + 30.0
		if not visible:
			return
	var target := waypoints[_idx]
	var to := target - global_position
	to.y = 0.0
	if to.length() < 1.6:
		_idx = (_idx + 1) % waypoints.size()
		return
	var dir := to.normalized()
	global_position += dir * speed * delta
	look_at(global_position + dir, Vector3.UP)

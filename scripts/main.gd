extends Node3D
## Main world builder for My GTA World.
##
## Builds the starter open world in code (so the .tscn stays small):
##   * A chunked low-poly city. Buildings are MultiMesh instances — one draw
##     call per (chunk x material) instead of one per building — grouped into
##     chunks that are distance-culled against Settings.view_distance.
##   * Ambient traffic: simple kinematic cars looping on street rectangles
##     (no physics bodies — see traffic_car.gd).
##   * One drivable car near the spawn point (see drivable_car.gd).
##
## LOD structure: buildings are static boxes, so "LOD" here is the chunk
## culling below plus per-preset shadow/resolution scaling. When real
## building meshes arrive, give each chunk's MultiMesh a second, lower-detail
## MultiMesh and swap by the same distance check (the chunk metadata already
## stores the centre you need).

const TrafficCar := preload("res://scripts/traffic_car.gd")
const DrivableCar := preload("res://scripts/drivable_car.gd")

const BLOCK_SIZE := 18.0
const STREET_WIDTH := 10.0
const PITCH := BLOCK_SIZE + STREET_WIDTH # 28 m between block centres
const BLOCKS := 3 # blocks from -3..3 on both axes (7x7 = 49 blocks)
const CHUNK_SIZE := 56.0 # 2x2 blocks per culling chunk

var _rng := RandomNumberGenerator.new()
var _chunk_nodes: Array[MultiMeshInstance3D] = []
var _cull_timer := 0.0

@onready var _city: Node3D = $City
@onready var _traffic_root: Node3D = $Traffic


func _ready() -> void:
	_rng.seed = 20261018 # deterministic city layout
	_build_city()
	_build_traffic()
	_build_hero_car()
	Settings.apply_scene_settings()
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	Settings.apply_scene_settings()


func _process(delta: float) -> void:
	_cull_timer += delta
	if _cull_timer < 0.25:
		return
	_cull_timer = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var limit := Settings.view_distance + CHUNK_SIZE
	var pp := player.global_position
	for mmi in _chunk_nodes:
		var center: Vector3 = mmi.get_meta("chunk_center")
		var d := Vector2(pp.x - center.x, pp.z - center.z).length()
		mmi.visible = d <= limit


# ---------------------------------------------------------------------------
# City: MultiMesh buildings grouped into culling chunks
# ---------------------------------------------------------------------------
func _build_city() -> void:
	var mats: Array[StandardMaterial3D] = []
	for c in [
		Color(0.56, 0.58, 0.62), Color(0.64, 0.56, 0.48),
		Color(0.46, 0.53, 0.62), Color(0.62, 0.62, 0.58),
	]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.95
		mats.append(m)
	var pavement := StandardMaterial3D.new()
	pavement.albedo_color = Color(0.32, 0.32, 0.34)
	pavement.roughness = 1.0
	mats.append(pavement)
	var pavement_idx := mats.size() - 1

	var box := BoxMesh.new()
	box.size = Vector3.ONE

	# key: "chunk_x,chunk_z,mat" -> Array[Transform3D]
	var buckets := {}
	var slots := [Vector2(-4.6, -4.6), Vector2(4.6, -4.6), Vector2(-4.6, 4.6), Vector2(4.6, 4.6)]

	for bx in range(-BLOCKS, BLOCKS + 1):
		for bz in range(-BLOCKS, BLOCKS + 1):
			var cx := bx * PITCH
			var cz := bz * PITCH
			_add_instance(buckets, pavement_idx,
				Transform3D(Basis.from_scale(Vector3(BLOCK_SIZE + 2.0, 0.2, BLOCK_SIZE + 2.0)),
					Vector3(cx, 0.1, cz)))
			# 3 buildings per block, taller towards the city centre.
			var center_factor := 1.6 - Vector2(bx, bz).length() / float(BLOCKS + 1)
			var slot_offset := posmod(bx + bz, 4)
			for i in range(3):
				var s: Vector2 = slots[(slot_offset + i) % 4]
				var w := _rng.randf_range(7.0, 12.5)
				var d := _rng.randf_range(7.0, 12.5)
				var h := _rng.randf_range(6.0, 20.0) * center_factor
				_add_instance(buckets, _rng.randi_range(0, 2),
					Transform3D(Basis.from_scale(Vector3(w, h, d)),
						Vector3(cx + s.x, h * 0.5 + 0.2, cz + s.y)))

	for key in buckets:
		var parts := String(key).split(",")
		var chunk := Vector2(int(parts[0]), int(parts[1]))
		var mat_idx := int(parts[2])
		var transforms: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[mat_idx]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var center3 := Vector3(
			chunk.x * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0.0,
			chunk.y * CHUNK_SIZE + CHUNK_SIZE * 0.5)
		mmi.set_meta("chunk_center", center3)
		mmi.custom_aabb = AABB(
			Vector3(center3.x - CHUNK_SIZE * 0.5 - 14.0, 0.0, center3.z - CHUNK_SIZE * 0.5 - 14.0),
			Vector3(CHUNK_SIZE + 28.0, 48.0, CHUNK_SIZE + 28.0))
		mmi.add_to_group("city_chunk")
		_city.add_child(mmi)
		_chunk_nodes.append(mmi)


func _add_instance(buckets: Dictionary, mat_idx: int, t: Transform3D) -> void:
	var chunk := Vector2(
		floori(t.origin.x / CHUNK_SIZE), floori(t.origin.z / CHUNK_SIZE))
	var key := "%d,%d,%d" % [int(chunk.x), int(chunk.y), mat_idx]
	if not buckets.has(key):
		buckets[key] = []
	(buckets[key] as Array).append(t)


# ---------------------------------------------------------------------------
# Ambient traffic: rectangular loops on the street grid
# ---------------------------------------------------------------------------
func _build_traffic() -> void:
	var palette := [
		Color(0.75, 0.25, 0.2), Color(0.2, 0.4, 0.8), Color(0.9, 0.75, 0.25),
		Color(0.3, 0.7, 0.35), Color(0.85, 0.85, 0.88), Color(0.25, 0.25, 0.3),
	]
	var car_no := 0
	for loop_radius in [42.0, 70.0, 98.0]:
		var r: float = loop_radius
		var waypoints: Array[Vector3] = [
			Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r),
		]
		for k in range(2):
			var car: Node3D = TrafficCar.new()
			car.set("waypoints", waypoints)
			car.set("speed", _rng.randf_range(8.0, 13.0))
			car.set("body_color", palette[car_no % palette.size()])
			car.set("start_index", (car_no + k) % waypoints.size())
			_traffic_root.add_child(car)
			car_no += 1


# ---------------------------------------------------------------------------
# The player's drivable car, parked next to the spawn point
# ---------------------------------------------------------------------------
func _build_hero_car() -> void:
	var car: CharacterBody3D = DrivableCar.new()
	car.position = Vector3(5.0, 0.2, 12.0)
	car.rotation.y = deg_to_rad(-90.0)
	add_child(car)

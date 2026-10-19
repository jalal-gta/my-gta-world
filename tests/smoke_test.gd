extends SceneTree
## Automated smoke test — run with:
##   godot --headless --path . -s res://tests/smoke_test.gd
## Exercises: Settings (FPS modes, presets, battery saver), player movement,
## car enter/drive/exit, traffic motion and distance culling.
## Prints PASS/FAIL lines and exits with the number of failures.

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	_run.call_deferred()


func _press(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _run() -> void:
	await process_frame
	await process_frame

	var settings: Node = root.get_node_or_null("Settings")
	_check(settings != null, "Settings autoload present")
	if settings == null:
		quit(1)
		return

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await physics_frame

	# --- FPS modes -------------------------------------------------------
	_check(Engine.max_fps == 60, "Auto mode on headless (unknown refresh) caps at 60, got %d" % Engine.max_fps)
	settings.call("set_fps_mode", 3) # FPS_90
	_check(Engine.max_fps == 90, "FPS_90 sets Engine.max_fps=90, got %d" % Engine.max_fps)
	settings.call("set_fps_mode", 1) # FPS_30
	_check(Engine.max_fps == 30, "FPS_30 sets Engine.max_fps=30, got %d" % Engine.max_fps)
	settings.call("set_fps_mode", 0) # back to Auto

	# --- Presets ---------------------------------------------------------
	settings.call("set_preset", 3) # ULTRA
	_check(is_equal_approx(root.scaling_3d_scale, 1.0), "ULTRA scale=1.0, got %f" % root.scaling_3d_scale)
	_check(root.msaa_3d == 2, "ULTRA MSAA=4x(2), got %d" % root.msaa_3d)
	settings.call("set_preset", 0) # LOW
	_check(is_equal_approx(root.scaling_3d_scale, 0.6), "LOW scale=0.6, got %f" % root.scaling_3d_scale)
	var lights := get_nodes_in_group("shadow_light")
	_check(lights.size() == 1 and not (lights[0] as DirectionalLight3D).shadow_enabled,
		"LOW disables directional shadows")
	settings.call("set_preset", 1) # BALANCED
	_check((lights[0] as DirectionalLight3D).shadow_enabled, "BALANCED re-enables shadows")

	# --- Battery saver ---------------------------------------------------
	settings.call("set_battery_saver", true)
	_check(Engine.max_fps == 30, "Battery saver caps at 30 FPS, got %d" % Engine.max_fps)
	_check(int(settings.call("effective_preset")) == 0, "Battery saver forces Low preset")
	settings.call("set_battery_saver", false)

	# --- World content ---------------------------------------------------
	var chunks := get_nodes_in_group("city_chunk")
	_check(chunks.size() >= 25, "City chunks built (%d MultiMesh chunks)" % chunks.size())
	var traffic := scene.get_node("Traffic")
	_check(traffic.get_child_count() == 6, "6 traffic cars, got %d" % traffic.get_child_count())
	var car0 := traffic.get_child(0) as Node3D
	var car0_start := car0.global_position
	var player := get_first_node_in_group("player") as CharacterBody3D
	_check(player != null, "Player present")

	# --- Player movement ---------------------------------------------------
	var start_pos := player.global_position
	_press("move_forward")
	for i in 30:
		await physics_frame
	_release("move_forward")
	var moved := start_pos.z - player.global_position.z
	_check(moved > 0.8, "Player walked forward %.2f m" % moved)
	_check(player.is_on_floor(), "Player is on the floor")

	# --- Traffic moves -----------------------------------------------------
	for i in 30:
		await physics_frame
	_check(car0.global_position.distance_to(car0_start) > 0.5,
		"Traffic car moved %.2f m" % car0.global_position.distance_to(car0_start))

	# --- Car enter / drive / exit ------------------------------------------
	var cars := get_nodes_in_group("drivable")
	_check(cars.size() == 1, "One drivable car")
	var car := cars[0] as Node3D
	player.global_position = car.global_position + Vector3(2.2, 0.2, 0)
	for i in 5:
		await physics_frame
	_press("interact")
	await physics_frame
	_release("interact")
	for i in 5:
		await physics_frame
	_check(player.get("_car") != null, "Player entered the car")
	_check(not player.visible, "Player hidden while driving")
	var car_start := car.global_position
	_press("move_forward")
	for i in 90:
		await physics_frame
	_release("move_forward")
	_check(car.global_position.distance_to(car_start) > 2.0,
		"Car drove %.2f m" % car.global_position.distance_to(car_start))
	_press("interact")
	await physics_frame
	_release("interact")
	for i in 5:
		await physics_frame
	_check(player.get("_car") == null and player.visible, "Player exited the car")

	# --- Distance culling ---------------------------------------------------
	settings.call("set_view_distance", 60.0)
	await create_timer(0.6).timeout
	var hidden_count := 0
	for c in chunks:
		if not (c as MultiMeshInstance3D).visible:
			hidden_count += 1
	_check(hidden_count > 0, "View distance 60 culls distant chunks (%d hidden)" % hidden_count)
	settings.call("set_view_distance", 320.0)
	await create_timer(0.6).timeout
	var still_hidden := 0
	for c in chunks:
		if not (c as MultiMeshInstance3D).visible:
			still_hidden += 1
	_check(still_hidden == 0, "View distance 320 shows all chunks")

	print("SMOKE TEST DONE — failures: %d" % _failures)
	quit(_failures)

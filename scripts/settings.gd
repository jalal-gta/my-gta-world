extends Node
## GameSettings — autoloaded as "Settings".
##
## Owns the whole performance system for My GTA World:
##   * FPS modes: 30 / 60 / 90 / Auto (Engine.max_fps cap).
##   * Graphics presets: Low / Balanced / High / Ultra, applied at runtime
##     without restarting (resolution scale, MSAA, shadow atlas size, shadow
##     on/off, city shadow casting, view distance).
##   * Battery saver: forces Low visuals + a 30 FPS cap while enabled.
##   * Persistence to user:// so the player's choices survive restarts.
##
## Honesty notes:
##   * Engine.max_fps is a *cap*, not a promise. The display/OS vsync has the
##     final say — a 60 Hz phone can never show 90 FPS, so Auto mode reads
##     DisplayServer.screen_get_refresh_rate() and never targets more than
##     the panel supports (and never more than 90).
##   * Godot does not expose phone temperature to GDScript, so "thermal"
##     handling here is: (a) Auto mode adapts the 3D resolution scale down
##     when the frame rate cannot hold its target (device capability), and
##     (b) Battery Saver. The OS thermal throttling itself is respected,
##     never fought.
##   * Texture *compression* quality is chosen at import/export time
##     (project.godot enables ETC2/ASTC). The anisotropic filtering level
##     set here is a project setting: it is stored immediately and fully
##     applies to textures loaded afterwards / after a restart.

signal changed

enum FpsMode { AUTO, FPS_30, FPS_60, FPS_90 }
enum Preset { LOW, BALANCED, HIGH, ULTRA }

const SAVE_PATH := "user://my_gta_world_settings.cfg"
const VIEW_DISTANCE_MIN := 60.0
const VIEW_DISTANCE_MAX := 320.0

# Per-preset knobs. view_distance is in metres and drives camera far plane,
# city-chunk culling and traffic culling (see main.gd / traffic_car.gd).
const PRESETS := {
	Preset.LOW: {
		"scale": 0.6, "msaa": 0, "shadow_atlas": 1024, "shadows": false,
		"cast_shadows": false, "view_distance": 90.0, "aniso": 0,
	},
	Preset.BALANCED: {
		"scale": 0.8, "msaa": 0, "shadow_atlas": 2048, "shadows": true,
		"cast_shadows": true, "view_distance": 140.0, "aniso": 2,
	},
	Preset.HIGH: {
		"scale": 1.0, "msaa": 1, "shadow_atlas": 4096, "shadows": true,
		"cast_shadows": true, "view_distance": 200.0, "aniso": 4,
	},
	Preset.ULTRA: {
		"scale": 1.0, "msaa": 2, "shadow_atlas": 4096, "shadows": true,
		"cast_shadows": true, "view_distance": 260.0, "aniso": 8,
	},
}

var fps_mode: int = FpsMode.AUTO
var preset: int = Preset.BALANCED
var battery_saver: bool = false
var show_fps_overlay: bool = false
var view_distance: float = 140.0

var _loaded := false
var _dyn_factor := 1.0 # Adaptive resolution factor used by Auto mode (0.5..1.0)
var _adapt_timer := 0.0
var _restore_timer := 0.0


func _ready() -> void:
	_register_input_actions()
	load_settings()
	apply_all()
	_loaded = true


# ---------------------------------------------------------------------------
# Input actions (registered in code so project.godot stays hand-editable)
# ---------------------------------------------------------------------------
func _register_input_actions() -> void:
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("sprint", [KEY_SHIFT])
	_add_key_action("interact", [KEY_E])


func _add_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------------------
# Public setters (called by the settings UI)
# ---------------------------------------------------------------------------
func set_fps_mode(mode: int) -> void:
	fps_mode = mode
	_dyn_factor = 1.0
	apply_all()
	save_settings()
	changed.emit()


func set_preset(p: int) -> void:
	preset = p
	view_distance = float(PRESETS[effective_preset()]["view_distance"])
	apply_all()
	save_settings()
	changed.emit()


func set_battery_saver(on: bool) -> void:
	battery_saver = on
	view_distance = float(PRESETS[effective_preset()]["view_distance"])
	apply_all()
	save_settings()
	changed.emit()


func set_show_fps_overlay(on: bool) -> void:
	show_fps_overlay = on
	save_settings()
	changed.emit()


func set_view_distance(v: float) -> void:
	view_distance = clampf(v, VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX)
	save_settings()
	changed.emit()


func effective_preset() -> int:
	return Preset.LOW if battery_saver else preset


## The FPS cap that is currently in force (what Auto resolved to, or the
## manual selection, or 30 while Battery Saver is on).
func current_fps_target() -> int:
	if battery_saver:
		return 30
	match fps_mode:
		FpsMode.FPS_30:
			return 30
		FpsMode.FPS_60:
			return 60
		FpsMode.FPS_90:
			return 90
	# Auto: highest target the display can actually show, capped at 90.
	var rate := DisplayServer.screen_get_refresh_rate()
	if rate < 30.0: # Unknown (editor/headless/some panels) — safe default.
		return 60
	return mini(int(round(rate)), 90)


func fps_mode_name() -> String:
	if battery_saver:
		return "Battery Saver (30)"
	match fps_mode:
		FpsMode.FPS_30:
			return "30 FPS"
		FpsMode.FPS_60:
			return "60 FPS"
		FpsMode.FPS_90:
			return "90 FPS"
	return "Auto (%d FPS)" % current_fps_target()


func preset_name() -> String:
	match effective_preset():
		Preset.LOW:
			return "Low"
		Preset.HIGH:
			return "High"
		Preset.ULTRA:
			return "Ultra"
	return "Balanced"


# ---------------------------------------------------------------------------
# Applying settings
# ---------------------------------------------------------------------------
func apply_all() -> void:
	_apply_fps()
	_apply_preset_engine()
	apply_scene_settings()


func _apply_fps() -> void:
	Engine.max_fps = current_fps_target()


func _apply_preset_engine() -> void:
	var cfg: Dictionary = PRESETS[effective_preset()]
	_update_viewport_scale()
	get_viewport().msaa_3d = int(cfg["msaa"]) # Viewport.MSAA: 0=off, 1=2x, 2=4x
	RenderingServer.directional_shadow_atlas_set_size(int(cfg["shadow_atlas"]), true)
	ProjectSettings.set_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", int(cfg["aniso"]))


## Scene-level application: safe to call before the world exists (group
## lookups simply return nothing) and again once it is loaded.
func apply_scene_settings() -> void:
	var cfg: Dictionary = PRESETS[effective_preset()]
	for n in get_tree().get_nodes_in_group("shadow_light"):
		if n is DirectionalLight3D:
			(n as DirectionalLight3D).shadow_enabled = bool(cfg["shadows"])
	var cast_mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if bool(cfg["cast_shadows"])
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for n in get_tree().get_nodes_in_group("city_chunk"):
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = cast_mode


func _update_viewport_scale() -> void:
	var base := float(PRESETS[effective_preset()]["scale"])
	get_viewport().scaling_3d_scale = clampf(base * _dyn_factor, 0.4, 1.0)


# ---------------------------------------------------------------------------
# Auto mode: adaptive resolution from *measured* frame rate.
# If the game cannot hold its target, step the 3D scale down (floor 0.5 of
# the preset scale); if it holds the target comfortably for a while, step
# back up. Cooldowns prevent oscillation.
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _loaded or DisplayServer.get_name() == "headless":
		return
	if fps_mode != FpsMode.AUTO or battery_saver:
		if _dyn_factor != 1.0:
			_dyn_factor = 1.0
			_update_viewport_scale()
		return
	var target := current_fps_target()
	if target <= 0:
		return
	var fps := float(Engine.get_frames_per_second())
	_adapt_timer += delta
	if fps < target * 0.8 and _adapt_timer > 1.5 and _dyn_factor > 0.5:
		_dyn_factor = maxf(0.5, _dyn_factor - 0.1)
		_update_viewport_scale()
		_adapt_timer = 0.0
		_restore_timer = 0.0
	elif fps >= target * 0.97:
		_restore_timer += delta
		if _restore_timer > 6.0 and _dyn_factor < 1.0:
			_dyn_factor = minf(1.0, _dyn_factor + 0.1)
			_update_viewport_scale()
			_restore_timer = 0.0
	else:
		_restore_timer = 0.0


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("perf", "fps_mode", fps_mode)
	cf.set_value("perf", "preset", preset)
	cf.set_value("perf", "battery_saver", battery_saver)
	cf.set_value("perf", "show_fps_overlay", show_fps_overlay)
	cf.set_value("perf", "view_distance", view_distance)
	cf.save(SAVE_PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	fps_mode = int(cf.get_value("perf", "fps_mode", fps_mode))
	preset = int(cf.get_value("perf", "preset", preset))
	battery_saver = bool(cf.get_value("perf", "battery_saver", battery_saver))
	show_fps_overlay = bool(cf.get_value("perf", "show_fps_overlay", show_fps_overlay))
	view_distance = clampf(
		float(cf.get_value("perf", "view_distance", view_distance)),
		VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX)

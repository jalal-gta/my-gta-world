extends CanvasLayer
## Settings UI + FPS overlay + touch joystick host.
##
## Everything is built in code so the .tscn stays tiny and the layout is
## easy to adjust. All controls are touch-sized (>= 48 px tall) and every
## change applies immediately through the Settings autoload — no restart.
##
## The FPS overlay shows *measured* values only: Engine FPS, approximate
## frame time, and the renderer's draw-call count for the last frame.

const Joystick := preload("res://scripts/virtual_joystick.gd")

var _fps_label: Label
var _panel: PanelContainer
var _fps_option: OptionButton
var _preset_option: OptionButton
var _battery_check: CheckBox
var _overlay_check: CheckBox
var _dist_slider: HSlider
var _dist_value: Label
var _syncing := false
var _overlay_timer := 0.0


func _ready() -> void:
	_build_overlay()
	_build_panel()
	_build_joystick()
	_sync_from_settings()
	if not Settings.changed.is_connected(_sync_from_settings):
		Settings.changed.connect(_sync_from_settings)


func _build_overlay() -> void:
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 10)
	_fps_label.add_theme_font_size_override("font_size", 20)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_fps_label.visible = false
	add_child(_fps_label)


func _build_joystick() -> void:
	var joy: Control = Joystick.new()
	joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joy.position = Vector2(28, -232)
	joy.size = Vector2(204, 204)
	# Only useful where a touchscreen exists; harmless elsewhere (mouse works).
	joy.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("editor")
	add_child(joy)


func _build_panel() -> void:
	var open_btn := Button.new()
	open_btn.text = "SETTINGS"
	open_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	open_btn.position = Vector2(-172, 14)
	open_btn.size = Vector2(158, 52)
	open_btn.pressed.connect(func() -> void: _panel.visible = not _panel.visible)
	add_child(open_btn)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-230, -250)
	_panel.size = Vector2(460, 500)
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Performance Settings"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	_fps_option = OptionButton.new()
	for label in ["Auto (match display)", "30 FPS", "60 FPS", "90 FPS"]:
		_fps_option.add_item(label)
	_fps_option.custom_minimum_size = Vector2(0, 52)
	_fps_option.item_selected.connect(_on_fps_selected)
	vbox.add_child(_row("Frame rate", _fps_option))

	_preset_option = OptionButton.new()
	for label in ["Low", "Balanced", "High", "Ultra"]:
		_preset_option.add_item(label)
	_preset_option.custom_minimum_size = Vector2(0, 52)
	_preset_option.item_selected.connect(_on_preset_selected)
	vbox.add_child(_row("Graphics preset", _preset_option))

	_battery_check = CheckBox.new()
	_battery_check.text = "Battery saver (Low + 30 FPS)"
	_battery_check.custom_minimum_size = Vector2(0, 48)
	_battery_check.toggled.connect(func(on: bool) -> void:
		if not _syncing: Settings.set_battery_saver(on))
	vbox.add_child(_battery_check)

	_overlay_check = CheckBox.new()
	_overlay_check.text = "Show FPS overlay"
	_overlay_check.custom_minimum_size = Vector2(0, 48)
	_overlay_check.toggled.connect(func(on: bool) -> void:
		if not _syncing: Settings.set_show_fps_overlay(on))
	vbox.add_child(_overlay_check)

	_dist_slider = HSlider.new()
	_dist_slider.min_value = Settings.VIEW_DISTANCE_MIN
	_dist_slider.max_value = Settings.VIEW_DISTANCE_MAX
	_dist_slider.step = 10.0
	_dist_slider.custom_minimum_size = Vector2(0, 48)
	_dist_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing: Settings.set_view_distance(v))
	_dist_value = Label.new()
	vbox.add_child(_row("View distance (m)", _dist_slider))
	vbox.add_child(_dist_value)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 52)
	close_btn.pressed.connect(func() -> void: _panel.visible = false)
	vbox.add_child(close_btn)


func _row(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 19)
	box.add_child(l)
	box.add_child(control)
	return box


func _on_fps_selected(idx: int) -> void:
	if _syncing:
		return
	# Option order: Auto, 30, 60, 90 -> FpsMode: AUTO, FPS_30, FPS_60, FPS_90
	Settings.set_fps_mode(idx)


func _on_preset_selected(idx: int) -> void:
	if _syncing:
		return
	Settings.set_preset(idx)


func _sync_from_settings() -> void:
	_syncing = true
	_fps_option.selected = Settings.fps_mode
	_preset_option.selected = Settings.preset
	_battery_check.button_pressed = Settings.battery_saver
	_overlay_check.button_pressed = Settings.show_fps_overlay
	_dist_slider.value = Settings.view_distance
	_dist_value.text = "Current: %d m | Preset: %s | Target: %s" % [
		int(Settings.view_distance), Settings.preset_name(), Settings.fps_mode_name()]
	_fps_label.visible = Settings.show_fps_overlay
	_syncing = false


func _process(delta: float) -> void:
	_overlay_timer += delta
	if _overlay_timer < 0.25:
		return
	_overlay_timer = 0.0
	if _fps_label != null and _fps_label.visible:
		var fps := Engine.get_frames_per_second()
		var ms := 1000.0 / maxf(1.0, float(fps))
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		_fps_label.text = "FPS %d | %.1f ms | draws %d | objects %d\n%s | %s" % [
			fps, ms, int(draws), int(objects), Settings.preset_name(), Settings.fps_mode_name()]
		# Keep the panel's info line fresh while it is open.
		if _panel.visible:
			_sync_from_settings()

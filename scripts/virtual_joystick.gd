extends Control
## Minimal virtual joystick for touchscreens.
##
## `output` follows the same convention as Input.get_vector(): x is
## right-positive, y is down/back-positive, magnitude 0..1. The player
## reads it via the "joystick" group. Mouse input also works, so the
## joystick can be tested on a desktop.

const RADIUS := 92.0

var output := Vector2.ZERO

var _active := false
var _touch_id := -1


func _ready() -> void:
	add_to_group("joystick")
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	mouse_filter = MOUSE_FILTER_STOP


func _center() -> Vector2:
	return size * 0.5


func _set_from_point(p: Vector2) -> void:
	var off := p - _center()
	if off.length() > RADIUS:
		off = off.normalized() * RADIUS
	output = off / RADIUS
	queue_redraw()


func _release() -> void:
	_active = false
	_touch_id = -1
	output = Vector2.ZERO
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _active:
			_active = true
			_touch_id = t.index
			_set_from_point(t.position)
		elif not t.pressed and t.index == _touch_id:
			_release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _active and d.index == _touch_id:
			_set_from_point(d.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _active:
				_active = true
				_touch_id = -2
				_set_from_point(mb.position)
			elif not mb.pressed and _touch_id == -2:
				_release()
	elif event is InputEventMouseMotion and _active and _touch_id == -2:
		_set_from_point((event as InputEventMouseMotion).position)


func _draw() -> void:
	var c := _center()
	draw_circle(c, RADIUS, Color(1, 1, 1, 0.13))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(c + output * RADIUS * 0.55, 34.0, Color(1, 1, 1, 0.35))

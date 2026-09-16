class_name MapCamera
extends Camera2D
## Pan (drag / middle / space) and zoom-to-cursor (wheel) camera.

var min_zoom: float = 0.4
var max_zoom: float = 20.0
var _dragging: bool = false
var _drag_button: int = -1
var _space_held: bool = false
var map_rect := Rect2(0, 0, 1280, 800)

# The map is shown below the right-hand controls and above the status bar.
# Fitting against the full viewport made the last strip of the map disappear
# beneath the sidebar and caused apparent jumps when a map was loaded.
var reserved_right: float = 340.0
var reserved_bottom: float = 34.0


func _ready() -> void:
	make_current()
	position = map_rect.size / 2.0
	zoom = Vector2(1.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			_space_held = event.pressed

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_at(mb.position, 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT] or (_space_held and mb.button_index == MOUSE_BUTTON_LEFT):
			_dragging = mb.pressed
			_drag_button = mb.button_index
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / zoom.x
		_clamp_position()
		get_viewport().set_input_as_handled()


func _zoom_at(_screen_pos: Vector2, factor: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clampf(old_zoom * factor, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var world_pos := get_global_mouse_position()
	zoom = Vector2(new_zoom, new_zoom)
	# keep the world point under the cursor
	var world_pos_after := get_global_mouse_position()
	position += world_pos - world_pos_after
	_clamp_position()


func _clamp_position() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view: Vector2 = viewport_size * 0.5 / zoom.x
	var margin: float = 300.0
	position.x = clampf(position.x, -margin + half_view.x, map_rect.size.x + margin - half_view.x)
	position.y = clampf(position.y, -margin + half_view.y, map_rect.size.y + margin - half_view.y)
	if half_view.x * 2.0 > map_rect.size.x + margin * 2.0:
		position.x = map_rect.size.x / 2.0 - reserved_right / (2.0 * zoom.x)
	if half_view.y * 2.0 > map_rect.size.y + margin * 2.0:
		position.y = map_rect.size.y / 2.0 - reserved_bottom / (2.0 * zoom.y)


func fit_to_map() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var usable_size := Vector2(
		maxf(viewport_size.x - reserved_right, 320.0),
		maxf(viewport_size.y - reserved_bottom, 240.0)
	)
	var z: float = minf(usable_size.x / (map_rect.size.x + 40.0), usable_size.y / (map_rect.size.y + 40.0))
	z = clampf(z, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	position = map_rect.size / 2.0 - Vector2(reserved_right, reserved_bottom) / (2.0 * z)

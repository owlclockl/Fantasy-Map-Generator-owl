class_name MapCamera
extends Camera2D
## Pan (drag / middle / right / space+LMB) and smooth zoom-to-cursor camera.
## LMB drag pans the map like the original generator whenever no editing tool
## (heightmap brush, ruler) is active; the orchestrator toggles that flag.
##
## The zoom limits are derived from the actual map/viewport ratio, so even a
## 8192 pt map can be zoomed out until it fits the window (a fixed minimum of
## 0.4 used to make large maps impossible to overview).

var min_zoom: float = 0.05
var max_zoom: float = 24.0
var _dragging: bool = false
var _drag_button: int = -1
var _space_held: bool = false
var map_rect := Rect2(0, 0, 1280, 800)
var lmb_pan_enabled: bool = true

# Smooth zoom (wheel): the camera glides towards the requested zoom while the
# map point under the cursor stays put.
var smooth_zoom: bool = true
var zoom_step: float = 1.12
var _target_zoom: float = 1.0
var _zoom_anchor_screen: Vector2 = Vector2.ZERO
var _zoom_anchor_world: Vector2 = Vector2.ZERO
var _zooming: bool = false

# The FMG menu floats over the map (top-left), so the map can use the whole
# window; only the slim status bar at the bottom is reserved.
var reserved_right: float = 0.0
var reserved_bottom: float = 30.0


func _ready() -> void:
	make_current()
	update_zoom_limits()
	position = map_rect.size / 2.0
	zoom = Vector2(1.0, 1.0)
	_target_zoom = 1.0
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	update_zoom_limits()
	_clamp_position()


## Keeps min_zoom in sync with the map size: the map must always be zoomable
## down to ~40 % of the scale that fits it into the viewport.
func update_zoom_limits() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var usable := Vector2(
		maxf(viewport_size.x - reserved_right, 320.0),
		maxf(viewport_size.y - reserved_bottom, 240.0)
	)
	var fit_scale: float = minf(usable.x / maxf(map_rect.size.x + 40.0, 1.0),
		usable.y / maxf(map_rect.size.y + 40.0, 1.0))
	min_zoom = clampf(fit_scale * 0.4, 0.01, 0.5)
	max_zoom = maxf(min_zoom * 4.0, 24.0)
	_target_zoom = clampf(_target_zoom, min_zoom, max_zoom)


func set_map_rect(rect: Rect2) -> void:
	map_rect = rect
	update_zoom_limits()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			_space_held = event.pressed

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor: float = zoom_step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step
			_zoom_at(mb.position, factor)
			get_viewport().set_input_as_handled()
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT] or ((_space_held or lmb_pan_enabled) and mb.button_index == MOUSE_BUTTON_LEFT):
			_dragging = mb.pressed
			_drag_button = mb.button_index
			_zooming = false
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / zoom.x
		_zoom_anchor_world = get_global_mouse_position()
		_clamp_position()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _zooming:
		return
	var weight: float = clampf(delta * 16.0, 0.0, 1.0)
	var next_zoom: float = lerpf(zoom.x, _target_zoom, weight)
	if absf(next_zoom - _target_zoom) < 0.0015:
		next_zoom = _target_zoom
		_zooming = false
	zoom = Vector2(next_zoom, next_zoom)
	# keep the map point that was under the cursor in place
	var screen_center: Vector2 = get_viewport_rect().size * 0.5
	position += _zoom_anchor_world - _screen_to_world(_zoom_anchor_screen, screen_center)
	_clamp_position()


func _screen_to_world(screen_pos: Vector2, screen_center: Vector2) -> Vector2:
	return position + (screen_pos - screen_center) / zoom.x


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var base_zoom: float = _target_zoom if _zooming else zoom.x
	var new_zoom: float = clampf(base_zoom * factor, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, base_zoom):
		return
	if not smooth_zoom:
		# instant zoom that keeps the map point under the cursor in place
		var world_before := get_global_mouse_position()
		zoom = Vector2(new_zoom, new_zoom)
		var world_after := get_global_mouse_position()
		position += world_before - world_after
		_zooming = false
		_clamp_position()
		return
	_zoom_anchor_screen = screen_pos
	_zoom_anchor_world = _screen_to_world(screen_pos, get_viewport_rect().size * 0.5)
	_target_zoom = new_zoom
	_zooming = true


func _clamp_position() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view: Vector2 = viewport_size * 0.5 / zoom.x
	var margin: float = 300.0
	position.x = clampf(position.x, -margin + half_view.x, map_rect.size.x + margin - half_view.x)
	position.y = clampf(position.y, -margin + half_view.y, map_rect.size.y + margin - half_view.y)
	if half_view.x * 2.0 > map_rect.size.x + margin * 2.0:
		# Centre the map in the area that is not covered by the status bar.
		position.x = map_rect.size.x / 2.0 + reserved_right / (2.0 * zoom.x)
	if half_view.y * 2.0 > map_rect.size.y + margin * 2.0:
		position.y = map_rect.size.y / 2.0 + reserved_bottom / (2.0 * zoom.y)


## Fits the whole map into the visible area (used on generation, on load and by
## the "0" hotkey).
func fit_to_map() -> void:
	update_zoom_limits()
	var viewport_size: Vector2 = get_viewport_rect().size
	var usable_size := Vector2(
		maxf(viewport_size.x - reserved_right, 320.0),
		maxf(viewport_size.y - reserved_bottom, 240.0)
	)
	var z: float = minf(usable_size.x / (map_rect.size.x + 40.0), usable_size.y / (map_rect.size.y + 40.0))
	z = clampf(z, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	_target_zoom = z
	_zooming = false
	# The status bar floats over the bottom of the window: centre the map in the
	# remaining area instead of hiding its lower edge underneath the bar.
	position = map_rect.size / 2.0 + Vector2(reserved_right, reserved_bottom) / (2.0 * z)

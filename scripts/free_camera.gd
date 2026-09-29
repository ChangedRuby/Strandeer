class_name FreeCamera
extends Camera2D
## Free-fly camera for exploring the generated world.
## WASD/arrows pan, Shift pans faster, mouse wheel zooms, right/middle mouse drag pans.

@export var pan_speed: float = 600.0
@export var fast_multiplier: float = 4.0
## Zooming out past the chunk loader's max render distance shows unloaded (empty) space.
@export var zoom_step: float = 1.15

var _dragging: bool = false


func _process(delta: float) -> void:
	var direction := Vector2(
		_key_axis(KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT),
		_key_axis(KEY_W, KEY_UP, KEY_S, KEY_DOWN)
	)
	if direction == Vector2.ZERO:
		return
	var speed: float = pan_speed * (fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	# Divide by zoom so the on-screen pan speed stays constant.
	position += direction.normalized() * speed * delta / zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_set_zoom_level(zoom.x * zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_set_zoom_level(zoom.x / zoom_step)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x


func _set_zoom_level(level: float) -> void:
	zoom = Vector2(level, level)


func _key_axis(negative: Key, negative_alt: Key, positive: Key, positive_alt: Key) -> float:
	var value: float = 0.0
	if Input.is_physical_key_pressed(negative) or Input.is_key_pressed(negative_alt):
		value -= 1.0
	if Input.is_physical_key_pressed(positive) or Input.is_key_pressed(positive_alt):
		value += 1.0
	return value

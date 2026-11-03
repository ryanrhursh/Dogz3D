extends Node3D
## Orbit camera. Right-drag orbits, wheel zooms, WASD pans (and stops following),
## C goes back to following the dog.

@export var follow_target: Node3D
@export var follow := true
@export var distance := 6.5
@export var min_distance := 1.5
@export var max_distance := 16.0
@export var yaw_degrees := 15.0
@export var pitch_degrees := -40.0
@export var pan_speed := 5.0
@export var look_height := 0.35

@onready var camera: Camera3D = $Camera3D

var _focus := Vector3.ZERO
var _orbiting := false


func _ready() -> void:
	if follow_target != null:
		_focus = follow_target.global_position
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = maxf(min_distance, distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = minf(max_distance, distance * 1.1)
			_:
				pass
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		yaw_degrees -= mm.relative.x * 0.3
		pitch_degrees = clampf(pitch_degrees - mm.relative.y * 0.3, -85.0, -8.0)


func toggle_follow() -> void:
	follow = not follow


## Follows a new target (the selected dog). snap jumps there instead of gliding.
func set_target(target: Node3D, snap: bool) -> void:
	follow_target = target
	follow = target != null
	if snap and target != null:
		_focus = target.global_position
		_apply()


func _process(delta: float) -> void:
	var pan := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		pan.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pan.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		pan.x += 1.0

	if pan != Vector3.ZERO:
		follow = false
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
		_focus += yaw_basis * pan.normalized() * pan_speed * delta
	elif follow and follow_target != null:
		_focus = _focus.lerp(follow_target.global_position, 1.0 - exp(-4.0 * delta))
	_apply()


func _apply() -> void:
	var rot := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0))
	var look_at_point := _focus + Vector3(0.0, look_height, 0.0)
	camera.global_position = look_at_point + rot * Vector3(0.0, 0.0, distance)
	camera.look_at(look_at_point, Vector3.UP)

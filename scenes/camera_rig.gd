extends Node3D
## Orbit camera. Right-drag orbits, wheel zooms, WASD pans (and stops following),
## C goes back to following the dog. Close-up mode frames one dog from near by and
## locks panning; leaving it restores the previous view.

@export var follow_target: Node3D
@export var follow := true
@export var distance := 6.5
@export var min_distance := 1.5
@export var max_distance := 16.0
@export var yaw_degrees := 15.0
@export var pitch_degrees := -40.0
@export var pan_speed := 5.0
@export var look_height := 0.35
@export_group("Close-up")
@export var closeup_distance := 1.9
@export var closeup_min_distance := 0.9
@export var closeup_max_distance := 3.5
@export var closeup_pitch_degrees := -32.0
@export var closeup_look_height := 0.3

@onready var camera: Camera3D = $Camera3D

var _focus := Vector3.ZERO
var _orbiting := false
## Values the camera eases toward distance / pitch / look_height (smooth zoom and framing).
var _shown_distance := 6.5
var _shown_pitch := -40.0
var _shown_look_height := 0.35
var _closeup := false
## The view before close-up: distance, pitch, look_height, follow, follow_target, focus,
## min_distance, max_distance.
var _saved_view: Dictionary = {}


func _ready() -> void:
	if follow_target != null:
		_focus = follow_target.global_position
	_snap_shown()
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = maxf(_min_zoom(), distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = minf(_max_zoom(), distance * 1.1)
			_:
				pass
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		yaw_degrees -= mm.relative.x * 0.3
		pitch_degrees = clampf(pitch_degrees - mm.relative.y * 0.3, -85.0, -8.0)


func toggle_follow() -> void:
	if _closeup:
		return
	follow = not follow


## Frames `target` from near by and follows it. Panning is off until exit_closeup.
func enter_closeup(target: Node3D) -> void:
	if target == null:
		return
	if not _closeup:
		_saved_view = {
			"distance": distance,
			"pitch": pitch_degrees,
			"look_height": look_height,
			"follow": follow,
			"follow_target": follow_target,
			"focus": _focus,
		}
	_closeup = true
	follow_target = target
	follow = true
	distance = closeup_distance
	pitch_degrees = closeup_pitch_degrees
	look_height = closeup_look_height


## Back to the view from before enter_closeup (the yaw stays where the player left it).
## If the old target is gone, it follows `fallback` instead.
func exit_closeup(fallback: Node3D = null) -> void:
	if not _closeup:
		return
	_closeup = false
	distance = float(_saved_view.get("distance", distance))
	pitch_degrees = float(_saved_view.get("pitch", pitch_degrees))
	look_height = float(_saved_view.get("look_height", look_height))
	var old_target: Variant = _saved_view.get("follow_target")
	if fallback != null:
		follow_target = fallback
	elif old_target is Node3D and is_instance_valid(old_target):
		follow_target = old_target
	follow = bool(_saved_view.get("follow", true)) and follow_target != null
	if not follow:
		_focus = _saved_view.get("focus", _focus)
	_saved_view.clear()


func is_closeup() -> bool:
	return _closeup


## Jumps straight to the current framing (no easing). For tests and screenshots.
func snap_view() -> void:
	if follow and follow_target != null:
		_focus = follow_target.global_position
	_snap_shown()
	_apply()


## Follows a new target (the selected dog). snap jumps there instead of gliding.
func set_target(target: Node3D, snap: bool) -> void:
	follow_target = target
	follow = target != null
	if snap and target != null:
		_focus = target.global_position
		_snap_shown()
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

	if _closeup:
		pan = Vector3.ZERO
	if pan != Vector3.ZERO:
		follow = false
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
		_focus += yaw_basis * pan.normalized() * pan_speed * delta
	elif follow and follow_target != null:
		_focus = _focus.lerp(follow_target.global_position, 1.0 - exp(-4.0 * delta))
	var ease_amount := 1.0 - exp(-6.0 * delta)
	_shown_distance = lerpf(_shown_distance, distance, ease_amount)
	_shown_pitch = lerpf(_shown_pitch, pitch_degrees, ease_amount)
	_shown_look_height = lerpf(_shown_look_height, look_height, ease_amount)
	_apply()


func _min_zoom() -> float:
	return closeup_min_distance if _closeup else min_distance


func _max_zoom() -> float:
	return closeup_max_distance if _closeup else max_distance


func _snap_shown() -> void:
	_shown_distance = distance
	_shown_pitch = pitch_degrees
	_shown_look_height = look_height


func _apply() -> void:
	var rot := Basis.from_euler(Vector3(deg_to_rad(_shown_pitch), deg_to_rad(yaw_degrees), 0.0))
	var look_at_point := _focus + Vector3(0.0, _shown_look_height, 0.0)
	camera.global_position = look_at_point + rot * Vector3(0.0, 0.0, _shown_distance)
	camera.look_at(look_at_point, Vector3.UP)

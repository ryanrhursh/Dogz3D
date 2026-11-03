class_name Dog
extends CharacterBody3D
## The dog's body: moves, poses, and exposes the world to the brain.
##
## The placeholder visual (capsule torso, sphere head, cone ears) is built in code
## under $Visual. Milestone 4 replaces it with the rigged Blender model; the brain
## and body API below stay the same.

@export var dog_id := "dog_1"
@export var dog_name := "Biscuit"
@export var breed: BreedData
## 0 = new random personality each fresh game.
@export var personality_seed := 0
@export var walk_speed := 1.2
@export var turn_speed := 8.0
## Movement speeds up with the sim clock, but only this far, so fast-forward stays readable.
@export var max_movement_time_scale := 6.0
@export var show_status_label := true

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual_root: Node3D = $Visual
@onready var status_label: Label3D = $StatusLabel

var brain := DogBrain.new()
var sleeping := false
var pose: StringName = &"stand"

var _target := Vector3.ZERO
var _arrive_radius := 0.3
var _moving := false
var _stuck := false
var _stuck_timer := 0.0
var _progress_ref := Vector3.ZERO
var _face_target := Vector3.ZERO
var _has_face_target := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _body_root: Node3D
var _tail_pivot: Node3D
var _ear_pivots: Array[Node3D] = []
var _anim_time := 0.0
var _emote := ""
var _emote_timer := 0.0


func _ready() -> void:
	add_to_group("dogs")
	_build_placeholder()
	var seed_value := personality_seed
	if seed_value == 0:
		seed_value = randi()
	reroll_personality(seed_value)
	_target = global_position
	_progress_ref = global_position


func _process(delta: float) -> void:
	brain.tick(self, SimClock.last_delta_minutes)
	_update_visual(delta)
	_update_label(delta)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var move_scale := 0.0
	if not SimClock.paused:
		move_scale = minf(SimClock.time_scale, max_movement_time_scale)

	var flat := Vector3.ZERO
	if _moving and move_scale > 0.0:
		if _flat_distance(global_position, _target) <= _arrive_radius:
			_moving = false
		else:
			var dir := nav_agent.get_next_path_position() - global_position
			dir.y = 0.0
			if dir.length() < 0.01:
				# Navmesh not ready or no path: steer straight at the target.
				dir = _target - global_position
				dir.y = 0.0
			dir = dir.normalized()
			flat = dir * walk_speed * move_scale
			_turn_toward(dir, delta * move_scale)
			_check_stuck(delta)
	elif _has_face_target and move_scale > 0.0:
		var to_face := _face_target - global_position
		to_face.y = 0.0
		if to_face.length() > 0.05:
			_turn_toward(to_face.normalized(), delta * move_scale)

	velocity.x = flat.x
	velocity.z = flat.z
	move_and_slide()


# --- Body API used by behaviors --------------------------------------------------

func go_to(point: Vector3, arrive_radius: float = 0.3) -> void:
	_target = point
	_arrive_radius = arrive_radius
	_moving = true
	_stuck = false
	_stuck_timer = 0.0
	_progress_ref = global_position
	_has_face_target = false
	nav_agent.target_position = point
	set_pose(&"stand")


func go_to_item(item: WorldItem) -> void:
	go_to(item.get_approach_point(global_position), 0.25)


func stop_moving() -> void:
	_moving = false


func is_moving() -> bool:
	return _moving


func is_stuck() -> bool:
	return _stuck


func face_point(point: Vector3) -> void:
	_face_target = point
	_has_face_target = true


func set_pose(new_pose: StringName) -> void:
	pose = new_pose


func find_nearest_item(affordance: StringName) -> WorldItem:
	var best: WorldItem = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		if item == null or not item.has_affordance(affordance) or not item.is_available():
			continue
		var d := global_position.distance_squared_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	return best


func random_point_near(origin: Vector3, min_dist: float, max_dist: float) -> Vector3:
	var map_rid := get_world_3d().navigation_map
	for i in 8:
		var angle := brain.rng.randf() * TAU
		var dist := brain.rng.randf_range(min_dist, max_dist)
		var candidate := origin + Vector3(sin(angle), 0.0, cos(angle)) * dist
		var on_mesh := NavigationServer3D.map_get_closest_point(map_rid, candidate)
		if _flat_distance(on_mesh, candidate) < 0.3 and _flat_distance(on_mesh, origin) >= min_dist * 0.8:
			return on_mesh
	return NavigationServer3D.map_get_random_point(map_rid, 1, false)


# --- Player interaction (debug stand-ins until milestone 2) ----------------------

func pet() -> void:
	brain.on_petted(sleeping)
	if sleeping:
		show_emote("zz <3", 1.5)
	else:
		show_emote("<3", 1.5)


func show_emote(text: String, seconds: float) -> void:
	_emote = text
	_emote_timer = seconds


func reroll_personality(seed_value: int) -> void:
	if brain.current != null:
		brain.interrupt(self)
	sleeping = false
	set_pose(&"stand")
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = seed_value
	brain.setup(DogPersonality.roll(breed, roll_rng), seed_value)


# --- Save ------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": dog_id,
		"name": dog_name,
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"brain": brain.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	brain.interrupt(self)
	sleeping = false
	_moving = false
	dog_name = str(data.get("name", dog_name))
	var p: Array = data.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation.y = float(data.get("yaw", rotation.y))
	var b: Dictionary = data.get("brain", {})
	brain.from_dict(b)


# --- Internals -------------------------------------------------------------------

func _turn_toward(dir: Vector3, scaled_delta: float) -> void:
	var yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * scaled_delta))


func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < 1.0:
		return
	if _flat_distance(global_position, _progress_ref) < 0.1:
		_stuck = true
		_moving = false
	_stuck_timer = 0.0
	_progress_ref = global_position


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _update_visual(delta: float) -> void:
	if _body_root == null:
		return
	_anim_time += delta

	var target_y := 0.0
	var target_pitch := 0.0
	var ear_droop := 0.0
	match pose:
		&"sit":
			target_y = -0.05
			target_pitch = deg_to_rad(-22.0)
		&"lie":
			target_y = -0.17
		&"sleep":
			target_y = -0.19
			ear_droop = 0.9
		&"eat":
			target_y = -0.03
			target_pitch = deg_to_rad(16.0)
		&"sniff":
			target_pitch = deg_to_rad(9.0)
		_:
			pass

	var blend := 1.0 - exp(-10.0 * delta)
	_body_root.position.y = lerpf(_body_root.position.y, target_y, blend)
	_body_root.rotation.x = lerp_angle(_body_root.rotation.x, target_pitch, blend)

	# Breathing: slow and deep asleep, quicker when moving.
	var breath_rate := 1.2
	if sleeping:
		breath_rate = 0.5
	elif _moving:
		breath_rate = 2.5
	_body_root.scale.y = 1.0 + sin(_anim_time * TAU * breath_rate) * 0.015

	# Tail: wag amplitude and height follow mood.
	var mood := brain.mood()
	var happy := clampf((mood + 0.3) / 1.3, 0.0, 1.0)
	var wag_amp := 0.0
	if not sleeping:
		wag_amp = happy * 0.7
	var wag_speed := 7.0 + happy * 9.0
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_anim_time * wag_speed) * wag_amp
		_tail_pivot.rotation.x = lerpf(-0.25, -1.05, happy)

	# Ears flop down asleep or when unhappy.
	var droop := maxf(ear_droop, clampf(-mood, 0.0, 1.0) * 0.6)
	for i in _ear_pivots.size():
		var side := -1.0 if i == 0 else 1.0
		var ear := _ear_pivots[i]
		ear.rotation.z = lerpf(ear.rotation.z, side * (0.25 + droop * 0.9), blend)


func _update_label(delta: float) -> void:
	if status_label == null:
		return
	status_label.visible = show_status_label
	if not show_status_label:
		return
	if _emote_timer > 0.0:
		_emote_timer -= delta
	var doing := "..."
	if brain.current != null:
		doing = brain.current.label
	var text := "%s\n%s" % [dog_name, doing]
	if sleeping:
		text = "%s\nZzz" % dog_name
	if _emote_timer > 0.0:
		text += "\n" + _emote
	status_label.text = text


func _build_placeholder() -> void:
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.8, 0.6, 0.4)
	if breed != null:
		coat.albedo_color = breed.coat_color
	coat.roughness = 0.9
	var cream := StandardMaterial3D.new()
	cream.albedo_color = coat.albedo_color.lerp(Color(1.0, 0.95, 0.88), 0.7)
	cream.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.05, 0.05)
	dark.roughness = 0.3

	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	visual_root.add_child(_body_root)

	# Torso along +Z (front) / -Z (rear).
	var torso := CapsuleMesh.new()
	torso.radius = 0.16
	torso.height = 0.72
	_add_part(_body_root, torso, coat, Vector3(0.0, 0.33, 0.0), Vector3(90.0, 0.0, 0.0))
	var belly := CapsuleMesh.new()
	belly.radius = 0.12
	belly.height = 0.5
	_add_part(_body_root, belly, cream, Vector3(0.0, 0.27, 0.04), Vector3(90.0, 0.0, 0.0))

	var leg := CylinderMesh.new()
	leg.top_radius = 0.045
	leg.bottom_radius = 0.04
	leg.height = 0.22
	for x in [-0.09, 0.09]:
		for z in [-0.22, 0.2]:
			_add_part(_body_root, leg, cream, Vector3(x, 0.11, z), Vector3.ZERO)

	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	_add_part(_body_root, head, coat, Vector3(0.0, 0.5, 0.36), Vector3.ZERO)
	var snout := BoxMesh.new()
	snout.size = Vector3(0.11, 0.09, 0.14)
	_add_part(_body_root, snout, cream, Vector3(0.0, 0.46, 0.5), Vector3.ZERO)
	var nose := SphereMesh.new()
	nose.radius = 0.03
	nose.height = 0.06
	_add_part(_body_root, nose, dark, Vector3(0.0, 0.48, 0.575), Vector3.ZERO)
	var eye := SphereMesh.new()
	eye.radius = 0.022
	eye.height = 0.044
	_add_part(_body_root, eye, dark, Vector3(-0.055, 0.54, 0.47), Vector3.ZERO)
	_add_part(_body_root, eye, dark, Vector3(0.055, 0.54, 0.47), Vector3.ZERO)

	var ear := CylinderMesh.new()
	ear.top_radius = 0.0
	ear.bottom_radius = 0.05
	ear.height = 0.15
	for x in [-0.075, 0.075]:
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 0.6, 0.33)
		_body_root.add_child(pivot)
		_add_part(pivot, ear, coat, Vector3(0.0, 0.075, 0.0), Vector3.ZERO)
		_ear_pivots.append(pivot)

	_tail_pivot = Node3D.new()
	_tail_pivot.position = Vector3(0.0, 0.38, -0.36)
	_body_root.add_child(_tail_pivot)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.018
	tail.bottom_radius = 0.035
	tail.height = 0.18
	_add_part(_tail_pivot, tail, coat, Vector3(0.0, 0.09, 0.0), Vector3.ZERO)

	if breed != null:
		visual_root.scale = Vector3.ONE * breed.size_scale


func _add_part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3,
		rot_degrees: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation_degrees = rot_degrees
	parent.add_child(part)
	return part

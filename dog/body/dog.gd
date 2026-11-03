class_name Dog
extends CharacterBody3D
## The dog's body: moves, poses, and exposes the world to the brain.
##
## The placeholder visual (capsule torso, sphere head, cone ears) is built in code
## under $Visual. Milestone 8 (art pass) replaces it with the rigged Blender model; the brain
## and body API below stay the same.

@export var dog_id := "dog_1"
@export var dog_name := "Biscuit"
@export var breed: BreedData
## 0 = new random personality each fresh game.
@export var personality_seed := 0
@export var walk_speed := 1.2
## Speed multiplier for set_gait(&"run").
@export var run_speed_multiplier := 2.2
@export var turn_speed := 8.0
## Highest point (world y) the dog can grab something from.
const MAX_REACH_HEIGHT := 0.45
## How far off the navmesh an item may be and still be reachable.
const REACH_SLACK := 0.45
## Moving dogs steer away from other dogs closer than this (flat metres).
const SEPARATION_RADIUS := 0.65
const SEPARATION_WEIGHT := 1.2
## No separation this close to the destination, so friends can share a bed.
const SEPARATION_ARRIVE_ZONE := 1.0
## Game minutes an invitation (play) stays open.
const INVITE_MINUTES := 4.0
## Re-evaluations allowed per frame on top of the pack's average need (see evals_per_frame).
const EVAL_SLACK := 2

## Every dog in the simulation (cheaper than querying the group each physics tick).
static var _all_dogs: Array = []
## dog_id -> Dog for the same dogs.
static var _dogs_by_id: Dictionary = {}
## Per-frame budget of routine brain re-evaluations, shared by all dogs.
static var _eval_frame := -1
static var _evals_left := 0

## Movement speeds up with the sim clock, but only this far, so fast-forward stays readable.
@export var max_movement_time_scale := 6.0
@export var show_status_label := true

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual_root: Node3D = $Visual
@onready var status_label: Label3D = $StatusLabel

var brain := DogBrain.new()
var sleeping := false
var pose: StringName = &"stand"
var gait: StringName = &"walk"
## The item in the dog's mouth, if any.
var held_item: WorldItem
## Zone id -> TouchZone.
var touch_zones: Dictionary = {}
## Items this dog has claimed a slot on (bowl it's eating from, its bed).
var _claims: Array[WorldItem] = []
## Items this dog is waiting in line for.
var _queues: Array[WorldItem] = []
## dog_id of the dog this one is greeting or playing with, "" if none. Others read it via
## get_dog_info, so a game of chase only runs while both dogs point at each other.
var social_partner_id := ""
## Invitation kind (StringName) -> [from dog_id, SimClock.total_minutes when sent].
var _invites: Dictionary = {}

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
var _mouth: Node3D
var _tail_pivot: Node3D
var _ear_pivots: Array[Node3D] = []
var _anim_time := 0.0
var _emote := ""
var _emote_timer := 0.0


func _ready() -> void:
	add_to_group("dogs")
	if not _all_dogs.has(self):
		_all_dogs.append(self)
	_dogs_by_id[dog_id] = self
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
			var push := _separation_push()
			if push != Vector3.ZERO:
				dir = (dir + push * SEPARATION_WEIGHT).normalized()
			var speed := walk_speed
			if gait == &"run":
				speed *= run_speed_multiplier
			flat = dir * speed * move_scale
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


## &"walk" or &"run". Behaviors that set run should reset to walk in exit().
func set_gait(new_gait: StringName) -> void:
	gait = new_gait


## Nearest available item with the affordance that nobody is carrying and that has a
## free slot for this dog (other dogs' claims count).
func find_nearest_item(affordance: StringName) -> WorldItem:
	var best: WorldItem = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		if item == null or item.held or not item.has_affordance(affordance) \
				or not item.is_available() or not item.is_free_for(self):
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


## Item with the affordance currently held out by the player's hand, nearest first.
func find_offered_item(affordance: StringName) -> WorldItem:
	var best: WorldItem = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		if item == null or not item.is_held_by_player() or not item.has_affordance(affordance):
			continue
		var d := global_position.distance_squared_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	return best


## Nearest usable item with the affordance that is busy for this dog right now (all
## slots taken, or others are waiting first). For waiting in line, not for using.
func find_busy_item(affordance: StringName) -> WorldItem:
	var best: WorldItem = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		if item == null or item.held or not item.has_affordance(affordance) \
				or not item.is_available() or item.is_free_for(self):
			continue
		var d := global_position.distance_squared_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	return best


## Gets in line for a busy item. Leave with leave_queue in the behavior's exit().
## Claiming the item also takes the dog out of the line.
func join_queue(item: WorldItem) -> void:
	if item == null or not is_instance_valid(item):
		return
	item.enqueue(self)
	if not _queues.has(item):
		_queues.append(item)


func leave_queue(item: WorldItem) -> void:
	_queues.erase(item)
	if item != null and is_instance_valid(item):
		item.dequeue(self)


## Nearest item with the affordance that is full, but only with dogs that are friends
## with this one both ways (affinity >= min_affinity), and that has a share slot free.
## Claim it with claim_item(item, true).
func find_shared_item(affordance: StringName, min_affinity: float) -> WorldItem:
	var best: WorldItem = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		if item == null or item.held or not item.has_affordance(affordance) \
				or not item.is_available() or not item.has_share_slot():
			continue
		var users := item.get_users()
		if users.is_empty() or users.has(self):
			continue
		var all_friends := true
		for user in users:
			var other := user as Dog
			if other == null or brain.memory.get_affinity(other.dog_id) < min_affinity \
					or other.brain.memory.get_affinity(dog_id) < min_affinity:
				all_friends = false
				break
		if not all_friends:
			continue
		var d := global_position.distance_squared_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	return best


## Claims a slot on the item so other dogs look elsewhere. Release in the behavior's
## exit(). False if another dog got there first. `shared` may take a friend's share slot.
func claim_item(item: WorldItem, shared: bool = false) -> bool:
	_prune_claims()
	if item == null or not is_instance_valid(item) or not item.reserve(self, shared):
		return false
	if not _claims.has(item):
		_claims.append(item)
	return true


func release_item(item: WorldItem) -> void:
	if item == null or not is_instance_valid(item):
		return
	_claims.erase(item)
	item.release(self)


func release_all_claims() -> void:
	_prune_claims()
	for item in _claims.duplicate():
		release_item(item)
	for i in _queues.size():
		if is_instance_valid(_queues[i]):
			_queues[i].dequeue(self)
	_queues.clear()


func _prune_claims() -> void:
	for i in range(_claims.size() - 1, -1, -1):
		if not is_instance_valid(_claims[i]):
			_claims.remove_at(i)


## The brain asks before a routine re-evaluation. False means the frame's budget is used
## up; the brain stays due and asks again next frame.
func take_eval_slot() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _eval_frame:
		_eval_frame = frame
		_evals_left = evals_per_frame()
	if _evals_left <= 0:
		return false
	_evals_left -= 1
	return true


## Enough slots for the pack's average evaluation rate at the current speed, plus slack:
## a lone dog is never held back, and a burst of due dogs is spread over a few frames.
static func evals_per_frame() -> int:
	var per_frame := float(_all_dogs.size()) * SimClock.last_delta_minutes \
			/ DogBrain.EVAL_INTERVAL_MINUTES
	return ceili(per_frame) + EVAL_SLACK


# --- Other dogs (brains never touch other brains; they ask the body) ------------

## dog_id of the nearest other dog within `max_dist` (flat metres) for which
## `filter.call(info)` is true (info as from get_dog_info), or "" if none.
func find_nearest_dog(max_dist: float, filter: Callable = Callable()) -> String:
	var best_id := ""
	var best_dist := max_dist
	for other: Dog in _all_dogs:
		if other == self or not is_instance_valid(other):
			continue
		var d := _flat_distance(global_position, other.global_position)
		if d > best_dist:
			continue
		if filter.is_valid() and not bool(filter.call(other._info_for(self))):
			continue
		best_dist = d
		best_id = other.dog_id
	return best_id


## dog_ids of the other dogs within `max_dist` (flat metres), nearest first. Cheaper than
## find_nearest_dog when the behavior can rule most dogs out from its own memory before
## asking get_dog_info.
func dogs_near(max_dist: float) -> PackedStringArray:
	var dists := PackedFloat32Array()
	var ids := PackedStringArray()
	var max_sq := max_dist * max_dist
	var here := global_position
	for other: Dog in _all_dogs:
		if other == self:
			continue
		var there := other.global_position
		var dx := there.x - here.x
		var dz := there.z - here.z
		var d_sq := dx * dx + dz * dz
		if d_sq <= max_sq:
			var at := dists.bsearch(d_sq)
			dists.insert(at, d_sq)
			ids.insert(at, other.dog_id)
	return ids


## What this dog can observe about another dog: id, name, position, distance,
## doing (behavior id), sleeping, moving, mood (-1..1), partner (its social_partner_id)
## and affinity_to_me (how it feels about this dog). Empty if there's no such dog.
func get_dog_info(id: String) -> Dictionary:
	var other := _dog_by_id(id)
	if other == null:
		return {}
	return other._info_for(self)


## Asks another dog to join in (`kind` e.g. &"play"). Its behaviors see it with get_invite.
func invite_dog(id: String, kind: StringName) -> bool:
	var other := _dog_by_id(id)
	if other == null:
		return false
	other._invites[kind] = [dog_id, SimClock.total_minutes]
	return true


## dog_id of whoever invited this dog to `kind` in the last INVITE_MINUTES, or "".
func get_invite(kind: StringName) -> String:
	if not _invites.has(kind):
		return ""
	var entry: Array = _invites[kind]
	if SimClock.total_minutes - float(entry[1]) > INVITE_MINUTES:
		_invites.erase(kind)
		return ""
	return str(entry[0])


func clear_invite(kind: StringName) -> void:
	_invites.erase(kind)


## Tells another dog something social happened between them (&"greeted", &"played").
## That dog's body passes it to its own brain.
func notify_dog(id: String, kind: StringName) -> void:
	var other := _dog_by_id(id)
	if other != null:
		other.receive_social(dog_id, dog_name, kind)


func receive_social(from_id: String, from_name: String, kind: StringName) -> void:
	brain.on_social(from_id, from_name, kind)


func set_social_partner(id: String) -> void:
	social_partner_id = id


func _info_for(asker: Dog) -> Dictionary:
	var doing: StringName = &""
	if brain.current != null:
		doing = brain.current.id
	return {
		"id": dog_id,
		"name": dog_name,
		"position": global_position,
		"distance": _flat_distance(global_position, asker.global_position),
		"doing": doing,
		"sleeping": sleeping,
		"moving": _moving,
		"mood": brain.mood(),
		"partner": social_partner_id,
		"affinity_to_me": brain.memory.get_affinity(asker.dog_id),
	}


func _dog_by_id(id: String) -> Dog:
	if id == "" or id == dog_id:
		return null
	var other: Dog = _dogs_by_id.get(id)
	if other == null or not is_instance_valid(other):
		return null
	return other


## Sum of pushes away from dogs within SEPARATION_RADIUS. Zero when no dog is that
## close, so a lone dog moves exactly as before.
func _separation_push() -> Vector3:
	if _all_dogs.size() < 2 or _flat_distance(global_position, _target) < SEPARATION_ARRIVE_ZONE:
		return Vector3.ZERO
	var push := Vector3.ZERO
	for other: Dog in _all_dogs:
		if other == self or not is_instance_valid(other):
			continue
		var offset := global_position - other.global_position
		offset.y = 0.0
		var d := offset.length()
		if d < SEPARATION_RADIUS and d > 0.001:
			push += offset / d * (1.0 - d / SEPARATION_RADIUS)
	return push


## True if the dog can walk close enough to put its mouth on `point`
## (on the navmesh and low enough: not on the table).
func can_reach(point: Vector3) -> bool:
	if point.y > MAX_REACH_HEIGHT:
		return false
	var map_rid := get_world_3d().navigation_map
	var on_mesh := NavigationServer3D.map_get_closest_point(map_rid, point)
	return _flat_distance(on_mesh, point) <= REACH_SLACK


## Takes the item in the mouth. Fails if someone else is holding it.
func pick_up(item: WorldItem) -> bool:
	if item == null or not is_instance_valid(item) or item.held:
		return false
	if held_item != null:
		drop_held()
	held_item = item
	item.attach_to(_mouth)
	return true


## Drops whatever is in the mouth, optionally tossing it.
func drop_held(velocity: Vector3 = Vector3.ZERO) -> void:
	if held_item == null:
		return
	if is_instance_valid(held_item) and held_item.holder == _mouth:
		held_item.detach(velocity)
	held_item = null


## The point the mouth is at, for behaviors lining up with items.
func get_mouth_position() -> Vector3:
	return _mouth.global_position


# --- Player interaction (debug stand-ins until milestone 3, Hands) ----------------------

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
	drop_held()
	release_all_claims()
	social_partner_id = ""
	_invites.clear()
	sleeping = false
	set_pose(&"stand")
	set_gait(&"walk")
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = seed_value
	# Touch prefs roll after personality from the same RNG, so the personality
	# (and the brain's decision RNG) for a given seed stays what it was.
	var new_personality := DogPersonality.roll(breed, roll_rng)
	var prefs := DogTouchPrefs.roll(new_personality, roll_rng)
	brain.setup(new_personality, seed_value, prefs)


## Takes the dog out of the simulation before it's freed (rehomed, removed by load).
func retire() -> void:
	brain.interrupt(self)
	drop_held()
	release_all_claims()
	social_partner_id = ""
	_invites.clear()
	remove_from_group("dogs")
	_unregister()
	set_process(false)
	set_physics_process(false)


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
	drop_held()
	release_all_claims()
	sleeping = false
	_moving = false
	set_gait(&"walk")
	dog_name = str(data.get("name", dog_name))
	var p: Array = data.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation.y = float(data.get("yaw", rotation.y))
	var b: Dictionary = data.get("brain", {})
	brain.from_dict(b)


# --- Internals -------------------------------------------------------------------

func _exit_tree() -> void:
	_unregister()


func _unregister() -> void:
	_all_dogs.erase(self)
	if _dogs_by_id.get(dog_id) == self:
		_dogs_by_id.erase(dog_id)


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

	_mouth = Node3D.new()
	_mouth.name = "Mouth"
	_mouth.position = Vector3(0.0, 0.43, 0.62)
	_body_root.add_child(_mouth)

	_build_touch_zones()

	if breed != null:
		visual_root.scale = Vector3.ONE * breed.size_scale


## Touch zones ride on BodyRoot so they follow poses. Milestone 8 moves them onto
## bone attachments of the rigged model. A zero y size makes a sphere.
func _build_touch_zones() -> void:
	var specs := {
		&"head": [Vector3(0.0, 0.5, 0.4), Vector3(0.15, 0.0, 0.0)],
		&"ears": [Vector3(0.0, 0.67, 0.33), Vector3(0.28, 0.12, 0.12)],
		&"back": [Vector3(0.0, 0.47, -0.06), Vector3(0.28, 0.1, 0.5)],
		&"belly": [Vector3(0.0, 0.2, 0.02), Vector3(0.24, 0.12, 0.42)],
	}
	for zone_id: StringName in specs:
		var spec: Array = specs[zone_id]
		var zone := TouchZone.new()
		zone.configure(self, zone_id, spec[1])
		zone.position = spec[0]
		_body_root.add_child(zone)
		touch_zones[zone_id] = zone


func _add_part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3,
		rot_degrees: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation_degrees = rot_degrees
	parent.add_child(part)
	return part

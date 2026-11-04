class_name HandTool
extends Node3D
## The player's hand in close-up mode. A camera raycast finds what's under the cursor:
## hovering a touch zone of the close-up dog highlights it, a press pats it, and dragging
## strokes it (one stroke per STROKE_DISTANCE of hand travel). Pressing on the food bowl
## or treat jar takes a piece (the item's hand_piece); letting go near a dog's head feeds
## it, anywhere else drops it on the floor. Pressing on the ball (on the floor or in a
## dog's mouth) grabs it; letting go while the hand moves fast throws it with the hand's
## recent velocity, a slow release just drops it. Off in Live mode, where LMB selects dogs.
##
## Items held by the hand follow the Anchor child, which is in group "player_hands".
## Code-facing API (tests, and the --autohands soak later): stroke(), pick_from(),
## release_at(), throw_item().

signal reaction_shown(dog: Dog, zone: StringName, reaction: StringName)

const RAY_LENGTH := 60.0
## Physics layers the hand ray hits: world | touch | items.
const RAY_MASK := 1 | TouchZone.TOUCH_LAYER | 8
## Metres of hand travel per stroke while dragging over the dog.
const STROKE_DISTANCE := 0.15
## The hand marker hovers this far off the surface it points at.
const MARKER_LIFT := 0.04
const LABEL_OFFSET := Vector2(18.0, 10.0)
const ZONE_NAMES := {&"head": "Head", &"ears": "Ears", &"back": "Back", &"belly": "Belly"}
## Carried food floats this high over the floor (dog-head height).
const CARRY_HEIGHT := 0.35
## Let go within this distance of a dog's mouth and it eats from the hand.
const FEED_RADIUS := 0.45
## Dogs within this many flat metres notice food in the hand...
const NOTICE_RANGE := 4.0
## ...when it's picked up and each time the hand has moved this far since.
const NOTICE_EVERY := 1.5
## Hand velocity is measured over this many real seconds of hand points.
const VELOCITY_WINDOW := 0.1
## A release with the hand moving slower than this (flat m/s) drops instead of throwing.
const THROW_MIN_SPEED := 1.2
## Throws are capped at this speed (m/s), so a wild flick stays in the room.
const MAX_THROW_SPEED := 7.0
## A mouse throw gets this much upward speed per m/s of flat speed, for an arc.
const THROW_LIFT := 0.3
## Vertical hand speed (m/s) a mouse throw keeps, before the lift.
const THROW_MAX_UP := 2.0
## Awake dogs within this many flat metres see a throw.
const THROW_NOTICE_RANGE := 10.0

## &"off" (Live mode), &"hover", &"petting", or &"carrying" (from step 3).
var state: StringName = &"off"
## The close-up dog. Only its zones respond.
var dog: Dog
## The zone under the cursor (or being stroked), null if none.
var hovered_zone: TouchZone
## The item under the cursor the hand could take from or pick up, null if none.
var hovered_item: WorldItem
## What the hand carries (state &"carrying"), null otherwise.
var held_item: WorldItem
## What the last touch did, for the overlay: dog name, zone, reaction, strokes.
var last_reaction := ""
## Where the hand is in the world (the point it touches or hovers over).
var hand_point := Vector3.ZERO

var anchor: Node3D

var _marker: MeshInstance3D
var _ui: CanvasLayer
var _zone_label: Label
var _hint: Label
var _has_point := false
## While petting: the drag plane (through the press point, facing the camera), the last
## hand point on it, and travel not yet turned into a stroke.
var _drag_plane := Plane()
var _last_drag_point := Vector3.ZERO
var _travel := 0.0
var _press_strokes := 0
var _last_notice_point := Vector3.ZERO
## Recent hand points while carrying, [real seconds, point], oldest first.
var _samples: Array = []
## True between activate() and deactivate(): the mouse drives the hand. The code API
## works without it (state can be &"carrying" in Live mode then).
var _closeup := false


func _ready() -> void:
	add_to_group("hand_tool")
	anchor = Node3D.new()
	anchor.name = "Anchor"
	anchor.add_to_group("player_hands")
	add_child(anchor)
	_build_marker()
	_build_ui()
	_set_visuals(false)


## True in close-up mode (the mouse drives the hand).
func is_active() -> bool:
	return _closeup


## Turns the hand on for the close-up dog `target`.
func activate(target: Dog) -> void:
	if target != dog:
		_end_press()
		_set_hover(null)
	dog = target
	_closeup = true
	if state == &"off":
		state = &"hover"
	_hint.text = ("Close-up with %s   ·   LMB pat, drag to stroke   ·   Esc back\n" \
			+ "hold LMB on bowl or jar, let go at the head to feed   ·   " \
			+ "grab the ball, flick and let go to throw") % target.dog_name
	_set_visuals(true)


func deactivate() -> void:
	if held_item != null:
		_drop(hand_point)
	_end_press()
	_set_hover(null)
	hovered_item = null
	state = &"off"
	dog = null
	_closeup = false
	_has_point = false
	_set_visuals(false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# --- Code-facing API -----------------------------------------------------------------

## Strokes `zone_id` on `target` (`strokes` strokes; 1 is a pat), with the hand placed just
## above the zone. Works in either mode. Returns the reaction.
func stroke(target: Dog, zone_id: StringName, strokes: int = 1) -> StringName:
	if target == null or not is_instance_valid(target):
		return &""
	var zone: TouchZone = target.touch_zones.get(zone_id)
	var point := target.global_position + Vector3(0.0, 0.6, 0.0)
	if zone != null:
		point = zone.global_position + Vector3(0.0, 0.15, 0.0)
	_move_hand(point)
	return _touch(target, zone_id, strokes, point)


## Takes a piece from `item` (kibble from a bowl with enough fill, a treat from the jar)
## or picks up a loose movable item (a dropped treat, the ball, also from a dog's mouth).
## The hand starts carrying it and nearby dogs notice food. False if there's nothing to
## take or the hand is already full.
func pick_from(item: WorldItem) -> bool:
	if item == null or not is_instance_valid(item) or held_item != null:
		return false
	if item.held:
		var mouth := _dog_holding(item)
		if mouth == null or not item.movable:
			return false
		mouth.drop_held()
	var piece: WorldItem = null
	if item.hand_piece != null:
		if item.fill < item.hand_piece_fill - 0.0001:
			return false
		item.consume(item.hand_piece_fill)
		piece = item.hand_piece.instantiate()
		item.get_parent().add_child(piece)
	elif item.movable:
		piece = item
	else:
		return false
	if not _has_point or hand_point.distance_to(item.global_position) > 1.0:
		_move_hand(item.global_position + Vector3(0.0, CARRY_HEIGHT, 0.0))
	piece.attach_to(anchor)
	held_item = piece
	_samples.clear()
	state = &"carrying"
	_set_hover(null)
	hovered_item = null
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	_notice_dogs()
	return true


## Moves the hand (and what it carries) to `point`. Dogs re-notice the food every
## NOTICE_EVERY metres.
func carry_to(point: Vector3) -> void:
	_move_hand(point)
	if held_item != null and point.distance_to(_last_notice_point) >= NOTICE_EVERY:
		_notice_dogs()


## Lets go of the carried item at `point`: near an awake dog's mouth it feeds that dog,
## anywhere else it drops to the floor below. Returns the dog that ate, or null.
func release_at(point: Vector3) -> Dog:
	if held_item == null:
		return null
	if not is_instance_valid(held_item):
		_forget_held()
		return null
	_move_hand(point)
	var item := held_item
	var eater := _dog_at_mouth(point)
	if eater != null and eater.feed_from_hand(item):
		_forget_held()
		last_reaction = "%s ate the %s" % [eater.dog_name, item.display_name.to_lower()]
		return eater
	_drop(point)
	return null


## Throws the carried item from where the hand is with `velocity` (capped at
## MAX_THROW_SPEED). Awake dogs in sight notice (&"ball_thrown") and may chase it. Items
## without a physics body can't fly: they're released as with release_at. True if thrown.
func throw_item(velocity: Vector3) -> bool:
	if held_item == null:
		return false
	if not is_instance_valid(held_item):
		_forget_held()
		return false
	var item := held_item
	if item.physics_body == null:
		release_at(hand_point)
		return false
	_forget_held()
	item.detach(velocity.limit_length(MAX_THROW_SPEED))
	last_reaction = "threw the %s" % item.display_name.to_lower()
	for node in get_tree().get_nodes_in_group("dogs"):
		var d := node as Dog
		if d == null or d.sleeping:
			continue
		var offset := d.global_position - hand_point
		offset.y = 0.0
		if offset.length() <= THROW_NOTICE_RANGE:
			d.notice(&"ball_thrown", hand_point)
	return true


## The hand's velocity over the last VELOCITY_WINDOW real seconds while carrying (zero if
## it has too few points). `now` is in real seconds; it defaults to the current time.
func hand_velocity(now: float = -1.0) -> Vector3:
	if now < 0.0:
		now = Time.get_ticks_usec() / 1000000.0
	if _samples.size() < 2:
		return Vector3.ZERO
	var newest: Array = _samples.back()
	if now - float(newest[0]) > VELOCITY_WINDOW:
		return Vector3.ZERO
	var oldest: Array = newest
	for sample: Array in _samples:
		if now - float(sample[0]) <= VELOCITY_WINDOW:
			oldest = sample
			break
	var dt := float(newest[0]) - float(oldest[0])
	if dt < 0.01:
		return Vector3.ZERO
	var to: Vector3 = newest[1]
	var from: Vector3 = oldest[1]
	return (to - from) / dt


## Records a hand point at real time `at` (seconds) for hand_velocity. _move_hand does
## this while carrying; tests call it with made-up times.
func add_hand_sample(point: Vector3, at: float) -> void:
	_samples.append([at, point])
	while _samples.size() > 2 and at - float(_samples[0][0]) > VELOCITY_WINDOW * 2.0:
		_samples.pop_front()


## The throw a mouse release makes from hand velocity `v`: the flat part as is, the
## vertical part capped, plus some lift for an arc. Zero if the hand was too slow.
static func throw_from_hand(v: Vector3) -> Vector3:
	var flat := Vector2(v.x, v.z).length()
	if flat < THROW_MIN_SPEED:
		return Vector3.ZERO
	return Vector3(v.x, clampf(v.y, -THROW_MAX_UP, THROW_MAX_UP) + flat * THROW_LIFT, v.z)


## Starts a press on `zone` with the hand at `point`: pats it once. Mouse input and
## tests both come through here.
func press_zone(zone: TouchZone, point: Vector3) -> void:
	if zone == null or zone.dog == null or zone.dog != dog:
		return
	state = &"petting"
	_set_hover(zone)
	var cam := get_viewport().get_camera_3d()
	var normal := Vector3.UP
	if cam != null:
		normal = cam.global_transform.basis.z
	_drag_plane = Plane(normal, point)
	_last_drag_point = point
	_travel = 0.0
	_press_strokes = 0
	_move_hand(point)
	_touch(dog, zone.zone_id, 1, point)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)


## Moves a pressed hand to `point`. Travel while over a zone of the dog (`zone`, null if
## the hand has slid off it) turns into strokes on that zone. Returns strokes sent.
func drag_to(point: Vector3, zone: TouchZone) -> int:
	if state != &"petting":
		return 0
	var moved := point.distance_to(_last_drag_point)
	_last_drag_point = point
	_move_hand(point)
	if zone == null or zone.dog != dog:
		_set_hover(null)
		return 0
	_set_hover(zone)
	_travel += moved
	var count := floori(_travel / STROKE_DISTANCE)
	if count <= 0:
		return 0
	_travel -= count * STROKE_DISTANCE
	_press_strokes += count
	_touch(dog, zone.zone_id, count, point)
	return count


## Ends a press.
func release() -> void:
	_end_press()


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _closeup:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			var hit := _raycast(mb.position)
			var collider: Object = hit.get("collider")
			var zone := collider as TouchZone
			if zone != null and zone.dog == dog:
				press_zone(zone, hit["position"])
			elif collider != null:
				pick_from(WorldItem.from_collider(collider))
		elif state == &"carrying":
			_release_from_mouse()
		else:
			release()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and state == &"petting":
		_drag_from_screen((event as InputEventMouseMotion).position)


func _process(_delta: float) -> void:
	if state == &"carrying" and (held_item == null or not is_instance_valid(held_item)):
		_forget_held()
	if not _closeup:
		return
	if not is_instance_valid(dog):
		deactivate()
		return
	var mouse := get_viewport().get_mouse_position()
	if state == &"hover":
		_hover_from_screen(mouse)
	elif state == &"carrying":
		_carry_from_screen(mouse)
	_zone_label.position = mouse + LABEL_OFFSET
	_zone_label.visible = hovered_zone != null or hovered_item != null or held_item != null
	if hovered_zone != null:
		_zone_label.text = ZONE_NAMES.get(hovered_zone.zone_id, String(hovered_zone.zone_id))
	elif held_item != null:
		_zone_label.text = held_item.display_name
	elif hovered_item != null:
		_zone_label.text = hovered_item.display_name
	_marker.visible = _has_point


func _hover_from_screen(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		_has_point = false
		_set_hover(null)
		return
	var point: Vector3 = hit["position"]
	_move_hand(point + Vector3(hit["normal"]) * MARKER_LIFT)
	var collider: Object = hit.get("collider")
	var zone := collider as TouchZone
	hovered_item = null
	if zone != null and zone.dog == dog:
		_set_hover(zone)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return
	_set_hover(null)
	var item := WorldItem.from_collider(collider)
	if _can_take(item):
		hovered_item = item
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## Carried food floats CARRY_HEIGHT over whatever is under the cursor, or sits right at
## a dog's touch zone (so it can go to the head).
func _carry_from_screen(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos)
	if hit.is_empty():
		return
	var point: Vector3 = hit["position"]
	if hit.get("collider") is TouchZone:
		carry_to(point)
		return
	var normal: Vector3 = hit["normal"]
	if normal.y > 0.5:
		carry_to(point + Vector3(0.0, CARRY_HEIGHT, 0.0))
	else:
		carry_to(point + normal * 0.15)


func _drag_from_screen(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var on_plane: Variant = _drag_plane.intersects_ray(from, dir)
	if on_plane == null:
		return
	var hit := _raycast(screen_pos)
	var zone := hit.get("collider") as TouchZone
	drag_to(on_plane, zone)


func _raycast(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	query.collide_with_areas = true
	# A carried ball rides at the hand point: don't let the ray land on it.
	if held_item != null and is_instance_valid(held_item) and held_item.physics_body != null:
		query.exclude = [held_item.physics_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Mouse release while carrying: a throwable item leaves with the hand's velocity if the
## hand was moving fast enough, everything else is let go at the hand.
func _release_from_mouse() -> void:
	if held_item != null and is_instance_valid(held_item) \
			and held_item.has_affordance(&"throwable"):
		var v := throw_from_hand(hand_velocity())
		if v != Vector3.ZERO:
			throw_item(v)
			return
	release_at(hand_point)


## True if the hand could take `item`: a piece source, or a loose movable item that is
## lying around or in a dog's mouth.
func _can_take(item: WorldItem) -> bool:
	if item == null or not (item.hand_piece != null or item.movable):
		return false
	return not item.held or _dog_holding(item) != null


## The dog with `item` in its mouth, or null.
func _dog_holding(item: WorldItem) -> Dog:
	for node in get_tree().get_nodes_in_group("dogs"):
		var d := node as Dog
		if d != null and d.held_item == item:
			return d
	return null


# --- Internals -----------------------------------------------------------------------

func _touch(target: Dog, zone_id: StringName, strokes: int, point: Vector3) -> StringName:
	var reaction := target.touch(zone_id, strokes, point)
	var total := strokes
	if state == &"petting":
		total = _press_strokes + 1
	last_reaction = "%s %s: %s (x%d)" % [target.dog_name, zone_id, reaction, total]
	reaction_shown.emit(target, zone_id, reaction)
	return reaction


func _drop(point: Vector3) -> void:
	var item := held_item
	_forget_held()
	if item == null or not is_instance_valid(item):
		return
	item.detach()
	# Things that roll just fall from the hand; the rest land on the surface below.
	if item.physics_body == null:
		item.get_root().global_position = _floor_below(point)
	last_reaction = "dropped the %s" % item.display_name.to_lower()


func _forget_held() -> void:
	held_item = null
	if state == &"carrying":
		state = &"hover" if _closeup else &"off"
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## The nearest awake dog whose mouth is within FEED_RADIUS of `point`, or null.
func _dog_at_mouth(point: Vector3) -> Dog:
	var best: Dog = null
	var best_dist := FEED_RADIUS
	for node in get_tree().get_nodes_in_group("dogs"):
		var d := node as Dog
		if d == null or d.sleeping:
			continue
		var dist := d.get_mouth_position().distance_to(point)
		if dist <= best_dist:
			best_dist = dist
			best = d
	return best


func _notice_dogs() -> void:
	_last_notice_point = hand_point
	if held_item == null or not held_item.has_affordance(&"food"):
		return
	for node in get_tree().get_nodes_in_group("dogs"):
		var d := node as Dog
		if d == null:
			continue
		var offset := d.global_position - hand_point
		offset.y = 0.0
		if offset.length() <= NOTICE_RANGE:
			d.notice(&"food_offered", hand_point)


## The world surface straight below `point` (floor or table top).
func _floor_below(point: Vector3) -> Vector3:
	var from := point + Vector3(0.0, 0.05, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3(point.x, 0.0, point.z)
	return hit["position"]


func _end_press() -> void:
	if state == &"petting":
		state = &"hover" if _closeup else &"off"
	_travel = 0.0
	_press_strokes = 0
	if state == &"hover":
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _set_hover(zone: TouchZone) -> void:
	if zone == hovered_zone:
		return
	if hovered_zone != null and is_instance_valid(hovered_zone):
		hovered_zone.set_highlight(false)
	hovered_zone = zone
	if zone != null:
		zone.set_highlight(true)


func _move_hand(point: Vector3) -> void:
	hand_point = point
	_has_point = true
	anchor.global_position = point
	_marker.global_position = point
	# The held item would catch up next physics frame; move it now so it never lags.
	if held_item != null and is_instance_valid(held_item):
		held_item.get_root().global_position = point
		add_hand_sample(point, Time.get_ticks_usec() / 1000000.0)


func _set_visuals(on: bool) -> void:
	_marker.visible = on and _has_point
	_zone_label.visible = false
	_hint.visible = on


## A soft, flattened palm with four finger nubs, so the cursor reads as a hand in 3D.
func _build_marker() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.86, 0.72)
	mat.roughness = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	_marker.top_level = true
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var palm := SphereMesh.new()
	palm.radius = 0.05
	palm.height = 0.04
	_marker.mesh = palm
	_marker.material_override = mat
	add_child(_marker)
	var finger := CapsuleMesh.new()
	finger.radius = 0.012
	finger.height = 0.06
	for i in 4:
		var part := MeshInstance3D.new()
		part.mesh = finger
		part.material_override = mat
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.position = Vector3(-0.03 + i * 0.02, 0.0, -0.055)
		part.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_marker.add_child(part)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "HandUI"
	_ui.layer = 8
	add_child(_ui)
	_zone_label = Label.new()
	_zone_label.add_theme_font_size_override("font_size", 14)
	_zone_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_zone_label.add_theme_constant_override("shadow_offset_x", 1)
	_zone_label.add_theme_constant_override("shadow_offset_y", 1)
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_zone_label)
	# Top center: clear of the overlay (top-left) and the dog card (bottom-right).
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y = 14.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hint)

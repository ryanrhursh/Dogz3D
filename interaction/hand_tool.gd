class_name HandTool
extends Node3D
## The player's hand in close-up mode. A camera raycast finds what's under the cursor:
## hovering a touch zone of the close-up dog highlights it, a press pats it, and dragging
## strokes it (one stroke per STROKE_DISTANCE of hand travel). Pressing on the food bowl
## or treat jar takes a piece (the item's hand_piece); letting go near a dog's head feeds
## it, anywhere else drops it on the floor. Off in Live mode, where LMB selects dogs.
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
	_hint.text = ("Close-up with %s   ·   LMB pat, drag to stroke   ·   " \
			+ "hold LMB on bowl or jar, let go at the head to feed   ·   Esc back") % target.dog_name
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
## or picks up a loose movable item (a dropped treat). The hand starts carrying it and
## nearby dogs notice. False if there's nothing to take or the hand is already full.
func pick_from(item: WorldItem) -> bool:
	if item == null or not is_instance_valid(item) or held_item != null or item.held:
		return false
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


## Step 4 (ball) fills this in.
func throw_item(_velocity: Vector3) -> void:
	pass


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
			release_at(hand_point)
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
	if item != null and not item.held and (item.hand_piece != null or item.movable):
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
	return get_world_3d().direct_space_state.intersect_ray(query)


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

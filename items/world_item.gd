class_name WorldItem
extends Node3D
## Anything the dog can use. The AI reads affordances (food, water, bed, chewable,
## throwable...), never item names, so new items need no AI changes.
##
## Items can be held by the player's hand or the dog's mouth (attach_to / detach).
## A held item follows its holder each physics frame instead of being reparented,
## so its scene path (the save key) never changes. Items that roll around put a
## RigidBody3D at the root and this script on a child, and set physics_body.

signal fill_changed(item: WorldItem)

@export var display_name := "Item"
@export var affordances: PackedStringArray = PackedStringArray()
@export var consumable := false
@export_range(0.0, 1.0) var fill := 1.0:
	set(value):
		fill = clampf(value, 0.0, 1.0)
		_update_fill_visual()
		fill_changed.emit(self)
## Optional node scaled vertically with fill (bowl contents).
@export var fill_visual: Node3D
## How far from the item's center the dog stops. Small for things it stands on (bed).
@export var approach_radius := 0.45
## Save and restore position (things that get carried or thrown).
@export var movable := false
## Remove from the world once the fill is used up (hand-fed kibble, a dropped treat).
@export var free_when_empty := false
## Optional physics body this item rides on (ball). Frozen while held.
@export var physics_body: RigidBody3D

## True while a hand or mouth carries this item.
var held := false
## The Node3D it follows while held (hand anchor, dog mouth). Null otherwise.
var holder: Node3D


func _ready() -> void:
	add_to_group("items")
	_update_fill_visual()


func _physics_process(_delta: float) -> void:
	if not held:
		return
	if holder == null or not is_instance_valid(holder):
		detach(Vector3.ZERO)
		return
	get_root().global_position = holder.global_position


func has_affordance(affordance: StringName) -> bool:
	return affordances.has(String(affordance))


func is_available() -> bool:
	return not consumable or fill > 0.001


## Takes up to `amount` of fill and returns how much was actually taken.
func consume(amount: float) -> float:
	if not consumable:
		return amount
	var taken := minf(amount, fill)
	fill -= taken
	if free_when_empty and fill <= 0.001:
		remove()
	return taken


## The node that moves in the world: the physics body if there is one, else self.
func get_root() -> Node3D:
	if physics_body != null:
		return physics_body
	return self


## Start following `new_holder` (a hand anchor or a dog's mouth).
func attach_to(new_holder: Node3D) -> void:
	held = true
	holder = new_holder
	if physics_body != null:
		physics_body.linear_velocity = Vector3.ZERO
		physics_body.angular_velocity = Vector3.ZERO
		physics_body.freeze = true
	get_root().global_position = new_holder.global_position


## Let go where it is now. Physics items fly off with `velocity`.
func detach(velocity: Vector3 = Vector3.ZERO) -> void:
	held = false
	holder = null
	if physics_body != null:
		physics_body.freeze = false
		physics_body.linear_velocity = velocity


## True if a player hand (group "player_hands") is holding it.
func is_held_by_player() -> bool:
	return held and holder != null and is_instance_valid(holder) \
			and holder.is_in_group("player_hands")


## Takes the item out of the world (eaten, used up).
func remove() -> void:
	held = false
	holder = null
	remove_from_group("items")
	get_root().queue_free()


## Finds the WorldItem behind a raycast hit: the collider itself, its parent,
## or a direct child (physics items put the WorldItem under a RigidBody3D).
static func from_collider(collider: Object) -> WorldItem:
	if collider is WorldItem:
		return collider as WorldItem
	var node := collider as Node
	if node == null:
		return null
	if node.get_parent() is WorldItem:
		return node.get_parent() as WorldItem
	for child in node.get_children():
		if child is WorldItem:
			return child as WorldItem
	return null


func refill() -> void:
	fill = 1.0


## A point on the dog's side of the item, at approach_radius.
func get_approach_point(from: Vector3) -> Vector3:
	var offset := from - global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		offset = Vector3.BACK
	return global_position + offset.normalized() * approach_radius


func to_dict() -> Dictionary:
	var out := {"fill": fill}
	if movable:
		var p := get_root().global_position
		out["pos"] = [p.x, p.y, p.z]
	return out


func from_dict(data: Dictionary) -> void:
	fill = float(data.get("fill", fill))
	if held:
		detach(Vector3.ZERO)
	var p: Array = data.get("pos", [])
	if movable and p.size() == 3:
		get_root().global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		if physics_body != null:
			physics_body.linear_velocity = Vector3.ZERO


func _update_fill_visual() -> void:
	if fill_visual == null or not is_instance_valid(fill_visual):
		return
	fill_visual.visible = fill > 0.001
	fill_visual.scale.y = maxf(fill, 0.05)

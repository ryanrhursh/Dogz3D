class_name WorldItem
extends Node3D
## Anything the dog can use. The AI reads affordances (food, water, bed, chewable,
## throwable...), never item names, so new items need no AI changes.

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


func _ready() -> void:
	add_to_group("items")
	_update_fill_visual()


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
	return taken


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
	return {"fill": fill}


func from_dict(data: Dictionary) -> void:
	fill = float(data.get("fill", fill))


func _update_fill_visual() -> void:
	if fill_visual == null or not is_instance_valid(fill_visual):
		return
	fill_visual.visible = fill > 0.001
	fill_visual.scale.y = maxf(fill, 0.05)

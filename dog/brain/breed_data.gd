class_name BreedData
extends Resource
## Breed template. Each trait is a min..max range a new puppy rolls inside.
## Body shape keys and the real model hook in here in milestone 4.

@export var breed_name := "Mutt"
@export var size_scale := 1.0
@export var coat_color := Color(0.75, 0.55, 0.35)

@export_group("Trait ranges (x = min, y = max)")
@export var energy_range := Vector2(0.3, 0.7)
@export var sociability_range := Vector2(0.3, 0.7)
@export var boldness_range := Vector2(0.3, 0.7)
@export var food_drive_range := Vector2(0.3, 0.7)
@export var toy_drive_range := Vector2(0.3, 0.7)
@export var stubbornness_range := Vector2(0.3, 0.7)
@export var trainability_range := Vector2(0.3, 0.7)


func get_range(trait_name: StringName) -> Vector2:
	var value: Variant = get(String(trait_name) + "_range")
	if value is Vector2:
		return value
	return Vector2(0.2, 0.8)

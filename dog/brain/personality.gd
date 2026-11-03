class_name DogPersonality
extends Resource
## Stable traits, each 0..1. Breed sets the range, the puppy rolls inside it,
## and (later milestones) experience nudges them over the dog's life.

const TRAITS := [
	&"energy",
	&"sociability",
	&"boldness",
	&"food_drive",
	&"toy_drive",
	&"stubbornness",
	&"trainability",
]

@export_range(0.0, 1.0) var energy := 0.5
@export_range(0.0, 1.0) var sociability := 0.5
@export_range(0.0, 1.0) var boldness := 0.5
@export_range(0.0, 1.0) var food_drive := 0.5
@export_range(0.0, 1.0) var toy_drive := 0.5
@export_range(0.0, 1.0) var stubbornness := 0.5
@export_range(0.0, 1.0) var trainability := 0.5


static func roll(breed: BreedData, rng: RandomNumberGenerator) -> DogPersonality:
	var p := DogPersonality.new()
	for trait_name: StringName in TRAITS:
		var range_v := Vector2(0.2, 0.8)
		if breed != null:
			range_v = breed.get_range(trait_name)
		p.set(trait_name, rng.randf_range(range_v.x, range_v.y))
	return p


func get_trait_value(trait_name: StringName) -> float:
	return float(get(trait_name))


func to_dict() -> Dictionary:
	var out := {}
	for trait_name: StringName in TRAITS:
		out[String(trait_name)] = get_trait_value(trait_name)
	return out


func from_dict(data: Dictionary) -> void:
	for trait_name: StringName in TRAITS:
		var key := String(trait_name)
		if data.has(key):
			set(trait_name, clampf(float(data[key]), 0.0, 1.0))

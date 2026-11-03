class_name Pack
extends Node3D
## Owns every dog on the estate: spawns them, gives each a unique id, name and seed,
## and tracks which one the player has selected. In group "pack".
##
## Dog 0 uses the base seed and the classic spawn point, so a one-dog run with a given
## seed is identical to milestone 1. Dog i uses base_seed + i * SEED_STRIDE.

signal selection_changed(dog: Dog)
signal dog_added(dog: Dog)
signal dog_removed(dog: Dog)

const DOG_SCENE := preload("res://dog/body/dog.tscn")
const SEED_STRIDE := 7919
const FIRST_NAME := "Biscuit"
const NAMES := [
	"Maple", "Pepper", "Waffles", "Juniper", "Noodle", "Clover", "Bean", "Hazel",
	"Pickles", "Rosie", "Toast", "Willow", "Mochi", "Olive", "Pumpkin", "Scout",
	"Tater", "Daisy", "Nutmeg", "Ziggy", "Pretzel", "Luna", "Crumpet", "Fig",
	"Gus", "Sprout", "Marble", "Poppy", "Dumpling",
]
## Spawn spots for dogs after the first: open floor west of the room's center.
const SPAWN_COLUMNS := 5
const SPAWN_SPACING := 0.7
const SPAWN_ROWS_Z := [2.0, 0.0, -1.0, -2.0, 1.0]

@export var first_spawn := Vector3(0.0, 0.05, 1.0)

var dogs: Array[Dog] = []
var selected: Dog
var base_seed := 0
## Applied to every spawned dog when > 0 (the soak test uncaps movement speed).
var movement_time_scale_cap := -1.0

var _next_index := 0


func _ready() -> void:
	add_to_group("pack")


## Replaces the pack with `count` fresh dogs from `seed_value`. Selects dog 0.
func populate(count: int, seed_value: int) -> void:
	clear()
	base_seed = seed_value
	_next_index = 0
	for i in maxi(count, 1):
		adopt()
	select(dogs[0])


## Adds one new dog with the next index (and seed). Doesn't change the selection
## unless nothing was selected.
func adopt() -> Dog:
	var index := _next_index
	return _spawn(index, "dog_%d" % index, base_seed + index * SEED_STRIDE)


## Removes a dog from the estate. Selection moves to another dog if needed.
func remove_dog(dog: Dog) -> void:
	if dog == null or not dogs.has(dog):
		return
	dogs.erase(dog)
	dog.retire()
	dog.queue_free()
	dog_removed.emit(dog)
	if selected == dog:
		selected = null
		if not dogs.is_empty():
			select(dogs[0])
		else:
			selection_changed.emit(null)


func clear() -> void:
	for dog in dogs.duplicate():
		remove_dog(dog)
	selected = null


func select(dog: Dog) -> void:
	if dog != null and not dogs.has(dog):
		return
	selected = dog
	selection_changed.emit(dog)


func select_next() -> void:
	if dogs.is_empty():
		return
	var i := dogs.find(selected)
	select(dogs[(i + 1) % dogs.size()])


func get_dog(id: String) -> Dog:
	for dog in dogs:
		if dog.dog_id == id:
			return dog
	return null


## Makes the pack hold exactly the dogs with these ids (used by load): spawns missing
## ones (their state then comes from the save) and removes the rest.
func sync_to_ids(ids: PackedStringArray) -> void:
	for dog in dogs.duplicate():
		if not ids.has(dog.dog_id):
			remove_dog(dog)
	for id in ids:
		if get_dog(id) != null:
			continue
		var index := _index_from_id(id)
		_spawn(index, id, base_seed + maxi(index, 0) * SEED_STRIDE)
	if selected == null and not dogs.is_empty():
		select(dogs[0])


func _spawn(index: int, id: String, seed_value: int) -> Dog:
	var dog: Dog = DOG_SCENE.instantiate()
	dog.dog_id = id
	dog.dog_name = _name_for(index)
	dog.personality_seed = seed_value
	dog.position = _spawn_point(index)
	if movement_time_scale_cap > 0.0:
		dog.max_movement_time_scale = movement_time_scale_cap
	_next_index = maxi(_next_index, index + 1)
	add_child(dog)
	dogs.append(dog)
	dog_added.emit(dog)
	if selected == null:
		select(dog)
	return dog


func _name_for(index: int) -> String:
	if index <= 0:
		return FIRST_NAME
	var base_name: String = NAMES[(index - 1) % NAMES.size()]
	var lap := floori(float(index - 1) / NAMES.size())
	if lap > 0:
		return "%s %d" % [base_name, lap + 1]
	return base_name


func _spawn_point(index: int) -> Vector3:
	if index <= 0:
		return first_spawn
	var slot := index - 1
	var col := slot % SPAWN_COLUMNS + 1
	var row := floori(float(slot) / SPAWN_COLUMNS) % SPAWN_ROWS_Z.size()
	var lap := floori(float(slot) / (SPAWN_COLUMNS * SPAWN_ROWS_Z.size()))
	var z: float = SPAWN_ROWS_Z[row]
	return Vector3(-SPAWN_SPACING * col, first_spawn.y, z + 0.3 * lap)


static func _index_from_id(id: String) -> int:
	var parts := id.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		return int(parts[1])
	return -1

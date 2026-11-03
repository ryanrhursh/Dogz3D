class_name DogMemory
extends RefCounted
## What the dog remembers: its bond with the player and how it feels about each other dog.
## Object/room/sound associations (fear of the vacuum, etc.) arrive with quests (milestone 6).

const MAX_BOND := 100.0
## Affinity at or above this, both ways, and two dogs will share a bed.
const FRIEND_AFFINITY := 0.5

## 0..100 trust toward the player.
var bond := 20.0

## Key (e.g. "item:vacuum") -> -1.0 (fear) .. +1.0 (love). Unused until milestone 6.
var associations: Dictionary = {}

## Other dog's dog_id (String) -> -1.0 (dislikes) .. +1.0 (best friend). Unknown dogs are 0.
var relationships: Dictionary = {}

## dog_id -> SimClock.total_minutes of the last greeting. Not saved: after a load the dogs
## may greet once more, which is harmless.
var last_greeted: Dictionary = {}


func change_bond(amount: float) -> void:
	bond = clampf(bond + amount, 0.0, MAX_BOND)


func get_affinity(dog_id: String) -> float:
	return float(relationships.get(dog_id, 0.0))


func change_affinity(dog_id: String, amount: float) -> void:
	if dog_id == "":
		return
	relationships[dog_id] = clampf(get_affinity(dog_id) + amount, -1.0, 1.0)


func knows(dog_id: String) -> bool:
	return relationships.has(dog_id)


## Game minutes since this dog last greeted `dog_id`, or INF if never.
func minutes_since_greeted(dog_id: String, now: float) -> float:
	if not last_greeted.has(dog_id):
		return INF
	return now - float(last_greeted[dog_id])


func to_dict() -> Dictionary:
	return {"bond": bond, "associations": associations, "relationships": relationships}


func from_dict(data: Dictionary) -> void:
	bond = clampf(float(data.get("bond", bond)), 0.0, MAX_BOND)
	var saved: Dictionary = data.get("associations", {})
	associations = saved.duplicate()
	relationships.clear()
	last_greeted.clear()
	var saved_rel: Dictionary = data.get("relationships", {})
	for key in saved_rel:
		relationships[str(key)] = clampf(float(saved_rel[key]), -1.0, 1.0)

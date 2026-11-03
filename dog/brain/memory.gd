class_name DogMemory
extends RefCounted
## What the dog remembers. Milestone 1 tracks only the bond with the player.
## Object/room/sound associations (fear of the vacuum, etc.) arrive with quests (milestone 6).

const MAX_BOND := 100.0

## 0..100 trust toward the player.
var bond := 20.0

## Key (e.g. "item:vacuum") -> -1.0 (fear) .. +1.0 (love). Unused until milestone 6.
var associations: Dictionary = {}


func change_bond(amount: float) -> void:
	bond = clampf(bond + amount, 0.0, MAX_BOND)


func to_dict() -> Dictionary:
	return {"bond": bond, "associations": associations}


func from_dict(data: Dictionary) -> void:
	bond = clampf(float(data.get("bond", bond)), 0.0, MAX_BOND)
	var saved: Dictionary = data.get("associations", {})
	associations = saved.duplicate()

extends Node
## JSON save of the clock, every dog and every item. Autoloaded as SaveManager.
##
## Autosaves every few game hours and on window close. On load, real time that
## passed since the save is converted to game time (capped) and applied to the
## dogs' needs, so the dog notices you were gone without being punished hard.

signal saved(path: String)
signal loaded(path: String)

const SAVE_PATH := "user://save.json"
## v1: milestone 1. v2: touch prefs per dog, positions of movable items.
## v3: dog-to-dog relationships in each dog's memory.
const SAVE_VERSION := 3
const MAX_OFFLINE_MINUTES := 8.0 * 60.0
const AUTOSAVE_EVERY_HOURS := 3

## main.gd turns this off for --no-save soak tests.
var enabled := true


func _ready() -> void:
	SimClock.hour_changed.connect(_on_hour_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled:
		save_game()


func _on_hour_changed(hour: int) -> void:
	if enabled and hour % AUTOSAVE_EVERY_HOURS == 0:
		save_game()


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save_game(path: String = SAVE_PATH) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false

	var dogs: Array = []
	for node in get_tree().get_nodes_in_group("dogs"):
		var dog := node as Dog
		if dog != null:
			dogs.append(dog.to_dict())

	var items: Dictionary = {}
	for node in get_tree().get_nodes_in_group("items"):
		var item := node as WorldItem
		# Spawned pieces (kibble, treats) aren't saved: their paths don't exist on load.
		if item != null and not item.free_when_empty:
			items[String(scene.get_path_to(item))] = item.to_dict()

	var data := {
		"version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"clock": SimClock.to_dict(),
		"dogs": dogs,
		"items": items,
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	# Full precision so floats (traits, prefs, needs) round-trip exactly.
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	saved.emit(path)
	return true


## Upgrades an older save dictionary to SAVE_VERSION, one version step at a time.
## Fields a step doesn't touch keep their defaults or get rolled on load.
static func migrate(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var version: int = int(out.get("version", 0))
	if version < 3:
		# v3: every dog starts with no relationships (it hasn't met the others yet).
		var dogs: Array = out.get("dogs", [])
		for entry in dogs:
			var dog_data: Dictionary = entry
			var brain: Dictionary = dog_data.get("brain", {})
			var memory: Dictionary = brain.get("memory", {})
			if not memory.has("relationships"):
				memory["relationships"] = {}
			brain["memory"] = memory
			dog_data["brain"] = brain
		version = 3
	out["version"] = version
	return out


func load_game(path: String = SAVE_PATH) -> bool:
	if not has_save(path):
		return false
	var scene := get_tree().current_scene
	if scene == null:
		return false

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("Save file is not valid JSON: %s" % path)
		return false
	var data: Dictionary = parsed

	var version: int = int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("Save version %d is newer than %d. Loading anyway." % [version, SAVE_VERSION])
	elif version < SAVE_VERSION:
		print("SaveManager: upgrading save from v%d to v%d." % [version, SAVE_VERSION])
		data = migrate(data)

	var clock: Dictionary = data.get("clock", {})
	SimClock.from_dict(clock)

	var saved_dogs: Array = data.get("dogs", [])
	# The pack spawns saved dogs that don't exist yet and removes ones that aren't saved.
	var pack := get_tree().get_first_node_in_group("pack") as Pack
	if pack != null:
		var ids := PackedStringArray()
		for entry in saved_dogs:
			var entry_data: Dictionary = entry
			ids.append(str(entry_data.get("id", "")))
		pack.sync_to_ids(ids)

	var dogs_by_id: Dictionary = {}
	for node in get_tree().get_nodes_in_group("dogs"):
		var dog := node as Dog
		if dog != null:
			dogs_by_id[dog.dog_id] = dog
	for entry in saved_dogs:
		var dog_data: Dictionary = entry
		var dog: Dog = dogs_by_id.get(str(dog_data.get("id", "")))
		if dog != null:
			dog.from_dict(dog_data)

	var saved_items: Dictionary = data.get("items", {})
	for item_path in saved_items:
		var item := scene.get_node_or_null(NodePath(str(item_path))) as WorldItem
		if item != null:
			var item_data: Dictionary = saved_items[item_path]
			item.from_dict(item_data)

	# Offline catch-up: real time away becomes (capped) game time.
	var saved_at: float = float(data.get("saved_at_unix", Time.get_unix_time_from_system()))
	var elapsed_real := maxf(0.0, Time.get_unix_time_from_system() - saved_at)
	var offline_minutes := minf(elapsed_real * SimClock.minutes_per_real_second, MAX_OFFLINE_MINUTES)
	if offline_minutes > 1.0:
		SimClock.advance(offline_minutes)
		for id in dogs_by_id:
			var dog: Dog = dogs_by_id[id]
			dog.brain.simulate_offline(offline_minutes)
		print("SaveManager: caught up %.0f game minutes while you were away." % offline_minutes)

	loaded.emit(path)
	return true

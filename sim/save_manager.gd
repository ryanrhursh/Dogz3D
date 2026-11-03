extends Node
## JSON save of the clock, every dog and every item. Autoloaded as SaveManager.
##
## Autosaves every few game hours and on window close. On load, real time that
## passed since the save is converted to game time (capped) and applied to the
## dogs' needs, so the dog notices you were gone without being punished hard.

signal saved(path: String)
signal loaded(path: String)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
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


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
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
		if item != null:
			items[String(scene.get_path_to(item))] = item.to_dict()

	var data := {
		"version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"clock": SimClock.to_dict(),
		"dogs": dogs,
		"items": items,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	saved.emit(SAVE_PATH)
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var scene := get_tree().current_scene
	if scene == null:
		return false

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary):
		push_error("Save file is not valid JSON: %s" % SAVE_PATH)
		return false
	var data: Dictionary = parsed

	var version: int = int(data.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("Save version %d, expected %d. Loading anyway." % [version, SAVE_VERSION])

	var clock: Dictionary = data.get("clock", {})
	SimClock.from_dict(clock)

	var dogs_by_id: Dictionary = {}
	for node in get_tree().get_nodes_in_group("dogs"):
		var dog := node as Dog
		if dog != null:
			dogs_by_id[dog.dog_id] = dog
	var saved_dogs: Array = data.get("dogs", [])
	for entry in saved_dogs:
		var dog_data: Dictionary = entry
		var dog: Dog = dogs_by_id.get(str(dog_data.get("id", "")))
		if dog != null:
			dog.from_dict(dog_data)

	var saved_items: Dictionary = data.get("items", {})
	for path in saved_items:
		var item := scene.get_node_or_null(NodePath(str(path))) as WorldItem
		if item != null:
			var item_data: Dictionary = saved_items[path]
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

	loaded.emit(SAVE_PATH)
	return true

extends Node3D
## Gray-box entry point: bakes the navmesh, spawns the pack, wires selection and
## debug keys, loads the save, and handles command-line soak-test arguments.
##
## Soak test (headless, no window):
##   godot --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 \
##         --quit-after-hours=48 --autofeed --seed=42 --log
## Args after `--`:
##   --fresh               ignore the save file
##   --no-save             never write the save file
##   --timescale=N         start at N x speed
##   --quit-after-hours=N  quit after N game hours and print a summary
##   --autofeed            refill bowls when empty (an attentive owner)
##   --autopet             pet any dog whose affection drops below 40
##   --seed=N              fixed personality and decision RNG (dog i gets N + i * 7919)
##   --dogs=N              start with N dogs (default 1)
##   --bowls=N             N food and N water bowls (default 1, max 4), for big-pack soaks
##   --log                 print every behavior change
##   --closeup             start in close-up mode on the selected dog (for screenshots)
##   --screenshot=PATH     save a PNG after --screenshot-delay=N real seconds (default 3), then quit
##   --test=SUITE|all      run headless tests (tests/test_runner.gd), then quit with 0/1

const TIME_SCALES := [1.0, 4.0, 16.0, 60.0]
const MAX_BOWL_PAIRS := 4
## Extra bowl pairs go west along the north wall, this far apart.
const BOWL_PAIR_SPACING := 1.3
const WORLD_LAYER := 1
const DOGS_LAYER := 2

@onready var home: NavigationRegion3D = $Home
@onready var pack: Pack = $Pack
# Untyped on purpose: their scripts have no class_name, so calls resolve at runtime.
@onready var overlay = $DebugOverlay
@onready var camera_rig = $CameraRig
@onready var dog_panel: DogPanel = $DogPanel
@onready var hand_tool: HandTool = $HandTool
@onready var food_bowl: WorldItem = $Items/FoodBowl
@onready var water_bowl: WorldItem = $Items/WaterBowl
@onready var treat_jar: WorldItem = $Items/TreatJar

var _quit_after_minutes := -1.0
var _start_minutes := 0.0
var _log_decisions := false
var _autofeed := false
var _autopet := false
var _refills := 0
var _pets := 0
var _lowest_seen: Dictionary = {}
## Wall-clock microseconds between frames, for the soak summary's frame time line.
var _frame_usecs: PackedInt64Array = PackedInt64Array()
var _last_frame_usec := 0
## The dog in close-up mode, null in Live mode.
var closeup_dog: Dog


func _ready() -> void:
	home.bake_navigation_mesh(false)

	var args := _parse_args()
	if args.has("no-save"):
		SaveManager.enabled = false
	pack.selection_changed.connect(_on_selection_changed)
	pack.dog_added.connect(_on_dog_added)
	var seed_value := randi()
	if args.has("seed"):
		seed_value = int(args["seed"])
		# The engine's global RNG drives NavigationServer3D.map_get_random_point (the
		# random_point_near fallback). Seed it too, so seeded runs are reproducible.
		seed(seed_value)
	_add_bowl_pairs(int(args.get("bowls", "1")) - 1)
	pack.populate(int(args.get("dogs", "1")), seed_value)
	camera_rig.set_target(pack.selected, true)
	if not args.has("fresh") and SaveManager.has_save():
		SaveManager.load_game()
	if args.has("timescale"):
		SimClock.time_scale = float(args["timescale"])
	if args.has("quit-after-hours"):
		_quit_after_minutes = float(args["quit-after-hours"]) * 60.0
		_uncap_movement_for_soak()
	_log_decisions = args.has("log")
	_autofeed = args.has("autofeed")
	_autopet = args.has("autopet")
	_start_minutes = SimClock.total_minutes

	for need: StringName in DogNeeds.BASE_DECAY_PER_HOUR:
		_lowest_seen[need] = DogNeeds.MAX_VALUE

	if args.has("closeup"):
		enter_closeup(pack.selected)

	if args.has("screenshot"):
		_screenshot_and_quit(str(args["screenshot"]), float(args.get("screenshot-delay", "3")))

	if args.has("test"):
		_run_tests(args["test"])


func _run_tests(which: Variant) -> void:
	var suite := "all"
	if which is String:
		suite = which
	SimClock.time_scale = 60.0
	_uncap_movement_for_soak()
	var runner: Node = load("res://tests/test_runner.gd").new()
	runner.name = "TestRunner"
	add_child(runner)
	runner.run(self, suite)


## Saves a PNG of the window after `delay` real seconds, then quits. Needs a real
## renderer (not --headless).
func _screenshot_and_quit(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot -> %s (%s)" % [path, error_string(err)])
	get_tree().quit()


func _process(_delta: float) -> void:
	if _quit_after_minutes > 0.0:
		var now := Time.get_ticks_usec()
		if _last_frame_usec > 0:
			_frame_usecs.append(now - _last_frame_usec)
		_last_frame_usec = now
	for dog in pack.dogs:
		for need: StringName in _lowest_seen:
			_lowest_seen[need] = minf(float(_lowest_seen[need]), dog.brain.needs.get_value(need))

	if _autofeed:
		for node in get_tree().get_nodes_in_group("items"):
			var bowl := node as WorldItem
			if bowl == null or not bowl.consumable or bowl.free_when_empty:
				continue
			if bowl.fill < 0.05:
				bowl.refill()
				_refills += 1
				if _log_decisions:
					print("[%s] owner refilled %s" % [SimClock.format_short(), bowl.display_name])

	if _autopet:
		for dog in pack.dogs:
			if not dog.sleeping and dog.brain.needs.get_value(&"affection") < 40.0:
				dog.pet()
				_pets += 1

	if _quit_after_minutes > 0.0 and SimClock.total_minutes - _start_minutes >= _quit_after_minutes:
		_print_summary()
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# In close-up the hand tool owns LMB.
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and closeup_dog == null:
			if click_dog(pick_dog_at(mb.position)):
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			_set_speed(0)
		KEY_2:
			_set_speed(1)
		KEY_3:
			_set_speed(2)
		KEY_4:
			_set_speed(3)
		KEY_ESCAPE:
			if closeup_dog == null:
				return
			exit_closeup()
		KEY_SPACE:
			SimClock.paused = not SimClock.paused
		KEY_E:
			if pack.selected != null:
				pack.selected.pet()
		KEY_TAB:
			pack.select_next()
		KEY_N:
			var pup := pack.adopt()
			pup.show_emote("new friend!", 2.0)
		KEY_F:
			food_bowl.refill()
			treat_jar.refill()
		KEY_G:
			water_bowl.refill()
		KEY_C:
			camera_rig.toggle_follow()
		KEY_F3:
			overlay.toggle()
		KEY_I:
			dog_panel.toggle()
		KEY_F5:
			if SaveManager.save_game() and pack.selected != null:
				pack.selected.show_emote("(saved)", 1.0)
		KEY_F9:
			if SaveManager.load_game() and pack.selected != null:
				pack.selected.show_emote("(loaded)", 1.0)
		KEY_F8:
			if pack.selected != null:
				pack.selected.reroll_personality(randi())
				pack.selected.show_emote("new puppy!", 1.5)
		_:
			return
	get_viewport().set_input_as_handled()


func _set_speed(index: int) -> void:
	SimClock.paused = false
	SimClock.time_scale = TIME_SCALES[index]


## Debug: more bowls for a big pack. Pair k sits west of the first pair along the wall.
func _add_bowl_pairs(extra: int) -> void:
	for k in range(1, mini(extra, MAX_BOWL_PAIRS - 1) + 1):
		for original: WorldItem in [food_bowl, water_bowl]:
			var copy: WorldItem = load(original.scene_file_path).instantiate()
			copy.name = "%s%d" % [original.name, k + 1]
			copy.position = original.position + Vector3(-BOWL_PAIR_SPACING * k, 0.0, 0.0)
			original.get_parent().add_child(copy)


## Live-mode click on `picked` (null for empty space): a new dog gets selected, the
## already-selected one goes into close-up. True if the click was used.
func click_dog(picked: Dog) -> bool:
	if picked == null:
		return false
	if picked == pack.selected:
		enter_closeup(picked)
	else:
		pack.select(picked)
	return true


## Close-up mode: the camera frames `target` and the hand tool takes over LMB.
func enter_closeup(target: Dog) -> void:
	if target == null or not pack.dogs.has(target):
		return
	if pack.selected != target:
		pack.select(target)
	_set_closeup_dog(target)


## Back to Live mode and the view from before close-up.
func exit_closeup() -> void:
	if closeup_dog == null:
		return
	_set_closeup_dog(null)
	hand_tool.deactivate()
	camera_rig.exit_closeup(pack.selected)


func _set_closeup_dog(target: Dog) -> void:
	closeup_dog = target
	_update_label_modes()
	if target == null:
		return
	camera_rig.enter_closeup(target)
	hand_tool.activate(target)


## In close-up every dog's 3D label shrinks (the camera is near) and the close-up dog's
## shows only emotes.
func _update_label_modes() -> void:
	for d in pack.dogs:
		if closeup_dog == null:
			d.set_label_mode(&"normal")
		elif d == closeup_dog:
			d.set_label_mode(&"emote")
		else:
			d.set_label_mode(&"small")


## The dog under a screen position (its body or a touch zone), or null.
## Walls and furniture block the pick.
func pick_dog_at(screen_pos: Vector2) -> Dog:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to,
			WORLD_LAYER | DOGS_LAYER | TouchZone.TOUCH_LAYER)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	if collider is Dog:
		return collider as Dog
	if collider is TouchZone:
		return (collider as TouchZone).dog
	return null


func _on_selection_changed(dog: Dog) -> void:
	overlay.dog = dog
	dog_panel.dog = dog
	if closeup_dog != null:
		# Tab in close-up moves it to the next dog; losing the dog ends it.
		if dog == null:
			exit_closeup()
			return
		_set_closeup_dog(dog)
		return
	camera_rig.set_target(dog, false)


func _on_dog_added(dog: Dog) -> void:
	dog.brain.behavior_changed.connect(_on_behavior_changed.bind(dog))
	if closeup_dog != null:
		dog.set_label_mode(&"small")


func _on_behavior_changed(from_id: StringName, to_id: StringName, reason: String,
		dog: Dog) -> void:
	if not _log_decisions:
		return
	var needs := dog.brain.needs
	var who := ""
	if pack.dogs.size() > 1:
		who = dog.dog_name + ": "
	print("[%s] %s%s -> %s (%s) | hun %.0f thi %.0f ene %.0f fun %.0f aff %.0f" % [
			SimClock.format_short(), who, from_id, to_id, reason,
			needs.get_value(&"hunger"), needs.get_value(&"thirst"), needs.get_value(&"energy"),
			needs.get_value(&"fun"), needs.get_value(&"affection")])


## One dog: the milestone 1 format, so baselines compare directly. Several dogs: one
## line per dog, then pack totals (choices summed, needs averaged, lowest over all dogs).
func _print_summary() -> void:
	var dogs := pack.dogs
	print("")
	print("=== Soak summary: %.1f game hours, ended %s, %d dog(s) ===" % [
			(SimClock.total_minutes - _start_minutes) / 60.0, SimClock.format_time(), dogs.size()])
	var total_choices := {}
	var need_sums := {}
	var bond_sum := 0.0
	var mood_sum := 0.0
	for dog in dogs:
		var brain := dog.brain
		for id: StringName in brain.choice_counts:
			total_choices[id] = int(total_choices.get(id, 0)) + int(brain.choice_counts[id])
		for need: StringName in _lowest_seen:
			need_sums[need] = float(need_sums.get(need, 0.0)) + brain.needs.get_value(need)
		bond_sum += brain.memory.bond
		mood_sum += brain.mood()
		if dogs.size() > 1:
			var friends := 0
			var best := 0.0
			for other_id: String in brain.memory.relationships:
				var a := brain.memory.get_affinity(other_id)
				best = maxf(best, a)
				if a >= DogMemory.FRIEND_AFFINITY:
					friends += 1
			print("  %-10s %s | bond %.1f mood %+.2f | knows %d friends %d best %.2f" % [
					dog.dog_name, str(brain.choice_counts), brain.memory.bond, brain.mood(),
					brain.memory.relationships.size(), friends, best])
	var n := maxf(1.0, float(dogs.size()))
	print("Behavior choices: %s" % str(total_choices))
	var final_line := PackedStringArray()
	var low_line := PackedStringArray()
	for need: StringName in _lowest_seen:
		final_line.append("%s %.0f" % [need, float(need_sums.get(need, 0.0)) / n])
		low_line.append("%s %.0f" % [need, float(_lowest_seen[need])])
	print("Final needs:  %s" % ", ".join(final_line))
	print("Lowest seen:  %s" % ", ".join(low_line))
	print("Bowl refills: %d   Pets: %d   Bond: %.1f   Mood: %+.2f" % [
			_refills, _pets, bond_sum / n, mood_sum / n])
	_print_frame_time()


## Wall-clock frame time (process plus all physics substeps). Not part of the baseline:
## it depends on the machine.
func _print_frame_time() -> void:
	if _frame_usecs.is_empty():
		return
	var sorted := _frame_usecs.duplicate()
	sorted.sort()
	var total := 0
	for usec in sorted:
		total += usec
	var count := sorted.size()
	print("Frame time:   avg %.2f ms, p95 %.2f ms, max %.2f ms over %d frames (%d physics ticks/s)" % [
			float(total) / count / 1000.0, float(sorted[floori(count * 0.95)]) / 1000.0,
			float(sorted[count - 1]) / 1000.0, count, Engine.physics_ticks_per_second])


## At high soak speeds, walking must keep pace with game time or every trip
## eats hours. Uncap movement and add physics substeps so the dog doesn't overshoot.
func _uncap_movement_for_soak() -> void:
	var scale := maxf(1.0, SimClock.time_scale)
	pack.movement_time_scale_cap = scale
	for dog in pack.dogs:
		dog.max_movement_time_scale = scale
	var substeps := int(ceil(scale / 6.0))
	Engine.physics_ticks_per_second = 60 * substeps
	Engine.max_physics_steps_per_frame = substeps + 2


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq == -1:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out

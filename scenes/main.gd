extends Node3D
## Gray-box entry point: bakes the navmesh, wires debug keys, loads the save,
## and handles command-line soak-test arguments.
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
##   --autopet             pet the dog when affection drops below 40
##   --seed=N              fixed personality and decision RNG
##   --log                 print every behavior change
##   --screenshot=PATH     save a PNG after --screenshot-delay=N real seconds (default 3), then quit
##   --test=SUITE|all      run headless tests (tests/test_runner.gd), then quit with 0/1

const TIME_SCALES := [1.0, 4.0, 16.0, 60.0]

@onready var home: NavigationRegion3D = $Home
@onready var dog: Dog = $Dog
# Untyped on purpose: their scripts have no class_name, so calls resolve at runtime.
@onready var overlay = $DebugOverlay
@onready var camera_rig = $CameraRig
@onready var food_bowl: WorldItem = $Items/FoodBowl
@onready var water_bowl: WorldItem = $Items/WaterBowl

var _quit_after_minutes := -1.0
var _start_minutes := 0.0
var _log_decisions := false
var _autofeed := false
var _autopet := false
var _refills := 0
var _pets := 0
var _lowest_seen: Dictionary = {}


func _ready() -> void:
	home.bake_navigation_mesh(false)

	var args := _parse_args()
	if args.has("no-save"):
		SaveManager.enabled = false
	if args.has("seed"):
		dog.reroll_personality(int(args["seed"]))
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

	dog.brain.behavior_changed.connect(_on_behavior_changed)
	for need: StringName in dog.brain.needs.names():
		_lowest_seen[need] = DogNeeds.MAX_VALUE

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
	for need: StringName in dog.brain.needs.names():
		_lowest_seen[need] = minf(float(_lowest_seen[need]), dog.brain.needs.get_value(need))

	if _autofeed:
		for bowl: WorldItem in [food_bowl, water_bowl]:
			if bowl.fill < 0.05:
				bowl.refill()
				_refills += 1
				if _log_decisions:
					print("[%s] owner refilled %s" % [SimClock.format_short(), bowl.display_name])

	if _autopet and not dog.sleeping and dog.brain.needs.get_value(&"affection") < 40.0:
		dog.pet()
		_pets += 1

	if _quit_after_minutes > 0.0 and SimClock.total_minutes - _start_minutes >= _quit_after_minutes:
		_print_summary()
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
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
		KEY_SPACE:
			SimClock.paused = not SimClock.paused
		KEY_E:
			dog.pet()
		KEY_F:
			food_bowl.refill()
		KEY_G:
			water_bowl.refill()
		KEY_C:
			camera_rig.toggle_follow()
		KEY_F3:
			overlay.toggle()
		KEY_F5:
			if SaveManager.save_game():
				dog.show_emote("(saved)", 1.0)
		KEY_F9:
			if SaveManager.load_game():
				dog.show_emote("(loaded)", 1.0)
		KEY_F8:
			dog.reroll_personality(randi())
			dog.show_emote("new puppy!", 1.5)
		_:
			return
	get_viewport().set_input_as_handled()


func _set_speed(index: int) -> void:
	SimClock.paused = false
	SimClock.time_scale = TIME_SCALES[index]


func _on_behavior_changed(from_id: StringName, to_id: StringName, reason: String) -> void:
	if not _log_decisions:
		return
	var needs := dog.brain.needs
	print("[%s] %s -> %s (%s) | hun %.0f thi %.0f ene %.0f fun %.0f aff %.0f" % [
			SimClock.format_short(), from_id, to_id, reason,
			needs.get_value(&"hunger"), needs.get_value(&"thirst"), needs.get_value(&"energy"),
			needs.get_value(&"fun"), needs.get_value(&"affection")])


func _print_summary() -> void:
	var brain := dog.brain
	print("")
	print("=== Soak summary: %.1f game hours, ended %s ===" % [
			(SimClock.total_minutes - _start_minutes) / 60.0, SimClock.format_time()])
	print("Behavior choices: %s" % str(brain.choice_counts))
	var final_line := PackedStringArray()
	var low_line := PackedStringArray()
	for need: StringName in brain.needs.names():
		final_line.append("%s %.0f" % [need, brain.needs.get_value(need)])
		low_line.append("%s %.0f" % [need, float(_lowest_seen[need])])
	print("Final needs:  %s" % ", ".join(final_line))
	print("Lowest seen:  %s" % ", ".join(low_line))
	print("Bowl refills: %d   Pets: %d   Bond: %.1f   Mood: %+.2f" % [
			_refills, _pets, brain.memory.bond, brain.mood()])


## At high soak speeds, walking must keep pace with game time or every trip
## eats hours. Uncap movement and add physics substeps so the dog doesn't overshoot.
func _uncap_movement_for_soak() -> void:
	var scale := maxf(1.0, SimClock.time_scale)
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

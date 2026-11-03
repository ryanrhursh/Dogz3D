extends TestSuite
## Milestone 3 Hands step 2: close-up mode, the hand tool, touch effects, enjoy_pets
## and duck_away.

## Slow enough that the touch windows (0.75 / 0.5 game minutes) span several frames.
const TEST_SPEED := 4.0


func before_each() -> void:
	await super.before_each()
	main.exit_closeup()


func after_each() -> void:
	main.exit_closeup()
	SimClock.paused = false


func _behavior(d: Dog, id: StringName) -> DogBehavior:
	for behavior in d.brain.planner.behaviors:
		if behavior.id == id:
			return behavior
	return null


func _doing(d: Dog) -> StringName:
	if d.brain.current == null:
		return &""
	return d.brain.current.id


## Starts behavior `id` on `d` right now, as if the planner had picked it.
func _force(d: Dog, id: StringName) -> DogBehavior:
	d.brain.interrupt(d)
	var behavior := _behavior(d, id)
	if behavior != null:
		d.brain._start(d, behavior)
	return behavior


## A calm, awake dog resting in place, with a known bond and affection, the given raw
## prefs, and the clock paused.
func _prep(prefs: Dictionary) -> void:
	SimClock.paused = true
	for need: StringName in dog.brain.needs.names():
		dog.brain.needs.values[need] = 95.0
	dog.brain.needs.values[&"affection"] = 50.0
	dog.brain.memory.bond = 50.0
	for zone: StringName in prefs:
		dog.brain.touch_prefs.values[zone] = float(prefs[zone])
	_force(dog, &"idle")


## Unpauses at TEST_SPEED and waits until SimClock runs at it.
func _run_slow() -> void:
	SimClock.time_scale = TEST_SPEED
	SimClock.paused = false
	await tree.process_frame
	await tree.process_frame


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_hand_behaviors_registered_last_and_quiet() -> void:
	var behaviors := dog.brain.planner.behaviors
	var n := behaviors.size()
	check(behaviors[n - 2].id == &"enjoy_pets" and behaviors[n - 1].id == &"duck_away",
			"enjoy_pets and duck_away are registered last")
	SimClock.paused = true
	var state_before := dog.brain.rng.state
	dog.pet()
	for id: StringName in [&"enjoy_pets", &"duck_away"]:
		var behavior := _behavior(dog, id)
		if check(behavior != null, "%s is registered" % id):
			check(behavior.score(dog) == 0.0, "%s scores 0 without a hand touch" % id)
	check(dog.brain.stimuli.is_empty(), "the E pet records no touch stimulus")
	check(dog.brain.rng.state == state_before, "scoring doesn't touch the decision RNG")


func test_liked_touch() -> void:
	_prep({&"back": 0.8})
	var reaction := dog.touch(&"back", 3)
	check(reaction == &"likes", "a 0.8 zone is liked (got %s)" % reaction)
	check_near(dog.brain.needs.get_value(&"affection"), 50.0 + (2.0 + 4.0 * 0.8) * 3.0, 0.001,
			"affection per stroke scales with the pref")
	check_near(dog.brain.memory.bond, 50.0 + (0.05 + 0.15 * 0.8) * 3.0, 0.001,
			"bond per stroke scales with the pref")
	check(dog._emote == "<3", "liked emote is <3 (got %s)" % dog._emote)
	var touch := dog.brain.get_stimulus(&"touch")
	check(touch.get("zone") == &"back" and int(touch.get("strokes", 0)) == 3,
			"stimulus records zone and strokes")

	await _run_slow()
	var started := await wait_until(func() -> bool: return _doing(dog) == &"enjoy_pets", 0.5)
	check(started, "enjoy_pets starts right after the touch (doing %s)" % _doing(dog))
	check(dog.pose == &"sit", "sits for a back rub (pose %s)" % dog.pose)
	var start := SimClock.total_minutes
	var ended := await wait_until(func() -> bool: return _doing(dog) != &"enjoy_pets", 5.0)
	check(ended, "enjoy_pets ends without more touches")
	check(SimClock.total_minutes - start >= 0.9,
			"enjoy_pets lasts about a minute (%.2f)" % (SimClock.total_minutes - start))


func test_more_liked_gives_more() -> void:
	_prep({&"head": 0.3, &"back": 0.9})
	dog.touch(&"head", 1)
	var head_gain := dog.brain.needs.get_value(&"affection") - 50.0
	var head_bond := dog.brain.memory.bond - 50.0
	dog.brain.needs.values[&"affection"] = 50.0
	dog.brain.memory.bond = 50.0
	dog.touch(&"back", 1)
	check(dog.brain.needs.get_value(&"affection") - 50.0 > head_gain, "more liked, more affection")
	check(dog.brain.memory.bond - 50.0 > head_bond, "more liked, more bond")


func test_low_bond_uses_effective_pref() -> void:
	_prep({&"head": 0.3})
	dog.brain.memory.bond = 5.0
	check(dog.touch(&"head", 1) == &"neutral",
			"a barely liked zone reads neutral to a dog that hardly knows you")
	dog.brain.memory.bond = 50.0
	check(dog.touch(&"head", 1) == &"likes", "and liked once it trusts you")


func test_neutral_touch() -> void:
	_prep({&"head": 0.0})
	check(dog.touch(&"head", 2) == &"neutral", "a 0.0 zone is neutral")
	check_near(dog.brain.needs.get_value(&"affection"), 52.0, 0.001, "small affection")
	check_near(dog.brain.memory.bond, 50.0, 0.001, "no bond change")
	check(dog._emote == "~", "neutral emote is ~")
	await _run_slow()
	check(await wait_until(func() -> bool: return _doing(dog) == &"enjoy_pets", 0.5),
			"a neutral touch is enjoyed too")


func test_disliked_touch_ducks() -> void:
	_prep({&"ears": -0.8})
	var start_pos := dog.global_position
	check(dog.touch(&"ears", 2) == &"dislikes", "a -0.8 zone is disliked")
	check_near(dog.brain.needs.get_value(&"affection"), 48.0, 0.001, "small affection loss")
	check_near(dog.brain.memory.bond, 50.0 - (0.1 + 0.2 * 0.8) * 2.0, 0.001, "small bond loss")
	check(dog._emote == "!", "disliked emote is !")
	check(dog.ears_flat(), "ears flatten")
	check(_behavior(dog, &"enjoy_pets").score(dog) == 0.0, "a disliked touch isn't enjoyed")

	await _run_slow()
	check(await wait_until(func() -> bool: return _doing(dog) == &"duck_away", 0.5),
			"duck_away starts right after the touch (doing %s)" % _doing(dog))
	var ended := await wait_until(func() -> bool: return _doing(dog) != &"duck_away", 5.0)
	check(ended, "duck_away finishes")
	var moved := _flat(dog.global_position, start_pos)
	check(moved >= 0.6, "ducked away from the hand (%.2f m)" % moved)
	for i in 60:
		await tree.process_frame
	check(not dog.ears_flat(), "ears come back up after %.1f real seconds" % Dog.EARS_FLAT_SECONDS)


func test_forced_eval_skips_min_duration_and_budget() -> void:
	_prep({&"back": 0.8})
	# A routine re-evaluation with no budget left doesn't happen.
	Dog._eval_frame = Engine.get_process_frames()
	Dog._evals_left = 0
	var idle := dog.brain.current
	var state_before := dog.brain.rng.state
	dog.brain.tick(dog, 3.5)
	check(dog.brain.current == idle and dog.brain.rng.state == state_before,
			"no budget, no routine re-evaluation")

	# A touch re-evaluates on the next tick anyway, inside a fresh behavior's min_duration.
	_force(dog, &"idle")
	dog.touch(&"back", 1)
	Dog._eval_frame = Engine.get_process_frames()
	Dog._evals_left = 0
	dog.brain.tick(dog, 0.05)
	check(_doing(dog) == &"enjoy_pets", "the touch wins at once (doing %s)" % _doing(dog))


func test_touch_reacts_at_full_speed() -> void:
	# At 60x a game minute passes every frame; the reaction must still happen.
	_prep({&"back": 0.8})
	dog.touch(&"back", 1)
	SimClock.time_scale = 60.0
	SimClock.paused = false
	check(await wait_until(func() -> bool: return _doing(dog) == &"enjoy_pets", 3.0),
			"enjoy_pets starts at 60x")


func _put_to_sleep() -> void:
	dog.brain.needs.values[&"energy"] = 30.0
	var sleep := _force(dog, &"sleep")
	dog.stop_moving()
	sleep._fall_asleep(dog)


func test_asleep_liked_stays_asleep() -> void:
	_prep({&"back": 0.8})
	_put_to_sleep()
	check(dog.sleeping, "dog is asleep")
	check(dog.touch(&"back", 2) == &"likes", "liked while asleep")
	check_near(dog.brain.needs.get_value(&"affection"), 52.0, 0.001, "small affection asleep")
	check_near(dog.brain.memory.bond, 50.0, 0.001, "no bond while asleep")
	check(dog._emote == "zz <3", "sleepy emote (got %s)" % dog._emote)
	await _run_slow()
	for i in 6:
		await tree.process_frame
	check(dog.sleeping and _doing(dog) == &"sleep", "stays asleep (doing %s)" % _doing(dog))


func test_asleep_disliked_wakes_and_ducks() -> void:
	_prep({&"belly": -0.8})
	_put_to_sleep()
	check(dog.touch(&"belly", 1) == &"dislikes", "disliked while asleep")
	await _run_slow()
	check(await wait_until(func() -> bool: return _doing(dog) == &"duck_away", 0.5),
			"wakes and ducks (doing %s)" % _doing(dog))
	check(not dog.sleeping, "awake")


func test_closeup_enter_exit() -> void:
	var rig = main.camera_rig
	var live_distance: float = rig.distance
	var live_pitch: float = rig.pitch_degrees
	check(main.click_dog(dog), "click on the selected dog is used")
	check(main.closeup_dog == dog and rig.is_closeup(), "clicking the selected dog enters close-up")
	check(main.hand_tool.is_active(), "hand is on in close-up")
	rig.snap_view()
	var cam_dist: float = rig.camera.global_position.distance_to(dog.global_position)
	check(cam_dist < 3.0, "camera frames the dog (%.2f m)" % cam_dist)

	# Tab moves close-up to the next dog.
	var b := pack.adopt()
	await frames(1)
	pack.select_next()
	check(main.closeup_dog == b and main.hand_tool.dog == b, "Tab moves close-up to the next dog")

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	main._unhandled_input(esc)
	check(main.closeup_dog == null and not rig.is_closeup(), "Esc leaves close-up")
	check(not main.hand_tool.is_active(), "hand is off in Live mode")
	check_near(rig.distance, live_distance, 0.001, "zoom restored")
	check_near(rig.pitch_degrees, live_pitch, 0.001, "pitch restored")
	check(rig.follow and rig.follow_target == b, "follows the selected dog again")

	check(main.click_dog(dog) and pack.selected == dog and main.closeup_dog == null,
			"in Live mode clicking another dog only selects it")


func test_hand_tool_stroke_api() -> void:
	_prep({&"back": 0.8})
	var hand: HandTool = main.hand_tool
	check(hand.anchor.is_in_group("player_hands"), "hand anchor is in player_hands")
	check(hand.stroke(dog, &"back", 2) == &"likes", "stroke() returns the reaction")
	check(hand.last_reaction.contains("back"), "last reaction recorded (%s)" % hand.last_reaction)
	check(hand.anchor.global_position.distance_to(dog.touch_zones[&"back"].global_position) < 0.3,
			"hand moved to the zone")
	check(not hand.pick_from(null), "pick_from is a stub until step 3")


func test_hand_press_and_drag() -> void:
	_prep({&"back": 0.8})
	main.enter_closeup(dog)
	var rig = main.camera_rig
	rig.snap_view()
	await frames(2)
	var hand: HandTool = main.hand_tool
	var back: TouchZone = dog.touch_zones[&"back"]

	# The real mouse path: a click on the back's screen position hits one of the dog's zones.
	var screen: Vector2 = rig.camera.unproject_position(back.global_position)
	var hit := hand._raycast(screen)
	var hit_zone := hit.get("collider") as TouchZone
	check(hit_zone != null and hit_zone.dog == dog, "hand ray hits the dog's zone")
	if hit_zone == null:
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	var affection := dog.brain.needs.get_value(&"affection")
	hand._unhandled_input(press)
	check(hand.state == &"petting", "press starts petting (state %s)" % hand.state)
	check(dog.brain.needs.get_value(&"affection") > affection, "press pats")
	check(hit_zone._highlight.visible, "pressed zone is highlighted")

	var strokes := 0
	var p := hit_zone.global_position
	for i in 10:
		p += Vector3(0.05, 0.0, 0.0)
		strokes += hand.drag_to(p, hit_zone)
	check(strokes == 3, "0.5 m of drag is 3 strokes (got %d)" % strokes)
	for i in 10:
		p += Vector3(0.05, 0.0, 0.0)
		strokes += hand.drag_to(p, null)
	check(strokes == 3, "dragging off the dog doesn't stroke")

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen
	hand._unhandled_input(up)
	check(hand.state == &"hover", "release goes back to hover")
	main.exit_closeup()
	check(not hit_zone._highlight.visible, "highlight off after close-up")

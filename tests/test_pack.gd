extends TestSuite
## Milestone 2 Pack: spawning, unique ids and seeds, item sharing, selection, save/load,
## and pack scale: eval budget, waiting in line for a bowl, the dog card, extra bowls.

const TEST_SAVE := "user://test_pack_save.json"


func test_adopt_unique_dogs() -> void:
	var b := pack.adopt()
	var c := pack.adopt()
	check(pack.dogs.size() == 3, "pack has 3 dogs")
	check(dog.dog_id != b.dog_id and b.dog_id != c.dog_id and dog.dog_id != c.dog_id,
			"ids are unique")
	check(dog.dog_name != b.dog_name and b.dog_name != c.dog_name, "names are unique")
	check(b.brain.personality.to_dict() != c.brain.personality.to_dict(),
			"dogs roll different personalities")
	var rng := RandomNumberGenerator.new()
	rng.seed = pack.base_seed + Pack.SEED_STRIDE
	var expected := DogPersonality.roll(b.breed, rng)
	check(b.brain.personality.to_dict() == expected.to_dict(), "dog 1 uses base seed + stride")
	check(b.is_in_group("dogs") and c.is_in_group("dogs"), "new dogs join the dogs group")


func test_item_claims_are_exclusive() -> void:
	SimClock.paused = true  # Freeze brains so they don't claim things themselves.
	var b := pack.adopt()
	await frames(1)
	dog.brain.interrupt(dog)
	b.brain.interrupt(b)
	var bowl: WorldItem = main.get_node("Items/FoodBowl")
	check(bowl.max_users == 1, "food bowl takes one dog at a time")
	check(dog.claim_item(bowl), "first dog claims the bowl")
	check(b.find_nearest_item(&"food") == null, "second dog doesn't see a claimed bowl")
	check(not b.claim_item(bowl), "second dog can't claim it")
	check(dog.find_nearest_item(&"food") == bowl, "claimer still finds its bowl")
	dog.release_item(bowl)
	check(b.find_nearest_item(&"food") == bowl, "released bowl is free again")
	check(b.claim_item(bowl), "second dog claims it after release")
	pack.remove_dog(b)
	check(bowl.user_count() == 0, "removing a dog frees its claims")


func test_selection() -> void:
	var b := pack.adopt()
	var c := pack.adopt()
	var overlay = main.get_node("DebugOverlay")
	var camera_rig = main.get_node("CameraRig")
	check(pack.selected == dog, "first dog stays selected after adopting")
	pack.select(b)
	check(overlay.dog == b, "overlay shows the selected dog")
	check(camera_rig.follow_target == b, "camera follows the selected dog")
	pack.select_next()
	check(pack.selected == c, "Tab selects the next dog")
	pack.select_next()
	check(pack.selected == dog, "Tab wraps around")
	pack.select(c)
	pack.remove_dog(c)
	check(pack.selected == dog, "removing the selected dog selects another")


func test_click_picks_dog() -> void:
	SimClock.paused = true
	await frames(2)
	var scene = main  # Untyped: pick_dog_at is defined by main.gd, not Node3D.
	var camera := main.get_viewport().get_camera_3d()
	var back: TouchZone = dog.touch_zones[&"back"]
	var screen := camera.unproject_position(back.global_position)
	check(scene.pick_dog_at(screen) == dog, "clicking the dog's back picks it")
	check(scene.pick_dog_at(Vector2(2.0, 2.0)) == null, "clicking a corner picks nothing")


func test_save_load_pack() -> void:
	var b := pack.adopt()
	var c := pack.adopt()
	var ids := [dog.dog_id, b.dog_id, c.dog_id]
	var b_personality := b.brain.personality.to_dict()
	check(SaveManager.save_game(TEST_SAVE), "saved")

	pack.remove_dog(c)
	b.dog_name = "Renamed"
	b.reroll_personality(12345)
	var d := pack.adopt()
	await frames(1)
	check(SaveManager.load_game(TEST_SAVE), "loaded")
	await frames(1)

	var loaded_ids := []
	for each in pack.dogs:
		loaded_ids.append(each.dog_id)
	loaded_ids.sort()
	ids.sort()
	check(loaded_ids == ids, "pack holds exactly the saved dogs (%s)" % str(loaded_ids))
	check(not is_instance_valid(d) or not pack.dogs.has(d), "unsaved dog was removed")
	var b2 := pack.get_dog(ids[1])
	check(b2 != null and b2.dog_name != "Renamed", "saved name restored")
	check(b2 != null and b2.brain.personality.to_dict() == b_personality,
			"saved personality restored")
	var c2 := pack.get_dog(ids[2])
	check(c2 != null and c2.brain.touch_prefs.to_dict().size() == 4, "removed dog re-spawned from save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _force(d: Dog, id: StringName) -> DogBehavior:
	d.brain.interrupt(d)
	for behavior in d.brain.planner.behaviors:
		if behavior.id == id:
			behavior.score(d)
			d.brain._start(d, behavior)
			return behavior
	return null


func _behavior(d: Dog, id: StringName) -> DogBehavior:
	for behavior in d.brain.planner.behaviors:
		if behavior.id == id:
			return behavior
	return null


## Physics runs several ticks per process frame in tests, so frames() is too short here.
func _process_frames(count: int) -> void:
	for i in count:
		await tree.process_frame


func test_eval_budget_per_frame() -> void:
	check(Dog.evals_per_frame() >= 1, "a lone dog always gets a slot")
	for i in 7:
		pack.adopt()
	await frames(1)
	SimClock.time_scale = 1.0
	await _process_frames(2)
	var budget := Dog.evals_per_frame()
	check(budget == Dog.EVAL_SLACK + 1, "8 dogs at 1x: slack + 1 slots (got %d)" % budget)
	Dog._eval_frame = -1
	var granted := 0
	for i in 20:
		if dog.take_eval_slot():
			granted += 1
	check(granted == budget, "slots per frame are capped (%d of %d)" % [granted, budget])


func test_eval_stagger_spreads_bursts() -> void:
	for i in 7:
		pack.adopt()
	await frames(1)
	SimClock.time_scale = 1.0
	await _process_frames(2)
	for d in pack.dogs:
		_force(d, &"idle")
		d.brain.minutes_in_current = 100.0
		d.brain._since_eval = 100.0
	await _process_frames(1)
	var evaluated := 0
	for d in pack.dogs:
		if d.brain._since_eval < 50.0:
			evaluated += 1
	check(evaluated >= 1 and evaluated <= Dog.evals_per_frame(),
			"one frame evaluates at most the budget (%d of 8)" % evaluated)
	await _process_frames(4)
	var waiting := 0
	for d in pack.dogs:
		if d.brain._since_eval >= 50.0:
			waiting += 1
	check(waiting == 0, "every dog got its turn within a few frames (%d waiting)" % waiting)


func test_queue_is_fair() -> void:
	SimClock.paused = true
	var b := pack.adopt()
	var c := pack.adopt()
	await frames(1)
	for d in pack.dogs:
		d.brain.interrupt(d)
	var bowl: WorldItem = main.get_node("Items/WaterBowl")
	check(dog.claim_item(bowl), "first dog drinks")
	check(b.find_nearest_item(&"water") == null and b.find_busy_item(&"water") == bowl,
			"busy bowl is found as busy, not free")
	b.join_queue(bowl)
	check(bowl.queue_position(b) == 0, "b is first in line")
	dog.release_item(bowl)
	check(bowl.is_free_for(b), "the free slot goes to the front of the line")
	check(not bowl.is_free_for(c), "c can't cut in")
	check(c.find_busy_item(&"water") == bowl, "c sees the bowl as busy")
	check(b.claim_item(bowl), "b claims it")
	check(bowl.queue_position(b) == -1, "claiming leaves the line")
	b.release_item(bowl)
	check(bowl.is_free_for(c), "free for anyone once the line is empty")
	c.join_queue(bowl)
	check(not bowl.is_free_for(dog), "dog waits behind c")
	pack.remove_dog(c)
	await frames(1)
	check(bowl.is_free_for(dog), "a removed dog leaves the line")


func test_wait_turn() -> void:
	var b := pack.adopt()
	await frames(1)
	var bowl: WorldItem = main.get_node("Items/WaterBowl")
	bowl.refill()
	check(_behavior(dog, &"wait_turn").score(dog) == 0.0, "lone dog never waits")
	for d in pack.dogs:
		d.brain.interrupt(d)
		for need: StringName in d.brain.needs.names():
			d.brain.needs.values[need] = 95.0
	b.brain.needs.values[&"thirst"] = 30.0
	check(dog.claim_item(bowl), "first dog holds the bowl")
	check(_behavior(b, &"drink").score(b) == 0.0, "can't drink from a busy bowl")
	check(_behavior(b, &"wait_turn").score(b) > 0.0, "thirsty dog wants to wait its turn")
	_force(b, &"wait_turn")
	check(bowl.queue_position(b) == 0, "waiting dog is in line")
	await game_minutes(3.0)
	check(b.brain.current != null and b.brain.current.id == &"wait_turn", "still waiting")
	dog.release_item(bowl)
	var drank := await wait_until(func() -> bool:
		return b.brain.needs.get_value(&"thirst") > 40.0, 20.0)
	check(drank, "drinks once its turn comes")
	var done := await wait_until(func() -> bool: return b.brain.current == null \
			or b.brain.current.id != &"wait_turn", 30.0)
	check(done, "wait_turn ends")
	check(bowl.user_count() == 0 and bowl.queue_position(b) == -1, "bowl and line are clear")


func test_dog_panel() -> void:
	var b := pack.adopt()
	await frames(1)
	var panel: DogPanel = main.get_node("DogPanel")
	check(panel.dog == dog, "card shows the selected dog")
	pack.select(b)
	check(panel.dog == b, "card follows the selection")
	panel.refresh_view()
	var lines := panel.get_lines()
	check(lines[0].begins_with(b.dog_name), "card shows the name (%s)" % lines[0])
	check(lines[1].begins_with("Feeling "), "card shows the mood")
	check(DogPanel.mood_word(0.9) == "great" and DogPanel.mood_word(-0.9) == "miserable",
			"mood words")
	check(DogPanel.bond_word(20.0) == "Getting to know you" and DogPanel.bond_word(99.0) \
			== "Best buddies", "bond words")
	var words := DogPanel.top_traits(b.brain.personality, 3)
	check(words.size() == 3, "three top traits")
	var p := DogPersonality.new()
	p.energy = 0.95
	p.sociability = 0.05
	var top := DogPanel.top_traits(p, 2)
	check(top.has("Energetic") and top.has("Shy"), "strongest traits win (%s)" % str(top))
	check(DogPanel.friend_text(b) == "Hasn't met the pack yet", "no relationships yet")
	b.brain.memory.change_affinity(dog.dog_id, 0.8)
	check(DogPanel.friend_text(b) == "Best friend: %s" % dog.dog_name, "best friend named")
	b.set_social_partner(dog.dog_id)
	_force(b, &"idle")
	b.set_social_partner(dog.dog_id)
	check(DogPanel.doing_text(b).ends_with("with %s" % dog.dog_name), "doing names the partner")
	b.set_social_partner("")
	pack.select(dog)


func test_extra_bowls() -> void:
	main._add_bowl_pairs(1)
	var food: WorldItem = main.get_node_or_null("Items/FoodBowl2")
	var water: WorldItem = main.get_node_or_null("Items/WaterBowl2")
	check(food != null and water != null, "second bowl pair added")
	if food != null:
		var first: WorldItem = main.get_node("Items/FoodBowl")
		check(food.has_affordance(&"food") and food.global_position.x < first.global_position.x,
				"west of the first pair")
		check(dog.can_reach(food.global_position), "reachable")
		food.remove()
	if water != null:
		water.remove()
	await frames(1)

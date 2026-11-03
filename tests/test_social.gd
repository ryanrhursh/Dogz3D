extends TestSuite
## Milestone 2 Pack, dog to dog: body API for other dogs, relationships, greet,
## play_together, bed sharing, separation, save v3 and its migration.

const TEST_SAVE := "user://test_social_save.json"


## Starts behavior `id` on `d` right now, as if the planner had picked it.
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


func _doing(d: Dog) -> StringName:
	if d.brain.current == null:
		return &""
	return d.brain.current.id


## Second dog placed `dist` metres east of the first, both standing still and awake.
func _neighbor(dist: float) -> Dog:
	var b := pack.adopt()
	await frames(1)
	b.global_position = dog.global_position + Vector3(dist, 0.0, 0.0)
	dog.brain.interrupt(dog)
	b.brain.interrupt(b)
	await frames(1)
	return b


func _calm(d: Dog) -> void:
	for need: StringName in d.brain.needs.names():
		d.brain.needs.values[need] = 95.0


func test_lone_dog_social_scores_zero() -> void:
	SimClock.paused = true
	var state_before := dog.brain.rng.state
	for id: StringName in [&"greet", &"play_together"]:
		var behavior := _behavior(dog, id)
		if check(behavior != null, "%s is registered" % id):
			check(behavior.score(dog) == 0.0, "%s scores 0 with no other dog" % id)
	dog.invite_dog("nobody", &"play")
	check(dog.find_nearest_dog(INF) == "", "no other dog to find")
	check(dog.brain.rng.state == state_before, "scoring doesn't touch the decision RNG")


func test_find_nearest_dog_and_info() -> void:
	SimClock.paused = true
	var b := await _neighbor(2.0)
	var c := pack.adopt()
	await frames(1)
	c.global_position = dog.global_position + Vector3(-4.0, 0.0, 0.0)
	await frames(1)
	check(dog.find_nearest_dog(10.0) == b.dog_id, "nearest is the dog 2 m away")
	check(dog.find_nearest_dog(1.0) == "", "nothing within 1 m")
	var not_b := func(info: Dictionary) -> bool: return str(info["id"]) != b.dog_id
	check(dog.find_nearest_dog(10.0, not_b) == c.dog_id, "filter skips b")
	var info := dog.get_dog_info(b.dog_id)
	check(str(info.get("name", "")) == b.dog_name, "info has the name")
	check_near(float(info.get("distance", -1.0)), 2.0, 0.05, "info has the distance")
	for key in ["position", "doing", "sleeping", "moving", "mood", "partner", "affinity_to_me"]:
		check(info.has(key), "info has %s" % key)
	b.brain.memory.change_affinity(dog.dog_id, 0.4)
	check_near(float(dog.get_dog_info(b.dog_id)["affinity_to_me"]), 0.4, 0.0001,
			"affinity_to_me is the other dog's feeling toward the asker")
	check(dog.get_dog_info(dog.dog_id).is_empty(), "no info about itself")
	check(dog.get_dog_info("dog_999").is_empty(), "no info about an unknown dog")


func test_relationships_memory() -> void:
	var memory := DogMemory.new()
	check(memory.get_affinity("dog_1") == 0.0 and not memory.knows("dog_1"), "strangers are 0")
	memory.change_affinity("dog_1", 0.7)
	memory.change_affinity("dog_1", 0.7)
	check(memory.get_affinity("dog_1") == 1.0, "affinity clamps at 1")
	memory.change_affinity("dog_2", -3.0)
	check(memory.get_affinity("dog_2") == -1.0, "affinity clamps at -1")
	var copy := DogMemory.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(memory.to_dict(), "", true, true)))
	check(copy.relationships == memory.relationships, "relationships survive JSON")


func test_greet() -> void:
	var b := await _neighbor(2.5)
	_calm(dog)
	_calm(b)
	check(_behavior(dog, &"greet").score(dog) > 0.0, "greet scores > 0 with a dog nearby")
	_force(dog, &"greet")
	check(dog.social_partner_id == b.dog_id, "greeter points at its partner")
	var greeted := await wait_until(func() -> bool:
		return dog.brain.memory.last_greeted.has(b.dog_id), 15.0)
	check(greeted, "greeting happened")
	check(dog.brain.memory.get_affinity(b.dog_id) > 0.0, "greeter likes the other dog more")
	check(b.brain.memory.get_affinity(dog.dog_id) > 0.0, "greeted dog heard about it")
	var finished := await wait_until(func() -> bool: return _doing(dog) != &"greet", 10.0)
	check(finished, "greet ends")
	check(dog.social_partner_id == "", "partner cleared on exit")


func test_greet_skips_sleeping_dog() -> void:
	SimClock.paused = true
	var b := await _neighbor(2.0)
	b.sleeping = true
	check(_behavior(dog, &"greet").score(dog) == 0.0, "nobody to greet when the dog sleeps")
	b.sleeping = false
	check(_behavior(dog, &"greet").score(dog) > 0.0, "greets once it's awake")


func test_play_together() -> void:
	var b := await _neighbor(2.0)
	for d: Dog in [dog, b]:
		_calm(d)
		d.brain.needs.values[&"fun"] = 30.0
	dog.brain.memory.change_affinity(b.dog_id, 0.3)
	b.brain.memory.change_affinity(dog.dog_id, 0.3)
	check(_behavior(dog, &"play_together").score(dog) > 0.0, "play scores > 0 with a friend")
	_force(dog, &"play_together")
	check(b.get_invite(&"play") == dog.dog_id, "partner got the invitation")
	var joined := await wait_until(func() -> bool: return _doing(b) == &"play_together", 8.0)
	check(joined, "partner accepted")
	check(b.social_partner_id == dog.dog_id, "partner plays with the inviter")
	var affinity_before := dog.brain.memory.get_affinity(b.dog_id)
	await game_minutes(3.0)
	check(_doing(dog) == &"play_together", "still playing after 3 min")
	check(dog.brain.needs.get_value(&"fun") > 30.0, "play is fun")
	check(dog.brain.memory.get_affinity(b.dog_id) > affinity_before, "play builds affinity")
	var over := await wait_until(func() -> bool:
		return _doing(dog) != &"play_together" and _doing(b) != &"play_together", 20.0)
	check(over, "game ends for both")
	check(dog.gait == &"walk" and b.gait == &"walk", "gait reset after play")


func test_play_needs_acquaintance() -> void:
	SimClock.paused = true
	var b := await _neighbor(2.0)
	dog.brain.needs.values[&"fun"] = 20.0
	check(_behavior(dog, &"play_together").score(dog) == 0.0, "won't start a game with a stranger")
	dog.brain.memory.change_affinity(b.dog_id, -0.5)
	check(_behavior(dog, &"play_together").score(dog) == 0.0, "won't start a game with a disliked dog")


func test_bed_sharing() -> void:
	SimClock.paused = true
	var b := await _neighbor(1.5)
	var c := pack.adopt()
	await frames(1)
	c.brain.interrupt(c)
	var bed: WorldItem = main.get_node("Items/DogBed")
	check(bed.share_slots == 1, "bed has a share slot")
	check(dog.claim_item(bed), "first dog takes the bed")
	check(b.find_nearest_item(&"bed") == null, "bed is full for others")
	check(b.find_shared_item(&"bed", DogMemory.FRIEND_AFFINITY) == null, "not friends yet")
	b.brain.memory.change_affinity(dog.dog_id, 0.8)
	check(b.find_shared_item(&"bed", DogMemory.FRIEND_AFFINITY) == null, "one-sided isn't enough")
	dog.brain.memory.change_affinity(b.dog_id, 0.8)
	check(b.find_shared_item(&"bed", DogMemory.FRIEND_AFFINITY) == bed, "friends can share")
	check(not b.claim_item(bed), "a normal claim still fails")
	_force(b, &"sleep")
	check(bed.user_count() == 2, "friend's sleep behavior claimed the share slot")
	c.brain.memory.change_affinity(dog.dog_id, 0.9)
	c.brain.memory.change_affinity(b.dog_id, 0.9)
	dog.brain.memory.change_affinity(c.dog_id, 0.9)
	b.brain.memory.change_affinity(c.dog_id, 0.9)
	check(c.find_shared_item(&"bed", DogMemory.FRIEND_AFFINITY) == null, "no room for a third")
	b.brain.interrupt(b)
	check(bed.user_count() == 1, "sleep exit releases the shared slot")
	dog.release_item(bed)


func test_separation_only_near_other_dogs() -> void:
	SimClock.paused = true
	dog.go_to(dog.global_position + Vector3(0.0, 0.0, -4.0))
	check(dog._separation_push() == Vector3.ZERO, "a lone dog gets no push")
	var b := await _neighbor(0.3)
	dog.go_to(dog.global_position + Vector3(0.0, 0.0, -4.0))
	var push := dog._separation_push()
	check(push.x < 0.0, "pushed away from the dog on its east side (%s)" % str(push))
	dog.go_to(b.global_position + Vector3(0.2, 0.0, 0.0))
	check(dog._separation_push() == Vector3.ZERO, "no push when arriving next to it")
	b.global_position = dog.global_position + Vector3(2.0, 0.0, 0.0)
	dog.go_to(dog.global_position + Vector3(0.0, 0.0, -4.0))
	check(dog._separation_push() == Vector3.ZERO, "no push when the other dog is far")
	dog.stop_moving()


func test_save_relationships() -> void:
	var b := pack.adopt()
	await frames(1)
	dog.brain.memory.change_affinity(b.dog_id, 0.625)
	b.brain.memory.change_affinity(dog.dog_id, -0.25)
	check(SaveManager.save_game(TEST_SAVE), "saved")
	dog.brain.memory.relationships.clear()
	b.brain.memory.change_affinity(dog.dog_id, 1.0)
	check(SaveManager.load_game(TEST_SAVE), "loaded")
	var b2 := pack.get_dog(b.dog_id)
	check(dog.brain.memory.get_affinity(b.dog_id) == 0.625, "affinity restored")
	check(b2 != null and b2.brain.memory.get_affinity(dog.dog_id) == -0.25, "negative affinity restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func test_migrate_v2_save() -> void:
	var v2 := {
		"version": 2,
		"dogs": [{"id": "dog_0", "brain": {"memory": {"bond": 33.0, "associations": {}}}}],
	}
	var out := SaveManager.migrate(v2)
	check(int(out["version"]) == SaveManager.SAVE_VERSION, "migrated to the current version")
	var dogs: Array = out["dogs"]
	var first: Dictionary = dogs[0]
	var memory: Dictionary = first["brain"]["memory"]
	check(memory.has("relationships") and (memory["relationships"] as Dictionary).is_empty(),
			"v2 dogs get empty relationships")
	check(float(memory["bond"]) == 33.0, "other memory fields kept")
	check(not (v2["dogs"][0]["brain"]["memory"] as Dictionary).has("relationships"),
			"migrate doesn't modify its input")

	# A real v2 file on disk loads cleanly.
	var b := pack.adopt()
	await frames(1)
	check(SaveManager.save_game(TEST_SAVE), "saved")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	data["version"] = 2
	for entry in data["dogs"]:
		(entry["brain"]["memory"] as Dictionary).erase("relationships")
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	dog.brain.memory.change_affinity(b.dog_id, 0.5)
	check(SaveManager.load_game(TEST_SAVE), "v2 save loaded")
	check(dog.brain.memory.relationships.is_empty(), "loaded v2 dog has no relationships")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

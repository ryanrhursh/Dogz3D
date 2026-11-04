extends TestSuite
## Hands (milestone 3) plumbing: touch prefs, touch zones, holding items, reach, save v2.


func test_touch_prefs_deterministic() -> void:
	var first := dog.brain.touch_prefs.to_dict()
	dog.reroll_personality(42)
	check(dog.brain.touch_prefs.to_dict() == first, "same seed rolls the same prefs")
	dog.reroll_personality(7)
	check(dog.brain.touch_prefs.to_dict() != first, "a different seed rolls different prefs")


func test_touch_prefs_ranges() -> void:
	var with_dislike := 0
	for seed_value in range(1, 201):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var personality := DogPersonality.roll(dog.breed, rng)
		var prefs := DogTouchPrefs.roll(personality, rng)
		var best := -1.0
		var disliked := false
		for zone: StringName in DogTouchPrefs.ZONES:
			var v := prefs.get_raw(zone)
			check(v >= -1.0 and v <= 1.0, "seed %d %s in range" % [seed_value, zone])
			best = maxf(best, v)
			if v <= DogTouchPrefs.DISLIKE_AT:
				disliked = true
		check(best >= DogTouchPrefs.MIN_FAVORITE, "seed %d has a favorite zone" % seed_value)
		if disliked:
			with_dislike += 1
	# Corgis should mostly be easygoing, but some must have a zone to avoid.
	check(with_dislike >= 10 and with_dislike <= 140,
			"%d / 200 corgis dislike some zone" % with_dislike)


func test_personality_unchanged_by_prefs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var expected := DogPersonality.roll(dog.breed, rng)
	check(dog.brain.personality.to_dict() == expected.to_dict(),
			"seed 42 personality matches milestone 1")


func test_low_bond_lowers_prefs() -> void:
	var prefs := dog.brain.touch_prefs
	for zone: StringName in DogTouchPrefs.ZONES:
		var raw := prefs.get_raw(zone)
		check_near(prefs.effective(zone, 50.0), raw, 0.0001, "%s unchanged at bond 50" % zone)
		check_near(prefs.effective(zone, 0.0), clampf(raw - DogTouchPrefs.LOW_BOND_PENALTY, -1.0, 1.0),
				0.0001, "%s lowered at bond 0" % zone)


func test_touch_zones_queryable() -> void:
	check(dog.touch_zones.size() == 4, "dog has 4 touch zones")
	var space := dog.get_world_3d().direct_space_state
	for zone_id: StringName in DogTouchPrefs.ZONES:
		var zone: TouchZone = dog.touch_zones.get(zone_id)
		if not check(zone != null, "zone %s exists" % zone_id):
			continue
		var query := PhysicsPointQueryParameters3D.new()
		query.position = zone.global_position
		query.collision_mask = TouchZone.TOUCH_LAYER
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var found := false
		for hit in space.intersect_point(query):
			if hit["collider"] == zone:
				found = true
		check(found, "zone %s found by point query" % zone_id)

	# The hand's real path: a ray from the camera to the back hits a zone on this dog.
	var camera := main.get_viewport().get_camera_3d()
	var back: TouchZone = dog.touch_zones[&"back"]
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, back.global_position,
			TouchZone.TOUCH_LAYER)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var hit := space.intersect_ray(ray)
	var hit_zone := hit.get("collider") as TouchZone
	check(hit_zone != null and hit_zone.dog == dog, "camera ray hits the dog's touch zone")


func test_hold_offer_and_mouth() -> void:
	var item := WorldItem.new()
	# Not "toy": the room's ball would be the nearest one.
	item.affordances = PackedStringArray(["test_toy"])
	item.movable = true
	main.get_node("Items").add_child(item)
	item.global_position = dog.global_position + Vector3(1.0, 0.0, 0.0)
	var hand := Node3D.new()
	hand.add_to_group("player_hands")
	main.add_child(hand)
	hand.global_position = dog.global_position + Vector3(0.0, 0.8, 1.0)

	check(dog.find_nearest_item(&"test_toy") == item, "loose toy is found")
	item.attach_to(hand)
	hand.global_position += Vector3(0.3, 0.0, 0.0)
	await frames(2)
	check(item.global_position.distance_to(hand.global_position) < 0.001, "held item follows hand")
	check(dog.find_nearest_item(&"test_toy") == null, "held toy is skipped by find_nearest_item")
	check(dog.find_offered_item(&"test_toy") == item, "hand-held toy is offered")

	check(not dog.pick_up(item), "dog can't take an item someone holds")
	item.detach()
	check(dog.pick_up(item), "dog picks up a loose item")
	await frames(2)
	check(dog.held_item == item, "dog holds it")
	check(item.global_position.distance_to(dog.get_mouth_position()) < 0.001, "item sits in the mouth")
	check(dog.find_offered_item(&"test_toy") == null, "mouth-held toy is not offered")
	dog.drop_held()
	check(not item.held and dog.held_item == null, "dog dropped it")

	var saved := item.to_dict()
	check(saved.has("pos"), "movable item saves its position")
	item.global_position += Vector3(0.5, 0.0, 0.0)
	item.from_dict(saved)
	var p: Array = saved["pos"]
	check(item.global_position.distance_to(Vector3(p[0], p[1], p[2])) < 0.001, "position restored")

	item.remove()
	hand.queue_free()
	await frames(1)
	check(not is_instance_valid(item), "removed item is freed")


func test_can_reach() -> void:
	check(dog.can_reach(Vector3(0.0, 0.05, 2.0)), "open floor is reachable")
	check(not dog.can_reach(Vector3(1.6, 0.8, 0.6)), "table top is not reachable")
	check(not dog.can_reach(Vector3(1.6, 0.05, 0.6)), "under the table is not reachable")


func test_save_roundtrip_and_v1() -> void:
	var data := dog.brain.to_dict()
	var copy := DogBrain.new()
	copy.from_dict(data)
	check(copy.touch_prefs.to_dict() == dog.brain.touch_prefs.to_dict(), "v2 round-trips touch prefs")

	data.erase("touch_prefs")
	var old_a := DogBrain.new()
	old_a.from_dict(data)
	var old_b := DogBrain.new()
	old_b.from_dict(data)
	var best := -1.0
	for zone: StringName in DogTouchPrefs.ZONES:
		best = maxf(best, old_a.touch_prefs.get_raw(zone))
	check(best >= DogTouchPrefs.MIN_FAVORITE, "v1 save gets rolled prefs")
	check(old_a.touch_prefs.to_dict() == old_b.touch_prefs.to_dict(), "v1 migration is deterministic")

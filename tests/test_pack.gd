extends TestSuite
## Milestone 2 Pack: spawning, unique ids and seeds, item sharing, selection, save/load.

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

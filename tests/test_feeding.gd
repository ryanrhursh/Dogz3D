extends TestSuite
## Milestone 3 Hands step 3: hand feeding (kibble from the bowl, treats from the jar),
## Dog.feed_from_hand, dropped food, come_for_food.

const TEST_SPEED := 4.0
const ComeForFood := preload("res://dog/brain/behaviors/come_for_food.gd")

var hand: HandTool
var bowl: WorldItem
var jar: WorldItem


func before_each() -> void:
	await super.before_each()
	main.exit_closeup()
	hand = main.hand_tool
	bowl = main.food_bowl
	jar = main.treat_jar
	bowl.refill()
	jar.refill()


func after_each() -> void:
	if hand.held_item != null:
		hand.release_at(Vector3(-3.0, 0.4, -2.0))
	for node in tree.get_nodes_in_group("items"):
		var item := node as WorldItem
		if item != null and item.free_when_empty:
			item.remove()
	bowl.refill()
	jar.refill()
	SimClock.paused = false
	await frames(1)


func _behavior(d: Dog, id: StringName) -> DogBehavior:
	for behavior in d.brain.planner.behaviors:
		if behavior.id == id:
			return behavior
	return null


func _doing(d: Dog) -> StringName:
	if d.brain.current == null:
		return &""
	return d.brain.current.id


func _force(d: Dog, id: StringName) -> DogBehavior:
	d.brain.interrupt(d)
	var behavior := _behavior(d, id)
	if behavior != null:
		d.brain._start(d, behavior)
	return behavior


## Calm, awake, resting dog with known hunger, affection and bond; clock paused.
func _prep(hunger: float) -> void:
	SimClock.paused = true
	dog.global_position = Vector3(0.0, 0.05, 1.0)
	for need: StringName in dog.brain.needs.names():
		dog.brain.needs.values[need] = 95.0
	dog.brain.needs.values[&"hunger"] = hunger
	dog.brain.needs.values[&"affection"] = 50.0
	dog.brain.needs.values[&"fun"] = 50.0
	dog.brain.memory.bond = 50.0
	_force(dog, &"idle")


func _run_slow() -> void:
	SimClock.time_scale = TEST_SPEED
	SimClock.paused = false
	await tree.process_frame
	await tree.process_frame


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _bond_scale() -> float:
	return lerpf(DogBrain.HAND_FED_BOND_LOW, DogBrain.HAND_FED_BOND_HIGH,
			dog.brain.personality.get_trait_value(&"food_drive"))


func test_come_for_food_quiet() -> void:
	var behaviors := dog.brain.planner.behaviors
	check(behaviors[behaviors.size() - 2].id == &"come_for_food",
			"come_for_food is registered after the other hand behaviors, before chase_toy")
	SimClock.paused = true
	var state_before := dog.brain.rng.state
	check(not WorldItem.any_held_by_player(), "the hand holds nothing")
	check(_behavior(dog, &"come_for_food").score(dog) == 0.0, "scores 0 with nothing held")
	check(dog.find_offered_item(&"food") == null, "nothing offered")
	check(dog.brain.rng.state == state_before, "scoring doesn't touch the decision RNG")


func test_pick_colliders() -> void:
	var space := dog.get_world_3d().direct_space_state
	for item: WorldItem in [bowl, jar]:
		var from := item.global_position + Vector3(0.0, 2.0, 0.0)
		var query := PhysicsRayQueryParameters3D.create(from, item.global_position, HandTool.RAY_MASK)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		check(WorldItem.from_collider(hit.get("collider")) == item,
				"the hand ray finds the %s" % item.display_name)


func test_take_kibble_and_drop() -> void:
	check(hand.pick_from(bowl), "takes kibble from the bowl")
	check_near(bowl.fill, 0.9, 0.0001, "a handful is 0.1 of the bowl")
	var kibble := hand.held_item
	check(kibble is FoodPiece and kibble.has_affordance(&"food"), "it's food")
	check(hand.state == &"carrying" and kibble.is_held_by_player(), "the hand carries it")
	check(WorldItem.any_held_by_player(), "any_held_by_player sees it")
	check(dog.find_offered_item(&"food") == kibble, "dogs see it offered")
	check(not hand.pick_from(jar), "one thing at a time")

	var spot := dog.global_position + Vector3(-1.5, 0.4, 0.0)
	check(hand.release_at(spot) == null, "released away from any dog: no one eats")
	await frames(1)
	check(is_instance_valid(kibble) and not kibble.held, "dropped, not eaten")
	check(kibble.global_position.y < 0.1, "it fell to the floor (y %.2f)" % kibble.global_position.y)
	check(not WorldItem.any_held_by_player(), "nothing held now")
	check(hand.state == &"off", "hand state back to off in Live mode")
	check(hand.pick_from(kibble), "dropped kibble can be picked up again")
	hand.release_at(spot)

	bowl.fill = 0.05
	check(not hand.pick_from(bowl), "not enough left in the bowl for a handful")


func test_treat_from_jar() -> void:
	check(hand.pick_from(jar), "takes a treat from the jar")
	check_near(jar.fill, 0.9, 0.0001, "the jar holds 10 treats")
	check(hand.held_item.has_affordance(&"treat") and hand.held_item.has_affordance(&"food"),
			"a treat is food and a treat")


func test_hand_feed_kibble() -> void:
	_prep(50.0)
	hand.pick_from(bowl)
	var kibble := hand.held_item
	var eater := hand.release_at(dog.get_mouth_position())
	check(eater == dog, "let go at the mouth: the dog eats")
	check_near(dog.brain.needs.get_value(&"hunger"), 58.0, 0.001, "kibble: hunger +8")
	check_near(dog.brain.needs.get_value(&"affection"), 54.0, 0.001, "kibble: affection +4")
	check_near(dog.brain.memory.bond, 50.0 + 1.0 * _bond_scale(), 0.001,
			"kibble: bond +1 scaled by food_drive")
	check(dog._emote == "nom <3", "nom emote")
	check(not dog.brain.get_stimulus(&"hand_fed").is_empty(), "hand_fed stimulus recorded")
	check(hand.held_item == null and hand.state == &"off", "hand is empty")
	await frames(1)
	check(not is_instance_valid(kibble), "the kibble is gone")


func test_hand_feed_treat() -> void:
	_prep(50.0)
	hand.pick_from(jar)
	check(hand.release_at(dog.get_mouth_position()) == dog, "the dog takes the treat")
	check_near(dog.brain.needs.get_value(&"hunger"), 53.0, 0.001, "treat: hunger +3")
	check_near(dog.brain.needs.get_value(&"affection"), 58.0, 0.001, "treat: affection +8")
	check_near(dog.brain.needs.get_value(&"fun"), 55.0, 0.001, "treat: fun +5")
	check_near(dog.brain.memory.bond, 50.0 + 1.5 * _bond_scale(), 0.001,
			"treat: bond +1.5 scaled by food_drive")


func test_asleep_dog_not_fed() -> void:
	_prep(50.0)
	dog.brain.needs.values[&"energy"] = 30.0
	var sleep := _force(dog, &"sleep")
	dog.stop_moving()
	sleep._fall_asleep(dog)
	hand.pick_from(bowl)
	var kibble := hand.held_item
	check(hand.release_at(dog.get_mouth_position()) == null, "a sleeping dog doesn't eat")
	check_near(dog.brain.needs.get_value(&"hunger"), 50.0, 0.001, "no hunger change")
	check(is_instance_valid(kibble) and not kibble.held, "the kibble is dropped instead")


func test_bowl_gives_no_bond() -> void:
	_prep(30.0)
	SimClock.paused = false
	_force(dog, &"eat")
	var done := await wait_until(func() -> bool: return _doing(dog) != &"eat", 60.0)
	check(done, "finished eating")
	check(dog.brain.needs.get_value(&"hunger") > 60.0, "ate from the bowl")
	check_near(dog.brain.memory.bond, 50.0, 0.001, "bowl food gives no bond")


func test_come_for_food_scores() -> void:
	_prep(40.0)
	var come := _behavior(dog, &"come_for_food")
	hand.pick_from(bowl)
	hand.carry_to(dog.global_position + Vector3(3.0, 0.35, 0.0))
	var hungry := come.score(dog)
	check(hungry > 0.3 and hungry <= ComeForFood.MAX_SCORE, "hungry dog wants it (%.2f)" % hungry)
	dog.brain.needs.values[&"hunger"] = 100.0
	var full := come.score(dog)
	check(full > 0.0 and full < hungry, "a full dog is less keen (%.2f)" % full)
	dog.brain.needs.values[&"hunger"] = 0.0
	check(come.score(dog) <= ComeForFood.MAX_SCORE, "capped below the emergency score")
	hand.carry_to(dog.global_position + Vector3(4.5, 0.35, 0.0))
	check(come.score(dog) == 0.0, "out of range scores 0")
	hand.release_at(Vector3(-3.0, 0.4, -2.0))

	dog.brain.needs.values[&"hunger"] = 40.0
	hand.pick_from(jar)
	hand.carry_to(dog.global_position + Vector3(3.0, 0.35, 0.0))
	check(come.score(dog) > hungry, "a treat beats kibble")


func test_come_for_food() -> void:
	_prep(40.0)
	hand.pick_from(bowl)
	# The bowl is far from the dog: carrying the food over makes it notice.
	var spot := dog.global_position + Vector3(-2.0, 0.35, 0.0)
	hand.carry_to(spot)
	await _run_slow()
	check(await wait_until(func() -> bool: return _doing(dog) == &"come_for_food", 0.5),
			"comes for the food (doing %s)" % _doing(dog))
	var arrived := await wait_until(func() -> bool:
		return _doing(dog) == &"come_for_food" and not dog.is_moving() \
				and _flat(dog.global_position, spot) < 0.8, 5.0)
	check(arrived, "walks up to the hand (%.2f m)" % _flat(dog.global_position, spot))
	var mouth_gap := _flat(dog.get_mouth_position(), spot)
	await tree.process_frame
	check(dog.pose == &"sit", "sits and looks up (pose %s)" % dog.pose)
	check(mouth_gap < 0.45, "its mouth ends up under the hand (%.2f m)" % mouth_gap)

	# The hand moves: the dog follows.
	spot = spot + Vector3(-0.6, 0.0, 1.0)
	hand.carry_to(spot)
	var followed := await wait_until(func() -> bool:
		return not dog.is_moving() and _flat(dog.global_position, spot) < 0.8, 5.0)
	check(followed and _doing(dog) == &"come_for_food",
			"follows the hand (%.2f m, doing %s)" % [_flat(dog.global_position, spot), _doing(dog)])

	check(hand.release_at(dog.get_mouth_position()) == dog, "let go at the head: fed")
	check(await wait_until(func() -> bool: return _doing(dog) != &"come_for_food", 1.0),
			"stops coming once fed")


func test_dropped_food_gets_eaten() -> void:
	_prep(40.0)
	hand.pick_from(bowl)
	var kibble := hand.held_item
	hand.release_at(dog.global_position + Vector3(-1.4, 0.4, 0.0))
	check(dog.find_nearest_item(&"food") == kibble, "dropped kibble is the nearest food")
	var hunger := dog.brain.needs.get_value(&"hunger")
	await _run_slow()
	dog.brain.interrupt(dog)
	# A weak ref: a lambda capturing the kibble itself errors once it's freed.
	var ref: WeakRef = weakref(kibble)
	var eaten := await wait_until(func() -> bool: return ref.get_ref() == null, 20.0)
	check(eaten, "the dog ate the dropped kibble")
	check(dog.brain.needs.get_value(&"hunger") > hunger, "hunger went up")
	check(not dog.brain.cooldowns.has(&"eat"), "eating a piece up counts as done, not failed")


func test_pack_spreads_round_the_hand() -> void:
	_prep(20.0)
	var dogs: Array[Dog] = [dog, pack.adopt(), pack.adopt()]
	await frames(1)
	var starts := [Vector3(0.0, 0.05, 1.0), Vector3(0.5, 0.05, 1.4), Vector3(0.4, 0.05, 0.5)]
	for i in dogs.size():
		var d := dogs[i]
		d.global_position = starts[i]
		for need: StringName in d.brain.needs.names():
			d.brain.needs.values[need] = 95.0
		d.brain.needs.values[&"hunger"] = 20.0
		_force(d, &"idle")
	hand.pick_from(bowl)
	# With the bowl empty, eating can't compete: this is about where they wait.
	bowl.fill = 0.0
	var spot := Vector3(-1.6, 0.35, 1.0)
	hand.carry_to(spot)
	await _run_slow()
	var settled := await wait_until(func() -> bool:
		for d in dogs:
			if _doing(d) != &"come_for_food" or d.is_moving() or d.pose != &"sit":
				return false
		return true, 8.0)
	check(settled, "all three come and sit")
	for i in dogs.size():
		check(_flat(dogs[i].global_position, spot) < 1.0,
				"%s waits by the hand (%.2f m)" % [dogs[i].dog_name, _flat(dogs[i].global_position, spot)])
		for j in range(i + 1, dogs.size()):
			var gap := _flat(dogs[i].global_position, dogs[j].global_position)
			check(gap >= 0.3, "%s and %s don't stack (%.2f m)" % [dogs[i].dog_name, dogs[j].dog_name, gap])

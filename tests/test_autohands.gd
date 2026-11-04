extends TestSuite
## Milestone 3 Hands step 5: the --autohands simulated owner (AutoHands), which plays
## through the HandTool code API only.

const TEST_SPEED := 4.0

var hand: HandTool
var owner: AutoHands
var ball: Ball


func before_each() -> void:
	await super.before_each()
	main.exit_closeup()
	hand = main.hand_tool
	ball = get_ball()
	main.food_bowl.refill()
	main.treat_jar.refill()
	owner = AutoHands.new()
	runner.add_child(owner)
	owner.setup(hand, pack, main.food_bowl, main.treat_jar, ball, 42)
	# Only the calls below act; the owner's own schedule stays out of the way.
	owner.set_process(false)
	SimClock.paused = true
	dog.global_position = Vector3(0.0, 0.05, 1.0)
	for need: StringName in dog.brain.needs.names():
		dog.brain.needs.values[need] = 95.0
	dog.brain.interrupt(dog)


func after_each() -> void:
	owner._feeding = null
	if hand.held_item != null:
		hand.release_at(Vector3(-3.0, 0.4, -2.0))
	for node in tree.get_nodes_in_group("items"):
		var item := node as WorldItem
		if item != null and item.free_when_empty:
			item.remove()
	owner.queue_free()
	main.food_bowl.refill()
	main.treat_jar.refill()
	SimClock.paused = false
	await frames(1)


func _run_slow() -> void:
	SimClock.time_scale = TEST_SPEED
	SimClock.paused = false
	await tree.process_frame
	await tree.process_frame


func test_nothing_to_do() -> void:
	check(not owner._try_feed(), "nobody hungry: no feeding")
	check(not owner._try_pet(), "nobody lonely: no petting")
	check(not owner._try_throw(), "nobody bored: no throw")
	check(hand.held_item == null, "the hand stays empty")


func test_pets_and_learns() -> void:
	dog.brain.needs.values[&"affection"] = 30.0
	dog.brain.touch_prefs.values[&"back"] = -0.8
	dog.brain.touch_prefs.values[&"head"] = 0.8
	dog.brain.memory.bond = 60.0
	check(owner._try_pet(), "strokes a lonely dog")
	check(owner.strokes == AutoHands.STROKES, "counts the strokes")
	check(dog.brain.get_stimulus(&"touch")["zone"] == &"back", "tries the back first")
	check(owner._try_pet(), "strokes again")
	check(dog.brain.get_stimulus(&"touch")["zone"] == &"head", "the back was disliked: tries the head")
	check(owner._try_pet(), "and again")
	check(dog.brain.get_stimulus(&"touch")["zone"] == &"head", "sticks with the liked zone")


func test_hand_feeds_a_hungry_dog() -> void:
	dog.brain.needs.values[&"hunger"] = 40.0
	owner.rng.seed = 1
	check(owner._try_feed(), "holds food out")
	check(hand.held_item != null and hand.held_item.has_affordance(&"food"), "the hand has food")
	check(owner._feeding == dog, "for the hungry dog")
	owner.set_process(true)
	await _run_slow()
	var fed := await wait_until(func() -> bool: return owner.kibble + owner.treats == 1, 10.0)
	check(fed, "the dog came and ate from the hand")
	check(dog.brain.needs.get_value(&"hunger") > 40.0, "hunger went up")
	check(hand.held_item == null and owner._feeding == null, "the hand is empty again")


func test_throws_for_a_bored_dog() -> void:
	dog.brain.needs.values[&"fun"] = 50.0
	ball.get_root().global_position = Vector3(-1.2, 0.06, 1.0)
	await frames(2)
	check(owner._try_throw(), "throws the ball")
	check(owner.throws == 1 and not ball.held, "it's flying")
	check(not dog.brain.get_stimulus(&"ball_thrown").is_empty(), "the dog saw it")
	check(hand.held_item == null, "the hand is empty")

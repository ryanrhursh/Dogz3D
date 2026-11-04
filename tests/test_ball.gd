extends TestSuite
## Milestone 3 Hands step 4: the ball, item bounds, throwing from the hand, chase_toy.

const TEST_SPEED := 4.0
const ChaseToy := preload("res://dog/brain/behaviors/chase_toy.gd")
## Open floor for the ball, away from the dog's spot (0, 0.05, 1).
const FLOOR_SPOT := Vector3(-1.2, 0.06, 1.0)
## The gap between the couch's east end and the north wall: off the navmesh.
const BEHIND_COUCH := Vector3(-1.44, 0.06, -3.85)

var hand: HandTool
var ball: Ball


func before_each() -> void:
	await super.before_each()
	main.exit_closeup()
	hand = main.hand_tool
	ball = get_ball()
	dog.global_position = Vector3(0.0, 0.05, 1.0)


func after_each() -> void:
	if hand.held_item != null:
		hand.release_at(Vector3(-3.0, 0.4, -2.0))
	park_ball()
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


## Awake, rested, a bit bored; resting in place with the clock paused.
func _prep(d: Dog, fun: float) -> void:
	SimClock.paused = true
	for need: StringName in d.brain.needs.names():
		d.brain.needs.values[need] = 95.0
	d.brain.needs.values[&"fun"] = fun
	d.brain.cooldowns.clear()
	_force(d, &"idle")


func _place_ball(at: Vector3) -> void:
	if ball.held:
		park_ball()
	ball.get_root().global_position = at
	ball.physics_body.linear_velocity = Vector3.ZERO
	ball.physics_body.angular_velocity = Vector3.ZERO


func _run_slow() -> void:
	SimClock.time_scale = TEST_SPEED
	SimClock.paused = false
	await tree.process_frame
	await tree.process_frame


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ball_at() -> Vector3:
	return ball.get_root().global_position


func test_ball_setup() -> void:
	check(ball != null, "the room has a ball")
	if ball == null:
		return
	var body := ball.physics_body
	check(body != null and body == ball.get_root(), "it rides on its RigidBody3D")
	check(body.collision_layer == 8, "items layer")
	check(body.collision_mask == (1 | 2 | 16), "hits world, dogs and item bounds")
	check(ball.has_affordance(&"toy") and ball.has_affordance(&"throwable"), "a throwable toy")
	check(ball.movable and not ball.consumable, "movable, not used up")
	var behaviors := dog.brain.planner.behaviors
	check(behaviors[behaviors.size() - 1].id == &"chase_toy", "chase_toy is registered last")
	for wall_name: String in ["South", "East"]:
		var wall := main.get_node("ItemBounds/%s" % wall_name) as StaticBody3D
		check(wall != null and wall.collision_layer == 16, "%s item bound on layer 5" % wall_name)
		check(not (wall.get_parent() is NavigationRegion3D), "%s bound is not under the navmesh" % wall_name)
	check(dog.collision_mask & 16 == 0, "dogs walk through item bounds")
	var nav := main.get_node("Home") as NavigationRegion3D
	check(nav.navigation_mesh.geometry_collision_mask & 16 == 0, "bounds aren't baked")


func test_chase_toy_quiet() -> void:
	_prep(dog, 50.0)
	var chase := _behavior(dog, &"chase_toy")
	var state_before := dog.brain.rng.state
	check(chase.score(dog) == 0.0, "a parked (unreachable) ball scores 0")
	_place_ball(FLOOR_SPOT)
	await frames(2)
	dog.brain.needs.values[&"fun"] = 98.0
	check(chase.score(dog) == 0.0, "not bored at all: 0")
	dog.brain.needs.values[&"fun"] = 50.0
	dog.brain.needs.values[&"energy"] = 20.0
	check(chase.score(dog) == 0.0, "too tired: 0")
	dog.brain.needs.values[&"energy"] = 95.0
	var idle_score := chase.score(dog)
	check(idle_score > 0.1 and idle_score < 0.5, "a bored dog fancies a ball lying about (%.2f)" % idle_score)
	check(dog.brain.rng.state == state_before, "scoring doesn't touch the decision RNG")
	dog.notice(&"ball_thrown", FLOOR_SPOT)
	var thrown_score := chase.score(dog)
	check(thrown_score > idle_score + 0.3 and thrown_score <= ChaseToy.MAX_SCORE,
			"a throw is far more exciting (%.2f)" % thrown_score)
	_force(dog, &"chase_toy")
	_force(dog, &"idle")
	dog.brain._stamp_new_stimuli()
	check(chase.score(dog) == 0.0, "one throw, one chase: it won't go after the same throw again")
	SimClock.advance(0.01)
	dog.notice(&"ball_thrown", FLOOR_SPOT)
	check(chase.score(dog) > idle_score, "a new throw counts again")


func test_hand_velocity() -> void:
	_place_ball(FLOOR_SPOT)
	await frames(2)
	check(hand.pick_from(ball), "the hand grabs the ball")
	check(hand.held_item == ball and ball.is_held_by_player(), "the hand holds it")
	check(ball.physics_body.freeze, "held, it's frozen")
	var p := Vector3(-1.0, 0.4, 1.0)
	hand._samples.clear()
	hand.add_hand_sample(p, 10.0)
	hand.add_hand_sample(p + Vector3(0.2, 0.0, 0.0), 10.05)
	hand.add_hand_sample(p + Vector3(0.4, 0.0, 0.0), 10.1)
	var v := hand.hand_velocity(10.1)
	check_near(v.x, 4.0, 0.01, "hand velocity over the window")
	check(hand.hand_velocity(10.5) == Vector3.ZERO, "a hand that stopped has no velocity")
	var throw := HandTool.throw_from_hand(v)
	check(throw.x > 3.9 and throw.y > 1.0, "a flick throws with some lift (%s)" % throw)
	check(HandTool.throw_from_hand(Vector3(0.5, 0.0, 0.0)) == Vector3.ZERO, "a slow release doesn't throw")


func test_slow_release_drops() -> void:
	_prep(dog, 50.0)
	_place_ball(FLOOR_SPOT)
	await frames(2)
	hand.pick_from(ball)
	hand.carry_to(FLOOR_SPOT + Vector3(0.0, 0.35, 0.0))
	hand._samples.clear()
	hand._release_from_mouse()
	check(not ball.held and hand.held_item == null, "let go")
	check(dog.brain.get_stimulus(&"ball_thrown").is_empty(), "a drop isn't a throw")
	await frames(400)
	check(_flat(_ball_at(), FLOOR_SPOT) < 0.3 and _ball_at().y < 0.15,
			"it fell where the hand was (%s)" % _ball_at())


func test_throw_moves_ball() -> void:
	_prep(dog, 50.0)
	_place_ball(FLOOR_SPOT)
	await frames(2)
	hand.pick_from(ball)
	var from := Vector3(-1.0, 0.4, 1.0)
	hand.carry_to(from)
	check(hand.throw_item(Vector3(-3.0, 1.0, 0.0)), "thrown")
	check(not ball.held and not ball.physics_body.freeze, "flying free")
	check(hand.state == &"off" and hand.held_item == null, "the hand is empty")
	check(not dog.brain.get_stimulus(&"ball_thrown").is_empty(), "the dog saw the throw")
	await frames(240)
	check(_ball_at().x < from.x - 0.6, "the ball flew off (%s)" % _ball_at())

	hand.pick_from(ball)
	hand.carry_to(Vector3(0.0, 0.4, -1.0))
	hand.throw_item(Vector3(50.0, 0.0, 0.0))
	check(ball.physics_body.linear_velocity.length() <= HandTool.MAX_THROW_SPEED + 0.01,
			"throw speed is capped (%.2f)" % ball.physics_body.linear_velocity.length())


func test_bounds_keep_ball_in_room() -> void:
	SimClock.paused = true
	dog.global_position = Vector3(-3.0, 0.05, -2.0)
	for shot: Array in [[Vector3(0.0, 0.4, 3.2), Vector3(0.0, 1.5, 7.0)],
			[Vector3(4.2, 0.4, 0.0), Vector3(7.0, 1.5, 0.0)]]:
		_place_ball(FLOOR_SPOT)
		await frames(2)
		hand.pick_from(ball)
		hand.carry_to(shot[0])
		hand.throw_item(shot[1])
		await frames(600)
		var at := _ball_at()
		check(at.z < 4.0 and at.x < 5.0 and at.y > -0.5,
				"thrown at the low wall, it stays in the room (%s)" % at)


func test_respawn() -> void:
	SimClock.paused = true
	_place_ball(Vector3(0.0, -2.5, 0.0))
	await frames(5)
	check(_flat(_ball_at(), ball.respawn_point) < 0.2 and _ball_at().y > -0.5,
			"a ball that fell out comes back (%s)" % _ball_at())


func test_unreachable_ball_comes_back() -> void:
	_prep(dog, 40.0)
	check(ball.unreachable_return_minutes == INF, "parked for the tests, the return is off")
	ball.unreachable_return_minutes = 5.0
	_place_ball(FLOOR_SPOT)
	await frames(30)
	check(ball.is_reachable(), "on open floor a dog can reach it")
	for i in 8:
		ball.advance_minutes(1.0)
	check(_flat(_ball_at(), FLOOR_SPOT) < 0.3, "a reachable ball stays where it is")

	dog.global_position = Vector3(3.0, 0.05, 2.0)
	_place_ball(BEHIND_COUCH)
	await frames(30)
	check(not ball.is_reachable(), "behind the couch no dog can reach it (%s)" % _ball_at())
	check(_behavior(dog, &"chase_toy").score(dog) == 0.0, "chase_toy ignores it there")
	_place_ball(FLOOR_SPOT)
	await frames(30)
	check(_behavior(dog, &"chase_toy").score(dog) > 0.0, "but plays with it on the floor")
	_place_ball(BEHIND_COUCH)
	await frames(30)
	for i in 3:
		ball.advance_minutes(1.0)
	check(_flat(_ball_at(), BEHIND_COUCH) < 0.3, "not back before its time")
	ball.advance_minutes(0.5)
	ball.advance_minutes(0.5)
	check_near(ball.unreachable_minutes, 4.0, 0.001, "half minutes add up to whole checks")
	# The last minute goes through the real clock (Ball._process).
	SimClock.time_scale = 60.0
	SimClock.paused = false
	check(await wait_until(func() -> bool: return _flat(_ball_at(), ball.respawn_point) < 0.2, 3.0),
			"after 5 game minutes out of reach it is back at its respawn point")
	check(ball.unreachable_minutes == 0.0, "the count starts over")


func test_dog_chases_thrown_ball() -> void:
	_prep(dog, 50.0)
	_place_ball(FLOOR_SPOT)
	await frames(2)
	hand.pick_from(ball)
	hand.carry_to(dog.global_position + Vector3(0.4, 0.4, 0.4))
	hand.throw_item(Vector3(-3.0, 1.0, 0.0))
	await _run_slow()
	check(await wait_until(func() -> bool: return _doing(dog) == &"chase_toy", 0.5),
			"chases the ball at once (doing %s)" % _doing(dog))
	check(dog.gait == &"run", "runs after it")
	var fun := dog.brain.needs.get_value(&"fun")
	var grabbed := await wait_until(func() -> bool: return dog.held_item == ball, 5.0)
	check(grabbed, "grabs the ball (%.2f m away)" % _flat(dog.global_position, _ball_at()))
	await frames(2)
	check(_ball_at().distance_to(dog.get_mouth_position()) < 0.05, "carries it in its mouth")
	var dropped := await wait_until(func() -> bool:
		return dog.held_item == null and _doing(dog) != &"chase_toy", 12.0)
	check(dropped, "drops the ball and stops (doing %s)" % _doing(dog))
	check(not ball.held, "the ball is loose again")
	check(dog.gait == &"walk", "back to walking")
	check(dog.brain.needs.get_value(&"fun") > fun, "playing was fun")
	check(not dog.brain.cooldowns.has(&"chase_toy"), "a game counts as done, not failed")


func test_cant_reach_fails_with_cooldown() -> void:
	_prep(dog, 50.0)
	# The ball rests on the table, which dogs can't reach.
	park_ball()
	await frames(60)
	dog.notice(&"ball_thrown", _ball_at())
	await _run_slow()
	var failed := await wait_until(func() -> bool:
		return dog.brain.cooldowns.has(&"chase_toy"), 1.0)
	check(failed, "gives up on a ball it can't reach (doing %s)" % _doing(dog))
	check(dog.gait == &"walk", "stops running")
	check(_behavior(dog, &"chase_toy").score(dog) >= 0.0, "scoring a cooled-down behavior is safe")
	await tree.process_frame
	check(_doing(dog) != &"chase_toy", "doesn't try again while cooling down")


func test_grab_ball_from_mouth() -> void:
	_prep(dog, 30.0)
	_place_ball(dog.global_position + Vector3(-1.0, 0.0, 0.0))
	await frames(2)
	await _run_slow()
	_force(dog, &"chase_toy")
	var grabbed := await wait_until(func() -> bool: return dog.held_item == ball, 5.0)
	check(grabbed, "the dog has the ball")
	check(hand._can_take(ball), "the hand may take it from the dog's mouth")
	check(hand.pick_from(ball), "the hand takes it")
	check(dog.held_item == null and ball.is_held_by_player(), "now the hand holds it")
	var stopped := await wait_until(func() -> bool: return _doing(dog) != &"chase_toy", 1.0)
	check(stopped, "the dog's game is over")
	check(not dog.brain.cooldowns.has(&"chase_toy"), "losing the ball isn't a failure")
	check(hand.held_item == ball, "the hand still holds it")


func test_two_dogs_race_for_a_throw() -> void:
	_prep(dog, 50.0)
	var b := pack.adopt()
	await frames(1)
	_prep(b, 50.0)
	dog.global_position = Vector3(0.0, 0.05, 1.0)
	b.global_position = Vector3(0.0, 0.05, 0.2)
	_place_ball(FLOOR_SPOT)
	await frames(2)
	hand.pick_from(ball)
	hand.carry_to(Vector3(0.3, 0.4, 0.6))
	hand.throw_item(Vector3(-3.0, 1.0, 0.0))
	await _run_slow()
	var both := await wait_until(func() -> bool:
		return _doing(dog) == &"chase_toy" and _doing(b) == &"chase_toy", 0.5)
	check(both, "both dogs race for it")
	var got := await wait_until(func() -> bool: return ball.held, 5.0)
	check(got, "one of them gets it")
	var winner := dog if dog.held_item == ball else b
	var loser := b if winner == dog else dog
	check(winner.held_item == ball and loser.held_item == null, "only one holds it")
	var gave_up := await wait_until(func() -> bool: return _doing(loser) != &"chase_toy", 1.0)
	check(gave_up, "the other one lets it go")
	check(not loser.brain.cooldowns.has(&"chase_toy"), "losing the race isn't a failure")

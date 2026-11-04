class_name TestSuite
extends RefCounted
## Base for headless test suites. Every method named test_* runs in declaration
## order, inside the real main scene (navmesh, physics, sim clock all live).
## Tests may await (frames, game minutes). A test passes if no check() failed.

const MAX_WAIT_FRAMES := 20000

var runner: Node
var main: Node3D
var pack: Pack
## The pack's first dog, reset to seed 42 before every test.
var dog: Dog
var tree: SceneTree
var failures: PackedStringArray = PackedStringArray()


func setup(p_runner: Node, p_main: Node3D) -> void:
	runner = p_runner
	main = p_main
	tree = p_runner.get_tree()
	pack = p_main.get_node("Pack") as Pack


## Where park_ball() puts the room's ball: on the table, out of every dog's reach.
const BALL_PARK := Vector3(1.6, 0.82, 0.45)


## Runs before every test. Default: the pack trimmed to one fresh seed-42 dog,
## selected, fast clock running, and the ball parked out of reach.
func before_each() -> void:
	if pack.dogs.is_empty():
		pack.adopt()
	for extra in pack.dogs.slice(1):
		pack.remove_dog(extra)
	dog = pack.dogs[0]
	dog.reroll_personality(42)
	pack.select(dog)
	SimClock.paused = false
	SimClock.time_scale = 60.0
	park_ball()
	await frames(2)


## The room's ball (its WorldItem), or null.
func get_ball() -> Ball:
	return main.get_node_or_null("Items/Ball/Item") as Ball


## Puts the ball on the table where no dog can reach it, so chase_toy scores 0 and
## suites that aren't about the ball run as before it existed. Turns off the ball's
## return from out of reach, so it stays parked.
func park_ball() -> void:
	var ball := get_ball()
	if ball == null:
		return
	ball.unreachable_return_minutes = INF
	ball.unreachable_minutes = 0.0
	if ball.held:
		for d in pack.dogs:
			if d.held_item == ball:
				d.drop_held()
		if ball.held:
			ball.detach()
	ball.get_root().global_position = BALL_PARK
	ball.physics_body.linear_velocity = Vector3.ZERO
	ball.physics_body.angular_velocity = Vector3.ZERO


func after_each() -> void:
	pass


func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func check_near(actual: float, expected: float, epsilon: float, message: String) -> bool:
	return check(absf(actual - expected) <= epsilon,
			"%s (got %.4f, expected %.4f +- %.4f)" % [message, actual, expected, epsilon])


func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## Waits until `minutes` of game time have passed.
func game_minutes(minutes: float) -> void:
	var until := SimClock.total_minutes + minutes
	var guard := 0
	while SimClock.total_minutes < until and guard < MAX_WAIT_FRAMES:
		await tree.process_frame
		guard += 1


## Waits until condition.call() is true or `max_minutes` of game time pass.
## Returns whether the condition became true.
func wait_until(condition: Callable, max_minutes: float) -> bool:
	var until := SimClock.total_minutes + max_minutes
	var guard := 0
	while guard < MAX_WAIT_FRAMES:
		if bool(condition.call()):
			return true
		if SimClock.total_minutes >= until:
			return false
		await tree.process_frame
		guard += 1
	return false

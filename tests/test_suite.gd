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


## Runs before every test. Default: the pack trimmed to one fresh seed-42 dog,
## selected, fast clock running.
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
	await frames(2)


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

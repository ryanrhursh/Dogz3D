class_name DogBehavior
extends RefCounted
## Base class for one thing the dog can choose to do.
##
## Lifecycle: the planner calls score() on every behavior. The winner gets enter(),
## then tick() each frame with elapsed game minutes until it returns SUCCEEDED or
## FAILED, or the planner swaps it out. exit() is always called on the way out.
##
## Behaviors act on the world only through the Dog's body API
## (go_to, face_point, set_pose, find_nearest_item, ...).

const RUNNING := 0
const SUCCEEDED := 1
const FAILED := 2

var id: StringName = &"behavior"
var label := "Behavior"
## If false, only an emergency (another score >= UtilityPlanner.OVERRIDE_SCORE) can interrupt.
var interruptible := true
## Game minutes to stay committed before the planner may swap to something else.
var min_duration := 2.0
## Game minutes this behavior is blocked after it fails, so the dog doesn't retry in a loop.
var cooldown_on_fail := 10.0


## 0..1 desire to do this right now.
func score(_dog: Dog) -> float:
	return 0.0


func enter(_dog: Dog) -> void:
	pass


func tick(_dog: Dog, _game_minutes: float) -> int:
	return RUNNING


func exit(_dog: Dog) -> void:
	pass


## Response curve: maps 0..1 urgency to 0..1 desire. Exponent > 1 ignores mild need.
static func curve(x: float, exponent: float) -> float:
	return pow(clampf(x, 0.0, 1.0), exponent)


## Maps one of the dog's 0..1 traits onto [low, high].
static func trait_mod(dog: Dog, trait_name: StringName, low: float, high: float) -> float:
	return lerpf(low, high, dog.brain.personality.get_trait_value(trait_name))

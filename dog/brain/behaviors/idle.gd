extends DogBehavior
## Sit or lie down for a few minutes. The always-available fallback.

const BASE_SCORE := 0.12
const ENERGY_PER_HOUR := 3.0

var _duration := 0.0
var _elapsed := 0.0


func _init() -> void:
	id = &"idle"
	label = "Rest"
	min_duration = 3.0


func score(dog: Dog) -> float:
	return BASE_SCORE + dog.brain.needs.urgency(&"energy") * 0.15


func enter(dog: Dog) -> void:
	dog.stop_moving()
	_elapsed = 0.0
	_duration = dog.brain.rng.randf_range(5.0, 15.0)
	if dog.brain.rng.randf() < 0.5:
		dog.set_pose(&"sit")
	else:
		dog.set_pose(&"lie")


func tick(dog: Dog, game_minutes: float) -> int:
	_elapsed += game_minutes
	dog.brain.needs.change(&"energy", ENERGY_PER_HOUR * game_minutes / 60.0)
	if _elapsed >= _duration:
		return SUCCEEDED
	return RUNNING


func exit(dog: Dog) -> void:
	dog.set_pose(&"stand")

extends DogBehavior
## The player is petting a spot the dog likes (or doesn't mind): it stops, faces the
## hand and sits for it (lies down for a belly rub). Ends a minute after the last touch.
##
## Scores 0 until the hand touches the dog, so the soak baselines don't move.

## A liked or neutral touch younger than this (game minutes) wins the dog over.
const FRESH_MINUTES := 0.75
## Done once the hand has been away this long.
const DONE_MINUTES := 1.0
const SCORE := 0.95
## While running, the gap between FRESH_MINUTES and DONE_MINUTES still scores this.
const LINGER_SCORE := 0.5
## Only turn toward the hand when it's at least this far out (flat metres); a hand on the
## back is right above the dog.
const FACE_MIN_DISTANCE := 0.3


func _init() -> void:
	id = &"enjoy_pets"
	label = "Enjoy pets"
	min_duration = 0.5


func score(dog: Dog) -> float:
	var brain := dog.brain
	if brain.stimuli.is_empty() or dog.sleeping:
		return 0.0
	var touch := brain.get_stimulus(&"touch")
	if touch.is_empty() or touch["reaction"] == &"dislikes":
		return 0.0
	var age := brain.stimulus_age(&"touch")
	if age < FRESH_MINUTES:
		return SCORE
	if brain.current == self and age < DONE_MINUTES:
		return LINGER_SCORE
	return 0.0


func enter(dog: Dog) -> void:
	dog.stop_moving()
	_settle(dog)


func tick(dog: Dog, _game_minutes: float) -> int:
	var touch := dog.brain.get_stimulus(&"touch")
	if touch.is_empty() or touch["reaction"] == &"dislikes" \
			or dog.brain.stimulus_age(&"touch") >= DONE_MINUTES:
		return SUCCEEDED
	_settle(dog)
	return RUNNING


func exit(dog: Dog) -> void:
	dog.set_pose(&"stand")


func _settle(dog: Dog) -> void:
	var touch := dog.brain.get_stimulus(&"touch")
	if touch.is_empty():
		return
	if touch["zone"] == &"belly":
		dog.set_pose(&"lie")
	else:
		dog.set_pose(&"sit")
	var point: Vector3 = touch["point"]
	var offset := point - dog.global_position
	offset.y = 0.0
	if offset.length() >= FACE_MIN_DISTANCE:
		dog.face_point(point)

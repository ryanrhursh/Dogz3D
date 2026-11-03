extends DogBehavior
## The hand touched a spot the dog dislikes: it ducks out from under it, walking to a
## spot 0.8-1.4 m away from the hand. Beats eating and sleeping (a disliked touch wakes
## it). Not interruptible.
##
## Scores 0 until the hand touches the dog, so the soak baselines don't move.

## A disliked touch younger than this (game minutes) makes the dog duck.
const FRESH_MINUTES := 0.5
const SCORE := 1.0
const MIN_DISTANCE := 0.8
const MAX_DISTANCE := 1.4
## Gives up on the walk after this long (game minutes).
const MAX_MINUTES := 2.0

## SimClock minutes of the disliked touch this behavior last reacted to.
var _handled_at := -INF
var _elapsed := 0.0


func _init() -> void:
	id = &"duck_away"
	label = "Duck away"
	interruptible = false
	min_duration = 0.25


func score(dog: Dog) -> float:
	var brain := dog.brain
	if brain.stimuli.is_empty():
		return 0.0
	var touch := brain.get_stimulus(&"touch")
	if touch.is_empty() or touch["reaction"] != &"dislikes":
		return 0.0
	if brain.current == self:
		return SCORE
	if float(touch["at"]) <= _handled_at or brain.stimulus_age(&"touch") >= FRESH_MINUTES:
		return 0.0
	return SCORE


func enter(dog: Dog) -> void:
	_elapsed = 0.0
	_move_away(dog)


func tick(dog: Dog, game_minutes: float) -> int:
	_elapsed += game_minutes
	var touch := dog.brain.get_stimulus(&"touch")
	# Touched there again on the way: duck from the new spot (once the brain has stamped
	# the touch, so it isn't handled twice).
	if not touch.is_empty() and touch["reaction"] == &"dislikes" \
			and not bool(touch["new"]) and float(touch["at"]) > _handled_at:
		_move_away(dog)
		return RUNNING
	if dog.is_moving() and _elapsed < MAX_MINUTES:
		return RUNNING
	return SUCCEEDED


func exit(dog: Dog) -> void:
	dog.stop_moving()
	dog.set_pose(&"stand")


func _move_away(dog: Dog) -> void:
	var touch := dog.brain.get_stimulus(&"touch")
	var from := dog.global_position
	if not touch.is_empty():
		_handled_at = float(touch["at"])
		from = touch["point"]
	dog.go_to(dog.point_away_from(from, MIN_DISTANCE, MAX_DISTANCE), 0.2)

extends DogBehavior
## Go to the bed (or flop where it stands) and sleep. Restores energy.
## At night the dog stays asleep until morning once it's rested.

const ENERGY_PER_HOUR := 14.0
const BED_BONUS := 1.25
const WAKE_AT := 97.0
const NIGHT_PULL := 0.4

var _bed: WorldItem
var _asleep := false


func _init() -> void:
	id = &"sleep"
	label = "Sleep"
	interruptible = false
	min_duration = 20.0


func score(dog: Dog) -> float:
	var energy := dog.brain.needs.get_value(&"energy")
	if energy >= 90.0:
		return 0.0
	var s := curve(1.0 - energy / 100.0, 1.4) * 1.2
	if SimClock.is_night() and energy < 85.0:
		s += NIGHT_PULL
	return clampf(s, 0.0, 1.0)


func enter(dog: Dog) -> void:
	_asleep = false
	_bed = dog.find_nearest_item(&"bed")
	if _bed != null:
		dog.go_to_item(_bed)
	else:
		_fall_asleep(dog)


func tick(dog: Dog, game_minutes: float) -> int:
	if not _asleep:
		if dog.is_moving():
			return RUNNING
		_fall_asleep(dog)
		return RUNNING

	var rate := ENERGY_PER_HOUR
	if _bed != null and _flat_distance(dog.global_position, _bed.global_position) < 0.8:
		rate *= BED_BONUS
	dog.brain.needs.change(&"energy", rate * game_minutes / 60.0)

	if dog.brain.needs.get_value(&"energy") >= WAKE_AT and not SimClock.is_night():
		return SUCCEEDED
	return RUNNING


func exit(dog: Dog) -> void:
	_asleep = false
	_bed = null
	dog.sleeping = false
	dog.set_pose(&"stand")


func _fall_asleep(dog: Dog) -> void:
	dog.stop_moving()
	_asleep = true
	dog.sleeping = true
	dog.set_pose(&"sleep")


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

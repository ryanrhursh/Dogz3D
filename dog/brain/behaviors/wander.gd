extends DogBehavior
## Trot to a few nearby spots and sniff each one. Feeds the fun need.

const LEGS_MIN := 2
const LEGS_MAX := 4
const SNIFF_MIN := 0.5
const SNIFF_MAX := 2.5
const FUN_PER_MINUTE := 1.2
const EXTRA_ENERGY_PER_MINUTE := 0.04

var _legs_left := 0
var _sniff_left := 0.0
var _sniffing := false


func _init() -> void:
	id = &"wander"
	label = "Wander"
	min_duration = 3.0


func score(dog: Dog) -> float:
	var needs := dog.brain.needs
	# Tired dogs don't explore: fades out between 15 and 55 energy.
	var energy_gate := clampf((needs.get_value(&"energy") - 15.0) / 40.0, 0.0, 1.0)
	# A content dog (fun near 100) would rather rest; boredom makes it explore.
	var restless := 0.08 + needs.urgency(&"fun") * 0.6
	return clampf(restless * trait_mod(dog, &"energy", 0.75, 1.3) * energy_gate, 0.0, 1.0)


func enter(dog: Dog) -> void:
	_legs_left = dog.brain.rng.randi_range(LEGS_MIN, LEGS_MAX)
	_next_leg(dog)


func tick(dog: Dog, game_minutes: float) -> int:
	dog.brain.needs.change(&"fun", FUN_PER_MINUTE * game_minutes)

	if dog.is_moving():
		dog.brain.needs.change(&"energy", -EXTRA_ENERGY_PER_MINUTE * game_minutes)
		return RUNNING

	if not _sniffing:
		# Arrived (or got stuck, which is fine for wandering): sniff around.
		_sniffing = true
		_sniff_left = dog.brain.rng.randf_range(SNIFF_MIN, SNIFF_MAX)
		dog.set_pose(&"sniff")
		return RUNNING

	_sniff_left -= game_minutes
	if _sniff_left > 0.0:
		return RUNNING
	if _legs_left <= 0:
		return SUCCEEDED
	_next_leg(dog)
	return RUNNING


func exit(dog: Dog) -> void:
	dog.stop_moving()
	dog.set_pose(&"stand")


func _next_leg(dog: Dog) -> void:
	_legs_left -= 1
	_sniffing = false
	dog.go_to(dog.random_point_near(dog.global_position, 1.5, 5.0))

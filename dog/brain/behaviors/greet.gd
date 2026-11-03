extends DogBehavior
## Walk up to a nearby dog and sniff hello. Sociable dogs do it more, and strangers
## are the most interesting. Builds affinity both ways, unless the other dog is grumpy.
##
## Scores 0 when no other awake dog is within RANGE, so a lone dog never picks it.

## Flat metres to look for a dog to greet.
const RANGE := 6.0
## Close enough to sniff.
const SNIFF_DISTANCE := 0.9
const ARRIVE_RADIUS := 0.75
## Game minutes before greeting the same dog again.
const REGREET_MINUTES := 180.0
## Game minutes after any greeting before the next one.
const GAP_MINUTES := 60.0
const MAX_MINUTES := 8.0
const RETARGET_MINUTES := 1.0
const SNIFF_MIN := 1.0
const SNIFF_MAX := 2.5
## The other dog's mood below this and the greeting goes badly.
const GRUMPY_MOOD := -0.3
const STRANGER_BONUS := 0.15
const AFFINITY_LOW := 0.04
const AFFINITY_HIGH := 0.08
const SNUBBED_AFFINITY := -0.03
const AFFECTION_GAIN := 1.5

var _candidate := ""
var _partner := ""
var _elapsed := 0.0
var _retarget := 0.0
var _sniff_left := 0.0
var _sniffing := false
var _last_done := -INF


func _init() -> void:
	id = &"greet"
	label = "Greet"
	min_duration = 2.0
	cooldown_on_fail = 15.0


func score(dog: Dog) -> float:
	if dog.brain.current == self:
		return 0.5
	var now := SimClock.total_minutes
	if now - _last_done < GAP_MINUTES:
		return 0.0
	var needs := dog.brain.needs
	if needs.get_value(&"energy") < 20.0:
		return 0.0
	var memory := dog.brain.memory
	_candidate = dog.find_nearest_dog(RANGE, func(info: Dictionary) -> bool:
		var doing: StringName = info["doing"]
		return not bool(info["sleeping"]) and doing != &"play_together" \
				and doing != &"eat" and doing != &"drink" \
				and memory.minutes_since_greeted(str(info["id"]), now) >= REGREET_MINUTES)
	if _candidate == "":
		return 0.0
	var s := (0.08 + needs.urgency(&"affection") * 0.2) * trait_mod(dog, &"sociability", 0.6, 1.5)
	if not memory.knows(_candidate):
		s += STRANGER_BONUS
	if memory.get_affinity(_candidate) < -0.3:
		s *= 0.3
	return clampf(s, 0.0, 0.7)


func enter(dog: Dog) -> void:
	_partner = _candidate
	_elapsed = 0.0
	_retarget = 0.0
	_sniffing = false
	dog.set_social_partner(_partner)


func tick(dog: Dog, game_minutes: float) -> int:
	_elapsed += game_minutes
	var info := dog.get_dog_info(_partner)
	if info.is_empty() or bool(info["sleeping"]):
		return FAILED
	var where: Vector3 = info["position"]

	if _sniffing:
		dog.face_point(where)
		_sniff_left -= game_minutes
		if _sniff_left <= 0.0:
			return SUCCEEDED
		return RUNNING

	if _elapsed > MAX_MINUTES or dog.is_stuck():
		return FAILED
	if float(info["distance"]) <= SNIFF_DISTANCE:
		_start_sniff(dog, info)
		return RUNNING
	_retarget -= game_minutes
	if _retarget <= 0.0 or not dog.is_moving():
		_retarget = RETARGET_MINUTES
		dog.go_to(where, ARRIVE_RADIUS)
	return RUNNING


func exit(dog: Dog) -> void:
	dog.stop_moving()
	dog.set_pose(&"stand")
	dog.set_social_partner("")
	_last_done = SimClock.total_minutes
	_partner = ""


func _start_sniff(dog: Dog, info: Dictionary) -> void:
	_sniffing = true
	dog.stop_moving()
	dog.set_pose(&"sniff")
	_sniff_left = dog.brain.rng.randf_range(SNIFF_MIN, SNIFF_MAX)
	var brain := dog.brain
	brain.memory.last_greeted[_partner] = SimClock.total_minutes
	if float(info["mood"]) < GRUMPY_MOOD:
		brain.memory.change_affinity(_partner, SNUBBED_AFFINITY)
		dog.notify_dog(_partner, &"bothered")
		dog.show_emote("?", 1.0)
		return
	brain.memory.change_affinity(_partner, trait_mod(dog, &"sociability", AFFINITY_LOW, AFFINITY_HIGH))
	brain.add_social_affection(AFFECTION_GAIN)
	dog.notify_dog(_partner, &"greeted")
	dog.show_emote("sniff", 1.0)

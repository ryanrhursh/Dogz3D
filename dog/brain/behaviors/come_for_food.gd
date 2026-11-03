extends DogBehavior
## The player holds out food within RANGE: the dog walks to a spot by the hand (on a ring
## around it, from its own side, so a crowd of dogs spreads out), sits and looks up at it,
## following if the hand moves. The hand feeds it by letting go near its head
## (Dog.feed_from_hand). Hungry dogs, foodies and dogs that trust you come more readily;
## treats beat kibble. Capped below the emergency score, so it never interrupts eating
## or sleeping. Milestone 5 builds training lures on this.
##
## Scores 0 unless a player hand holds something (static check, no scans), so the soak
## baselines don't move.

## Flat metres from the dog to the held food.
const RANGE := 4.0
## Once coming, it keeps following a little further.
const KEEP_RANGE := 5.0
const MAX_SCORE := 0.85
const BASE := 0.3
const HUNGER_WEIGHT := 0.6
const TREAT_BONUS := 0.15
## Re-path when the hand has moved this far from where the dog was heading.
const REPATH_DISTANCE := 0.6
## The dog waits this far (flat) from the point under the hand: its mouth is then right
## below it.
const SPOT_RADIUS := 0.55
const ARRIVE_RADIUS := 0.15
## Another dog this close when it gets there: if that dog is already sitting there, or
## has the smaller dog_id (both just arrived), this one moves round the ring.
const CROWD_RADIUS := 0.4
## A spot counts as standable when the navmesh is this close to it.
const SPOT_SLACK := 0.15
## Angles (radians) tried round the ring from "straight from the dog's side". Neighbors
## 0.9 apart are about 0.48 m apart, outside CROWD_RADIUS.
const SPOT_ANGLES := [0.0, 0.9, -0.9, 1.8, -1.8, 2.7, -2.7, 3.14]
## Each radian away from its own side costs this much clearance when picking a spot.
const SIDE_PREFERENCE := 0.1
## Clearance from other dogs counts up to this (flat metres).
const ENOUGH_CLEARANCE := 1.0
const MAX_MOVES := 6
## Gives up waiting after this long (game minutes).
const MAX_MINUTES := 10.0

var _item: WorldItem
var _target := Vector3.ZERO
## Where the hand was when the dog picked its spot.
var _hand_at := Vector3.ZERO
## Times it moved round the ring because the spot was taken.
var _moves := 0
var _elapsed := 0.0
var _settled := false


func _init() -> void:
	id = &"come_for_food"
	label = "Come for food"
	min_duration = 1.0
	cooldown_on_fail = 3.0


func score(dog: Dog) -> float:
	if not WorldItem.any_held_by_player() or dog.sleeping:
		return 0.0
	var item := dog.find_offered_item(&"food")
	if item == null:
		return 0.0
	var reach := KEEP_RANGE if dog.brain.current == self else RANGE
	if _flat_distance(dog.global_position, item.global_position) > reach:
		return 0.0
	var s := BASE + dog.brain.needs.urgency(&"hunger") * HUNGER_WEIGHT
	s *= trait_mod(dog, &"food_drive", 0.6, 1.3)
	s *= lerpf(0.85, 1.15, dog.brain.memory.bond / DogMemory.MAX_BOND)
	if item.has_affordance(&"treat"):
		s += TREAT_BONUS
	return clampf(s, 0.0, MAX_SCORE)


func enter(dog: Dog) -> void:
	_elapsed = 0.0
	_moves = 0
	_item = dog.find_offered_item(&"food")
	if _item != null:
		_head_for(dog)


func tick(dog: Dog, game_minutes: float) -> int:
	_elapsed += game_minutes
	# Fed, dropped or put away: done.
	if _item == null or not is_instance_valid(_item) or not _item.is_held_by_player():
		return SUCCEEDED
	if _elapsed >= MAX_MINUTES:
		return SUCCEEDED
	if _flat_distance(_item.global_position, _hand_at) > REPATH_DISTANCE:
		_moves = 0
		_head_for(dog)
		return RUNNING
	if dog.is_moving():
		return RUNNING
	if not _settled:
		if _flat_distance(dog.global_position, _target) > ARRIVE_RADIUS + 0.3 \
				and _flat_distance(dog.global_position, _hand_at) > SPOT_RADIUS + 0.7:
			return FAILED
		if _moves < MAX_MOVES and _spot_taken(dog):
			_moves += 1
			_head_for(dog)
			return RUNNING
		_settled = true
		dog.set_pose(&"sit")
	dog.face_point(_item.global_position)
	return RUNNING


func exit(dog: Dog) -> void:
	dog.stop_moving()
	dog.set_pose(&"stand")
	_item = null


## Picks a reachable spot on the ring round the hand, near its own side and clear of the
## dogs already there, and walks to it.
func _head_for(dog: Dog) -> void:
	_hand_at = _item.global_position
	var center := Vector3(_hand_at.x, dog.global_position.y, _hand_at.z)
	var side := dog.global_position - center
	side.y = 0.0
	if side.length() < 0.05:
		side = Vector3.BACK
	side = side.normalized()
	var others := _dogs_round(dog, center)
	_target = center + side * SPOT_RADIUS
	var best := -INF
	for angle: float in SPOT_ANGLES:
		var candidate := center + side.rotated(Vector3.UP, angle) * SPOT_RADIUS
		if not dog.can_reach(candidate, SPOT_SLACK):
			continue
		var clearance := ENOUGH_CLEARANCE
		for p: Vector3 in others:
			clearance = minf(clearance, _flat_distance(candidate, p))
		var value := clearance - absf(angle) * SIDE_PREFERENCE
		if value > best:
			best = value
			_target = candidate
	_settled = false
	dog.go_to(_target, ARRIVE_RADIUS)


## Positions of the other dogs near the ring round `center`.
func _dogs_round(dog: Dog, center: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var reach := _flat_distance(dog.global_position, center) + SPOT_RADIUS + 0.6
	for other_id in dog.dogs_near(reach):
		var info := dog.get_dog_info(other_id)
		var p: Vector3 = info.get("position", Vector3.INF)
		if _flat_distance(p, center) <= SPOT_RADIUS + 0.6:
			out.append(p)
	return out


## True if a dog within CROWD_RADIUS was there first (sitting) or wins the tie (smaller id).
func _spot_taken(dog: Dog) -> bool:
	for other_id in dog.dogs_near(CROWD_RADIUS):
		var info := dog.get_dog_info(other_id)
		if info.get("pose") == &"sit" or other_id < dog.dog_id:
			return true
	return false


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

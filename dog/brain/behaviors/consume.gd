extends DogBehavior
## Walk to an item with a given affordance and consume from it until the need is met.
## One script drives both eat (food bowl) and drink (water bowl).

## Need points gained per game minute of consuming.
const SATISFY_PER_MINUTE := 6.0
## Item fill used per game minute (a full bowl = 12.5 minutes).
const UNITS_PER_MINUTE := 0.08
const STOP_AT := 96.0
const MAX_MINUTES := 15.0
## Below this urgency the dog isn't interested at all.
const MIN_URGENCY := 0.2

var need: StringName
var affordance: StringName
var drive_trait: StringName
var pose: StringName

var _item: WorldItem
var _consumed_minutes := 0.0


func _init(p_id: StringName, p_label: String, p_need: StringName, p_affordance: StringName,
		p_drive_trait: StringName, p_pose: StringName) -> void:
	id = p_id
	label = p_label
	need = p_need
	affordance = p_affordance
	drive_trait = p_drive_trait
	pose = p_pose
	interruptible = false
	min_duration = 1.0


func score(dog: Dog) -> float:
	var u := dog.brain.needs.urgency(need)
	if u < MIN_URGENCY:
		return 0.0
	if dog.find_nearest_item(affordance) == null:
		return 0.0
	var mod := 1.0
	if drive_trait != &"":
		mod = trait_mod(dog, drive_trait, 0.85, 1.2)
	return clampf(curve(u, 1.3) * 1.15 * mod, 0.0, 1.0)


func enter(dog: Dog) -> void:
	_consumed_minutes = 0.0
	_item = dog.find_nearest_item(affordance)
	if _item != null and not dog.claim_item(_item):
		_item = null
	if _item != null:
		dog.go_to_item(_item)


func tick(dog: Dog, game_minutes: float) -> int:
	if _item == null or not is_instance_valid(_item):
		# A piece of food on the floor is freed once it's eaten up.
		if _consumed_minutes > 0.0:
			return SUCCEEDED
		return FAILED
	if dog.is_moving():
		return RUNNING
	if dog.is_stuck():
		return FAILED
	if not _item.is_available():
		if _consumed_minutes > 0.5:
			return SUCCEEDED
		return FAILED

	dog.face_point(_item.global_position)
	dog.set_pose(pose)
	var wanted := UNITS_PER_MINUTE * game_minutes
	var got := _item.consume(wanted)
	var ratio := 0.0
	if wanted > 0.0:
		ratio = got / wanted
	dog.brain.needs.change(need, SATISFY_PER_MINUTE * game_minutes * ratio)
	_consumed_minutes += game_minutes

	if dog.brain.needs.get_value(need) >= STOP_AT or _consumed_minutes >= MAX_MINUTES:
		return SUCCEEDED
	return RUNNING


func exit(dog: Dog) -> void:
	dog.set_pose(&"stand")
	if is_instance_valid(_item):
		dog.release_item(_item)
	_item = null

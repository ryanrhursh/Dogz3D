extends DogBehavior
## A hungry or thirsty dog finds every bowl it needs busy: it gets in line, sits a little
## way off facing the bowl, and when its turn comes it eats or drinks (the same steps as
## eat/drink). Without this, a busy bowl was invisible and a dog could go without.
##
## Scores 0 whenever a bowl is free for the dog, so a lone dog never picks it.

const ConsumeBehavior := preload("res://dog/brain/behaviors/consume.gd")

## Need -> affordance of the items that satisfy it.
const NEEDS := {&"hunger": &"food", &"thirst": &"water"}
## Below this urgency the dog isn't interested (same as eat/drink).
const MIN_URGENCY := 0.2
## How far from the bowl the first dog in line sits; each later dog sits a bit further.
const WAIT_DISTANCE := 1.1
const LINE_SPACING := 0.5
const MAX_WAIT_MINUTES := 90.0

var _consumers: Dictionary = {}
var _need: StringName = &""
var _item: WorldItem
var _consumer: DogBehavior
var _eating := false
var _waited := 0.0


func _init() -> void:
	id = &"wait_turn"
	label = "Wait turn"
	interruptible = false
	min_duration = 1.0
	cooldown_on_fail = 10.0
	_consumers[&"hunger"] = ConsumeBehavior.new(&"eat", "Eat", &"hunger", &"food", &"food_drive", &"eat")
	_consumers[&"thirst"] = ConsumeBehavior.new(&"drink", "Drink", &"thirst", &"water", &"", &"eat")


func score(dog: Dog) -> float:
	if dog.brain.current == self:
		return 0.5
	var best := 0.0
	_need = &""
	for need: StringName in NEEDS:
		var u := dog.brain.needs.urgency(need)
		if u < MIN_URGENCY:
			continue
		var affordance: StringName = NEEDS[need]
		if dog.find_nearest_item(affordance) != null or dog.find_busy_item(affordance) == null:
			continue
		var s := clampf(curve(u, 1.3) * 1.15, 0.0, 1.0)
		if s > best:
			best = s
			_need = need
	return best


func enter(dog: Dog) -> void:
	_eating = false
	_waited = 0.0
	_consumer = _consumers.get(_need)
	_item = null
	if _need == &"":
		return
	var affordance: StringName = NEEDS[_need]
	_item = dog.find_busy_item(affordance)
	if _item == null:
		return
	dog.join_queue(_item)
	var place := maxi(_item.queue_position(dog), 0)
	dog.go_to(_item.get_wait_point(dog.global_position, WAIT_DISTANCE + LINE_SPACING * place), 0.3)


func tick(dog: Dog, game_minutes: float) -> int:
	if _eating:
		return _consumer.tick(dog, game_minutes)
	if _item == null or not is_instance_valid(_item) or not _item.is_available():
		return FAILED
	if _item.is_free_for(dog):
		# Our turn: walk up and eat or drink.
		_eating = true
		_consumer.enter(dog)
		return _consumer.tick(dog, game_minutes)
	_waited += game_minutes
	if _waited > MAX_WAIT_MINUTES:
		return FAILED
	if not dog.is_moving():
		dog.face_point(_item.global_position)
		dog.set_pose(&"sit")
	return RUNNING


func exit(dog: Dog) -> void:
	if _eating:
		_consumer.exit(dog)
	if is_instance_valid(_item):
		dog.leave_queue(_item)
	_item = null
	_eating = false
	dog.stop_moving()
	dog.set_pose(&"stand")

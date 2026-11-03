class_name DogBrain
extends RefCounted
## Decides what the dog wants and does. Owns needs, personality, memory and the planner.
## It touches the world only through the Dog passed into tick().

signal behavior_changed(from_id: StringName, to_id: StringName, reason: String)

const EVAL_INTERVAL_MINUTES := 2.0
const MAX_LOG := 12
## Needs never drop below this from offline catch-up: cozy, not punishing.
const OFFLINE_FLOOR := 20.0

const WanderBehavior := preload("res://dog/brain/behaviors/wander.gd")
const ConsumeBehavior := preload("res://dog/brain/behaviors/consume.gd")
const SleepBehavior := preload("res://dog/brain/behaviors/sleep.gd")
const IdleBehavior := preload("res://dog/brain/behaviors/idle.gd")

var needs := DogNeeds.new()
var personality := DogPersonality.new()
var memory := DogMemory.new()
var planner := UtilityPlanner.new()
var rng := RandomNumberGenerator.new()

var current: DogBehavior
var minutes_in_current := 0.0
## Behavior id -> game minutes of cooldown left.
var cooldowns: Dictionary = {}
var decision_log: Array[String] = []
## Behavior id -> times chosen. Used by the soak-test summary.
var choice_counts: Dictionary = {}

var _since_eval := 0.0
var _last_id: StringName = &"none"
var _end_reason := "start"


func setup(p_personality: DogPersonality, seed_value: int) -> void:
	personality = p_personality
	needs = DogNeeds.new()
	memory = DogMemory.new()
	rng.seed = seed_value
	current = null
	minutes_in_current = 0.0
	cooldowns.clear()
	decision_log.clear()
	choice_counts.clear()
	_last_id = &"none"
	_end_reason = "start"
	_apply_personality()

	var list: Array[DogBehavior] = [
		WanderBehavior.new(),
		ConsumeBehavior.new(&"eat", "Eat", &"hunger", &"food", &"food_drive", &"eat"),
		ConsumeBehavior.new(&"drink", "Drink", &"thirst", &"water", &"", &"eat"),
		SleepBehavior.new(),
		IdleBehavior.new(),
	]
	planner.behaviors = list


func tick(dog: Dog, game_minutes: float) -> void:
	if game_minutes <= 0.0:
		return
	needs.decay(game_minutes, dog.sleeping)
	_tick_cooldowns(game_minutes)

	if current != null:
		minutes_in_current += game_minutes
		var status := current.tick(dog, game_minutes)
		if status == DogBehavior.SUCCEEDED:
			_end_current(dog, "done")
		elif status == DogBehavior.FAILED:
			cooldowns[current.id] = current.cooldown_on_fail
			_end_current(dog, "failed")

	_since_eval += game_minutes
	var due := _since_eval >= EVAL_INTERVAL_MINUTES
	var may_switch := current == null or not current.interruptible \
			or minutes_in_current >= current.min_duration
	if current == null or (due and may_switch):
		_since_eval = 0.0
		var next := planner.choose(dog, current, cooldowns, rng)
		if next != current:
			if current != null:
				_end_current(dog, "outscored")
			_start(dog, next)


## Drops the current behavior without logging (used on load / reroll).
func interrupt(dog: Dog) -> void:
	if current != null:
		current.exit(dog)
	current = null
	minutes_in_current = 0.0
	_end_reason = "interrupted"


## -1 (miserable) .. +1 (content). The lowest need drags mood down hardest.
func mood() -> float:
	var blended := lerpf(needs.average(), needs.lowest(), 0.4)
	return clampf(blended / DogNeeds.MAX_VALUE * 2.0 - 1.0, -1.0, 1.0)


## Debug stand-in for milestone 2's hand tool.
func on_petted(asleep: bool) -> void:
	if asleep:
		needs.change(&"affection", 8.0)
		memory.change_bond(0.5)
		_log("petted while asleep")
		return
	needs.change(&"affection", 20.0)
	needs.change(&"fun", 5.0)
	memory.change_bond(1.5)
	_log("petted")


func simulate_offline(minutes: float) -> void:
	var left := minutes
	while left > 0.0:
		var step := minf(left, 60.0)
		needs.decay(step, false)
		left -= step
	for need: StringName in needs.names():
		if needs.get_value(need) < OFFLINE_FLOOR:
			needs.values[need] = OFFLINE_FLOOR
	# It napped some of that time.
	needs.change(&"energy", minutes / 60.0 * 4.0)
	_log("you were away %.0f min" % minutes)


func to_dict() -> Dictionary:
	return {
		"needs": needs.to_dict(),
		"personality": personality.to_dict(),
		"memory": memory.to_dict(),
		# 64-bit values don't survive JSON numbers, so store them as strings.
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
	}


func from_dict(data: Dictionary) -> void:
	var p: Dictionary = data.get("personality", {})
	personality.from_dict(p)
	_apply_personality()
	var n: Dictionary = data.get("needs", {})
	needs.from_dict(n)
	var m: Dictionary = data.get("memory", {})
	memory.from_dict(m)
	if data.has("rng_seed"):
		rng.seed = str(data["rng_seed"]).to_int()
	if data.has("rng_state"):
		rng.state = str(data["rng_state"]).to_int()
	cooldowns.clear()
	_log("loaded")


func _apply_personality() -> void:
	var energy := personality.get_trait_value(&"energy")
	needs.decay_multipliers[&"fun"] = lerpf(0.7, 1.4, energy)
	needs.decay_multipliers[&"energy"] = lerpf(0.85, 1.2, energy)
	needs.decay_multipliers[&"affection"] = lerpf(0.7, 1.4, personality.get_trait_value(&"sociability"))
	needs.decay_multipliers[&"hunger"] = lerpf(0.9, 1.15, personality.get_trait_value(&"food_drive"))


func _start(dog: Dog, next: DogBehavior) -> void:
	current = next
	minutes_in_current = 0.0
	if current == null:
		return
	current.enter(dog)
	choice_counts[current.id] = int(choice_counts.get(current.id, 0)) + 1
	var score: float = float(planner.last_scores.get(current.id, 0.0))
	var reason := "%s, score %.2f" % [_end_reason, score]
	_log("%s -> %s (%s)" % [_last_id, current.id, reason])
	behavior_changed.emit(_last_id, current.id, reason)
	_last_id = current.id


func _end_current(dog: Dog, reason: String) -> void:
	if current == null:
		return
	current.exit(dog)
	current = null
	minutes_in_current = 0.0
	_end_reason = reason


func _tick_cooldowns(game_minutes: float) -> void:
	for id in cooldowns.keys():
		var left: float = float(cooldowns[id]) - game_minutes
		if left <= 0.0:
			cooldowns.erase(id)
		else:
			cooldowns[id] = left


func _log(text: String) -> void:
	decision_log.append("%s  %s" % [SimClock.format_short(), text])
	while decision_log.size() > MAX_LOG:
		decision_log.pop_front()

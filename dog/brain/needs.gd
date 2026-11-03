class_name DogNeeds
extends RefCounted
## Hidden need meters. Each value is satisfaction 0..100 (100 = fully met).
## Behaviors score against urgency, the inverse on a 0..1 scale.

const MAX_VALUE := 100.0
const START_VALUE := 80.0

## Points lost per game hour while awake, before personality multipliers.
const BASE_DECAY_PER_HOUR := {
	&"hunger": 6.0,
	&"thirst": 8.0,
	&"energy": 5.0,
	&"fun": 10.0,
	&"affection": 4.0,
}

## Metabolism slows while asleep. Energy is restored by the sleep behavior instead.
const SLEEP_DECAY_FACTOR := 0.4

var values: Dictionary = {}
var decay_multipliers: Dictionary = {}


func _init() -> void:
	for need: StringName in BASE_DECAY_PER_HOUR:
		values[need] = START_VALUE
		decay_multipliers[need] = 1.0


func names() -> Array:
	return BASE_DECAY_PER_HOUR.keys()


func get_value(need: StringName) -> float:
	return float(values.get(need, MAX_VALUE))


func urgency(need: StringName) -> float:
	return 1.0 - get_value(need) / MAX_VALUE


func change(need: StringName, amount: float) -> void:
	values[need] = clampf(get_value(need) + amount, 0.0, MAX_VALUE)


func decay(game_minutes: float, sleeping: bool) -> void:
	var hours := game_minutes / 60.0
	for need: StringName in BASE_DECAY_PER_HOUR:
		var rate: float = float(BASE_DECAY_PER_HOUR[need]) * float(decay_multipliers[need])
		if sleeping:
			if need == &"energy":
				continue
			rate *= SLEEP_DECAY_FACTOR
		change(need, -rate * hours)


func lowest() -> float:
	var low := MAX_VALUE
	for need: StringName in values:
		low = minf(low, get_value(need))
	return low


func average() -> float:
	var total := 0.0
	for need: StringName in values:
		total += get_value(need)
	return total / maxf(1.0, float(values.size()))


func to_dict() -> Dictionary:
	var out := {}
	for need: StringName in values:
		out[String(need)] = get_value(need)
	return out


func from_dict(data: Dictionary) -> void:
	for key in data:
		var need := StringName(str(key))
		if values.has(need):
			values[need] = clampf(float(data[key]), 0.0, MAX_VALUE)

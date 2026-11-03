extends Node
## Game time. Autoloaded as SimClock.
##
## Everything that simulates reads `last_delta_minutes` (game minutes elapsed this
## frame) instead of the engine delta, so pause and fast-forward stay consistent.

signal hour_changed(hour: int)
signal day_changed(day: int)
signal time_scale_changed(new_scale: float)

const MINUTES_PER_DAY := 1440.0
const NIGHT_START_HOUR := 21
const NIGHT_END_HOUR := 6
const START_HOUR := 7.0

## Game minutes per real second at time_scale 1.0.
## 1.0 = one game day per 24 real minutes. Open design question; tune here.
var minutes_per_real_second := 1.0

var time_scale := 1.0:
	set(value):
		time_scale = maxf(value, 0.0)
		time_scale_changed.emit(time_scale)

var paused := false

## Game minutes since Day 1, 00:00.
var total_minutes := START_HOUR * 60.0

## Game minutes that elapsed this frame (0 while paused).
var last_delta_minutes := 0.0


func _process(delta: float) -> void:
	if paused:
		last_delta_minutes = 0.0
		return
	last_delta_minutes = delta * minutes_per_real_second * time_scale
	advance(last_delta_minutes)


## Moves time forward, emitting hour/day signals when they roll over.
func advance(minutes: float) -> void:
	var old_hour := get_hour()
	var old_day := get_day()
	total_minutes += minutes
	var new_day := get_day()
	if new_day != old_day:
		day_changed.emit(new_day)
	if get_hour() != old_hour or new_day != old_day:
		hour_changed.emit(get_hour())


func get_day() -> int:
	return int(total_minutes / MINUTES_PER_DAY) + 1


func get_minute_of_day() -> float:
	return fmod(total_minutes, MINUTES_PER_DAY)


func get_hour() -> int:
	return int(get_minute_of_day() / 60.0)


## 0.0 at midnight, 0.5 at noon.
func get_day_fraction() -> float:
	return get_minute_of_day() / MINUTES_PER_DAY


func is_night() -> bool:
	var h := get_hour()
	return h >= NIGHT_START_HOUR or h < NIGHT_END_HOUR


func format_time() -> String:
	var m := int(get_minute_of_day())
	return "Day %d  %02d:%02d" % [get_day(), int(m / 60.0), m % 60]


## Compact form for logs: "D2 07:42".
func format_short() -> String:
	var m := int(get_minute_of_day())
	return "D%d %02d:%02d" % [get_day(), int(m / 60.0), m % 60]


func to_dict() -> Dictionary:
	return {"total_minutes": total_minutes}


func from_dict(data: Dictionary) -> void:
	total_minutes = float(data.get("total_minutes", total_minutes))

class_name DogTouchPrefs
extends RefCounted
## How much this dog likes being touched on each zone, -1 (hates) .. +1 (loves).
##
## Rolled once per puppy from personality plus jitter, so two corgis differ.
## Hidden from the player, who learns it from the dog's reactions; the debug
## overlay shows the true values.

const ZONES := [&"head", &"ears", &"back", &"belly"]

## At or above: the dog likes it. At or below DISLIKE_AT: it ducks away.
const LIKE_AT := 0.25
const DISLIKE_AT := -0.25
const JITTER := 0.5
## Cozy guarantee: the favorite zone is always at least this liked.
const MIN_FAVORITE := 0.45
## Below this bond every zone reads lower, by up to LOW_BOND_PENALTY at bond 0.
const TRUST_BOND := 30.0
const LOW_BOND_PENALTY := 0.2

## Zone id -> raw preference.
var values: Dictionary = {}


func _init() -> void:
	for zone: StringName in ZONES:
		values[zone] = 0.0


## Sociable dogs like head and ear scritches, bold ones show their belly,
## stubborn ones guard their ears. Everyone tends to like the back.
static func roll(p: DogPersonality, rng: RandomNumberGenerator) -> DogTouchPrefs:
	var prefs := DogTouchPrefs.new()
	var social := p.sociability - 0.5
	var bold := p.boldness - 0.5
	var stubborn := p.stubbornness - 0.5
	var base := {
		&"head": 0.35 + social * 0.6,
		&"ears": 0.1 + social * 0.4 - stubborn * 0.4,
		&"back": 0.45,
		&"belly": -0.1 + bold * 1.2,
	}
	var favorite: StringName = ZONES[0]
	for zone: StringName in ZONES:
		var v: float = float(base[zone]) + rng.randf_range(-JITTER, JITTER)
		prefs.values[zone] = clampf(v, -1.0, 1.0)
		if prefs.get_raw(zone) > prefs.get_raw(favorite):
			favorite = zone
	if prefs.get_raw(favorite) < MIN_FAVORITE:
		prefs.values[favorite] = MIN_FAVORITE
	return prefs


func get_raw(zone: StringName) -> float:
	return float(values.get(zone, 0.0))


## Preference after trust: a dog that barely knows you is touchier everywhere.
func effective(zone: StringName, bond: float) -> float:
	var v := get_raw(zone)
	if bond < TRUST_BOND:
		v -= (TRUST_BOND - bond) / TRUST_BOND * LOW_BOND_PENALTY
	return clampf(v, -1.0, 1.0)


## &"likes", &"neutral" or &"dislikes".
static func reaction_for(pref: float) -> StringName:
	if pref >= LIKE_AT:
		return &"likes"
	if pref <= DISLIKE_AT:
		return &"dislikes"
	return &"neutral"


func to_dict() -> Dictionary:
	var out := {}
	for zone: StringName in ZONES:
		out[String(zone)] = get_raw(zone)
	return out


func from_dict(data: Dictionary) -> void:
	for zone: StringName in ZONES:
		var key := String(zone)
		if data.has(key):
			values[zone] = clampf(float(data[key]), -1.0, 1.0)

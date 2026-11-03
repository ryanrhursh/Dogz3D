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
const GreetBehavior := preload("res://dog/brain/behaviors/greet.gd")
const PlayTogetherBehavior := preload("res://dog/brain/behaviors/play_together.gd")
const WaitTurnBehavior := preload("res://dog/brain/behaviors/wait_turn.gd")
const EnjoyPetsBehavior := preload("res://dog/brain/behaviors/enjoy_pets.gd")
const DuckAwayBehavior := preload("res://dog/brain/behaviors/duck_away.gd")

## Affinity and affection a dog gains when another dog greets it nicely.
const GREETED_AFFINITY := 0.05
const GREETED_AFFECTION := 1.0
## Other dogs only top affection up to here: they can't replace the player.
const SOCIAL_AFFECTION_CAP := 60.0
## Affinity lost toward a dog that pestered this one while it was grumpy.
const BOTHERED_AFFINITY := -0.04

## Touch effects per stroke (a pat is one stroke), scaled by the effective preference.
## Liked: affection BASE + PER_PREF * pref, bond BASE + PER_PREF * pref.
const LIKED_AFFECTION := 2.0
const LIKED_AFFECTION_PER_PREF := 4.0
const LIKED_BOND := 0.05
const LIKED_BOND_PER_PREF := 0.15
const NEUTRAL_AFFECTION := 1.0
## Asleep and liked: it stays asleep and only soaks up a little affection.
const ASLEEP_LIKED_AFFECTION := 1.0
## Disliked: affection and bond drop, bond more the more it's disliked.
const DISLIKED_AFFECTION := 1.0
const DISLIKED_BOND := 0.1
const DISLIKED_BOND_PER_PREF := 0.2
## A new touch of the same zone and reaction within this many game minutes extends the
## last log line instead of adding one, so a long stroke doesn't flood the log.
const TOUCH_LOG_GAP := 1.0

var needs := DogNeeds.new()
var personality := DogPersonality.new()
var touch_prefs := DogTouchPrefs.new()
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
## Recent player stimuli, kind (&"touch") -> Dictionary with at least "at" (SimClock
## game minutes) and "new" (not yet reacted to). Touch adds zone, reaction, pref,
## strokes, point, asleep. Not saved.
var stimuli: Dictionary = {}

var _since_eval := 0.0
var _last_id: StringName = &"none"
var _end_reason := "start"
## Set by player input (on_touched); the next tick re-evaluates right away.
var _force_eval := false


## p_touch_prefs is normally rolled by the Dog alongside the personality. If null,
## it's rolled from a separate RNG so the decision RNG sequence is unaffected.
func setup(p_personality: DogPersonality, seed_value: int,
		p_touch_prefs: DogTouchPrefs = null) -> void:
	personality = p_personality
	touch_prefs = p_touch_prefs
	if touch_prefs == null:
		touch_prefs = _roll_touch_prefs(seed_value)
	needs = DogNeeds.new()
	memory = DogMemory.new()
	rng.seed = seed_value
	current = null
	minutes_in_current = 0.0
	cooldowns.clear()
	decision_log.clear()
	choice_counts.clear()
	stimuli.clear()
	_force_eval = false
	_last_id = &"none"
	_end_reason = "start"
	_apply_personality()

	var list: Array[DogBehavior] = [
		WanderBehavior.new(),
		ConsumeBehavior.new(&"eat", "Eat", &"hunger", &"food", &"food_drive", &"eat"),
		ConsumeBehavior.new(&"drink", "Drink", &"thirst", &"water", &"", &"eat"),
		SleepBehavior.new(),
		IdleBehavior.new(),
		# Pack behaviors go last and score 0 with no other dog around, so a lone dog
		# decides exactly as it did before they existed.
		GreetBehavior.new(),
		PlayTogetherBehavior.new(),
		WaitTurnBehavior.new(),
		# Hand behaviors score 0 until the player's hand does something.
		EnjoyPetsBehavior.new(),
		DuckAwayBehavior.new(),
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
	# Player input reacts now: no min_duration and no budget slot. The planner still only
	# lets an emergency score interrupt a non-interruptible behavior.
	var forced := _force_eval
	_force_eval = false
	# A dog with nothing to do always chooses now. A routine re-evaluation waits for a
	# slot in this frame's budget, so a big pack spreads its thinking over frames.
	if current == null or forced or (due and may_switch and dog.take_eval_slot()):
		_since_eval = 0.0
		if forced:
			_stamp_new_stimuli()
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


## Debug stand-in for the hand tool (milestone 3). Kept as the E-key fallback.
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


## The player's hand touched `zone` (`strokes` strokes; a pat is 1). Applies the touch
## effects, records the stimulus and re-evaluates next tick. Returns the reaction
## (&"likes", &"neutral", &"dislikes") for the body's emote.
func on_touched(zone: StringName, strokes: int, asleep: bool, point: Vector3) -> StringName:
	var n := float(maxi(strokes, 1))
	var pref := touch_prefs.effective(zone, memory.bond)
	var reaction := DogTouchPrefs.reaction_for(pref)
	match reaction:
		&"likes":
			if asleep:
				needs.change(&"affection", ASLEEP_LIKED_AFFECTION * n)
			else:
				needs.change(&"affection", (LIKED_AFFECTION + LIKED_AFFECTION_PER_PREF * pref) * n)
				memory.change_bond((LIKED_BOND + LIKED_BOND_PER_PREF * pref) * n)
		&"dislikes":
			needs.change(&"affection", -DISLIKED_AFFECTION * n)
			memory.change_bond(-(DISLIKED_BOND + DISLIKED_BOND_PER_PREF * -pref) * n)
		_:
			needs.change(&"affection", NEUTRAL_AFFECTION * n)

	var now := SimClock.total_minutes
	var last: Dictionary = stimuli.get(&"touch", {})
	var total := int(n)
	if not last.is_empty() and last["zone"] == zone and last["reaction"] == reaction \
			and now - float(last["at"]) < TOUCH_LOG_GAP:
		total += int(last["strokes"])
	else:
		var what := "touched %s" % zone
		if asleep:
			what += " while asleep"
		_log("%s: %s" % [what, reaction])
	stimuli[&"touch"] = {
		"at": now,
		"zone": zone,
		"reaction": reaction,
		"pref": pref,
		"strokes": total,
		"point": point,
		"asleep": asleep,
		"new": true,
	}
	_force_eval = true
	return reaction


## The stimulus of `kind` (see stimuli), or an empty Dictionary.
func get_stimulus(kind: StringName) -> Dictionary:
	return stimuli.get(kind, {})


## Game minutes since the last stimulus of `kind`, INF if none.
func stimulus_age(kind: StringName) -> float:
	var s: Dictionary = stimuli.get(kind, {})
	if s.is_empty():
		return INF
	return SimClock.total_minutes - float(s["at"])


## Affection from other dogs: fills the need only up to SOCIAL_AFFECTION_CAP.
func add_social_affection(amount: float) -> void:
	var room := SOCIAL_AFFECTION_CAP - needs.get_value(&"affection")
	if room > 0.0:
		needs.change(&"affection", minf(amount, room))


## Another dog did something social to this one (reported by the Dog body).
func on_social(from_id: String, from_name: String, kind: StringName) -> void:
	match kind:
		&"greeted":
			memory.change_affinity(from_id, GREETED_AFFINITY)
			add_social_affection(GREETED_AFFECTION)
			_log("greeted by %s" % from_name)
		&"bothered":
			memory.change_affinity(from_id, BOTHERED_AFFINITY)
			_log("bothered by %s" % from_name)
		_:
			pass


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
		"touch_prefs": touch_prefs.to_dict(),
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
	if data.has("touch_prefs"):
		var t: Dictionary = data["touch_prefs"]
		touch_prefs = DogTouchPrefs.new()
		touch_prefs.from_dict(t)
	else:
		# Save v1 predates touch zones: roll them from the saved personality.
		touch_prefs = _roll_touch_prefs(int(rng.seed))
	cooldowns.clear()
	stimuli.clear()
	_force_eval = false
	_log("loaded")


func _apply_personality() -> void:
	var energy := personality.get_trait_value(&"energy")
	needs.decay_multipliers[&"fun"] = lerpf(0.7, 1.4, energy)
	needs.decay_multipliers[&"energy"] = lerpf(0.85, 1.2, energy)
	needs.decay_multipliers[&"affection"] = lerpf(0.7, 1.4, personality.get_trait_value(&"sociability"))
	needs.decay_multipliers[&"hunger"] = lerpf(0.9, 1.15, personality.get_trait_value(&"food_drive"))


func _roll_touch_prefs(seed_value: int) -> DogTouchPrefs:
	var prefs_rng := RandomNumberGenerator.new()
	prefs_rng.seed = hash([seed_value, "touch_prefs"])
	return DogTouchPrefs.roll(personality, prefs_rng)


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


## A stimulus counts from when the brain first reacts to it, so at 60x speed (a game
## minute per frame) it isn't already stale by the tick after the touch.
func _stamp_new_stimuli() -> void:
	for kind: StringName in stimuli:
		var s: Dictionary = stimuli[kind]
		if bool(s.get("new", false)):
			s["at"] = SimClock.total_minutes
			s["new"] = false


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

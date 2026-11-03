extends DogBehavior
## Chase with another dog. One dog invites a friend it has met; the friend accepts by
## picking this behavior too (it sees the invitation through its body). The chaser runs
## at its partner; on a tag the roles swap. It lasts while both dogs keep playing with
## each other. Feeds fun, costs energy, builds affinity.
##
## Scores 0 with no other dog near and no invitation, so a lone dog never picks it.

const RANGE := 7.0
## Energy needed to start; play stops below STOP_ENERGY.
const MIN_ENERGY := 40.0
const STOP_ENERGY := 25.0
const ACCEPT_MIN_ENERGY := 32.0
## Game minutes the inviter waits for the partner to join.
const JOIN_WAIT := 5.0
const DURATION_MIN := 6.0
const DURATION_MAX := 12.0
const TAG_DISTANCE := 0.8
const TAG_COOLDOWN := 1.0
const RETARGET_MINUTES := 0.5
const WAIT_RADIUS := 1.0
const CHASE_RADIUS := 0.5
const FUN_PER_MINUTE := 3.0
const ENERGY_PER_MINUTE := 0.35
const AFFINITY_PER_MINUTE := 0.008
## Game minutes after a game before starting another.
const GAP_MINUTES := 60.0
## Lowest affinity (either way) to start or accept a game.
const MIN_AFFINITY := 0.0
const ACCEPT_MIN_AFFINITY := -0.2
const CONTINUE_SCORE := 0.55

var _candidate := ""
var _invited := false
var _partner := ""
var _joined := false
var _chasing := false
var _elapsed := 0.0
var _played := 0.0
var _duration := 0.0
var _tag_cooldown := 0.0
var _retarget := 0.0
var _last_done := -INF


func _init() -> void:
	id = &"play_together"
	label = "Play"
	min_duration = 3.0
	cooldown_on_fail = 30.0


func score(dog: Dog) -> float:
	var needs := dog.brain.needs
	var energy := needs.get_value(&"energy")
	if dog.brain.current == self:
		if energy < STOP_ENERGY:
			return 0.0
		return CONTINUE_SCORE
	var memory := dog.brain.memory
	var me := dog.dog_id

	# Accept an invitation from a dog that is waiting for us (no gap: it's polite).
	var inviter := dog.get_invite(&"play")
	if inviter != "" and energy >= ACCEPT_MIN_ENERGY:
		var info := dog.get_dog_info(inviter)
		if not info.is_empty() and info["doing"] == &"play_together" and str(info["partner"]) == me \
				and memory.get_affinity(inviter) >= ACCEPT_MIN_AFFINITY:
			_candidate = inviter
			_invited = true
			var s := 0.45 + needs.urgency(&"fun") * 0.3 + memory.get_affinity(inviter) * 0.2
			return clampf(s * trait_mod(dog, &"energy", 0.85, 1.2), 0.0, 0.85)

	if SimClock.total_minutes - _last_done < GAP_MINUTES or energy < MIN_ENERGY:
		return 0.0
	# Start a game with a dog we've met and like, that is free to play.
	_candidate = dog.find_nearest_dog(RANGE, func(info: Dictionary) -> bool:
		var doing: StringName = info["doing"]
		var other := str(info["id"])
		return not bool(info["sleeping"]) \
				and (doing == &"idle" or doing == &"wander" or doing == &"") \
				and memory.knows(other) and memory.get_affinity(other) >= MIN_AFFINITY \
				and float(info["affinity_to_me"]) >= ACCEPT_MIN_AFFINITY)
	if _candidate == "":
		return 0.0
	_invited = false
	var energy_gate := clampf((energy - MIN_ENERGY) / 30.0, 0.0, 1.0)
	var s := (0.1 + needs.urgency(&"fun") * 0.7) * energy_gate \
			* trait_mod(dog, &"energy", 0.7, 1.3) * trait_mod(dog, &"sociability", 0.8, 1.2) \
			* (0.8 + memory.get_affinity(_candidate) * 0.6)
	return clampf(s, 0.0, 0.8)


func enter(dog: Dog) -> void:
	_partner = _candidate
	_elapsed = 0.0
	_played = 0.0
	_tag_cooldown = 0.0
	_retarget = 0.0
	_duration = dog.brain.rng.randf_range(DURATION_MIN, DURATION_MAX)
	dog.set_social_partner(_partner)
	dog.set_gait(&"run")
	if _invited:
		dog.clear_invite(&"play")
		_joined = true
		_chasing = false
		dog.show_emote("!", 1.0)
	else:
		dog.invite_dog(_partner, &"play")
		_joined = false
		_chasing = true
		dog.show_emote("play?", 1.5)


func tick(dog: Dog, game_minutes: float) -> int:
	_elapsed += game_minutes
	var info := dog.get_dog_info(_partner)
	if info.is_empty():
		return SUCCEEDED if _joined else FAILED
	var partner_playing: bool = info["doing"] == &"play_together" \
			and str(info["partner"]) == dog.dog_id
	if not _joined:
		if partner_playing:
			_joined = true
		elif _elapsed > JOIN_WAIT or bool(info["sleeping"]):
			return FAILED
	elif not partner_playing:
		return SUCCEEDED

	var brain := dog.brain
	if _joined:
		_played += game_minutes
		brain.needs.change(&"fun", FUN_PER_MINUTE * game_minutes)
		brain.needs.change(&"energy", -ENERGY_PER_MINUTE * game_minutes)
		brain.memory.change_affinity(_partner, AFFINITY_PER_MINUTE * game_minutes)
		if brain.needs.get_value(&"energy") < STOP_ENERGY or _played >= _duration:
			return SUCCEEDED

	var where: Vector3 = info["position"]
	var distance: float = info["distance"]
	_tag_cooldown -= game_minutes
	if _joined and distance <= TAG_DISTANCE and _tag_cooldown <= 0.0:
		_chasing = not _chasing
		_tag_cooldown = TAG_COOLDOWN
		dog.stop_moving()

	_retarget -= game_minutes
	if _chasing or not _joined:
		if _retarget <= 0.0 or not dog.is_moving():
			_retarget = RETARGET_MINUTES
			var radius := CHASE_RADIUS
			if not _joined:
				radius = WAIT_RADIUS
			if distance > radius:
				dog.go_to(where, radius)
			else:
				dog.face_point(where)
	elif not dog.is_moving():
		dog.go_to(dog.random_point_near(dog.global_position, 1.5, 3.5))
	return RUNNING


func exit(dog: Dog) -> void:
	dog.stop_moving()
	dog.set_gait(&"walk")
	dog.set_pose(&"stand")
	dog.set_social_partner("")
	_last_done = SimClock.total_minutes
	_partner = ""
	_joined = false

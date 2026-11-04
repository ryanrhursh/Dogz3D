extends DogBehavior
## Play with the ball. A bored dog with energy goes after a ball lying around on its own
## (toy_drive makes it keener); a ball the player just threw is far more exciting. The dog
## runs to the ball (re-pathing while it rolls), grabs it, trots about with it in its
## mouth, then drops it with a little toss. Several dogs may race for a thrown ball: near
## it, a dog lets a nearer chaser (or, at the same distance, the smaller dog_id) have it
## and waits, watching. Fails with a cooldown if the ball can't be reached.
##
## States: CHASE -> PLAY (carry) -> DROP, WATCH while another dog is nearer, and RETURN,
## a stub for milestone 5 fetch (bring the ball back to the player).
##
## Scores 0 with no reachable ball lying about, and before any scan when the dog is too
## tired, not bored enough or played recently and there's no fresh throw.

enum State { CHASE, WATCH, PLAY, RETURN, DROP }

## Below this fun urgency a ball lying about doesn't tempt the dog (a throw always does).
const MIN_FUN_URGENCY := 0.05
const BASE := 0.08
const FUN_WEIGHT := 0.6
## Added for a throw younger than THROW_WINDOW game minutes (re-stamped when the brain
## first reacts, so it works at any speed).
const THROW_BONUS := 0.45
const THROW_WINDOW := 2.0
const MAX_SCORE := 0.85
const CONTINUE_SCORE := 0.5
## Energy gate: no play at START_ENERGY, full desire 30 points above it. Stops below
## STOP_ENERGY.
const START_ENERGY := 25.0
const STOP_ENERGY := 20.0
## Game minutes after a game before it starts one on its own again.
const GAP_MINUTES := 60.0
## It takes the ball (once it's down within reach) when its mouth gets this close (flat
## metres), or when it has stopped with the ball within GRAB_DISTANCE of its body.
const MOUTH_GRAB := 0.3
const GRAB_DISTANCE := 0.8
const ARRIVE_RADIUS := 0.2
## Re-path when the ball has rolled this far from where the dog was heading.
const REPATH_DISTANCE := 0.3
const MAX_CHASE_MINUTES := 6.0
## A ball faster than this (m/s) is still flying or rolling: don't judge its reach yet.
const MOVING_SPEED := 0.3
## Within this of the ball, another chaser nearer to it makes this dog wait and watch.
const RIVAL_RANGE := 1.4
## Same distance, within this: the smaller dog_id goes.
const RIVAL_TIE := 0.05
const PLAY_LEGS_MIN := 1
const PLAY_LEGS_MAX := 3
const PLAY_MIN_DISTANCE := 1.0
const PLAY_MAX_DISTANCE := 3.0
const MAX_PLAY_MINUTES := 8.0
## The drop: forward and upward speed (m/s), a little toss.
const DROP_TOSS := 1.0
const DROP_LIFT := 0.6
const FUN_PER_MINUTE := 1.5
const ENERGY_PER_MINUTE := 0.3

## Milestone 5 fetch sets this: after PLAY the dog brings the ball back instead.
var fetch := false

var _state: State = State.CHASE
var _ball: WorldItem
var _thrown := false
var _claimed := false
var _aim := Vector3.ZERO
var _elapsed := 0.0
var _play_elapsed := 0.0
var _legs := 0
var _last_done := -INF
## Stimulus time of the throw this dog last went after; one throw, one chase.
var _throw_used_at := -INF
## Reachability of a resting ball, re-checked only when it moves.
var _reach_at := Vector3.INF
var _reach_ok := false


func _init() -> void:
	id = &"chase_toy"
	label = "Play ball"
	min_duration = 1.0
	cooldown_on_fail = 20.0


func score(dog: Dog) -> float:
	var brain := dog.brain
	if dog.sleeping:
		return 0.0
	var energy := brain.needs.get_value(&"energy")
	if brain.current == self:
		return 0.0 if energy < STOP_ENERGY else CONTINUE_SCORE
	var gate := clampf((energy - START_ENERGY) / 30.0, 0.0, 1.0)
	if gate <= 0.0:
		return 0.0
	var thrown := not brain.stimuli.is_empty() and _fresh_throw(brain)
	var fun_urgency := brain.needs.urgency(&"fun")
	if not thrown and (fun_urgency < MIN_FUN_URGENCY \
			or SimClock.total_minutes - _last_done < GAP_MINUTES):
		return 0.0
	var ball := dog.find_nearest_item(&"toy", thrown)
	if ball == null or (not thrown and not _reachable(dog, ball)):
		return 0.0
	var s := (BASE + fun_urgency * FUN_WEIGHT) * trait_mod(dog, &"toy_drive", 0.6, 1.3) * gate
	if thrown:
		s += THROW_BONUS * trait_mod(dog, &"toy_drive", 0.8, 1.2) * gate
	return clampf(s, 0.0, MAX_SCORE)


func enter(dog: Dog) -> void:
	_state = State.CHASE
	_elapsed = 0.0
	_claimed = false
	_thrown = _fresh_throw(dog.brain)
	if _thrown:
		_throw_used_at = float(dog.brain.get_stimulus(&"ball_thrown")["at"])
	_ball = dog.find_nearest_item(&"toy", _thrown)
	# A ball lying about is one dog's game; a thrown one is a race.
	if _ball != null and not _thrown:
		_claimed = dog.claim_item(_ball)
		if not _claimed:
			_ball = null
	dog.set_gait(&"run")
	if _ball != null:
		if _thrown:
			dog.show_emote("!", 1.0)
		_head_for(dog)


func tick(dog: Dog, game_minutes: float) -> int:
	_elapsed += game_minutes
	dog.brain.needs.change(&"fun", FUN_PER_MINUTE * game_minutes)
	dog.brain.needs.change(&"energy", -ENERGY_PER_MINUTE * game_minutes)
	if _ball == null or not is_instance_valid(_ball):
		return FAILED
	match _state:
		State.CHASE:
			return _tick_chase(dog)
		State.WATCH:
			return _tick_watch(dog)
		State.PLAY:
			return _tick_play(dog, game_minutes)
		State.RETURN:
			# Milestone 5 fetch: carry the ball back to the player. Not built yet.
			_state = State.DROP
			return RUNNING
		_:
			return _drop(dog)


func exit(dog: Dog) -> void:
	dog.stop_moving()
	dog.set_gait(&"walk")
	dog.set_pose(&"stand")
	if _ball != null and is_instance_valid(_ball):
		if dog.held_item == _ball:
			dog.drop_held()
		if _claimed:
			dog.release_item(_ball)
	_claimed = false
	_ball = null
	_last_done = SimClock.total_minutes


func _tick_chase(dog: Dog) -> int:
	# Another dog or the hand got it first.
	if _ball.held:
		return SUCCEEDED
	if _elapsed > MAX_CHASE_MINUTES:
		return FAILED
	var at := _ball.global_position
	# In the air or rolling it may still land somewhere reachable.
	if not _ball_moving() and not _reachable(dog, _ball):
		return FAILED
	var gap := _flat(dog.global_position, at)
	var low := at.y <= Dog.MAX_REACH_HEIGHT
	if low and (_flat(dog.get_mouth_position(), at) <= MOUTH_GRAB \
			or (not dog.is_moving() and gap <= GRAB_DISTANCE)):
		dog.stop_moving()
		if dog.pick_up(_ball):
			_start_play(dog)
			return RUNNING
	if _rival_nearer(dog, at):
		_state = State.WATCH
		dog.stop_moving()
		dog.face_point(at)
		return RUNNING
	if not dog.is_moving():
		if dog.is_stuck():
			return FAILED
		_head_for(dog)
	elif _flat(at, _aim) > REPATH_DISTANCE:
		_head_for(dog)
	return RUNNING


func _tick_watch(dog: Dog) -> int:
	if _ball.held or _elapsed > MAX_CHASE_MINUTES:
		return SUCCEEDED
	var at := _ball.global_position
	dog.face_point(at)
	if not _rival_nearer(dog, at):
		_state = State.CHASE
		_head_for(dog)
	return RUNNING


func _tick_play(dog: Dog, game_minutes: float) -> int:
	# The hand took it out of its mouth.
	if dog.held_item != _ball:
		return SUCCEEDED
	_play_elapsed += game_minutes
	if _play_elapsed < MAX_PLAY_MINUTES:
		if dog.is_moving():
			return RUNNING
		if _legs > 0:
			_next_leg(dog)
			return RUNNING
	dog.stop_moving()
	_state = State.RETURN if fetch else State.DROP
	return RUNNING


func _drop(dog: Dog) -> int:
	var forward := dog.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	dog.drop_held(forward * DROP_TOSS + Vector3.UP * DROP_LIFT)
	return SUCCEEDED


func _start_play(dog: Dog) -> void:
	_state = State.PLAY
	_play_elapsed = 0.0
	_legs = dog.brain.rng.randi_range(PLAY_LEGS_MIN, PLAY_LEGS_MAX)
	dog.set_gait(&"walk")
	dog.show_emote("got it!", 1.2)
	_next_leg(dog)


func _next_leg(dog: Dog) -> void:
	_legs -= 1
	dog.go_to(dog.random_point_near(dog.global_position, PLAY_MIN_DISTANCE, PLAY_MAX_DISTANCE))


func _head_for(dog: Dog) -> void:
	_aim = _ball.global_position
	dog.go_to(_ball.get_approach_point(dog.global_position), ARRIVE_RADIUS)


## True if another dog chasing the ball is nearer to it than this one, once this one is
## within RIVAL_RANGE (a tie goes to the smaller dog_id).
func _rival_nearer(dog: Dog, at: Vector3) -> bool:
	var mine := _flat(dog.global_position, at)
	if mine > RIVAL_RANGE:
		return false
	for other_id in dog.dogs_near(mine + RIVAL_RANGE):
		var info := dog.get_dog_info(other_id)
		if info.get("doing") != id:
			continue
		var theirs := _flat(info["position"], at)
		if theirs < mine - RIVAL_TIE or (theirs <= mine + RIVAL_TIE and other_id < dog.dog_id):
			return true
	return false


## True for a throw younger than THROW_WINDOW that this dog hasn't chased yet.
func _fresh_throw(brain: DogBrain) -> bool:
	var throw := brain.get_stimulus(&"ball_thrown")
	return not throw.is_empty() and float(throw["at"]) > _throw_used_at \
			and brain.stimulus_age(&"ball_thrown") <= THROW_WINDOW


func _ball_moving() -> bool:
	var body := _ball.physics_body
	return body != null and not body.freeze and body.linear_velocity.length() > MOVING_SPEED


func _reachable(dog: Dog, ball: WorldItem) -> bool:
	var at := ball.global_position
	if not _reach_at.is_finite() or at.distance_to(_reach_at) > 0.05:
		_reach_at = at
		_reach_ok = dog.can_reach(at)
	return _reach_ok


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

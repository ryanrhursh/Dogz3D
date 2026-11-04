class_name Ball
extends WorldItem
## A ball that rolls and bounces: the RigidBody3D root does the physics, this child is
## the item dogs and the hand see (affordances toy, throwable). If it ever falls out of
## the room (y below FALL_LIMIT) it comes back at respawn_point, and so it does after
## lying at rest for unreachable_return_minutes where no dog can get to it (the couch
## top, a corner).

const FALL_LIMIT := -2.0
## Slower than this (m/s) the ball counts as lying at rest.
const REST_SPEED := 0.3
## How often (game minutes) the resting ball checks whether a dog could reach it.
const REACH_CHECK_MINUTES := 1.0

## Where the ball comes back if it falls out of the world. Defaults to where it starts.
@export var respawn_point := Vector3.INF
## Game minutes at rest out of every dog's reach before the ball comes back to
## respawn_point. INF turns it off.
@export var unreachable_return_minutes := 30.0

## Game minutes the ball has lain at rest out of reach (whole checks).
var unreachable_minutes := 0.0
var _since_check := 0.0


func _ready() -> void:
	super._ready()
	if not respawn_point.is_finite():
		respawn_point = get_root().global_position


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not held and get_root().global_position.y < FALL_LIMIT:
		respawn()


func _process(_delta: float) -> void:
	advance_minutes(SimClock.last_delta_minutes)


## Counts game minutes at rest out of reach, and brings the ball back once there are
## enough. Called every frame with the frame's game minutes.
func advance_minutes(game_minutes: float) -> void:
	if held:
		unreachable_minutes = 0.0
		_since_check = 0.0
		return
	_since_check += game_minutes
	if _since_check < REACH_CHECK_MINUTES:
		return
	var minutes := _since_check
	_since_check = 0.0
	if is_at_rest() and not is_reachable():
		unreachable_minutes += minutes
	else:
		unreachable_minutes = 0.0
	if unreachable_minutes >= unreachable_return_minutes \
			and get_root().global_position.distance_to(respawn_point) > 0.3:
		respawn()


func is_at_rest() -> bool:
	return physics_body == null or physics_body.linear_velocity.length() < REST_SPEED


## Whether a dog could get its mouth to the ball where it is, by the same rule as
## Dog.can_reach.
func is_reachable() -> bool:
	var at := get_root().global_position
	if at.y > Dog.MAX_REACH_HEIGHT:
		return false
	var map_rid := get_world_3d().navigation_map
	var on_mesh := NavigationServer3D.map_get_closest_point(map_rid, at)
	return Vector2(on_mesh.x - at.x, on_mesh.z - at.z).length() <= Dog.REACH_SLACK


## Puts the ball back at respawn_point, at rest.
func respawn() -> void:
	if held:
		detach(Vector3.ZERO)
	unreachable_minutes = 0.0
	_since_check = 0.0
	var body := get_root()
	body.global_position = respawn_point
	if physics_body != null:
		physics_body.linear_velocity = Vector3.ZERO
		physics_body.angular_velocity = Vector3.ZERO
		physics_body.sleeping = false

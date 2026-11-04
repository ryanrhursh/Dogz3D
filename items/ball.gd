class_name Ball
extends WorldItem
## A ball that rolls and bounces: the RigidBody3D root does the physics, this child is
## the item dogs and the hand see (affordances toy, throwable). If it ever falls out of
## the room (y below FALL_LIMIT) it comes back at respawn_point.

const FALL_LIMIT := -2.0

## Where the ball comes back if it falls out of the world. Defaults to where it starts.
@export var respawn_point := Vector3.INF


func _ready() -> void:
	super._ready()
	if not respawn_point.is_finite():
		respawn_point = get_root().global_position


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not held and get_root().global_position.y < FALL_LIMIT:
		respawn()


## Puts the ball back at respawn_point, at rest.
func respawn() -> void:
	if held:
		detach(Vector3.ZERO)
	var body := get_root()
	body.global_position = respawn_point
	if physics_body != null:
		physics_body.linear_velocity = Vector3.ZERO
		physics_body.angular_velocity = Vector3.ZERO
		physics_body.sleeping = false

extends TestSuite
## Milestone 4 Estate step 2: the outdoor plot (yard round the house, doorway, fence,
## gate), one navmesh over house and yard.

const TEST_SPEED := 4.0
const INSIDE := Vector3(0.0, 0.05, 1.0)
const YARD_SOUTH := Vector3(2.0, 0.05, 7.0)
const YARD_EAST := Vector3(8.0, 0.05, -2.0)
const DOORWAY := Vector3(-1.6, 0.05, 4.1)


func _map() -> RID:
	return dog.get_world_3d().navigation_map


func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(_map(), from, to, true)


func test_yard_is_walkable() -> void:
	for point: Vector3 in [YARD_SOUTH, YARD_EAST, Vector3(10.0, 0.05, 9.0)]:
		check(dog.can_reach(point), "the yard is reachable at %s" % point)
	check(dog.can_reach(DOORWAY), "the doorway is open")
	check(not dog.can_reach(Vector3(2.0, 0.05, 4.1), 0.3), "the south wall still stands east of the doorway")
	check(not dog.can_reach(Vector3(-4.0, 0.05, 4.1), 0.3), "and west of it")
	for point: Vector3 in [Vector3(2.0, 0.05, 11.0), Vector3(12.0, 0.05, 2.0), Vector3(-7.0, 0.05, 7.0)]:
		check(not dog.can_reach(point), "beyond the fence is out of reach (%s)" % point)


func test_path_goes_through_doorway() -> void:
	var path := _path(INSIDE, YARD_SOUTH)
	check(path.size() >= 2, "there is a path from the house to the yard")
	if path.size() < 2:
		return
	check(path[path.size() - 1].distance_to(YARD_SOUTH) < 0.3, "it ends at the yard point")
	var through_door := false
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if (a.z - 4.1) * (b.z - 4.1) <= 0.0 and absf(b.z - a.z) > 0.0001:
			var t := (4.1 - a.z) / (b.z - a.z)
			var x := lerpf(a.x, b.x, t)
			through_door = x > -2.35 and x < -0.85
	check(through_door, "it crosses the south wall line in the doorway")
	var east := _path(INSIDE, YARD_EAST)
	check(east.size() >= 2 and east[east.size() - 1].distance_to(YARD_EAST) < 0.3,
			"the east yard is reached round the house")


func test_fence_and_gate_hold() -> void:
	var outside := Vector3(2.0, 0.05, 11.0)
	var path := _path(YARD_SOUTH, outside)
	check(path.size() == 0 or path[path.size() - 1].z < 9.75, "no path leads out through the gate or fence")
	var gate := main.get_node_or_null("Home/Gate") as StaticBody3D
	check(gate != null and gate.collision_layer & 1 != 0, "the gate is a closed, solid part of the fence")


func test_dog_walks_outside() -> void:
	SimClock.paused = true
	dog.brain.interrupt(dog)
	dog.global_position = INSIDE
	# The brain is off (Dog._process ticks it); physics alone walks the dog.
	dog.set_process(false)
	dog.go_to(YARD_SOUTH)
	SimClock.time_scale = TEST_SPEED
	SimClock.paused = false
	var reached := false
	for i in 600:
		await tree.process_frame
		if Vector2(dog.global_position.x - YARD_SOUTH.x, dog.global_position.z - YARD_SOUTH.z).length() < 0.5:
			reached = true
			break
	dog.set_process(true)
	check(reached, "a dog walks from the house out into the yard (at %s)" % dog.global_position)
	check(not dog.is_stuck(), "without getting stuck")

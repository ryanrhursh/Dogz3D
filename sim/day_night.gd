extends DirectionalLight3D
## Drives the sun, ambient light and the indoor lamp from SimClock.

@export var world_environment: WorldEnvironment
@export var lamp: Light3D
@export var noon_energy := 1.2
@export var lamp_energy := 1.8
@export var day_color := Color(1.0, 0.96, 0.9)
@export var dusk_color := Color(1.0, 0.58, 0.32)


func _process(_delta: float) -> void:
	var t := SimClock.get_day_fraction()
	# -1 at midnight, 0 at 06:00 / 18:00, +1 at noon.
	var elevation := sin((t - 0.25) * TAU)
	var daylight := smoothstep(-0.05, 0.35, elevation)

	var pitch := -deg_to_rad(maxf(elevation, 0.08) * 65.0 + 6.0)
	var yaw := deg_to_rad(lerpf(-100.0, 100.0, clampf((t - 0.25) * 2.0, 0.0, 1.0)))
	rotation = Vector3(pitch, yaw, 0.0)

	light_energy = noon_energy * daylight
	light_color = dusk_color.lerp(day_color, smoothstep(0.0, 0.5, elevation))
	shadow_enabled = daylight > 0.05

	if world_environment != null and world_environment.environment != null:
		var env := world_environment.environment
		env.ambient_light_energy = lerpf(0.15, 0.6, daylight)
		env.background_energy_multiplier = lerpf(0.06, 1.0, daylight)

	if lamp != null:
		lamp.light_energy = lamp_energy * (1.0 - smoothstep(-0.05, 0.25, elevation))

class_name TouchZone
extends Area3D
## One pettable region of a dog (head, ears, back, belly). The hand tool finds it
## with a camera raycast on the "touch" physics layer and calls dog.touch(zone_id).
##
## The highlight is deliberately neutral: it shows where you can touch, never whether
## the dog likes it. The player learns that from the dog's reaction.

const TOUCH_LAYER := 4  # Physics layer 3, "touch".
const HIGHLIGHT_COLOR := Color(1.0, 0.95, 0.75, 0.22)

@export var zone_id: StringName = &"back"

## Set by the owning Dog.
var dog: Dog

var _highlight: MeshInstance3D


## Builds the collision shape and its highlight mesh. Size is a box extent; a
## zero y/z means a sphere of radius size.x.
func configure(p_dog: Dog, p_zone_id: StringName, size: Vector3) -> void:
	dog = p_dog
	zone_id = p_zone_id
	name = "Touch" + String(p_zone_id).capitalize()
	collision_layer = TOUCH_LAYER
	collision_mask = 0
	monitoring = false
	input_ray_pickable = false

	var shape_node := CollisionShape3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HIGHLIGHT_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_highlight = MeshInstance3D.new()
	_highlight.material_override = mat
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false

	if size.y <= 0.0:
		var sphere := SphereShape3D.new()
		sphere.radius = size.x
		shape_node.shape = sphere
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = size.x
		sphere_mesh.height = size.x * 2.0
		_highlight.mesh = sphere_mesh
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape_node.shape = box
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		_highlight.mesh = box_mesh

	add_child(shape_node)
	add_child(_highlight)


func set_highlight(on: bool) -> void:
	if _highlight != null:
		_highlight.visible = on

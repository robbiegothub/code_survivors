extends Resource
class_name BlockNode

# One block in a weapon program. The editor (GraphEdit) will create these;
# for now they're built in code. Kept deliberately small and serializable.
@export var id: StringName = &""          # unique within a program
@export var type: StringName = &""        # which block this is, e.g. &"shoot_toward"
@export var params: Dictionary = {}       # literal values the block carries (e.g. a repeat count)
@export var position: Vector2 = Vector2.ZERO  # where the node sits in the editor

# Defaults on every arg so Godot can construct a blank node when loading a saved program.
func _init(p_id: StringName = &"", p_type: StringName = &"", p_params: Dictionary = {}, p_position: Vector2 = Vector2.ZERO) -> void:
	id = p_id
	type = p_type
	params = p_params
	position = p_position

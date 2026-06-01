extends RefCounted
class_name BlockInterpreter

# Runs a WeaponProgram each fire tick. Walks execution wires from the hat block,
# resolves each statement's data inputs on demand, and dispatches to the
# WeaponController's op_* primitives. Control-flow blocks (repeat/if) run nested
# bodies via _run_sequence. No game logic lives here -- only the wiring.

const MAX_STEPS := 2000      # total statements per tick; bounds loops/recursion so we never hang the frame
const MAX_DATA_DEPTH := 64   # guard against a pathological data graph

# Big-O compute budget: the deepest a loop may nest before the budget is exceeded.
# Set each tick from the player's complexity tier. 0 = O(1), loops don't run.
var max_loop_depth: int = 99

var _program: WeaponProgram
var _wc: WeaponController
var _steps := 0
var _data_depth := 0
var _loop_depth := 0

func _init(program: WeaponProgram, weapon_controller: WeaponController) -> void:
	_program = program
	_wc = weapon_controller

# Run the chain hanging off the hat for `event_type` (e.g. the fire tick, a kill,
# taking damage). Does nothing if the program has no hat for that event.
func run(event_type: StringName = &"on_fire_tick") -> void:
	if _program == null:
		return
	var hat := _program.find_hat(event_type)
	if hat == null:
		return
	_steps = 0
	_loop_depth = 0
	_run_sequence(_program.get_exec_target(hat.id, &"next"))

# Walk a chain of statements via their &"next" exec wires until it runs out.
# Used for the top-level program and for each control-flow body.
func _run_sequence(start: BlockNode) -> void:
	var current := start
	while current != null and _steps < MAX_STEPS:
		_steps += 1
		_run_statement(current)
		current = _program.get_exec_target(current.id, &"next")

func _run_statement(node: BlockNode) -> void:
	match node.type:
		&"shoot_toward":
			var target: Variant = _resolve_input(node, &"target")
			if target is Node2D:  # nothing wired or no enemy -> no-op
				_wc.op_shoot_at(target as Node2D)
		&"heal_self":
			_wc.op_heal_self(int(_resolve_number(node, &"amount")))
		&"boost_damage":
			_wc.op_boost_damage(_resolve_number(node, &"percent"))
		&"pierce":
			_wc.op_pierce(int(_resolve_number(node, &"times")))
		&"damage_area":
			var center: Variant = _resolve_input(node, &"center")
			if center is Vector2:
				_wc.op_damage_area(center as Vector2, _resolve_number(node, &"radius"))
		&"repeat":
			# Over the Big-O compute budget? This loop is too deeply nested to run.
			if _loop_depth >= max_loop_depth:
				return
			var times := int(_resolve_number(node, &"times"))
			var body := _program.get_exec_target(node.id, &"body")
			_loop_depth += 1
			for i in maxi(times, 0):
				if _steps >= MAX_STEPS:
					break
				_steps += 1  # count the loop iteration itself, so empty bodies still cost budget
				_run_sequence(body)
			_loop_depth -= 1
		&"if":
			if _resolve_bool(node, &"cond"):
				_run_sequence(_program.get_exec_target(node.id, &"body"))
		_:
			push_warning("BlockInterpreter: unknown statement '%s'" % node.type)

# === Data evaluation ===

# Resolve the value feeding a node's data input port, or null if nothing is wired.
func _resolve_input(node: BlockNode, input_port: StringName) -> Variant:
	var source := _program.get_data_source(node.id, input_port)
	if source.is_empty():
		return null
	return _eval_data(source["node"], source["port"])

func _eval_data(node: BlockNode, out_port: StringName) -> Variant:
	if _data_depth >= MAX_DATA_DEPTH:
		return null
	_data_depth += 1
	var result: Variant = _eval_data_inner(node, out_port)
	_data_depth -= 1
	return result

func _eval_data_inner(node: BlockNode, _out_port: StringName) -> Variant:
	match node.type:
		&"find_nearest_enemy":
			return _wc.op_find_nearest_enemy()
		&"random_enemy":
			return _wc.op_random_enemy()
		&"enemy_count":
			return _wc.op_enemy_count()
		&"player_health_percent":
			return _wc.op_player_health_percent()
		&"closest_enemy_distance":
			return _wc.op_closest_enemy_distance()
		&"player_position":
			return _wc.op_player_position()
		&"enemy_position":
			return _wc.op_enemy_position(_resolve_input(node, &"of") as Node2D)
		&"number":
			return node.params.get("value", 0)
		&"greater_than":
			return _resolve_number(node, &"a") > _resolve_number(node, &"b")
		&"less_than":
			return _resolve_number(node, &"a") < _resolve_number(node, &"b")
		_:
			push_warning("BlockInterpreter: unknown data node '%s'" % node.type)
			return null

# Typed convenience wrappers with safe defaults for unwired inputs.
func _resolve_number(node: BlockNode, port: StringName) -> float:
	var v: Variant = _resolve_input(node, port)
	return float(v) if v != null else 0.0

func _resolve_bool(node: BlockNode, port: StringName) -> bool:
	var v: Variant = _resolve_input(node, port)
	return bool(v) if v != null else false

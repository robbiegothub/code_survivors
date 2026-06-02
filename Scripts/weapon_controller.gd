extends Node
class_name WeaponController

@export var projectile_scene: PackedScene
@export var fire_interval: float = 1.0
@export var projectile_speed: float = 200.0
@export var projectile_damage: int = 13
@export var projectile_count: int = 1
@export var spread_angle_degrees: float = 15.0  # Angle between projectiles when count > 1

const AOE_RADIUS_SCALE := 25.0  # a Damage Area's "radius" number is in these pixel units

var _timer: float = 0.0
var _player: Node2D
var _projectiles_container: Node2D
var _program: WeaponProgram
var _interpreter: BlockInterpreter

const MAX_EVENTS_PER_TICK := 64  # cap so an on_kill -> AoE -> on_kill cascade can't hang the frame

# Per-event scratch state, reset at the start of every event run.
var _shot_index: int = 0      # projectiles fired this run; drives the spread fan
var _damage_mult: float = 1.0  # boost_damage stacks into this
var _pierce: int = 0           # pierce blocks set this; shots consume it

# Events are queued and drained sequentially so a kill caused mid-event still fires
# On Kill, without re-entering the interpreter (which would corrupt the in-flight run).
var _running: bool = false
var _event_queue: Array[StringName] = []

func _ready() -> void:
	_player = get_parent()
	# Find the projectiles container in Main. Falls back to current_scene if missing.
	_projectiles_container = get_tree().current_scene.get_node_or_null("Projectiles")
	if _projectiles_container == null:
		_projectiles_container = get_tree().current_scene
	# Build the starting weapon program and the interpreter that runs it.
	# Later this program will come from the player's saved blocks / the editor.
	_program = _build_default_program()
	_interpreter = BlockInterpreter.new(_program, self)
	# Listen for the events that other hat blocks (on_kill / on_take_damage) run on.
	if _player.has_signal("enemy_killed"):
		_player.connect("enemy_killed", _on_player_killed)
	if _player.has_signal("took_damage"):
		_player.connect("took_damage", _on_player_took_damage)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		execute()
		_timer = fire_interval

# === The "program" ===
# The weapon's behavior lives in a WeaponProgram (a graph of blocks). Each game event
# runs the chain hanging off that event's hat block.
func execute() -> void:
	_enqueue_event(&"on_fire_tick")

func _on_player_killed() -> void:
	_enqueue_event(&"on_kill")

func _on_player_took_damage() -> void:
	_enqueue_event(&"on_take_damage")

# Queue an event. If nothing is currently running, drain right away; otherwise the
# in-flight drain loop will pick it up once the current event finishes.
func _enqueue_event(event_type: StringName) -> void:
	if _interpreter == null:
		return
	_event_queue.append(event_type)
	if not _running:
		_drain_events()

func _drain_events() -> void:
	_running = true
	var processed := 0
	while not _event_queue.is_empty():
		processed += 1
		if processed > MAX_EVENTS_PER_TICK:
			_event_queue.clear()  # runaway cascade; drop the rest this frame
			break
		var event_type: StringName = _event_queue.pop_front()
		_run_event(event_type)
	_running = false

# Run the program for one event. Resets per-run scratch state and the compute budget.
func _run_event(event_type: StringName) -> void:
	_shot_index = 0
	_damage_mult = 1.0
	_pierce = 0
	_interpreter.max_loop_depth = BlockCatalog.max_loop_depth()
	_interpreter.run(event_type)

# The starting program, hand-built in code. It reproduces the original behavior:
#   on_fire_tick -> shoot_toward( find_nearest_enemy )
# Once the GraphEdit editor exists, it will produce this same structure instead.
func _build_default_program() -> WeaponProgram:
	var prog := WeaponProgram.new()
	# Positions are editor metadata so the nodes don't stack when the editor opens.
	prog.add_node(BlockNode.new(&"hat", &"on_fire_tick", {}, Vector2(60, 60)))
	prog.add_node(BlockNode.new(&"enemy", &"find_nearest_enemy", {}, Vector2(60, 280)))
	prog.add_node(BlockNode.new(&"shoot", &"shoot_toward", {}, Vector2(440, 140)))
	# Execution flow: the hat kicks off the shoot block.
	prog.connect_ports(&"hat", &"next", &"shoot", &"exec")
	# Data flow: the nearest enemy feeds the shoot block's target input.
	prog.connect_ports(&"enemy", &"enemy", &"shoot", &"target")
	return prog

# Read/write access to the running program, used by the block editor.
func get_program() -> WeaponProgram:
	return _program

func set_program(program: WeaponProgram) -> void:
	_program = program
	_interpreter = BlockInterpreter.new(_program, self)

# === Operations (the primitives blocks dispatch to) ===

# Fire at a target. projectile_count shots go out per call; the per-tick fan in
# op_shoot_in_direction keeps them (and any other shots this tick) from stacking.
func op_shoot_at(target: Node2D) -> void:
	var base_dir := (target.global_position - _player.global_position).normalized()
	for i in maxi(projectile_count, 1):
		op_shoot_in_direction(base_dir)

func op_find_nearest_enemy() -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in enemies:
		var d: float = _player.global_position.distance_squared_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest

func op_shoot_in_direction(dir: Vector2) -> void:
	if projectile_scene == null:
		return
	# Fan every projectile fired this tick so successive shots never perfectly stack.
	var fired_dir := dir.rotated(deg_to_rad(_spread_offset_deg(_shot_index)))
	_shot_index += 1
	var p := projectile_scene.instantiate()
	p.global_position = _player.global_position
	p.setup(fired_dir, projectile_speed, int(projectile_damage * _damage_mult))
	p.set("pierce", _pierce)
	_projectiles_container.add_child(p)

# Symmetric fan offset for the k-th projectile fired this tick: 0, +s, -s, +2s, -2s, ...
func _spread_offset_deg(k: int) -> float:
	var tier := int(ceil(k / 2.0))
	var dir_sign := 1.0 if (k % 2 == 1) else -1.0
	return spread_angle_degrees * float(tier) * dir_sign

# --- Sensors (data blocks read these) ---

func op_enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func op_random_enemy() -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return null
	return enemies[randi() % enemies.size()] as Node2D

func op_player_health_percent() -> float:
	# _player is typed Node2D, so read player-specific members dynamically.
	var cur: Variant = _player.get("current_health")
	var mx: Variant = _player.get("max_health")
	if cur == null or mx == null or float(mx) <= 0.0:
		return 0.0
	return float(cur) / float(mx) * 100.0

func op_closest_enemy_distance() -> float:
	var e := op_find_nearest_enemy()
	if e == null:
		return INF
	return _player.global_position.distance_to(e.global_position)

func op_player_position() -> Vector2:
	return _player.global_position

func op_enemy_position(enemy: Node2D) -> Vector2:
	if enemy == null:
		return Vector2.ZERO
	return enemy.global_position

# --- Verbs ---

func op_heal_self(amount: int) -> void:
	# Grants a temporary buffer above max HP, so it does something even at full health.
	if _player.has_method("add_overheal"):
		_player.call("add_overheal", amount)
	elif _player.has_method("heal"):
		_player.call("heal", amount)

# Increase this run's outgoing damage (shots and areas) by a percent. Boosts stack.
func op_boost_damage(percent: float) -> void:
	_damage_mult += percent / 100.0

# Make this run's shots pass through extra enemies.
func op_pierce(times: int) -> void:
	_pierce = maxi(_pierce, times)

# Deal damage to every enemy within `radius_units` (scaled to pixels) of a point.
func op_damage_area(center: Vector2, radius_units: float) -> void:
	var radius := radius_units * AOE_RADIUS_SCALE
	if radius <= 0.0:
		return
	var dmg := int(projectile_damage * _damage_mult)
	for e in get_tree().get_nodes_in_group("enemies"):
		if center.distance_to(e.global_position) <= radius and e.has_method("take_damage"):
			e.take_damage(dmg)
	_spawn_aoe_flash(center, radius)

func _spawn_aoe_flash(center: Vector2, radius: float) -> void:
	var flash: Node2D = preload("res://Scripts/aoe_flash.gd").new()
	_projectiles_container.add_child(flash)
	flash.global_position = center
	flash.set("radius", radius)

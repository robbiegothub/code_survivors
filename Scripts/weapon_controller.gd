extends Node
class_name WeaponController

@export var projectile_scene: PackedScene
@export var fire_interval: float = 1.0
@export var projectile_speed: float = 200.0
@export var projectile_damage: int = 13
@export var projectile_count: int = 1
@export var spread_angle_degrees: float = 15.0  # Angle between projectiles when count > 1

var _timer: float = 0.0
var _player: Node2D
var _projectiles_container: Node2D

func _ready() -> void:
	_player = get_parent()
	# Find the projectiles container in Main. Falls back to current_scene if missing.
	_projectiles_container = get_tree().current_scene.get_node_or_null("Projectiles")
	if _projectiles_container == null:
		_projectiles_container = get_tree().current_scene

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		execute()
		_timer = fire_interval

# === The "program" ===
# Eventually this body will be replaced by an interpreter that reads
# from the player's collected powerups. For now, it's hardcoded.
func execute() -> void:
	var target := op_find_nearest_enemy()
	if target == null:
		return
	
	var base_dir := (target.global_position - _player.global_position).normalized()
	
	if projectile_count == 1:
		op_shoot_in_direction(base_dir)
		return
	
	# Spread N projectiles in a small fan centered on the target direction
	var total_spread := deg_to_rad(spread_angle_degrees * (projectile_count - 1))
	var start_angle := -total_spread / 2.0
	for i in projectile_count:
		var angle: float = start_angle + (total_spread / max(projectile_count - 1, 1)) * i
		var dir := base_dir.rotated(angle)
		op_shoot_in_direction(dir)

# === Operations (the primitives powerups will unlock) ===

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
	var p := projectile_scene.instantiate()
	p.global_position = _player.global_position
	p.setup(dir, projectile_speed, projectile_damage)
	_projectiles_container.add_child(p)

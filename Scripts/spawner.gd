extends Node

@export var enemy_scene: PackedScene
@export var base_spawn_interval: float = 2  # Spawn interval at level 1
@export var min_spawn_interval: float = 0.01  # Cap so it doesn't get insane
@export var interval_reduction_per_level: float = 0.125  # 10% faster each level
@export var spawn_distance: float = 400.0
@export var enemy_hp_scaling_per_level: float = 0.04   # 4% more HP per level
@export var enemy_speed_scaling_per_level: float = 0.01 # 1% more speed per level
@export var max_speed_multiplier: float = 16.5  # Cap speed scaling so it stays playable


var _timer: float = 0.0
var _player: Node2D
var _enemies_container: Node2D
var _current_interval: float

var _hp_multiplier: float = 1.0
var _speed_multiplier: float = 1.0

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_enemies_container = get_parent().get_node("Enemies")
	_current_interval = base_spawn_interval
	
	# Listen for level ups to recalculate spawn rate
	if _player != null:
		_player.leveled_up.connect(_on_player_leveled_up)

func _on_player_leveled_up(new_level: int) -> void:
	# Each level multiplies the interval by (1 - reduction). Level 1 = base, level 2 = base * 0.9, etc.
	var multiplier := pow(1.0 - interval_reduction_per_level, new_level - 1)
	_current_interval = max(base_spawn_interval * multiplier, min_spawn_interval)
	_hp_multiplier = 1.0 + (new_level - 1) * enemy_hp_scaling_per_level
	_speed_multiplier = min(1.0 + (new_level - 1) * enemy_speed_scaling_per_level, max_speed_multiplier)
func _process(delta: float) -> void:
	if _player == null or enemy_scene == null:
		return
	
	_timer -= delta
	if _timer <= 0.0:
		_spawn_enemy()
		_timer = _current_interval

func _spawn_enemy() -> void:
	var enemy := enemy_scene.instantiate()
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * spawn_distance
	enemy.global_position = _player.global_position + offset
	
	enemy.max_health = int(enemy.max_health * _hp_multiplier)
	enemy.speed *= _speed_multiplier
	
	_enemies_container.add_child(enemy)

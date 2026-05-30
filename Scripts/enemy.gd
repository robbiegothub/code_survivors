extends CharacterBody2D

@export var speed: float = 101.0
@export var max_health: int = 32.5
@export var contact_damage: int = 10
@export var damage_cooldown: float = 0.5  # Seconds between contact damage ticks
@export var xp_value: int = 4

var current_health: int
var _player: Node2D
var _damage_timer: float = 0.0

func _ready() -> void:
	current_health = max_health
	# Cache a reference to the player so we don't search for them every frame
	_player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	
	# Move toward the player
	var direction := (_player.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()
	
	# Tick down damage cooldown
	if _damage_timer > 0.0:
		_damage_timer -= delta
	
	# Check if we're touching the player and can damage them
	if _damage_timer <= 0.0:
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var collider := collision.get_collider()
			if collider != null and collider.is_in_group("player"):
				collider.take_damage(contact_damage)
				_damage_timer = damage_cooldown
				break

func take_damage(amount: int) -> void:
	current_health -= amount
	if current_health <= 0:
		die()

func die() -> void:
	if _player != null:
		if _player.has_method("gain_xp"):
			_player.gain_xp(xp_value)
		if _player.has_method("register_kill"):
			_player.register_kill()
	queue_free()

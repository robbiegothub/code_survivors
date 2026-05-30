extends CharacterBody2D

signal health_changed(current: int, max: int)
signal xp_changed(current: int, needed: int)
signal leveled_up(new_level: int)
signal kills_changed(total: int)


@export var speed: float = 300.0
@export var max_health: int = 100
@export var xp_to_first_level: int = 10

var current_health: int
var current_xp: int = 0
var current_level: int = 1
var xp_needed: int
var _regen_accumulator: float = 0.0
var kill_count: int = 0


@export var health_regen_percent_per_sec: float = 2.0  # 2% of max HP per second






func register_kill() -> void:
	kill_count += 1
	kills_changed.emit(kill_count)


func _ready() -> void:
	current_health = max_health
	xp_needed = xp_to_first_level
	# Emit initial values so the UI shows correct numbers on game start
	health_changed.emit(current_health, max_health)
	xp_changed.emit(current_xp, xp_needed)
	leveled_up.emit(current_level)
	kills_changed.emit(kill_count)


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")
	input_vector = input_vector.normalized()
	
	velocity = input_vector * speed
	move_and_slide()
	
	_process_regen(delta)

func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		die()

func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func gain_xp(amount: int) -> void:
	current_xp += amount
	while current_xp >= xp_needed:
		current_xp -= xp_needed
		level_up()
	xp_changed.emit(current_xp, xp_needed)

func level_up() -> void:
	current_level += 1
	# Each level needs 10% more XP than the last. Tweak this curve later.
	xp_needed = int(xp_needed * 1.1)
	leveled_up.emit(current_level)

func die() -> void:
	print("Player died!")
	# Brief pause so the death actually feels like something happened.
	# We'll replace this with a proper death animation/screen later.
	await get_tree().create_timer(1.0).timeout
	SceneManager.go_to_menu()
	# We'll handle game over later
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_damage"):
		take_damage(10)
	if event.is_action_pressed("debug_xp"):
		gain_xp(5)
		
		
		
		
		
		
func _process_regen(delta: float) -> void:
	if current_health >= max_health or current_health <= 0:
		return  # Don't regen if already full, or dead
	
	# Calculate fractional HP gained this frame, accumulate until we have a whole HP
	var hp_per_sec := max_health * (health_regen_percent_per_sec / 100.0)
	_regen_accumulator += hp_per_sec * delta
	
	if _regen_accumulator >= 1.0:
		var whole_hp := int(_regen_accumulator)
		_regen_accumulator -= whole_hp
		heal(whole_hp)

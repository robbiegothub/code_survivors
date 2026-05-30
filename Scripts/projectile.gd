extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 400.0
var damage: int = 10
var lifetime: float = 2.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func setup(dir: Vector2, spd: float, dmg: int) -> void:
	direction = dir.normalized()
	speed = spd
	damage = dmg
	rotation = direction.angle()  # rotate sprite to face travel direction

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()

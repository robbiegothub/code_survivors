extends Node2D

# A short-lived expanding ring drawn where a Damage Area block fired, purely for
# feedback. Spawned by WeaponController.op_damage_area and frees itself.

var radius: float = 50.0
var _life: float = 0.25
var _max_life: float = 0.25

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t := _life / _max_life          # 1 -> 0 over the flash's life
	var fill := Color(1.0, 0.55, 0.1, 0.25 * t)
	var ring := Color(1.0, 0.7, 0.2, 0.8 * t)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, ring, 2.0)

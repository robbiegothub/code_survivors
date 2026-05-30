extends Node

var all_powerups: Array[Powerup] = []

func _ready() -> void:
	_register_all()

func _register_all() -> void:
	# --- Damage up ---
	var damage_up := Powerup.new()
	damage_up.display_name = "Sharper Bytes"
	damage_up.description = "+17.5% projectile damage"
	damage_up.apply_effect = func(player):
		var wc: WeaponController = player.get_node("WeaponController")
		wc.projectile_damage = int(wc.projectile_damage * 1.175)
	all_powerups.append(damage_up)
	
	# --- Extra projectile ---
	var extra_proj := Powerup.new()
	extra_proj.display_name = "Fork Bomb"
	extra_proj.description = "+1 projectile per shot"
	extra_proj.apply_effect = func(player):
		var wc: WeaponController = player.get_node("WeaponController")
		wc.projectile_count += 1
	all_powerups.append(extra_proj)
	
	# --- Faster firing ---
	var fire_rate_up := Powerup.new()
	fire_rate_up.display_name = "Overclock"
	fire_rate_up.description = "Shoot 15% more often"
	fire_rate_up.apply_effect = func(player):
		var wc: WeaponController = player.get_node("WeaponController")
		wc.fire_interval /= 1.05  # Dividing makes it shorter = more often
	all_powerups.append(fire_rate_up)

# Pick N random powerups to offer (no duplicates within one choice)
func get_random_choices(count: int = 3) -> Array[Powerup]:
	var pool := all_powerups.duplicate()
	pool.shuffle()
	var picks: Array[Powerup] = []
	for i in min(count, pool.size()):
		picks.append(pool[i])
	return picks

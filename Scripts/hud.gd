extends Control

@onready var health_bar: ProgressBar = $BarsContainer/HealthBar
@onready var xp_bar: ProgressBar = $BarsContainer/XPBar
@onready var level_label: Label = $BarsContainer/LevelLabel
@onready var kill_counter: Label = $KillCounter


func _ready() -> void:
	# Find the player in the scene tree and connect to its signals.
	# We use a group so the HUD doesn't need to know exactly where the player lives.
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("HUD couldn't find a player node in the 'player' group!")
		return
	
	player.health_changed.connect(_on_health_changed)
	player.xp_changed.connect(_on_xp_changed)
	player.leveled_up.connect(_on_leveled_up)
	player.kills_changed.connect(_on_kills_changed)


func _on_health_changed(current: int, max_hp: int) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current

func _on_xp_changed(current: int, needed: int) -> void:
	xp_bar.max_value = needed
	xp_bar.value = current

func _on_leveled_up(new_level: int) -> void:
	level_label.text = "Level %d" % new_level
func _on_kills_changed(total: int) -> void:
	kill_counter.text = "Kills: %d" % total

extends Node

# Autoload. The single source of truth for every block (its editor layout/ports and
# level-up card text) AND the run's progression economy: how many of each block the
# player owns, the Number value cap, and the Big-O compute budget (loop-nest depth).
#
# Blocks are one-time-use: a level-up grant gives +1 of something. The editor palette
# shows how many are still free to place (owned minus how many are already wired in).

# Port "kinds". These double as GraphEdit slot *types*: GraphEdit only wires ports
# of equal kind, so the editor gets type-checking (number->number, enemy->enemy) free.
const KIND_EXEC := 0
const KIND_ENEMY := 1
const KIND_NUMBER := 2
const KIND_BOOL := 3
const KIND_POSITION := 4

# Progression tuning.
const NUMBER_CAP_START := 5         # the Number block can't exceed this at first
const NUMBER_CAP_STEP := 5          # each Number grant raises the cap by this
const COMPLEXITY_TIER_START := 2    # 2 = O(n): a single loop works out of the box; upgrades unlock nesting

# Special grant id (not a block) for the Big-O compute-budget upgrade.
const GRANT_COMPLEXITY := &"upgrade_complexity"

var _specs: Dictionary = {}      # StringName type -> spec Dictionary
var _owned: Dictionary = {}      # StringName type -> count the player has earned

var number_cap: int = NUMBER_CAP_START
var complexity_tier: int = COMPLEXITY_TIER_START

func _ready() -> void:
	_specs = _build_specs()
	reset()

# Reset the economy for a fresh run: start with the default program's blocks only.
func reset() -> void:
	_owned.clear()
	_owned[&"find_nearest_enemy"] = 1
	_owned[&"shoot_toward"] = 1
	number_cap = NUMBER_CAP_START
	complexity_tier = COMPLEXITY_TIER_START

func get_spec(type: StringName) -> Dictionary:
	return _specs.get(type, {})

func has_spec(type: StringName) -> bool:
	return _specs.has(type)

# --- Inventory ---

func get_owned(type: StringName) -> int:
	return _owned.get(type, 0)

# Block types the player owns at least one of (for the editor palette). Hat excluded.
func get_owned_types() -> Array:
	var out: Array = []
	for t in _owned:
		if _owned[t] > 0 and t != &"on_fire_tick":
			out.append(t)
	return out

# --- Big-O compute budget ---

# Max loop-nesting depth the interpreter will run. Tier 1 (O(1)) -> 0 (no loops).
func max_loop_depth() -> int:
	return maxi(complexity_tier - 1, 0)

func big_o_label(tier: int) -> String:
	match tier:
		1: return "O(1)"
		2: return "O(n)"
		3: return "O(n²)"   # n squared
		4: return "O(n³)"   # n cubed
		_: return "O(n^%d)" % max(tier - 1, 1)

# --- Level-up grants ---

# Apply a chosen grant: a block type (+1 owned, and bump the cap for Number), or the
# complexity upgrade.
func apply_grant(id: StringName) -> void:
	if id == GRANT_COMPLEXITY:
		complexity_tier += 1
		return
	if not _specs.has(id):
		return
	_owned[id] = get_owned(id) + 1
	if id == &"number":
		number_cap += NUMBER_CAP_STEP

# Up to `count` random grant cards: every grantable block plus the complexity upgrade.
func get_random_grants(count: int) -> Array:
	var pool: Array = []
	for t in _specs:
		if t != &"on_fire_tick":  # the hat is always present, never granted
			pool.append(_block_grant_card(t))
	pool.append(_complexity_grant_card())
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

func _block_grant_card(type: StringName) -> Dictionary:
	var spec: Dictionary = _specs[type]
	var desc: String = spec["description"]
	if type == &"number":
		desc += "\n(value cap %d → %d)" % [number_cap, number_cap + NUMBER_CAP_STEP]
	return {
		"id": type,
		"title": spec["display_name"],
		"description": "%s\n\n[own %d]" % [desc, get_owned(type)],
	}

func _complexity_grant_card() -> Dictionary:
	return {
		"id": GRANT_COMPLEXITY,
		"title": "Compute Budget +",
		"description": "Raise your Big-O budget so loops can nest deeper.\n\n%s → %s" % [big_o_label(complexity_tier), big_o_label(complexity_tier + 1)],
	}

func port_color(kind: int) -> Color:
	match kind:
		KIND_EXEC: return Color(1, 1, 1)            # white  - control flow
		KIND_ENEMY: return Color(0.95, 0.45, 0.45)  # red    - enemy reference
		KIND_NUMBER: return Color(0.5, 0.9, 0.55)   # green  - number
		KIND_BOOL: return Color(0.75, 0.55, 1.0)    # purple - boolean
		KIND_POSITION: return Color(1.0, 0.7, 0.2)  # orange - position (Vector2)
		_: return Color(0.7, 0.7, 0.7)

# === The catalog ===
# Each row: { label, left, right, widget? }. left/right are {} (no port) or
# { name, kind }. A port's index on its side is its order among the enabled ports
# on that side -- exactly how GraphEdit numbers slots.
func _build_specs() -> Dictionary:
	var exec_in := { "name": &"exec", "kind": KIND_EXEC }
	var exec_out := { "name": &"next", "kind": KIND_EXEC }

	return {
		# --- Starters: always available, mirror the default weapon program ---
		&"on_fire_tick": {
			"display_name": "On Fire Tick",
			"description": "Runs every time the weapon fires. The start of your program.",
			"category": &"event", "starter": true, "deletable": false,
			"rows": [
				{ "label": "start  ▶", "left": {}, "right": exec_out },
			],
		},
		&"find_nearest_enemy": {
			"display_name": "Find Nearest Enemy",
			"description": "Returns the closest living enemy.",
			"category": &"sensor", "starter": true, "deletable": true,
			"rows": [
				{ "label": "enemy  ▶", "left": {}, "right": { "name": &"enemy", "kind": KIND_ENEMY } },
			],
		},
		&"shoot_toward": {
			"display_name": "Shoot Toward",
			"description": "Fires a projectile at the target enemy.",
			"category": &"verb", "starter": true, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "target", "left": { "name": &"target", "kind": KIND_ENEMY }, "right": {} },
			],
		},

		# --- Values & operators ---
		&"number": {
			"display_name": "Number",
			"description": "A constant number you can plug into other blocks.",
			"category": &"value", "starter": false, "deletable": true,
			"rows": [
				{ "label": "value", "widget": "int_value", "left": {}, "right": { "name": &"value", "kind": KIND_NUMBER } },
			],
		},
		&"greater_than": {
			"display_name": "A > B",
			"description": "True when A is greater than B.",
			"category": &"operator", "starter": false, "deletable": true,
			"rows": [
				{ "label": "a", "left": { "name": &"a", "kind": KIND_NUMBER }, "right": { "name": &"result", "kind": KIND_BOOL } },
				{ "label": "b", "left": { "name": &"b", "kind": KIND_NUMBER }, "right": {} },
			],
		},
		&"less_than": {
			"display_name": "A < B",
			"description": "True when A is less than B.",
			"category": &"operator", "starter": false, "deletable": true,
			"rows": [
				{ "label": "a", "left": { "name": &"a", "kind": KIND_NUMBER }, "right": { "name": &"result", "kind": KIND_BOOL } },
				{ "label": "b", "left": { "name": &"b", "kind": KIND_NUMBER }, "right": {} },
			],
		},

		# --- Control flow (needs the interpreter's body-execution support) ---
		&"repeat": {
			"display_name": "Repeat (for)",
			"description": "Runs the body N times. A for-loop.",
			"category": &"control", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "times", "left": { "name": &"times", "kind": KIND_NUMBER }, "right": {} },
				{ "label": "body  ▶", "left": {}, "right": { "name": &"body", "kind": KIND_EXEC } },
			],
		},
		&"if": {
			"display_name": "If / Else",
			"description": "Runs 'then' when the condition is true, otherwise 'else'.",
			"category": &"control", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "cond", "left": { "name": &"cond", "kind": KIND_BOOL }, "right": {} },
				{ "label": "then  ▶", "left": {}, "right": { "name": &"body", "kind": KIND_EXEC } },
				{ "label": "else  ▶", "left": {}, "right": { "name": &"else", "kind": KIND_EXEC } },
			],
		},
		&"while": {
			"display_name": "While",
			"description": "Repeats the body while the condition is true. Costs compute budget like a loop.",
			"category": &"control", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "cond", "left": { "name": &"cond", "kind": KIND_BOOL }, "right": {} },
				{ "label": "body  ▶", "left": {}, "right": { "name": &"body", "kind": KIND_EXEC } },
			],
		},
		&"break": {
			"display_name": "Break",
			"description": "Exit the current loop immediately.",
			"category": &"control", "starter": false, "deletable": true,
			"rows": [
				{ "label": "break", "left": exec_in, "right": {} },
			],
		},
		&"return": {
			"display_name": "Return",
			"description": "Stop the whole program for this event (a guard clause).",
			"category": &"control", "starter": false, "deletable": true,
			"rows": [
				{ "label": "return", "left": exec_in, "right": {} },
			],
		},

		# --- Sensors ---
		&"enemy_count": {
			"display_name": "Enemy Count",
			"description": "How many enemies are currently alive.",
			"category": &"sensor", "starter": false, "deletable": true,
			"rows": [
				{ "label": "count  ▶", "left": {}, "right": { "name": &"count", "kind": KIND_NUMBER } },
			],
		},
		&"player_health_percent": {
			"display_name": "Health %",
			"description": "Your current health from 0 to 100.",
			"category": &"sensor", "starter": false, "deletable": true,
			"rows": [
				{ "label": "percent  ▶", "left": {}, "right": { "name": &"percent", "kind": KIND_NUMBER } },
			],
		},
		&"closest_enemy_distance": {
			"display_name": "Nearest Distance",
			"description": "Distance to the nearest enemy.",
			"category": &"sensor", "starter": false, "deletable": true,
			"rows": [
				{ "label": "distance  ▶", "left": {}, "right": { "name": &"distance", "kind": KIND_NUMBER } },
			],
		},
		&"random_enemy": {
			"display_name": "Random Enemy",
			"description": "Returns a random living enemy.",
			"category": &"sensor", "starter": false, "deletable": true,
			"rows": [
				{ "label": "enemy  ▶", "left": {}, "right": { "name": &"enemy", "kind": KIND_ENEMY } },
			],
		},

		# --- Event hats: alternate program entry points ---
		&"on_kill": {
			"display_name": "On Kill",
			"description": "Runs the moment you kill an enemy.",
			"category": &"event", "starter": false, "deletable": true,
			"rows": [
				{ "label": "on kill  ▶", "left": {}, "right": exec_out },
			],
		},
		&"on_take_damage": {
			"display_name": "On Take Damage",
			"description": "Runs when an enemy damages you. An emergency heal here can save you.",
			"category": &"event", "starter": false, "deletable": true,
			"rows": [
				{ "label": "on hit  ▶", "left": {}, "right": exec_out },
			],
		},

		# --- Position sensors (feed Damage Area) ---
		&"player_position": {
			"display_name": "Player Position",
			"description": "Your current location.",
			"category": &"sensor", "starter": false, "deletable": true,
			"rows": [
				{ "label": "pos  ▶", "left": {}, "right": { "name": &"pos", "kind": KIND_POSITION } },
			],
		},
		&"enemy_position": {
			"display_name": "Enemy Position",
			"description": "The location of an enemy.",
			"category": &"sensor", "starter": false, "deletable": true,
			"rows": [
				{ "label": "of → pos", "left": { "name": &"of", "kind": KIND_ENEMY }, "right": { "name": &"pos", "kind": KIND_POSITION } },
			],
		},

		# --- Verbs ---
		&"heal_self": {
			"display_name": "Heal Self",
			"description": "Heal yourself by an amount.",
			"category": &"verb", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "amount", "left": { "name": &"amount", "kind": KIND_NUMBER }, "right": {} },
			],
		},
		&"boost_damage": {
			"display_name": "Boost Damage",
			"description": "Increase this event's shot AND area damage by a percent. Boosts stack.",
			"category": &"verb", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "percent", "left": { "name": &"percent", "kind": KIND_NUMBER }, "right": {} },
			],
		},
		&"pierce": {
			"display_name": "Pierce",
			"description": "Shots fired this event pass through N extra enemies.",
			"category": &"verb", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "times", "left": { "name": &"times", "kind": KIND_NUMBER }, "right": {} },
			],
		},
		&"damage_area": {
			"display_name": "Damage Area",
			"description": "Damage every enemy near a position. Radius scales with the number.",
			"category": &"verb", "starter": false, "deletable": true,
			"rows": [
				{ "label": "exec          next", "left": exec_in, "right": exec_out },
				{ "label": "center", "left": { "name": &"center", "kind": KIND_POSITION }, "right": {} },
				{ "label": "radius", "left": { "name": &"radius", "kind": KIND_NUMBER }, "right": {} },
			],
		},
	}

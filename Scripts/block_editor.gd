extends CanvasLayer

# Visual editor for the weapon program. Renders each BlockNode as a GraphEdit
# GraphNode with named ports mapped onto GraphEdit's integer slots, and round-trips
# the graph back into a WeaponProgram the interpreter can run.
#
# Block definitions (ports, colors, which are unlocked) come from the BlockCatalog
# autoload. Toggle with the "toggle_block_editor" input action.

signal program_applied(program: WeaponProgram)

# Palette is grouped into one dropdown per category so the toolbar stays compact no
# matter how many blocks you own. Order/labels here drive the toolbar; tweak freely.
const CATEGORY_ORDER := [
	{ "id": &"event", "label": "Events" },
	{ "id": &"control", "label": "Control" },
	{ "id": &"value", "label": "Values" },
	{ "id": &"operator", "label": "Operators" },
	{ "id": &"sensor", "label": "Sensors" },
	{ "id": &"verb", "label": "Actions" },
]

var graph: GraphEdit
var _status: Label
var _error_panel: PanelContainer
var _error_label: Label
var _category_menus: Dictionary = {}   # category id -> MenuButton
var _category_types: Dictionary = {}   # category id -> Array of types currently in its popup
var _wc: WeaponController
var _id_counter := 0

func _init() -> void:
	# Process (and accept input) even while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_build_ui()

# Main wires us to the weapon controller so we can read/write its program directly.
func setup(weapon_controller: WeaponController) -> void:
	_wc = weapon_controller

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_block_editor"):
		if visible:
			_close()
		else:
			open()
		get_viewport().set_input_as_handled()

# === UI construction ===

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Vertical split: a fixed toolbar strip on top, GraphEdit filling the rest. This
	# keeps the GraphEdit's own zoom controls clear of our toolbar (no overlap).
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var bar := PanelContainer.new()
	vbox.add_child(bar)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	bar.add_child(toolbar)

	var title := Label.new()
	title.text = "Weapon Editor"
	toolbar.add_child(title)

	# One dropdown per category; their popups are filled in _rebuild_palette.
	for cat in CATEGORY_ORDER:
		var mb := MenuButton.new()
		mb.text = cat["label"]
		toolbar.add_child(mb)
		mb.get_popup().id_pressed.connect(_on_palette_selected.bind(cat["id"]))
		_category_menus[cat["id"]] = mb

	# Spacer pushes status + Apply to the right edge so they're always visible.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_status = Label.new()
	toolbar.add_child(_status)

	var apply_btn := Button.new()
	apply_btn.text = "Apply & Close"
	apply_btn.pressed.connect(_on_apply)
	toolbar.add_child(apply_btn)

	graph = GraphEdit.new()
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	vbox.add_child(graph)
	graph.connection_request.connect(_on_connection_request)
	graph.disconnection_request.connect(_on_disconnection_request)
	graph.delete_nodes_request.connect(_on_delete_nodes_request)

	# Red feedback box pinned to the bottom; hidden when the program has no issues.
	_error_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.5, 0.09, 0.09, 0.96)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_error_panel.add_theme_stylebox_override("panel", sb)
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(1, 0.92, 0.92))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_panel.add_child(_error_label)
	_error_panel.visible = false
	vbox.add_child(_error_panel)

# How many of `type` are still free to place (owned minus already in the graph).
func _available(type: StringName) -> int:
	return BlockCatalog.get_owned(type) - _count_in_graph(type)

func _count_in_graph(type: StringName) -> int:
	var n := 0
	for child in graph.get_children():
		if child is GraphNode and child.get_meta("block_type") == type:
			n += 1
	return n

# Refill each category dropdown from the current inventory. Items show remaining
# counts and grey out at 0; a category with nothing owned greys out its whole menu.
func _rebuild_palette() -> void:
	_category_types.clear()
	for cat in CATEGORY_ORDER:
		var cat_id: StringName = cat["id"]
		var mb: MenuButton = _category_menus[cat_id]
		var popup := mb.get_popup()
		popup.clear()
		var types := _owned_types_in_category(cat_id)
		_category_types[cat_id] = types
		for i in types.size():
			var type: StringName = types[i]
			var spec := BlockCatalog.get_spec(type)
			var available := _available(type)
			popup.add_item("%s  (%d)" % [spec["display_name"], available], i)
			popup.set_item_disabled(i, available <= 0)
		mb.disabled = types.is_empty()
	_update_status()

func _owned_types_in_category(category: StringName) -> Array:
	var out: Array = []
	for t in BlockCatalog.get_owned_types():
		var type: StringName = t
		if BlockCatalog.get_spec(type).get("category", &"") == category:
			out.append(type)
	return out

# A dropdown item was chosen: map its index back to the block type and place it.
func _on_palette_selected(item_id: int, category: StringName) -> void:
	var types: Array = _category_types.get(category, [])
	if item_id >= 0 and item_id < types.size():
		var type: StringName = types[item_id]
		_add_block(type)

func _update_status() -> void:
	_status.text = "   Compute: %s    Number cap: %d   " % [
		BlockCatalog.big_o_label(BlockCatalog.complexity_tier),
		BlockCatalog.number_cap,
	]

# === Open / close ===

func open() -> void:
	if _wc == null:
		push_warning("BlockEditor opened without a weapon controller; call setup() first.")
		return
	_populate(_wc.get_program())  # populate first so the palette can count placed blocks
	_rebuild_palette()
	_refresh_errors()
	get_tree().paused = true
	visible = true

func _close() -> void:
	get_tree().paused = false
	visible = false

func _on_apply() -> void:
	var prog := _build_program_from_graph()
	_wc.set_program(prog)
	program_applied.emit(prog)
	_close()

# === Feedback box ===

# Re-run validation and show/hide the red box. Called on every edit.
func _refresh_errors() -> void:
	if _error_panel == null:
		return
	var msgs := _validate()
	if msgs.is_empty():
		_error_panel.visible = false
		_error_label.text = ""
	else:
		var lines: Array = []
		for m in msgs:
			lines.append("⚠  " + m)
		_error_label.text = "\n".join(lines)
		_error_panel.visible = true

# Check the current graph for problems players should see.
func _validate() -> Array:
	var program := _build_program_from_graph()
	var msgs: Array = []

	# Rule 1: data inputs that aren't wired (the block can't work without them).
	for node in program.nodes:
		var spec := BlockCatalog.get_spec(node.type)
		for row in spec["rows"]:
			var left: Dictionary = row["left"]
			if left.is_empty() or left["kind"] == BlockCatalog.KIND_EXEC:
				continue
			var port_name: StringName = left["name"]
			if program.get_data_source(node.id, port_name).is_empty():
				msgs.append("%s: input '%s' isn't connected" % [spec["display_name"], port_name])

	# Rule 2: loops nested deeper than the current compute budget allows.
	var budget: int = BlockCatalog.max_loop_depth()
	var label: String = BlockCatalog.big_o_label(BlockCatalog.complexity_tier)
	for node in _overbudget_loops(program, budget):
		var sp := BlockCatalog.get_spec(node.type)
		msgs.append("%s is nested too deep for your %s budget and won't run" % [sp["display_name"], label])
	return msgs

# Loop nodes whose nesting depth meets/exceeds the budget (so the interpreter skips them).
func _overbudget_loops(program: WeaponProgram, budget: int) -> Array:
	var over: Array = []
	var visited: Dictionary = {}
	for hat_type in [&"on_fire_tick", &"on_kill", &"on_take_damage"]:
		var hat := program.find_hat(hat_type)
		if hat != null:
			_walk_exec(program, program.get_exec_target(hat.id, &"next"), 0, budget, visited, over)
	return over

func _walk_exec(program: WeaponProgram, node: BlockNode, depth: int, budget: int, visited: Dictionary, over: Array) -> void:
	while node != null and not visited.has(node.id):
		visited[node.id] = true
		var t: StringName = node.type
		if t == &"repeat" or t == &"while":
			if depth >= budget:
				over.append(node)
			_walk_exec(program, program.get_exec_target(node.id, &"body"), depth + 1, budget, visited, over)
		elif t == &"if":
			_walk_exec(program, program.get_exec_target(node.id, &"body"), depth, budget, visited, over)
			_walk_exec(program, program.get_exec_target(node.id, &"else"), depth, budget, visited, over)
		node = program.get_exec_target(node.id, &"next")

# === Graph <-> WeaponProgram ===

func _populate(program: WeaponProgram) -> void:
	# Free existing nodes immediately (queue_free is deferred and would clash names).
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.free()

	for node in program.nodes:
		graph.add_child(_make_graph_node(node))

	for c in program.connections:
		var from_type: StringName = program.get_node_by_id(c["from_node"]).type
		var to_type: StringName = program.get_node_by_id(c["to_node"]).type
		var from_idx := _port_index(from_type, "right", c["from_port"])
		var to_idx := _port_index(to_type, "left", c["to_port"])
		if from_idx >= 0 and to_idx >= 0:
			graph.connect_node(String(c["from_node"]), from_idx, String(c["to_node"]), to_idx)

func _build_program_from_graph() -> WeaponProgram:
	var prog := WeaponProgram.new()
	for child in graph.get_children():
		if child is GraphNode:
			var t: StringName = child.get_meta("block_type")
			var params := {}
			if child.has_meta("value_spin"):
				params["value"] = int((child.get_meta("value_spin") as SpinBox).value)
			prog.add_node(BlockNode.new(StringName(child.name), t, params, child.position_offset))
	for c in graph.get_connection_list():
		var from_id: StringName = c["from_node"]
		var to_id: StringName = c["to_node"]
		var from_type: StringName = prog.get_node_by_id(from_id).type
		var to_type: StringName = prog.get_node_by_id(to_id).type
		var from_port := _port_name(from_type, "right", c["from_port"])
		var to_port := _port_name(to_type, "left", c["to_port"])
		prog.connect_ports(from_id, from_port, to_id, to_port)
	return prog

func _make_graph_node(block: BlockNode) -> GraphNode:
	var spec := BlockCatalog.get_spec(block.type)
	var gn := GraphNode.new()
	gn.name = String(block.id)
	gn.title = spec["display_name"]
	gn.position_offset = block.position
	gn.set_meta("block_type", block.type)

	# Removable blocks get a visible "x" in their title bar that returns them to the
	# palette. (The Delete key on a selected node does the same thing.)
	if spec.get("deletable", true):
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var close_btn := Button.new()
		close_btn.text = "✕"
		close_btn.flat = true
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.tooltip_text = "Remove block (returns it to the palette)"
		var titlebar := gn.get_titlebar_hbox()
		titlebar.add_child(spacer)     # push the x to the right of the title
		titlebar.add_child(close_btn)
		close_btn.pressed.connect(_delete_node.bind(gn))

	var rows: Array = spec["rows"]
	for i in rows.size():
		var row: Dictionary = rows[i]
		gn.add_child(_make_row_control(row, block, gn))

		var has_left := not (row["left"] as Dictionary).is_empty()
		var has_right := not (row["right"] as Dictionary).is_empty()
		var type_left: int = row["left"]["kind"] if has_left else 0
		var type_right: int = row["right"]["kind"] if has_right else 0
		gn.set_slot(i, has_left, type_left, BlockCatalog.port_color(type_left), has_right, type_right, BlockCatalog.port_color(type_right))
	return gn

# Build the Control for one row. Most rows are a Label; widget rows add an editor
# (e.g. the Number block's SpinBox), whose reference we stash for read-back.
func _make_row_control(row: Dictionary, block: BlockNode, gn: GraphNode) -> Control:
	if row.get("widget", "") == "int_value":
		var hb := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = row["label"]
		hb.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = BlockCatalog.number_cap  # scales as the player earns Number grants
		spin.step = 1
		spin.value = clampf(float(block.params.get("value", 1)), 1, BlockCatalog.number_cap)
		hb.add_child(spin)
		gn.set_meta("value_spin", spin)
		return hb
	var label := Label.new()
	label.text = row["label"]
	return label

# === Port name <-> slot index mapping ===

# Ports enabled on one side of a block, in slot order. Index == GraphEdit port index.
func _ports_on_side(type: StringName, side: String) -> Array:
	var result: Array = []
	for row in BlockCatalog.get_spec(type)["rows"]:
		var port: Dictionary = row[side]
		if not port.is_empty():
			result.append(port)
	return result

func _port_name(type: StringName, side: String, index: int) -> StringName:
	var ports := _ports_on_side(type, side)
	if index < 0 or index >= ports.size():
		return &""
	return ports[index]["name"]

func _port_index(type: StringName, side: String, port_name: StringName) -> int:
	var ports := _ports_on_side(type, side)
	for i in ports.size():
		if ports[i]["name"] == port_name:
			return i
	return -1

# === Toolbar / GraphEdit signal handlers ===

func _add_block(type: StringName) -> void:
	if _available(type) <= 0:
		return  # out of this block; palette button should already be disabled
	_id_counter += 1
	var id := StringName("%s_%d" % [type, _id_counter])
	var params := {}
	if type == &"number":
		params["value"] = 1
	var block := BlockNode.new(id, type, params, graph.scroll_offset + Vector2(240, 200))
	graph.add_child(_make_graph_node(block))
	_rebuild_palette()  # refresh availability counts
	_refresh_errors()

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	# Each input accepts a single source: drop any existing wire into this port first.
	for c in graph.get_connection_list():
		if c["to_node"] == to_node and c["to_port"] == to_port:
			graph.disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	graph.connect_node(from_node, from_port, to_node, to_port)
	_refresh_errors()

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph.disconnect_node(from_node, from_port, to_node, to_port)
	_refresh_errors()

# Delete-key path: GraphEdit hands us the selected node names.
func _on_delete_nodes_request(names: Array) -> void:
	for n in names:
		_delete_node(graph.get_node_or_null(NodePath(String(n))) as GraphNode)

# Remove one block from the graph and return it to the palette. Used by both the
# Delete key and each node's "x" button.
func _delete_node(gn: GraphNode) -> void:
	if gn == null:
		return
	if not BlockCatalog.get_spec(gn.get_meta("block_type")).get("deletable", true):
		return  # the hat block stays
	var id := StringName(gn.name)
	for c in graph.get_connection_list():
		if c["from_node"] == id or c["to_node"] == id:
			graph.disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	graph.remove_child(gn)
	# queue_free (not free): when triggered by the node's own "x" button, the button
	# is mid-emit and a locked object can't be freed immediately.
	gn.queue_free()
	_rebuild_palette()  # the block is now available again
	_refresh_errors()

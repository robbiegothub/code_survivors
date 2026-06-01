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
	get_tree().paused = true
	visible = true

func _close() -> void:
	get_tree().paused = false
	visible = false

func _on_apply() -> void:
	var prog := _build_program_from_graph()
	# --- temporary debug: dump what we're about to run ---
	print("[BlockEditor] Apply: %d nodes, %d connections" % [prog.nodes.size(), prog.connections.size()])
	for c in prog.connections:
		print("   %s.%s -> %s.%s" % [c["from_node"], c["from_port"], c["to_node"], c["to_port"]])
	_wc.set_program(prog)
	program_applied.emit(prog)
	_close()

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

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	# Each input accepts a single source: drop any existing wire into this port first.
	for c in graph.get_connection_list():
		if c["to_node"] == to_node and c["to_port"] == to_port:
			graph.disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	graph.connect_node(from_node, from_port, to_node, to_port)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph.disconnect_node(from_node, from_port, to_node, to_port)

func _on_delete_nodes_request(names: Array) -> void:
	for n in names:
		var gn := graph.get_node_or_null(NodePath(String(n))) as GraphNode
		if gn == null:
			continue
		if not BlockCatalog.get_spec(gn.get_meta("block_type")).get("deletable", true):
			continue  # the hat block stays
		for c in graph.get_connection_list():
			if c["from_node"] == n or c["to_node"] == n:
				graph.disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
		graph.remove_child(gn)
		gn.free()
	_rebuild_palette()  # deleted blocks return to the palette

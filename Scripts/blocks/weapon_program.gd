extends Resource
class_name WeaponProgram

# The player's weapon "program": a graph of block nodes plus the wires between them.
# This is the single source of truth the interpreter runs and the editor edits.
@export var nodes: Array[BlockNode] = []

# Connections use *named* ports (e.g. &"next", &"target") so the interpreter reads
# clearly. GraphEdit works in integer slot indices; the editor layer will translate
# slot index <-> port name when it builds/saves this structure.
#   { from_node, from_port, to_node, to_port }
@export var connections: Array[Dictionary] = []

func add_node(node: BlockNode) -> BlockNode:
	nodes.append(node)
	return node

func connect_ports(from_node: StringName, from_port: StringName, to_node: StringName, to_port: StringName) -> void:
	connections.append({
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port,
	})

func get_node_by_id(id: StringName) -> BlockNode:
	for n in nodes:
		if n.id == id:
			return n
	return null

# The entry point for a given event (e.g. &"on_fire_tick", &"on_kill"), or null if
# the program has no hat for that event.
func find_hat(event_type: StringName) -> BlockNode:
	for n in nodes:
		if n.type == event_type:
			return n
	return null

# Follow an execution wire leaving `from_port` and return the node it leads to.
func get_exec_target(from_node: StringName, from_port: StringName) -> BlockNode:
	for c in connections:
		if c["from_node"] == from_node and c["from_port"] == from_port:
			return get_node_by_id(c["to_node"])
	return null

# Find what feeds a node's data input. Returns { node, port } or {} if nothing is wired.
func get_data_source(to_node: StringName, to_port: StringName) -> Dictionary:
	for c in connections:
		if c["to_node"] == to_node and c["to_port"] == to_port:
			return { "node": get_node_by_id(c["from_node"]), "port": c["from_port"] }
	return {}

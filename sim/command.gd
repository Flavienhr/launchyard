class_name Command
extends RefCounted
## A player action. Serializable: a whole game = seed + commands per day,
## which gives saves, replays and bug reports for free (ADR 0002).

const ORDER := &"order"

var type: StringName
var args: Dictionary


func _init(p_type: StringName = &"", p_args: Dictionary = {}) -> void:
	type = p_type
	args = p_args


static func order(supplier_id: String, component_id: String, quantity: int) -> Command:
	return Command.new(ORDER, {
		"supplier_id": supplier_id,
		"component_id": component_id,
		"quantity": quantity,
	})


func to_dict() -> Dictionary:
	return {"type": String(type), "args": args.duplicate(true)}


static func from_dict(d: Dictionary) -> Command:
	return Command.new(StringName(d["type"]), d["args"].duplicate(true))

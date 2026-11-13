class_name Command
extends RefCounted
## A player action. Serializable: a whole game = seed + commands per day,
## which gives saves, replays and bug reports for free (ADR 0002).

const ORDER := &"order"
const BUILD := &"build"
const HIRE := &"hire"
const FIRE := &"fire"
const ASSIGN_STAFF := &"assign_staff"
const QUEUE_JOB := &"queue_job"
const CANCEL_JOB := &"cancel_job"
const SCHEDULE_LAUNCH := &"schedule_launch"
const RESCHEDULE_LAUNCH := &"reschedule_launch"
const CANCEL_LAUNCH := &"cancel_launch"

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


static func build(facility_type: String) -> Command:
	return Command.new(BUILD, {"facility_type": facility_type})


static func hire(count: int) -> Command:
	return Command.new(HIRE, {"count": count})


static func fire(count: int) -> Command:
	return Command.new(FIRE, {"count": count})


static func assign_staff(facility_id: int, count: int) -> Command:
	return Command.new(ASSIGN_STAFF, {"facility_id": facility_id, "count": count})


static func queue_job(facility_id: int, recipe_id: String, count: int) -> Command:
	return Command.new(QUEUE_JOB, {
		"facility_id": facility_id, "recipe_id": recipe_id, "count": count,
	})


static func cancel_job(job_id: int) -> Command:
	return Command.new(CANCEL_JOB, {"job_id": job_id})


static func schedule_launch(launcher_id: int, pad_id: int, contract_id: int, launch_day: int) -> Command:
	return Command.new(SCHEDULE_LAUNCH, {
		"launcher_id": launcher_id, "pad_id": pad_id,
		"contract_id": contract_id, "launch_day": launch_day,
	})


static func reschedule_launch(launch_id: int, launch_day: int) -> Command:
	return Command.new(RESCHEDULE_LAUNCH, {"launch_id": launch_id, "launch_day": launch_day})


static func cancel_launch(launch_id: int) -> Command:
	return Command.new(CANCEL_LAUNCH, {"launch_id": launch_id})


func to_dict() -> Dictionary:
	return {"type": String(type), "args": args.duplicate(true)}


static func from_dict(d: Dictionary) -> Command:
	return Command.new(StringName(d["type"]), d["args"].duplicate(true))

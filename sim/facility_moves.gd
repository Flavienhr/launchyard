class_name FacilityMoves
extends RefCounted
## Move and demolish an installation (spec 008 R8). Pure functions of (state, data).
## A move is a `building` instance with the new position (same id, same jobs).

const PERCENT := 100  # layout.json percentages are integers out of 100


## Spec 008 R8: max(1, ceil(build_days x move_days_pct / 100)).
## Integer ceil written (a + b - 1) / b: GDScript integer division truncates
## toward zero, so the Python idiom -(-a // b) would round down here.
static func move_days(data: GameData, def: Dictionary) -> int:
	var scaled := int(def.get("build_days", 0)) * int(data.layout.get("move_days_pct", 0))
	return maxi(1, (scaled + PERCENT - 1) / PERCENT)


## Spec 008 R8: busy = started job, hall holding a launcher, or pad that is
## occupied, refurbishing or targeted by a scheduled launch.
static func is_busy(state: GameState, _data: GameData, facility: Dictionary) -> bool:
	for job in facility["jobs"]:
		if job["started"]:
			return true
	for launcher in state.launchers:
		if int(launcher["location_facility_id"]) == int(facility["id"]):
			return true
	if facility.has("pad_state") and facility["pad_state"] != Simulation.PAD_FREE:
		return true
	for launch in state.launches:
		if int(launch["pad_id"]) == int(facility["id"]):
			return true
	return false


## Stock units above the capacity left without this facility (0 = fine).
## Only storage facilities can overflow.
static func storage_excess(state: GameState, data: GameData, facility: Dictionary) -> int:
	var own := int(data.facilities[facility["type"]].get("storage_capacity", 0))
	if own <= 0:
		return 0
	var remaining := Simulation.storage_capacity(state, data)
	if facility["status"] == "ready":
		remaining -= own
	return maxi(0, Simulation.storage_used(state, data) - remaining)


static func apply_move(state: GameState, args: Dictionary, data: GameData) -> Array:
	var command := Command.new(Command.MOVE_FACILITY, args)
	var facility := Simulation._find_facility(state, int(args.get("facility_id", 0)))
	if facility.is_empty():
		return [Simulation._rejected("unknown_facility", command)]
	if is_busy(state, data, facility):
		return [Simulation._rejected("facility_busy", command)]
	var def: Dictionary = data.facilities[facility["type"]]
	var x := int(args.get("x", 0))
	var y := int(args.get("y", 0))
	var rotation := int(args.get("rotation", 0))
	# Without a map (or footprint) there is nowhere to move to.
	if not data.has_map() or not def.has("footprint") or (rotation != 0 and rotation != 1):
		return [Simulation._rejected(LayoutRules.REASON_OUT_OF_BOUNDS, command)]
	var rect := LayoutRules.rect_of(data, facility["type"], x, y, rotation)
	if not LayoutRules.is_buildable(state, data, rect):
		return [Simulation._rejected(LayoutRules.REASON_OUT_OF_BOUNDS, command)]
	var blocker := LayoutRules.overlapping_facility(state, data, rect, int(facility["id"]))
	if blocker != 0:
		return [Simulation._rejected(LayoutRules.REASON_OVERLAP, command, {"facility_id": blocker})]
	var excess := storage_excess(state, data, facility)
	if excess > 0:
		return [Simulation._rejected("storage_overflow", command, {"excess": excess})]
	var cost := int(def.get("build_cost", 0)) * int(data.layout.get("move_cost_pct", 0)) / PERCENT
	if cost > state.money:
		return [Simulation._rejected("insufficient_funds", command)]

	state.money -= cost
	var days := move_days(data, def)
	facility["status"] = "building"
	facility["ready_day"] = state.day + days
	facility["assigned"] = 0
	facility["moving"] = true
	Simulation._set_position(facility, x, y, rotation)
	return [Simulation._event("facility_move_started", {
		"facility_id": facility["id"], "x": x, "y": y, "rotation": rotation,
		"cost": cost, "ready_day": facility["ready_day"],
	})]


static func apply_demolish(state: GameState, args: Dictionary, data: GameData) -> Array:
	var command := Command.new(Command.DEMOLISH_FACILITY, args)
	var facility := Simulation._find_facility(state, int(args.get("facility_id", 0)))
	if facility.is_empty():
		return [Simulation._rejected("unknown_facility", command)]
	if is_busy(state, data, facility):
		return [Simulation._rejected("facility_busy", command)]
	var excess := storage_excess(state, data, facility)
	if excess > 0:
		return [Simulation._rejected("storage_overflow", command, {"excess": excess})]
	# A site without layout (fixtures of phases 1-2) refunds nothing.
	var refund := int(data.facilities[facility["type"]].get("build_cost", 0)) \
		* int(data.layout.get("demolish_refund_pct", 0)) / PERCENT
	state.money += refund
	state.facilities.erase(facility)  # staff, jobs, cells and max_count slot go with it
	return [Simulation._event("facility_demolished", {
		"facility_id": facility["id"], "facility_type": facility["type"], "refund": refund,
	})]

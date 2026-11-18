class_name LayoutRules
extends RefCounted
## Spatial model (spec 008 R1, R2, R4). Pure functions of (state, data).
## A site without `map` disables everything: placements are always valid.

const REASON_OUT_OF_BOUNDS := "out_of_bounds"
const REASON_OVERLAP := "overlap"


## Rectangle {x, y, w, h} of a facility type placed at (x, y), (x, y) being the
## top-left cell after rotation (R2). Rotation 1 swaps the footprint sides.
static func rect_of(data: GameData, facility_type: String, x: int, y: int, rotation: int) -> Dictionary:
	var footprint: Array = data.facilities[facility_type]["footprint"]
	var w := int(footprint[0])
	var h := int(footprint[1])
	if rotation == 1:
		return {"x": x, "y": y, "w": h, "h": w}
	return {"x": x, "y": y, "w": w, "h": h}


## Rectangle of an existing instance, or {} if it has no position.
static func instance_rect(data: GameData, facility: Dictionary) -> Dictionary:
	if facility.get("x") == null:
		return {}
	return rect_of(data, facility["type"], int(facility["x"]), int(facility["y"]), int(facility["rotation"]))


## R4: number of free cells between two rectangles, Chebyshev distance.
static func gap_cells(a: Dictionary, b: Dictionary) -> int:
	var gap_x := maxi(0, maxi(int(b["x"]) - (int(a["x"]) + int(a["w"])), int(a["x"]) - (int(b["x"]) + int(b["w"]))))
	var gap_y := maxi(0, maxi(int(b["y"]) - (int(a["y"]) + int(a["h"])), int(a["y"]) - (int(b["y"]) + int(b["h"]))))
	return maxi(gap_x, gap_y)


## R1: every cell of the rectangle belongs to an owned lot (lots are disjoint,
## so the cell count covered by owned lots must equal the rectangle area).
static func is_buildable(state: GameState, data: GameData, rect: Dictionary) -> bool:
	var covered := 0
	for lot_id in state.owned_lots:
		var lot := data.lot(lot_id)
		if lot.is_empty():
			continue
		var width := mini(int(rect["x"]) + int(rect["w"]), int(lot["x"]) + int(lot["w"])) - maxi(int(rect["x"]), int(lot["x"]))
		var height := mini(int(rect["y"]) + int(rect["h"]), int(lot["y"]) + int(lot["h"])) - maxi(int(rect["y"]), int(lot["y"]))
		if width > 0 and height > 0:
			covered += width * height
	return covered == int(rect["w"]) * int(rect["h"])


## R2: id of the occupying instance with the smallest id, or 0 if the area is
## free. Every status counts (`building` included). `ignore_id` is for moves.
static func overlapping_facility(state: GameState, data: GameData, rect: Dictionary, ignore_id := 0) -> int:
	var found := 0
	for facility in state.facilities:
		if int(facility["id"]) == ignore_id:
			continue
		var other := instance_rect(data, facility)
		if other.is_empty():
			continue
		if _intersects(rect, other):
			if found == 0 or int(facility["id"]) < found:
				found = int(facility["id"])
	return found


static func _intersects(a: Dictionary, b: Dictionary) -> bool:
	return int(a["x"]) < int(b["x"]) + int(b["w"]) and int(b["x"]) < int(a["x"]) + int(a["w"]) \
		and int(a["y"]) < int(b["y"]) + int(b["h"]) and int(b["y"]) < int(a["y"]) + int(a["h"])


## Spatial validity of a placement: {valid, reason, rect[, facility_id]} and,
## when valid on a site with rules (spec 008 R9): in_safety_zone_of, served,
## rollout (halls only), zone_contains (pads only).
## reason is "" when valid. Without map: always valid, rect {}.
static func placement_check(state: GameState, data: GameData, facility_type: String,
		x: int, y: int, rotation: int) -> Dictionary:
	if not data.has_map() or not data.facilities.get(facility_type, {}).has("footprint"):
		return {"valid": true, "reason": "", "rect": {}}
	if rotation != 0 and rotation != 1:
		return {"valid": false, "reason": REASON_OUT_OF_BOUNDS, "rect": {}}
	var rect := rect_of(data, facility_type, x, y, rotation)
	if not is_buildable(state, data, rect):
		return {"valid": false, "reason": REASON_OUT_OF_BOUNDS, "rect": rect}
	var blocker := overlapping_facility(state, data, rect)
	if blocker != 0:
		return {"valid": false, "reason": REASON_OVERLAP, "rect": rect, "facility_id": blocker}
	var result := {"valid": true, "reason": "", "rect": rect}
	if not rules_on(data):
		return result
	var def: Dictionary = data.facilities[facility_type]
	result["in_safety_zone_of"] = zone_pad_ids(state, data, rect, 0)
	result["served"] = not def.has("slots") or is_served(state, data, rect)
	if def.has("launcher_capacity"):
		var rollouts: Array = []
		for facility in state.facilities:
			if is_pad_instance(data, facility) and not instance_rect(data, facility).is_empty():
				var gap := gap_cells(rect, instance_rect(data, facility))
				rollouts.append({"pad_id": facility["id"], "rollout_days": rollout_days(data, gap),
					"rollout_cost": rollout_cost(data, gap)})
		result["rollout"] = rollouts
	if def.has("safety_radius_cells"):
		var contained: Array = []
		for facility in state.facilities:
			var other := instance_rect(data, facility)
			if not other.is_empty() and gap_cells(rect, other) < int(def["safety_radius_cells"]):
				contained.append(facility["id"])
		result["zone_contains"] = contained
	return result


# --- Distance rules (spec 008 R5 to R7). Off without a map or without layout.json.

static func rules_on(data: GameData) -> bool:
	return data.has_map() and not data.layout.is_empty()


static func is_pad_instance(data: GameData, facility: Dictionary) -> bool:
	return data.facilities[facility["type"]].has("safety_radius_cells")


## R5b: the facility is damaged during the resolution of day `state.day` while
## `damaged_until_day > day`.
static func is_damaged(state: GameState, facility: Dictionary) -> bool:
	return int(facility.get("damaged_until_day", -1)) > state.day


## R5: ids (ascending) of the pads, other than `ignore_id`, whose zone contains `rect`.
static func zone_pad_ids(state: GameState, data: GameData, rect: Dictionary, ignore_id: int) -> Array:
	var ids: Array = []
	for facility in state.facilities:
		if int(facility["id"]) == ignore_id or not is_pad_instance(data, facility):
			continue
		var pad_rect := instance_rect(data, facility)
		if pad_rect.is_empty():
			continue
		if gap_cells(rect, pad_rect) < int(data.facilities[facility["type"]]["safety_radius_cells"]):
			ids.append(facility["id"])
	return ids


## R5: instances (ascending id) other than the pad itself inside its zone.
static func zone_contents(state: GameState, data: GameData, pad: Dictionary) -> Array:
	var result: Array = []
	var pad_rect := instance_rect(data, pad)
	if pad_rect.is_empty():
		return result
	var radius := int(data.facilities[pad["type"]]["safety_radius_cells"])
	for facility in state.facilities:
		var rect := instance_rect(data, facility)
		if facility["id"] != pad["id"] and not rect.is_empty() and gap_cells(rect, pad_rect) < radius:
			result.append(facility)
	return result


## R6: a ready, undamaged warehouse within `service_radius_cells`.
static func is_served(state: GameState, data: GameData, rect: Dictionary) -> bool:
	var radius := int(data.layout["service_radius_cells"])
	for facility in state.facilities:
		if facility["status"] != "ready" or is_damaged(state, facility):
			continue
		if not data.facilities[facility["type"]].has("storage_capacity"):
			continue
		var other := instance_rect(data, facility)
		if not other.is_empty() and gap_cells(rect, other) <= radius:
			return true
	return false


## R6: work points per day of a ready instance with slots (unserved: reduced).
static func work_rate(state: GameState, data: GameData, facility: Dictionary) -> int:
	var def: Dictionary = data.facilities[facility["type"]]
	var rate := mini(int(facility["assigned"]), int(def["slots"])) * int(def["productivity_per_slot"])
	if rules_on(data):
		var rect := instance_rect(data, facility)
		if not rect.is_empty() and not is_served(state, data, rect):
			rate = rate * int(data.layout["unserved_productivity_pct"]) / 100
	return rate


## R7.
static func rollout_days(data: GameData, gap: int) -> int:
	return int(data.layout["rollout_base_days"]) + gap / int(data.layout["rollout_cells_per_day"])


static func rollout_cost(data: GameData, gap: int) -> int:
	return int(data.layout["rollout_cost_per_cell"]) * gap


## R5b: repair cost of an instance.
static func repair_cost(data: GameData, facility: Dictionary) -> int:
	return int(data.facilities[facility["type"]].get("build_cost", 0)) * int(data.layout["damage_repair_cost_pct"]) / 100


## R9: spatial facts of an instance for display.
static func facility_spatial(state: GameState, data: GameData, facility_id: int) -> Dictionary:
	var facility := {}
	for candidate in state.facilities:
		if candidate["id"] == facility_id:
			facility = candidate
	var rect := {} if facility.is_empty() else instance_rect(data, facility)
	if rect.is_empty() or not rules_on(data):
		return {"served": true, "in_safety_zone_of": [], "damaged_until_day": -1, "evacuated_today": false}
	var zone := zone_pad_ids(state, data, rect, facility_id)
	var evacuated := false
	if facility["status"] == "ready":
		for pad_id in zone:
			evacuated = evacuated or pad_fires_today(state, pad_id)
	return {
		"served": not data.facilities[facility["type"]].has("slots") or is_served(state, data, rect),
		"in_safety_zone_of": zone,
		"damaged_until_day": int(facility["damaged_until_day"]) if is_damaged(state, facility) else -1,
		"evacuated_today": evacuated,
	}


## R5a: a launch is planned for today from this pad (weather not yet drawn).
static func pad_fires_today(state: GameState, pad_id: int) -> bool:
	for launch in state.launches:
		if launch["pad_id"] == pad_id and launch["launch_day"] == state.day:
			return true
	return false


## First valid position of a facility type, scanning y then x, rotation 0 then 1.
## Returns {x, y, rotation}, or {} if none. Provisional rule for callers that
## give no position (UI and bot until they choose one themselves).
## Provisional auto-placement for a build without position (until the UI #79
## and the bot #81 choose positions). Deterministic scan by y, then x, then
## rotation. Prefers, in order: valid, outside every safety zone and served;
## then valid and outside every zone; then any valid position.
static func first_valid_position(state: GameState, data: GameData, facility_type: String) -> Dictionary:
	var site_map := data.site_map()
	var safe := {}
	var any := {}
	for y in int(site_map["height"]):
		for x in int(site_map["width"]):
			for rotation in 2:
				var check := placement_check(state, data, facility_type, x, y, rotation)
				if not check["valid"]:
					continue
				var position := {"x": x, "y": y, "rotation": rotation}
				var in_zone: bool = not check.get("in_safety_zone_of", []).is_empty()
				if not in_zone and check.get("served", true):
					return position
				if not in_zone and safe.is_empty():
					safe = position
				if any.is_empty():
					any = position
	return safe if not safe.is_empty() else any


## Lots for display: [{id, x, y, w, h, price, owned}], file order.
static func lot_list(state: GameState, data: GameData) -> Array:
	var result: Array = []
	for lot in data.lots():
		result.append({
			"id": lot["id"], "x": int(lot["x"]), "y": int(lot["y"]), "w": int(lot["w"]), "h": int(lot["h"]),
			"price": int(lot["price"]), "owned": lot["id"] in state.owned_lots,
		})
	return result

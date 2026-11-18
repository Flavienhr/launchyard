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


## Spatial validity of a placement: {valid, reason, rect[, facility_id]}.
## reason is "" when valid. Without map: always valid, rect {}.
## (Zone, service and roll-out fields come with spec 008 R5 to R7.)
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
	return {"valid": true, "reason": "", "rect": rect}


## First valid position of a facility type, scanning y then x, rotation 0 then 1.
## Returns {x, y, rotation}, or {} if none. Provisional rule for callers that
## give no position (UI and bot until they choose one themselves).
static func first_valid_position(state: GameState, data: GameData, facility_type: String) -> Dictionary:
	var site_map := data.site_map()
	for y in int(site_map["height"]):
		for x in int(site_map["width"]):
			for rotation in 2:
				if placement_check(state, data, facility_type, x, y, rotation)["valid"]:
					return {"x": x, "y": y, "rotation": rotation}
	return {}


## Lots for display: [{id, x, y, w, h, price, owned}], file order.
static func lot_list(state: GameState, data: GameData) -> Array:
	var result: Array = []
	for lot in data.lots():
		result.append({
			"id": lot["id"], "x": int(lot["x"]), "y": int(lot["y"]), "w": int(lot["w"]), "h": int(lot["h"]),
			"price": int(lot["price"]), "owned": lot["id"] in state.owned_lots,
		})
	return result

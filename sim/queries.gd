class_name SimQueries
extends RefCounted
## Read-only queries for the UI. Never mutates the state, no randomness.
## Derived numbers (progress, days left, buy/make comparison) live here so
## that the UI contains no game rule.


## Spatial model (spec 008 R4, R9): see LayoutRules.
static func gap_cells(rect_a: Dictionary, rect_b: Dictionary) -> int:
	return LayoutRules.gap_cells(rect_a, rect_b)


static func placement_check(state: GameState, data: GameData, facility_type: String,
		x: int, y: int, rotation: int) -> Dictionary:
	return LayoutRules.placement_check(state, data, facility_type, x, y, rotation)


static func lot_list(state: GameState, data: GameData) -> Array:
	return LayoutRules.lot_list(state, data)


static func facility_spatial(state: GameState, data: GameData, facility_id: int) -> Dictionary:
	return LayoutRules.facility_spatial(state, data, facility_id)


## Positioned facilities for the map: [{id, type, name, status, ready_day, rect,
## launchers: [model ids standing on the pad or stored in the hall], job_blocked,
## served, in_safety_zone_of, damaged_until_day (-1 = not damaged), evacuated_today}].
## Instances without a position (site without map) are skipped.
static func map_facilities(state: GameState, data: GameData) -> Array:
	var out: Array = []
	for facility in state.facilities:
		var rect := LayoutRules.instance_rect(data, facility)
		if rect.is_empty():
			continue
		var models: Array = []
		var on_pad := _launcher_by_id(state, int(facility.get("launcher_id", 0)))
		if not on_pad.is_empty():
			models.append(on_pad["model"])
		for launcher in launchers_in(state, int(facility["id"])):
			models.append(launcher["model"])
		var blocked := false
		for job in facility["jobs"]:
			if String(job["blocked"]) != "":
				blocked = true
		var spatial := LayoutRules.facility_spatial(state, data, int(facility["id"]))
		out.append({
			"id": int(facility["id"]), "type": facility["type"],
			"name": data.facilities[facility["type"]]["name"],
			"status": facility["status"], "ready_day": int(facility["ready_day"]),
			"rect": rect, "launchers": models, "job_blocked": blocked,
			"served": spatial["served"], "in_safety_zone_of": spatial["in_safety_zone_of"],
			"damaged_until_day": spatial["damaged_until_day"],
			"evacuated_today": spatial["evacuated_today"],
		})
	return out


## Cell rectangle (inclusive bounds, may exceed the map) covered by a safety zone
## of `radius` cells around `rect` (R5: free cells between < radius).
static func _grown(rect: Dictionary, margin: int) -> Dictionary:
	return {"x": int(rect["x"]) - margin, "y": int(rect["y"]) - margin,
		"w": int(rect["w"]) + 2 * margin, "h": int(rect["h"]) + 2 * margin}


## Safety zone drawn around a pad type placed at `rect` ({} if the type has none
## or the site has no distance rules).
static func safety_zone_rect(data: GameData, facility_type: String, rect: Dictionary) -> Dictionary:
	var def: Dictionary = data.facilities.get(facility_type, {})
	if not LayoutRules.rules_on(data) or not def.has("safety_radius_cells") or rect.is_empty():
		return {}
	return _grown(rect, maxi(0, int(def["safety_radius_cells"]) - 1))


## Zones of the placed instances for the map (R5, R6): {safety: [{pad_id, status,
## rect, fires_today}], service: [{facility_id, rect}]}. service lists the ready,
## undamaged storage facilities (those that serve workshops). Empty without rules.
static func map_zones(state: GameState, data: GameData) -> Dictionary:
	var out := {"safety": [], "service": []}
	if not LayoutRules.rules_on(data):
		return out
	for facility in state.facilities:
		var rect := LayoutRules.instance_rect(data, facility)
		if rect.is_empty():
			continue
		var def: Dictionary = data.facilities[facility["type"]]
		if def.has("safety_radius_cells"):
			out["safety"].append({"pad_id": int(facility["id"]), "status": facility["status"],
				"rect": safety_zone_rect(data, facility["type"], rect),
				"fires_today": LayoutRules.pad_fires_today(state, int(facility["id"]))})
		if def.has("storage_capacity") and facility["status"] == "ready" \
				and not LayoutRules.is_damaged(state, facility):
			out["service"].append({"facility_id": int(facility["id"]),
				"rect": _grown(rect, int(data.layout["service_radius_cells"]))})
	return out


## What moving or demolishing an instance costs, for display (spec 008 R8, same
## formulas as FacilityMoves): {exists, busy, storage_excess, move_cost, move_days,
## refund, can_afford_move}.
static func move_info(state: GameState, data: GameData, facility_id: int) -> Dictionary:
	for facility in state.facilities:
		if int(facility["id"]) != facility_id:
			continue
		var def: Dictionary = data.facilities[facility["type"]]
		var cost: int = int(def.get("build_cost", 0)) * int(data.layout.get("move_cost_pct", 0)) / 100
		return {
			"exists": true,
			"busy": FacilityMoves.is_busy(state, data, facility),
			"storage_excess": FacilityMoves.storage_excess(state, data, facility),
			"move_cost": cost,
			"move_days": FacilityMoves.move_days(data, def),
			"refund": int(def.get("build_cost", 0)) * int(data.layout.get("demolish_refund_pct", 0)) / 100,
			"can_afford_move": cost <= state.money,
		}
	return {"exists": false, "busy": false, "storage_excess": 0, "move_cost": 0, "move_days": 0,
		"refund": 0, "can_afford_move": false}


## Placement check of an existing instance moved to (x, y, rotation) (R8): like
## placement_check, but the instance does not collide with its own old position.
## {valid, reason, rect[, facility_id, in_safety_zone_of, served]}.
static func move_check(state: GameState, data: GameData, facility_id: int,
		x: int, y: int, rotation: int) -> Dictionary:
	var facility := {}
	for candidate in state.facilities:
		if int(candidate["id"]) == facility_id:
			facility = candidate
	if facility.is_empty() or not data.has_map() or rotation < 0 or rotation > 1:
		return {"valid": false, "reason": LayoutRules.REASON_OUT_OF_BOUNDS, "rect": {}}
	var rect := LayoutRules.rect_of(data, facility["type"], x, y, rotation)
	if not LayoutRules.is_buildable(state, data, rect):
		return {"valid": false, "reason": LayoutRules.REASON_OUT_OF_BOUNDS, "rect": rect}
	var blocker := LayoutRules.overlapping_facility(state, data, rect, facility_id)
	if blocker != 0:
		return {"valid": false, "reason": LayoutRules.REASON_OVERLAP, "rect": rect, "facility_id": blocker}
	var result := {"valid": true, "reason": "", "rect": rect}
	if LayoutRules.rules_on(data):
		result["in_safety_zone_of"] = LayoutRules.zone_pad_ids(state, data, rect, facility_id)
		result["served"] = not data.facilities[facility["type"]].has("slots") \
			or LayoutRules.is_served(state, data, rect)
	return result


## Roll-out between halls and pads for a placement (R7): [{pad_id, hall_id,
## rollout_days, rollout_cost}]. A hall type gets one row per pad (as in
## placement_check), a pad type one row per hall. Empty for other types.
static func placement_rollouts(state: GameState, data: GameData, facility_type: String,
		rect: Dictionary) -> Array:
	var rows: Array = []
	var def: Dictionary = data.facilities.get(facility_type, {})
	if not LayoutRules.rules_on(data) or rect.is_empty():
		return rows
	var new_is_hall := def.has("launcher_capacity")
	var new_is_pad := def.has("safety_radius_cells")
	if not new_is_hall and not new_is_pad:
		return rows
	for facility in state.facilities:
		var other := LayoutRules.instance_rect(data, facility)
		if other.is_empty():
			continue
		var other_def: Dictionary = data.facilities[facility["type"]]
		var gap := LayoutRules.gap_cells(rect, other)
		var row := {"rollout_days": LayoutRules.rollout_days(data, gap),
			"rollout_cost": LayoutRules.rollout_cost(data, gap)}
		if new_is_hall and other_def.has("safety_radius_cells"):
			row["pad_id"] = int(facility["id"])
			row["hall_id"] = 0
			rows.append(row)
		elif new_is_pad and other_def.has("launcher_capacity"):
			row["pad_id"] = 0
			row["hall_id"] = int(facility["id"])
			rows.append(row)
	return rows


## Work points per day of an instance, unserved penalty included (spec 008 R6).
## Unlike facility_rate, which ignores the position.
static func effective_rate(state: GameState, data: GameData, facility: Dictionary) -> int:
	if not data.facilities[facility["type"]].has("slots"):
		return 0
	return LayoutRules.work_rate(state, data, facility)


## Throughput (work points per day) of a facility instance.
static func facility_rate(data: GameData, facility: Dictionary) -> int:
	var def: Dictionary = data.facilities[facility["type"]]
	return mini(int(facility["assigned"]), int(def.get("slots", 0))) * int(def.get("productivity_per_slot", 0))


## Job state for display: {recipe_id, work_points, progress, percent, started,
## blocked, idle, days_left}. days_left is -1 when no progress is possible
## (no technician); otherwise the estimate at the current assignment.
## With `state`, the rate includes the unserved penalty (spec 008 R6).
static func job_info(data: GameData, facility: Dictionary, job: Dictionary, state: GameState = null) -> Dictionary:
	var recipe: Dictionary = data.recipes[job["recipe_id"]]
	var work := int(recipe["work_points"])
	var progress := int(job["progress"])
	var rate := facility_rate(data, facility) if state == null else effective_rate(state, data, facility)
	var days_left := -1
	if rate > 0:
		days_left = maxi(1, ceili(float(work - progress) / rate))
	return {
		"id": job["id"],
		"recipe_id": job["recipe_id"],
		"work_points": work,
		"progress": progress,
		"percent": clampi(progress * 100 / maxi(work, 1), 0, 100),
		"started": bool(job["started"]),
		"blocked": String(job["blocked"]),
		"idle": rate <= 0,
		"days_left": days_left,
	}


## Summary of a facility instance: slots, assigned, rate, jobs (job_info each).
static func facility_info(data: GameData, facility: Dictionary, day: int, state: GameState = null) -> Dictionary:
	var def: Dictionary = data.facilities[facility["type"]]
	var jobs: Array = []
	for job in facility["jobs"]:
		jobs.append(job_info(data, facility, job, state))
	return {
		"id": facility["id"],
		"type": facility["type"],
		"name": def["name"],
		"status": facility["status"],
		"ready_day": int(facility["ready_day"]),
		"days_until_ready": maxi(0, int(facility["ready_day"]) - day),
		"slots": int(def.get("slots", 0)),
		"assigned": int(facility["assigned"]),
		"rate": facility_rate(data, facility) if state == null else effective_rate(state, data, facility),
		"jobs": jobs,
		"recipes": recipes_for(data, facility["type"]),
	}


## Recipe ids runnable in a facility type, sorted.
static func recipes_for(data: GameData, facility_type: String) -> Array:
	var ids: Array = []
	for recipe_id in data.recipes:
		if data.recipes[recipe_id]["facility_type"] == facility_type:
			ids.append(recipe_id)
	ids.sort()
	return ids


## Buildable facility types: {type, name, cost, days, upkeep, count, max_count, remaining,
## requires: [{type, name, ready}], missing: [type ids without a ready instance]}.
static func build_options(state: GameState, data: GameData) -> Array:
	var options: Array = []
	for type in data.facilities:
		var def: Dictionary = data.facilities[type]
		if not bool(def.get("buildable", false)):
			continue
		var count := 0
		for facility in state.facilities:
			if facility["type"] == type:
				count += 1
		var requires: Array = []
		var missing: Array = []
		for required in def.get("requires_facilities", []):
			var ready := _has_ready(state, required)
			requires.append({"type": required, "name": data.facilities[required]["name"], "ready": ready})
			if not ready:
				missing.append(required)
		options.append({
			"requires": requires, "missing": missing,
			"type": type, "name": def["name"], "cost": int(def["build_cost"]),
			"days": int(def["build_days"]), "upkeep": int(def["upkeep_per_day"]),
			"count": count, "max_count": int(def["max_count"]),
			"remaining": maxi(0, int(def["max_count"]) - count),
		})
	options.sort_custom(func(a, b): return a["type"] < b["type"])
	return options


## Staff summary: {hired, assigned, free, max, hire_cost, fire_cost, salary_per_day, daily_salaries}.
static func staff_info(state: GameState, data: GameData) -> Dictionary:
	var def: Dictionary = data.staff.get("technician", {})
	var assigned := Simulation.total_assigned(state)
	return {
		"hired": state.technicians_hired,
		"assigned": assigned,
		"free": state.technicians_hired - assigned,
		"max": int(def.get("max_technicians", 0)),
		"hire_cost": int(def.get("hire_cost", 0)),
		"fire_cost": int(def.get("fire_cost", 0)),
		"salary_per_day": int(def.get("technician_salary_per_day", 0)),
		"daily_salaries": state.technicians_hired * int(def.get("technician_salary_per_day", 0)),
	}


## Quantity of each component on order: component_id -> quantity.
static func on_order(state: GameState) -> Dictionary:
	var result := {}
	for order in state.pending_orders:
		result[order["component_id"]] = int(result.get(order["component_id"], 0)) + int(order["quantity"])
	return result


## Bill of materials of a recipe: one row per input
## {component_id, required, in_stock, on_order, missing} where missing is the
## quantity short once stock and orders in transit are counted (0 = covered).
static func bill_of_materials(state: GameState, data: GameData, recipe_id: String) -> Array:
	var rows: Array = []
	var recipe: Dictionary = data.recipes.get(recipe_id, {})
	var ordered := on_order(state)
	var ids: Array = recipe.get("inputs", {}).keys()
	ids.sort()
	for component_id in ids:
		var required := int(recipe["inputs"][component_id])
		var stock := int(state.stock.get(component_id, 0))
		var incoming := int(ordered.get(component_id, 0))
		rows.append({
			"component_id": component_id, "required": required, "in_stock": stock,
			"on_order": incoming, "missing": maxi(0, required - stock - incoming),
		})
	return rows


## Supplier offers for a component, cheapest first:
## [{supplier_id, supplier_name, unit_price, lead_time_days, delay_chance}].
static func supplier_offers(data: GameData, component_id: String) -> Array:
	var offers: Array = []
	for supplier_id in data.suppliers:
		var entry := data.catalog_entry(supplier_id, component_id)
		if entry.is_empty():
			continue
		offers.append({
			"supplier_id": supplier_id,
			"supplier_name": data.suppliers[supplier_id]["name"],
			"unit_price": int(entry["unit_price"]),
			"lead_time_days": int(entry["lead_time_days"]),
			"delay_chance": float(data.suppliers[supplier_id]["delay_chance"]),
		})
	offers.sort_custom(func(a, b):
		if a["unit_price"] != b["unit_price"]:
			return a["unit_price"] < b["unit_price"]
		return a["supplier_id"] < b["supplier_id"])
	return offers


## Quote for ordering `quantity` units of a component from a supplier:
## {total_cost, affordable, storage_units (needed), free_storage (now), fits}.
## fits = false means the truck would wait at the gate until space is freed.
## Spec 007 R3: total_cost is priced at the spot price; unit_price = spot price
## (-1 if not in the catalog); spot_capacity_remaining (-1 = unlimited);
## within_capacity = the quantity fits the remaining spot capacity.
static func order_quote(state: GameState, data: GameData, supplier_id: String,
		component_id: String, quantity: int) -> Dictionary:
	var unit_price := spot_price(state, data, supplier_id, component_id)
	var total := quantity * maxi(unit_price, 0)
	var needed := quantity * int(data.components.get(component_id, {}).get("storage_units", 0))
	var free := Simulation.storage_capacity(state, data) - Simulation.storage_used(state, data)
	var remaining := spot_capacity_remaining(state, data, supplier_id, component_id)
	return {
		"total_cost": total, "affordable": total <= state.money,
		"storage_units": needed, "free_storage": free, "fits": needed <= free,
		"unit_price": unit_price, "spot_capacity_remaining": remaining,
		"within_capacity": remaining == MarketRules.UNLIMITED or quantity <= remaining,
	}


## Buy vs make comparison for a component (spec 006 R6).
## {component_id, offers, buy: cheapest offer or {}, make: {} if no recipe else
## {recipe_id, facility_type, material_cost, days, ready}}.
## material_cost = inputs at the cheapest supplier price per unit produced
## (-1 if an input has no supplier). days = job duration at the current
## assignment of the best ready facility (-1 if none can work).
## The chain of intermediate parts is followed (an input without supplier is
## made by its own recipe). Extra fields in make: effective_cost = material cost
## inflated by the current scrap rates (a scrapped piece still consumed its
## inputs; -1 if impossible), success_rate = product of (1 - rate) along the
## chain, steps = [{recipe_id, facility_type, scrap_rate}] (root first),
## missing_facilities = [{type, name, requires: [names], requires_missing:
## [names]}] for chain types without a ready instance.
static func buy_vs_make(state: GameState, data: GameData, component_id: String) -> Dictionary:
	var offers := supplier_offers(data, component_id)
	var result := {
		"component_id": component_id,
		"offers": offers,
		"buy": offers[0] if not offers.is_empty() else {},
		"make": {},
	}
	var recipe_ids: Array = data.recipes.keys()
	recipe_ids.sort()
	for recipe_id in recipe_ids:
		var recipe: Dictionary = data.recipes[recipe_id]
		if recipe["output"].get("component_id", "") != component_id:
			continue
		var cost := _material_cost(data, recipe_id, 0)
		var chain := _make_chain(state, data, recipe_id)
		var best_rate := 0
		for facility in state.facilities:
			if facility["type"] == recipe["facility_type"] and facility["status"] == "ready":
				best_rate = maxi(best_rate, facility_rate(data, facility))
		var days := -1
		if best_rate > 0:
			days = maxi(1, ceili(float(recipe["work_points"]) / best_rate))
		var effective := _effective_cost(state, data, recipe_id, 0)
		var success := 1.0
		for step in chain["steps"]:
			success *= 1.0 - float(step["scrap_rate"])
		result["make"] = {
			"recipe_id": recipe_id, "facility_type": recipe["facility_type"],
			"material_cost": cost, "days": days, "ready": _has_ready(state, recipe["facility_type"]),
			"effective_cost": effective, "success_rate": success,
			"steps": chain["steps"], "missing_facilities": chain["missing"],
		}
		break
	return result


## Launchers currently stored in a facility (hall).
static func launchers_in(state: GameState, facility_id: int) -> Array:
	return state.launchers.filter(func(l): return l["location_facility_id"] == facility_id)


## {used, capacity} of launcher places in a facility.
static func hall_occupancy(state: GameState, data: GameData, facility: Dictionary) -> Dictionary:
	return {
		"used": launchers_in(state, facility["id"]).size(),
		"capacity": int(data.facilities[facility["type"]].get("launcher_capacity", 0)),
	}


# --- Contracts (spec 002 UI) ---------------------------------------------------

## Display thresholds only (no balance effect): a payload at or above
## NEAR_CAPACITY_PCT % of the best capacity is flagged; an active contract
## without scheduled launch is flagged URGENT_DAYS days before its deadline.
const NEAR_CAPACITY_PCT := 80
const URGENT_DAYS := 10
const HISTORY_STATUSES := ["completed", "failed", "expired"]


## Whether accept_contract would be accepted now: {ok, reason}. Same checks and
## order as Simulation._apply_accept_contract (reason = its rejection reason).
static func can_accept(state: GameState, data: GameData, contract: Dictionary) -> Dictionary:
	var error := ContractRules.acceptance_error(state, data, contract)
	return {"ok": error == "", "reason": error}


## Open offers (ascending id): contract fields plus can_accept, reject_reason,
## deadline_days_left, offer_days_left (1 = last day to sign), capacity_kg
## (best lifter, 0 if none) and near_capacity.
static func contract_offers(state: GameState, data: GameData) -> Array:
	var out: Array = []
	if data.contracts.is_empty():
		return out
	var site := data.active_site()
	for contract in state.contracts:
		if contract["status"] != ContractRules.OFFER:
			continue
		var check := can_accept(state, data, contract)
		var capacity := ContractRules.best_capacity(data, contract["orbit"], site)
		var info: Dictionary = contract.duplicate()
		info["can_accept"] = check["ok"]
		info["reject_reason"] = check["reason"]
		info["deadline_days_left"] = int(contract["deadline_day"]) - state.day
		info["offer_days_left"] = int(contract["offer_expires_day"]) - state.day
		info["capacity_kg"] = capacity
		info["near_capacity"] = capacity > 0 and int(contract["payload_kg"]) * 100 >= capacity * NEAR_CAPACITY_PCT
		out.append(info)
	return out


## Active contracts sorted by deadline: contract fields plus deadline_days_left,
## launch_id / launch_day (-1 when no launch is scheduled), urgent.
static func active_contracts(state: GameState, data: GameData) -> Array:
	var out: Array = []
	for contract in state.contracts:
		if contract["status"] != ContractRules.ACTIVE:
			continue
		var info: Dictionary = contract.duplicate()
		var left := int(contract["deadline_day"]) - state.day
		info["deadline_days_left"] = left
		info["launch_id"] = -1
		info["launch_day"] = -1
		for launch in state.launches:
			if int(launch["contract_id"]) == int(contract["id"]):
				info["launch_id"] = launch["id"]
				info["launch_day"] = launch["launch_day"]
				break
		info["urgent"] = info["launch_id"] < 0 and left <= URGENT_DAYS
		out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["deadline_day"] != b["deadline_day"]:
			return a["deadline_day"] < b["deadline_day"]
		return a["id"] < b["id"])
	return out


## Last `limit` contracts completed, failed or expired, most recent id first.
static func contract_history(state: GameState, limit := 8) -> Array:
	var out: Array = []
	for i in range(state.contracts.size() - 1, -1, -1):
		if state.contracts[i]["status"] in HISTORY_STATUSES:
			out.append(state.contracts[i])
			if out.size() >= limit:
				break
	return out


## {value, min, max, next_unlock_at, next_unlock_orbit}: next_unlock_at is the
## lowest template min_reputation above the current value (-1 if none).
static func reputation_info(state: GameState, data: GameData) -> Dictionary:
	var next := -1
	var orbit := ""
	if not data.contracts.is_empty():
		for template in data.contracts["templates"]:
			var needed := int(template["min_reputation"])
			if needed > state.reputation and (next < 0 or needed < next):
				next = needed
				orbit = template["orbit"]
	return {
		"value": state.reputation,
		"min": int(data.contracts.get("reputation_min", 0)),
		"max": int(data.contracts.get("reputation_max", 100)),
		"next_unlock_at": next,
		"next_unlock_orbit": orbit,
	}


# --- Launches (spec 003 UI) ------------------------------------------------------
# Read-only helpers: same checks as the schedule_launch / reschedule_launch
# commands, so that the UI can grey out and explain instead of computing rules.

static func _launcher_by_id(state: GameState, launcher_id: int) -> Dictionary:
	for launcher in state.launchers:
		if launcher["id"] == launcher_id:
			return launcher
	return {}


static func _facility_by_id(state: GameState, facility_id: int) -> Dictionary:
	for facility in state.facilities:
		if facility["id"] == facility_id:
			return facility
	return {}


static func _contract_by_id(state: GameState, contract_id: int) -> Dictionary:
	for contract in state.contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


static func _launch_of(state: GameState, key: String, id: int) -> Dictionary:
	for launch in state.launches:
		if launch[key] == id:
			return launch
	return {}


## Current reliability of a launcher model (base + gain * successes, capped).
static func model_reliability(state: GameState, data: GameData, model_id: String) -> float:
	var successes: int = int(state.model_stats.get(model_id, {}).get("successes", 0))
	return LaunchRules.model_reliability(data.launchers[model_id], successes)


## {season, season_name, scrub_chance} of a day at the active site.
static func weather_risk(data: GameData, day: int) -> Dictionary:
	var site := data.active_site()
	var season := LaunchRules.season_of(day, site)
	return {
		"season": season,
		"season_name": site["season_names"][season],
		"scrub_chance": float(site["scrub_chance_by_season"][season]),
	}


## Launch pads in id order: id, name, status (building/ready), pad_state
## (free/occupied/refurbishing), ready_day, refurb_until_day, launcher_id and
## launcher_model (occupied only, "" otherwise), launch_id / launch_day (-1 if none).
static func pad_infos(state: GameState, data: GameData) -> Array:
	var out: Array = []
	for facility in state.facilities:
		if not data.facilities[facility["type"]].has("rollout_days"):
			continue
		var info := {
			"id": facility["id"],
			"name": data.facilities[facility["type"]]["name"],
			"status": facility["status"],
			"pad_state": facility.get("pad_state", "free"),
			"ready_day": facility["ready_day"],
			"refurb_until_day": facility.get("refurb_until_day", 0),
			"launcher_id": facility.get("launcher_id", 0),
			"launcher_model": "",
			"launch_id": -1,
			"launch_day": -1,
		}
		var launcher := _launcher_by_id(state, int(info["launcher_id"]))
		if not launcher.is_empty():
			info["launcher_model"] = launcher["model"]
		var launch := _launch_of(state, "pad_id", facility["id"])
		if not launch.is_empty():
			info["launch_id"] = launch["id"]
			info["launch_day"] = launch["launch_day"]
		out.append(info)
	return out


## Launchers without a scheduled launch: id, model, reliability, pad_id (-1 when
## still in the hall), location_name (facility holding it).
static func ready_launchers(state: GameState, data: GameData) -> Array:
	var out: Array = []
	for launcher in state.launchers:
		if not _launch_of(state, "launcher_id", launcher["id"]).is_empty():
			continue
		var location := _facility_by_id(state, int(launcher["location_facility_id"]))
		var on_pad: bool = not location.is_empty() and data.facilities[location["type"]].has("rollout_days")
		out.append({
			"id": launcher["id"],
			"model": launcher["model"],
			"reliability": model_reliability(state, data, launcher["model"]),
			"pad_id": location["id"] if on_pad else -1,
			"location_name": data.facilities[location["type"]]["name"] if not location.is_empty() else "",
		})
	return out


## Pads a launcher could be scheduled on: pad fields plus ok and reason
## (the rejection reason schedule_launch would give, "" when ok).
static func launch_pad_options(state: GameState, data: GameData, launcher_id: int) -> Array:
	var out: Array = []
	var launcher := _launcher_by_id(state, launcher_id)
	var pads := pad_infos(state, data)
	var on_a_pad := false
	for pad in pads:
		if launcher_id != 0 and pad["launcher_id"] == launcher_id:
			on_a_pad = true
	for pad in pads:
		var on_pad: bool = pad["launcher_id"] == launcher_id
		var reason := ""
		if launcher.is_empty():
			reason = "launcher_unavailable"
		elif pad["status"] != "ready":
			reason = "pad_unavailable"
		elif not (pad["pad_state"] == "free" or (pad["pad_state"] == "occupied" and on_pad)):
			reason = "pad_unavailable"
		elif on_a_pad and not on_pad:
			reason = "pad_unavailable"
		var option: Dictionary = pad.duplicate()
		option["ok"] = reason == ""
		option["reason"] = reason
		out.append(option)
	return out


## Active contracts without launch, ascending deadline, with ok and reason
## (orbit_unreachable / payload_too_heavy / "" when the launcher can fly it).
static func launch_contract_options(state: GameState, data: GameData, launcher_id: int) -> Array:
	var out: Array = []
	var launcher := _launcher_by_id(state, launcher_id)
	var site := data.active_site()
	for contract in active_contracts(state, data):
		if contract["launch_id"] >= 0:
			continue
		var reason := ""
		var orbit: Dictionary = data.orbits.get(contract["orbit"], {})
		if orbit.is_empty() or not LaunchRules.is_orbit_reachable(orbit, site):
			reason = "orbit_unreachable"
		elif not launcher.is_empty() and int(contract["payload_kg"]) > LaunchRules.payload_capacity(
				data.launchers[launcher["model"]], contract["orbit"], site):
			reason = "payload_too_heavy"
		var option: Dictionary = contract.duplicate()
		option["ok"] = reason == ""
		option["reason"] = reason
		out.append(option)
	return out


## Earliest launch day for a launcher on a pad: 1 day if it already stands on it,
## else the pad rollout time. Falls back to tomorrow when the pad is unknown.
static func min_launch_day(state: GameState, data: GameData, launcher_id: int, pad_id: int) -> int:
	var pad := _facility_by_id(state, pad_id)
	if pad.is_empty() or not data.facilities[pad["type"]].has("rollout_days"):
		return state.day + 1
	if pad.get("launcher_id", 0) == launcher_id:
		return state.day + 1
	return state.day + int(data.facilities[pad["type"]]["rollout_days"])


## What the player needs to see before choosing a day: min_day, max_day (contract
## deadline, -1 if unknown), margin_days (deadline - day), season_name,
## scrub_chance of that day, reliability of the model, and error (the rejection
## reason schedule_launch would give for this day, "" if it would be accepted).
static func launch_plan(state: GameState, data: GameData, launcher_id: int, pad_id: int,
		contract_id: int, day: int) -> Dictionary:
	var launcher := _launcher_by_id(state, launcher_id)
	var contract := _contract_by_id(state, contract_id)
	var weather := weather_risk(data, day)
	var plan := {
		"min_day": min_launch_day(state, data, launcher_id, pad_id),
		"max_day": int(contract["deadline_day"]) if not contract.is_empty() else -1,
		"margin_days": int(contract["deadline_day"]) - day if not contract.is_empty() else 0,
		"season_name": weather["season_name"],
		"scrub_chance": weather["scrub_chance"],
		"reliability": model_reliability(state, data, launcher["model"]) if not launcher.is_empty() else 0.0,
		"error": "",
	}
	if launcher.is_empty():
		plan["error"] = "launcher_unavailable"
	elif contract.is_empty():
		plan["error"] = "contract_unavailable"
	elif day < plan["min_day"]:
		plan["error"] = "too_early"
	elif day > plan["max_day"]:
		plan["error"] = "after_deadline"
	else:
		for option in launch_pad_options(state, data, launcher_id):
			if option["id"] == pad_id and not option["ok"]:
				plan["error"] = option["reason"]
		for option in launch_contract_options(state, data, launcher_id):
			if option["id"] == contract_id and not option["ok"]:
				plan["error"] = option["reason"]
	return plan


## Scheduled launches by day then id: launch fields plus launcher_model, pad_name,
## client, orbit, deadline_day, margin_days (deadline - launch_day), season_name,
## scrub_chance (of launch_day) and reliability.
static func scheduled_launches(state: GameState, data: GameData) -> Array:
	var out: Array = []
	for launch in state.launches:
		var launcher := _launcher_by_id(state, launch["launcher_id"])
		var pad := _facility_by_id(state, launch["pad_id"])
		var contract := _contract_by_id(state, launch["contract_id"])
		var weather := weather_risk(data, launch["launch_day"])
		var info: Dictionary = launch.duplicate()
		info["launcher_model"] = launcher.get("model", "")
		info["pad_name"] = data.facilities[pad["type"]]["name"] if not pad.is_empty() else ""
		info["client"] = contract.get("client", "")
		info["orbit"] = contract.get("orbit", "")
		info["deadline_day"] = int(contract.get("deadline_day", launch["launch_day"]))
		info["margin_days"] = info["deadline_day"] - launch["launch_day"]
		info["season_name"] = weather["season_name"]
		info["scrub_chance"] = weather["scrub_chance"]
		info["reliability"] = model_reliability(state, data, info["launcher_model"]) if info["launcher_model"] != "" else 0.0
		out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["launch_day"] != b["launch_day"]:
			return a["launch_day"] < b["launch_day"]
		return a["id"] < b["id"])
	return out


## Spec 004 display: {game_over, warning, days_in_debt, days_left}. warning is on
## from bankruptcy_warning_days of debt; days_left counts down to game over.
static func bankruptcy_status(state: GameState, data: GameData) -> Dictionary:
	var grace := int(data.rules.get("bankruptcy_grace_days", 0))
	var warning_days := int(data.rules.get("bankruptcy_warning_days", 0))
	return {
		"game_over": state.game_over,
		"warning": not data.rules.is_empty() and state.days_in_debt > 0 and state.days_in_debt >= warning_days,
		"days_in_debt": state.days_in_debt,
		"days_left": maxi(grace - state.days_in_debt, 0),
	}


## Current scrap rate of a recipe (spec 006 R4): max(floor, start - drop * attempts).
## A recipe without scrap fields has rate 0.
static func scrap_rate(state: GameState, data: GameData, recipe_id: String) -> float:
	var recipe: Dictionary = data.recipes[recipe_id]
	var attempts := int(state.recipe_attempts.get(recipe_id, 0))
	var start := float(recipe.get("scrap_rate_start", 0))
	var drop := float(recipe.get("scrap_rate_drop_per_attempt", 0))
	return maxf(float(recipe.get("scrap_rate_floor", 0)), start - drop * attempts)


static func _has_ready(state: GameState, facility_type: String) -> bool:
	for facility in state.facilities:
		if facility["type"] == facility_type and facility["status"] == "ready":
			return true
	return false


## Recipe producing a component, "" if none (first by id).
static func _recipe_making(data: GameData, component_id: String) -> String:
	var ids: Array = data.recipes.keys()
	ids.sort()
	for recipe_id in ids:
		if data.recipes[recipe_id]["output"].get("component_id", "") == component_id:
			return recipe_id
	return ""


const _MAX_CHAIN_DEPTH := 6


## Cost of one unit of a component when sourced the cheapest way: supplier price,
## else its own recipe (scrap included). -1 if neither exists.
static func _sourcing_cost(state: GameState, data: GameData, component_id: String, depth: int) -> int:
	var offers := supplier_offers(data, component_id)
	if not offers.is_empty():
		return int(offers[0]["unit_price"])
	var recipe_id := _recipe_making(data, component_id)
	if recipe_id == "" or depth >= _MAX_CHAIN_DEPTH:
		return -1
	return _effective_cost(state, data, recipe_id, depth + 1)


## Raw material cost per unit, scrap ignored, intermediate parts expanded (-1 if unsourceable).
static func _material_cost(data: GameData, recipe_id: String, depth: int) -> int:
	var recipe: Dictionary = data.recipes[recipe_id]
	var cost := 0
	for input_id in recipe["inputs"]:
		var offers := supplier_offers(data, input_id)
		var unit := -1
		if not offers.is_empty():
			unit = int(offers[0]["unit_price"])
		else:
			var sub := _recipe_making(data, input_id)
			if sub != "" and depth < _MAX_CHAIN_DEPTH:
				unit = _material_cost(data, sub, depth + 1)
		if unit < 0:
			return -1
		cost += int(recipe["inputs"][input_id]) * unit
	return cost / maxi(int(recipe["output"].get("quantity", 1)), 1)


## Cost per good unit: inputs cost / (quantity * (1 - current scrap rate)).
static func _effective_cost(state: GameState, data: GameData, recipe_id: String, depth: int) -> int:
	var recipe: Dictionary = data.recipes[recipe_id]
	var total := 0
	for input_id in recipe["inputs"]:
		var unit := _sourcing_cost(state, data, input_id, depth)
		if unit < 0:
			return -1
		total += int(recipe["inputs"][input_id]) * unit
	var success := 1.0 - scrap_rate(state, data, recipe_id)
	if success <= 0.0:
		return -1
	return ceili(float(total) / (maxi(int(recipe["output"].get("quantity", 1)), 1) * success))


## Recipes and missing facility types along the make chain of a recipe.
static func _make_chain(state: GameState, data: GameData, recipe_id: String) -> Dictionary:
	var steps: Array = []
	var missing: Array = []
	var seen: Dictionary = {}
	var queue: Array = [recipe_id]
	var depth := 0
	while not queue.is_empty() and depth < 16:
		depth += 1
		var current: String = queue.pop_front()
		var recipe: Dictionary = data.recipes[current]
		var type: String = recipe["facility_type"]
		steps.append({"recipe_id": current, "facility_type": type,
			"scrap_rate": scrap_rate(state, data, current)})
		if not seen.has(type) and not _has_ready(state, type):
			seen[type] = true
			var def: Dictionary = data.facilities[type]
			var reqs: Array = []
			var reqs_missing: Array = []
			for required in def.get("requires_facilities", []):
				var rname: String = data.facilities[required]["name"]
				reqs.append(rname)
				if not _has_ready(state, required):
					reqs_missing.append(rname)
			missing.append({"type": type, "name": def["name"], "requires": reqs,
				"requires_missing": reqs_missing})
		for input_id in recipe["inputs"]:
			if supplier_offers(data, input_id).is_empty():
				var sub := _recipe_making(data, input_id)
				if sub != "":
					queue.append(sub)
	return {"steps": steps, "missing": missing}


## Scrap curve of a recipe for display: {start, current, floor, attempts,
## attempts_to_floor (0 when already at the floor), scrapped (jobs lost so far)}.
static func scrap_info(state: GameState, data: GameData, recipe_id: String) -> Dictionary:
	var recipe: Dictionary = data.recipes[recipe_id]
	var start := float(recipe.get("scrap_rate_start", 0))
	var drop := float(recipe.get("scrap_rate_drop_per_attempt", 0))
	var floor_rate := float(recipe.get("scrap_rate_floor", 0))
	var attempts := int(state.recipe_attempts.get(recipe_id, 0))
	var to_floor := 0
	if drop > 0.0 and start > floor_rate:
		to_floor = maxi(0, ceili((start - floor_rate) / drop - 0.000001) - attempts)
	return {"start": start, "current": scrap_rate(state, data, recipe_id), "floor": floor_rate,
		"attempts": attempts, "attempts_to_floor": to_floor, "has_scrap": start > 0.0,
		"scrapped": int(state.recipe_scrapped.get(recipe_id, 0))}


# --- Market (spec 007) ---

## Current spot price of a catalog entry (R1): catalog price x effective index
## (shortage surcharge included), rounded half up. -1 if not in the catalog.
static func spot_price(state: GameState, data: GameData, supplier_id: String, component_id: String) -> int:
	var entry := data.catalog_entry(supplier_id, component_id)
	if entry.is_empty():
		return -1
	return MarketRules.spot_price(state, data, int(entry["unit_price"]), component_id)


## Delivery delay of a spot order today, shortage included (spec 007 R3).
## -1 if not in the catalog.
static func spot_lead_days(state: GameState, data: GameData, supplier_id: String, component_id: String) -> int:
	var entry := data.catalog_entry(supplier_id, component_id)
	if entry.is_empty():
		return -1
	return MarketRules.spot_lead_days(state, data, int(entry["lead_time_days"]), component_id)


## Spot units still buyable from a catalog entry this period (spec 007 R3).
## -1 = unlimited (MarketRules.UNLIMITED); 0 if not in the catalog.
static func spot_capacity_remaining(state: GameState, data: GameData, supplier_id: String, component_id: String) -> int:
	if data.catalog_entry(supplier_id, component_id).is_empty():
		return 0
	var capacity := MarketRules.spot_capacity(state, data, supplier_id, component_id)
	if capacity == MarketRules.UNLIMITED:
		return MarketRules.UNLIMITED
	return maxi(0, capacity - MarketRules.spot_used(state, supplier_id, component_id))


## Per component of market.json: {index, change (since the previous period),
## shortage, ends_day (-1 without shortage)}.
static func market_snapshot(state: GameState, data: GameData) -> Dictionary:
	var out := {}
	for row in data.market.get("components", []):
		var id: String = row["id"]
		var index := MarketRules.index_of(state, data, id)
		out[id] = {
			"index": index,
			"change": index - int(state.market["prev_index"].get(id, index)),
			"shortage": MarketRules.in_shortage(state, data, id),
			"ends_day": MarketRules.shortage_ends_day(state, data, id),
		}
	return out


# --- Supply contracts (spec 007) ---

## Quote for a supply contract with the arguments of sign_supply_contract (R9):
## {ok, reason (R4 rejection or ""), discount_pct, unit_price (indexed: at today's
## spot), invoice (per delivery), storage_units (per delivery), total_commitment
## (deliveries x invoice), termination_fee (due if terminated right after signing)}.
## Numeric fields are 0 when the entry cannot be priced (not_in_catalog,
## contracts_not_offered, bad period). Same checks as SupplyRules.sign (signing
## debits nothing, so no insufficient_funds).
static func supply_contract_quote(state: GameState, data: GameData, args: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": SupplyRules.sign_rejection(state, data, args), "discount_pct": 0,
		"unit_price": 0, "invoice": 0, "storage_units": 0, "total_commitment": 0, "termination_fee": 0}
	out["ok"] = out["reason"] == ""
	var entry := data.catalog_entry(args.get("supplier_id", ""), args.get("component_id", ""))
	if entry.is_empty() or entry.get("contract_terms", {}).is_empty():
		return out
	var quantity := int(args.get("quantity", 0))
	var period_days := int(args.get("period_days", 0))
	if period_days <= 0:
		return out
	var component_id: String = args["component_id"]
	var discount := SupplyRules.discount_pct(data, entry, quantity, period_days)
	var pct := SupplyRules.price_pct(data, discount, str(args.get("pricing", "")), bool(args.get("priority", false)))
	var spot := MarketRules.spot_price(state, data, int(entry["unit_price"]), component_id)
	var unit_price := (spot * pct + SupplyRules.PCT / 2) / SupplyRules.PCT
	var total := int(args.get("deliveries", 0)) * quantity * unit_price
	out["discount_pct"] = discount
	out["unit_price"] = unit_price
	out["invoice"] = quantity * unit_price
	out["storage_units"] = quantity * int(data.components[component_id]["storage_units"])
	out["total_commitment"] = total
	out["termination_fee"] = total * int(data.supply_contracts.get("termination_fee_pct", 0)) / SupplyRules.PCT
	return out


## Dated deliveries and invoices expected in the next `days` days (R9), sorted by
## day, then contract id, then order id: [{day (delivery day), invoice_day (day whose
## resolution debits the invoice, -1 when already paid), kind ("contract" = planned
## shipment, "transit" = order already on its way), contract_id (-1 if none),
## order_id (-1 for a planned shipment), supplier_id, component_id, quantity,
## storage_units, invoice (still to pay: 0 for transit orders and skipped
## deliveries), skipped}]. Window: delivery day in [day + 1, day + days]. Planned
## invoices use today's price (indexed) and the full quantity (no shortage reduction).
static func supply_schedule(state: GameState, data: GameData, days: int) -> Array:
	var rows: Array = []
	var last_day := state.day + days
	for order in state.pending_orders:
		var arrival := maxi(int(order["arrival_day"]), state.day + 1)
		if arrival > last_day:
			continue
		rows.append({"day": arrival, "invoice_day": -1, "kind": "transit",
			"contract_id": int(order.get("contract_id", -1)), "order_id": order["id"],
			"supplier_id": order["supplier_id"], "component_id": order["component_id"],
			"quantity": order["quantity"],
			"storage_units": int(order["quantity"]) * int(data.components[order["component_id"]]["storage_units"]),
			"invoice": 0, "skipped": false, "delay_days": int(order.get("delay_days", 0))})
	for contract in state.supply_contracts:
		if contract["status"] != SupplyRules.ACTIVE:
			continue
		var price := SupplyRules.current_unit_price(state, data, contract)
		var units := int(contract["quantity"]) * int(data.components[contract["component_id"]]["storage_units"])
		for k in int(contract["deliveries"]) - int(contract["deliveries_done"]):
			var delivery_day := int(contract["next_delivery_day"]) + k * int(contract["period_days"])
			if delivery_day > last_day:
				break
			var skipped: bool = k == 0 and contract["skip_next"]
			rows.append({"day": delivery_day, "invoice_day": delivery_day - 1, "kind": "contract",
				"contract_id": contract["id"], "order_id": -1,
				"supplier_id": contract["supplier_id"], "component_id": contract["component_id"],
				"quantity": contract["quantity"], "storage_units": units,
				"invoice": 0 if skipped else int(contract["quantity"]) * price, "skipped": skipped,
				"delay_days": 0})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["day"] != b["day"]:
			return a["day"] < b["day"]
		if a["contract_id"] != b["contract_id"]:
			return a["contract_id"] < b["contract_id"]
		return a["order_id"] < b["order_id"])
	return rows


## First day on which the next market update is visible (R2), or -1 when the
## market is inactive. The update is resolved at the end of the day before.
static func market_next_update_day(state: GameState, data: GameData) -> int:
	if not MarketRules.is_active(data):
		return -1
	var period := int(data.market["market_period_days"])
	return state.day + (period - (state.day + 1) % period) % period + 1


## Active supply contracts by ascending id, with what the UI shows before a click:
## the contract fields plus {unit_price (today), remaining (deliveries left, a
## skipped one excluded), skip_cost, termination_fee, can_skip, skip_reason
## ("already_skipped" | "notice_too_short" | "")}.
static func supply_contract_infos(state: GameState, data: GameData) -> Array:
	var out: Array = []
	for contract in state.supply_contracts:
		if contract["status"] != SupplyRules.ACTIVE:
			continue
		var info: Dictionary = contract.duplicate()
		info["unit_price"] = SupplyRules.current_unit_price(state, data, contract)
		info["remaining"] = SupplyRules.remaining_deliveries(contract)
		info["skip_cost"] = SupplyRules.skip_cost(state, data, contract)
		info["termination_fee"] = SupplyRules.termination_fee(state, data, contract)
		var reason := ""
		if contract["skip_next"]:
			reason = "already_skipped"
		elif int(contract["next_delivery_day"]) - state.day < int(SupplyRules.params(data)["skip_notice_days"]):
			reason = "notice_too_short"
		info["skip_reason"] = reason
		info["can_skip"] = reason == ""
		out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	return out


## Known fixed costs per day: upkeep of the ready facilities + salaries.
static func known_daily_costs(state: GameState, data: GameData) -> int:
	var total := 0
	for facility in state.facilities:
		if facility["status"] == "ready":
			total += int(data.facilities[facility["type"]]["upkeep_per_day"])
	if state.technicians_hired > 0:
		total += state.technicians_hired * int(data.staff["technician"]["technician_salary_per_day"])
	return total


## Projected cash for each of the next `days` days (R9), counting only what is
## known: the fixed costs and the planned contract invoices of supply_schedule.
## One row per day D in [day + 1, day + days]: {day, balance (cash at the start
## of D: after the resolution of D - 1, which debits the invoices of the
## deliveries of D), fixed_costs (per day), invoices (due for the deliveries
## of D), entries (supply_schedule rows whose delivery day is D)}.
static func cash_projection(state: GameState, data: GameData, days: int) -> Array:
	var schedule := supply_schedule(state, data, days)
	var fixed := known_daily_costs(state, data)
	var rows: Array = []
	var balance := state.money
	for offset in range(1, days + 1):
		var day := state.day + offset
		var invoices := 0
		var entries: Array = []
		for row in schedule:
			if row["day"] == day:
				entries.append(row)
				if row["kind"] == "contract":
					invoices += int(row["invoice"])
		balance -= fixed + invoices
		rows.append({"day": day, "balance": balance, "fixed_costs": fixed,
			"invoices": invoices, "entries": entries})
	return rows

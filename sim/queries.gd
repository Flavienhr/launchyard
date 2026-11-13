class_name SimQueries
extends RefCounted
## Read-only queries for the UI. Never mutates the state, no randomness.
## Derived numbers (progress, days left, buy/make comparison) live here so
## that the UI contains no game rule.


## Throughput (work points per day) of a facility instance.
static func facility_rate(data: GameData, facility: Dictionary) -> int:
	var def: Dictionary = data.facilities[facility["type"]]
	return mini(int(facility["assigned"]), int(def.get("slots", 0))) * int(def.get("productivity_per_slot", 0))


## Job state for display: {recipe_id, work_points, progress, percent, started,
## blocked, idle, days_left}. days_left is -1 when no progress is possible
## (no technician); otherwise the estimate at the current assignment.
static func job_info(data: GameData, facility: Dictionary, job: Dictionary) -> Dictionary:
	var recipe: Dictionary = data.recipes[job["recipe_id"]]
	var work := int(recipe["work_points"])
	var progress := int(job["progress"])
	var rate := facility_rate(data, facility)
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
static func facility_info(data: GameData, facility: Dictionary, day: int) -> Dictionary:
	var def: Dictionary = data.facilities[facility["type"]]
	var jobs: Array = []
	for job in facility["jobs"]:
		jobs.append(job_info(data, facility, job))
	return {
		"id": facility["id"],
		"type": facility["type"],
		"name": def["name"],
		"status": facility["status"],
		"ready_day": int(facility["ready_day"]),
		"days_until_ready": maxi(0, int(facility["ready_day"]) - day),
		"slots": int(def.get("slots", 0)),
		"assigned": int(facility["assigned"]),
		"rate": facility_rate(data, facility),
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


## Buildable facility types: {type, name, cost, days, upkeep, count, max_count, remaining}.
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
		options.append({
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


## Buy vs make comparison for a component.
## {component_id, offers, buy: cheapest offer or {}, make: {} if no recipe else
## {recipe_id, facility_type, material_cost, days, ready}}.
## material_cost = inputs at the cheapest supplier price per unit produced
## (-1 if an input has no supplier). days = job duration at the current
## assignment of the best ready facility (-1 if none can work).
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
		var cost := 0
		for input_id in recipe["inputs"]:
			var input_offers := supplier_offers(data, input_id)
			if input_offers.is_empty():
				cost = -1
				break
			cost += int(recipe["inputs"][input_id]) * int(input_offers[0]["unit_price"])
		if cost > 0:
			cost = cost / maxi(int(recipe["output"]["quantity"]), 1)
		var best_rate := 0
		var has_ready := false
		for facility in state.facilities:
			if facility["type"] == recipe["facility_type"] and facility["status"] == "ready":
				has_ready = true
				best_rate = maxi(best_rate, facility_rate(data, facility))
		var days := -1
		if best_rate > 0:
			days = maxi(1, ceili(float(recipe["work_points"]) / best_rate))
		result["make"] = {
			"recipe_id": recipe_id, "facility_type": recipe["facility_type"],
			"material_cost": cost, "days": days, "ready": has_ready,
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

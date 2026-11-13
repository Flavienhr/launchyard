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

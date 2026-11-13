class_name Simulation
extends RefCounted
## Game rules. Deterministic: same (state, commands, data) => same result.
## Daily resolution order is documented in sim/CLAUDE.md.
##
## Two ways in:
## - step(): pure, returns a new state. Used by tests, replays, balance runs.
## - apply_command() + end_day(): mutate a state in place. Used by the UI so the
##   player gets immediate feedback while planning. step() == both, in sequence.


static func new_game(data: GameData, game_seed: int) -> GameState:
	var state := GameState.new()
	state.game_seed = game_seed
	state.money = int(data.start["money"])
	for type in data.start["facilities"]:
		state.facilities.append(_new_facility(state, type, "ready", state.day))
	state.technicians_hired = int(data.start.get("technicians", 0))
	var assignments: Dictionary = data.start.get("assignments", {})
	for type in assignments:
		for facility in state.facilities:
			if facility["type"] == type:  # first instance of that type
				facility["assigned"] = int(assignments[type])
				break
	return state


static func step(state: GameState, commands: Array, data: GameData) -> StepResult:
	var next := state.copy()
	var events: Array = []
	for command in commands:
		events.append_array(apply_command(next, command, data))
	events.append_array(end_day(next, data))
	return StepResult.new(next, events)


# --- Planning phase ---------------------------------------------------------

static func apply_command(state: GameState, command: Command, data: GameData) -> Array:
	match command.type:
		Command.ORDER:
			return _apply_order(state, command.args, data)
		Command.BUILD:
			return _apply_build(state, command.args, data)
		Command.HIRE:
			return _apply_hire(state, command.args, data)
		Command.FIRE:
			return _apply_fire(state, command.args, data)
		Command.ASSIGN_STAFF:
			return _apply_assign_staff(state, command.args, data)
		Command.QUEUE_JOB:
			return _apply_queue_job(state, command.args, data)
		Command.CANCEL_JOB:
			return _apply_cancel_job(state, command.args)
	return [_rejected("unknown_command", command)]


static func _apply_order(state: GameState, args: Dictionary, data: GameData) -> Array:
	var supplier_id: String = args.get("supplier_id", "")
	var component_id: String = args.get("component_id", "")
	var quantity := int(args.get("quantity", 0))
	var entry := data.catalog_entry(supplier_id, component_id)
	if entry.is_empty():
		return [_rejected("not_in_catalog", Command.new(Command.ORDER, args))]
	if quantity <= 0:
		return [_rejected("invalid_quantity", Command.new(Command.ORDER, args))]
	var cost := quantity * int(entry["unit_price"])
	if cost > state.money:
		return [_rejected("insufficient_funds", Command.new(Command.ORDER, args))]

	state.money -= cost
	var order := {
		"id": state.next_order_id,
		"supplier_id": supplier_id,
		"component_id": component_id,
		"quantity": quantity,
		# Day on which the goods are available (start of day).
		"arrival_day": state.day + int(entry["lead_time_days"]),
		"delay_rolled": false,
	}
	state.next_order_id += 1
	state.pending_orders.append(order)
	return [_event("order_placed", {
		"order_id": order["id"], "cost": cost, "arrival_day": order["arrival_day"],
	})]


static func _apply_build(state: GameState, args: Dictionary, data: GameData) -> Array:
	var type: String = args.get("facility_type", "")
	var command := Command.new(Command.BUILD, args)
	var def: Dictionary = data.facilities.get(type, {})
	if def.is_empty() or not bool(def.get("buildable", false)):
		return [_rejected("not_buildable", command)]
	var count := 0
	for facility in state.facilities:
		if facility["type"] == type:
			count += 1  # "building" instances count too
	if count >= int(def.get("max_count", 0)):
		return [_rejected("max_count_reached", command)]
	var cost := int(def["build_cost"])
	if cost > state.money:
		return [_rejected("insufficient_funds", command)]

	state.money -= cost
	var instance := _new_facility(state, type, "building", state.day + int(def["build_days"]))
	state.facilities.append(instance)
	return [_event("facility_build_started", {
		"facility_id": instance["id"], "type": type, "cost": cost, "ready_day": instance["ready_day"],
	})]


static func _apply_hire(state: GameState, args: Dictionary, data: GameData) -> Array:
	var count := int(args.get("count", 0))
	var command := Command.new(Command.HIRE, args)
	var def: Dictionary = data.staff.get("technician", {})
	if count <= 0:
		return [_rejected("invalid_quantity", command)]
	if state.technicians_hired + count > int(def["max_technicians"]):
		return [_rejected("max_technicians", command)]
	var cost := count * int(def["hire_cost"])
	if cost > state.money:
		return [_rejected("insufficient_funds", command)]
	state.money -= cost
	state.technicians_hired += count
	return [_event("staff_hired", {"count": count, "cost": cost})]


static func _apply_fire(state: GameState, args: Dictionary, data: GameData) -> Array:
	var count := int(args.get("count", 0))
	var command := Command.new(Command.FIRE, args)
	if count <= 0:
		return [_rejected("invalid_quantity", command)]
	if count > state.technicians_hired - total_assigned(state):
		return [_rejected("staff_assigned", command)]
	var cost := count * int(data.staff["technician"]["fire_cost"])
	state.technicians_hired -= count
	state.money -= cost  # may go negative: severance is owed regardless
	return [_event("staff_fired", {"count": count, "cost": cost})]


static func _apply_assign_staff(state: GameState, args: Dictionary, data: GameData) -> Array:
	var facility_id := int(args.get("facility_id", 0))
	var count := int(args.get("count", 0))
	var command := Command.new(Command.ASSIGN_STAFF, args)
	var target: Dictionary = {}
	for facility in state.facilities:
		if facility["id"] == facility_id:
			target = facility
	if target.is_empty():
		return [_rejected("unknown_facility", command)]
	if target["status"] != "ready":
		return [_rejected("facility_not_ready", command)]
	var slots := int(data.facilities[target["type"]].get("slots", 0))
	if slots <= 0:
		return [_rejected("no_slots", command)]
	if count < 0:
		return [_rejected("invalid_quantity", command)]
	if count > slots:
		return [_rejected("too_many_for_slots", command)]
	if total_assigned(state) - int(target["assigned"]) + count > state.technicians_hired:
		return [_rejected("not_enough_staff", command)]
	target["assigned"] = count
	return [_event("staff_assigned", {"facility_id": facility_id, "count": count})]


static func _apply_queue_job(state: GameState, args: Dictionary, data: GameData) -> Array:
	var facility_id := int(args.get("facility_id", 0))
	var recipe_id: String = args.get("recipe_id", "")
	var count := int(args.get("count", 0))
	var command := Command.new(Command.QUEUE_JOB, args)
	var target := _find_facility(state, facility_id)
	if target.is_empty():
		return [_rejected("unknown_facility", command)]
	if target["status"] != "ready":
		return [_rejected("facility_not_ready", command)]
	var recipe: Dictionary = data.recipes.get(recipe_id, {})
	if recipe.is_empty():
		return [_rejected("unknown_recipe", command)]
	if recipe["facility_type"] != target["type"]:
		return [_rejected("wrong_facility", command)]
	if count <= 0:
		return [_rejected("invalid_quantity", command)]
	if target["jobs"].size() + count > int(data.staff["max_queue_length"]):
		return [_rejected("queue_full", command)]
	var events: Array = []
	for i in count:
		var job := {
			"id": state.next_job_id,
			"recipe_id": recipe_id,
			"started": false,
			"progress": 0,
			"blocked": "",  # last blocking reason already reported ("" = none)
		}
		state.next_job_id += 1
		target["jobs"].append(job)
		events.append(_event("job_queued", {
			"job_id": job["id"], "facility_id": facility_id, "recipe_id": recipe_id,
		}))
	return events


static func _apply_cancel_job(state: GameState, args: Dictionary) -> Array:
	var job_id := int(args.get("job_id", 0))
	var command := Command.new(Command.CANCEL_JOB, args)
	for facility in state.facilities:
		for i in facility["jobs"].size():
			var job: Dictionary = facility["jobs"][i]
			if job["id"] != job_id:
				continue
			if job["started"]:
				return [_rejected("job_started", command)]
			facility["jobs"].remove_at(i)
			return [_event("job_cancelled", {
				"job_id": job_id, "facility_id": facility["id"], "recipe_id": job["recipe_id"],
			})]
	return [_rejected("unknown_job", command)]


static func _find_facility(state: GameState, facility_id: int) -> Dictionary:
	for facility in state.facilities:
		if facility["id"] == facility_id:
			return facility
	return {}


static func _new_facility(state: GameState, type: String, status: String, ready_day: int) -> Dictionary:
	var instance := {
		"id": state.next_facility_id,
		"type": type,
		"status": status,
		"ready_day": ready_day,
		"assigned": 0,  # technicians assigned (spec 001 R4)
		"jobs": [],     # job queue, see _apply_queue_job (head = active job)
	}
	state.next_facility_id += 1
	return instance


# --- End of day resolution --------------------------------------------------

static func end_day(state: GameState, data: GameData) -> Array:
	var events: Array = []
	events.append_array(_resolve_deliveries(state, data))
	events.append_array(_resolve_constructions(state))
	events.append_array(_resolve_production(state, data))
	events.append_array(_resolve_finances(state, data))
	state.day += 1
	return events


static func _resolve_deliveries(state: GameState, data: GameData) -> Array:
	var rng := SimRng.for_stream(state, SimRng.DELIVERIES)
	var events: Array = []
	var still_pending: Array = []
	var tomorrow := state.day + 1
	for order in state.pending_orders:
		if order["arrival_day"] > tomorrow:
			still_pending.append(order)
			continue

		# Supplier reliability: rolled once per order, when it is due.
		if not order["delay_rolled"]:
			order["delay_rolled"] = true
			var supplier: Dictionary = data.suppliers[order["supplier_id"]]
			if rng.randf() < float(supplier["delay_chance"]):
				var delay := int(supplier["delay_days"])
				order["arrival_day"] += delay
				events.append(_event("delivery_delayed", {
					"order_id": order["id"], "supplier_id": order["supplier_id"],
					"delay_days": delay, "arrival_day": order["arrival_day"],
				}))
				still_pending.append(order)
				continue

		var component_id: String = order["component_id"]
		var units := int(order["quantity"]) * int(data.components[component_id]["storage_units"])
		if units > storage_capacity(state, data) - storage_used(state, data):
			# The truck waits at the gate and retries tomorrow.
			events.append(_event("warehouse_full", {"order_id": order["id"]}))
			still_pending.append(order)
			continue

		state.stock[component_id] = int(state.stock.get(component_id, 0)) + int(order["quantity"])
		events.append(_event("delivery_received", {
			"order_id": order["id"], "component_id": component_id, "quantity": order["quantity"],
		}))
	state.pending_orders = still_pending
	return events


static func _resolve_constructions(state: GameState) -> Array:
	var events: Array = []
	for facility in state.facilities:  # ascending id: stable order
		if facility["status"] == "building" and facility["ready_day"] <= state.day + 1:
			facility["status"] = "ready"
			events.append(_event("facility_built", {
				"facility_id": facility["id"], "type": facility["type"],
			}))
	return events


## Step 4 (spec 001 R5). Instances by ascending id (stable stock contention).
## At most one job completes per instance per day.
static func _resolve_production(state: GameState, data: GameData) -> Array:
	var events: Array = []
	for facility in state.facilities:
		if facility["status"] != "ready" or facility["jobs"].is_empty():
			continue
		var job: Dictionary = facility["jobs"][0]
		var recipe: Dictionary = data.recipes[job["recipe_id"]]
		if not job["started"]:
			if _start_job(state, data, facility, job, recipe, events):
				continue
		var def: Dictionary = data.facilities[facility["type"]]
		if job["progress"] < int(recipe["work_points"]):
			job["progress"] += mini(int(facility["assigned"]), int(def["slots"])) * int(def["productivity_per_slot"])
		if job["progress"] >= int(recipe["work_points"]):
			_finish_job(state, data, facility, job, recipe, events)
	return events


## Returns true if the job stays blocked. Blocking is reported once per reason.
static func _start_job(state: GameState, data: GameData, facility: Dictionary,
		job: Dictionary, recipe: Dictionary, events: Array) -> bool:
	var missing := {}
	for component_id in recipe["inputs"]:
		var short := int(recipe["inputs"][component_id]) - int(state.stock.get(component_id, 0))
		if short > 0:
			missing[component_id] = short
	var reason := ""
	if not missing.is_empty():
		reason = "missing_inputs"
	elif recipe["output"].has("launcher_model") and not _hall_has_room(state, data, facility):
		reason = "hall_occupied"
	if reason != "":
		if job["blocked"] != reason:
			job["blocked"] = reason
			events.append(_event("job_blocked", {"job_id": job["id"], "reason": reason, "missing": missing}))
		return true
	var consumed := {}
	for component_id in recipe["inputs"]:
		var qty := int(recipe["inputs"][component_id])
		state.stock[component_id] = int(state.stock.get(component_id, 0)) - qty
		consumed[component_id] = qty
	job["started"] = true
	job["blocked"] = ""
	events.append(_event("job_started", {
		"job_id": job["id"], "facility_id": facility["id"], "consumed": consumed,
	}))
	return false


static func _finish_job(state: GameState, data: GameData, facility: Dictionary,
		job: Dictionary, recipe: Dictionary, events: Array) -> void:
	var output: Dictionary = recipe["output"]
	if output.has("component_id"):
		var component_id: String = output["component_id"]
		var qty := int(output["quantity"])
		var units := qty * int(data.components[component_id]["storage_units"])
		if units > storage_capacity(state, data) - storage_used(state, data):
			if job["blocked"] != "output_blocked":
				job["blocked"] = "output_blocked"
				events.append(_event("output_blocked", {"job_id": job["id"], "facility_id": facility["id"]}))
			return
		state.stock[component_id] = int(state.stock.get(component_id, 0)) + qty
	else:
		var launcher := {
			"id": state.next_launcher_id,
			"model": output["launcher_model"],
			"location_facility_id": facility["id"],
		}
		state.next_launcher_id += 1
		state.launchers.append(launcher)
		events.append(_event("launcher_assembled", {
			"launcher_id": launcher["id"], "model": launcher["model"], "facility_id": facility["id"],
		}))
	facility["jobs"].pop_front()
	events.append(_event("job_completed", {"job_id": job["id"], "output": output.duplicate(true)}))


static func _hall_has_room(state: GameState, data: GameData, facility: Dictionary) -> bool:
	var capacity := int(data.facilities[facility["type"]]["launcher_capacity"])
	var present := 0
	for launcher in state.launchers:
		if launcher["location_facility_id"] == facility["id"]:
			present += 1
	return present < capacity


static func _resolve_finances(state: GameState, data: GameData) -> Array:
	var upkeep := 0
	for facility in state.facilities:
		if facility["status"] == "ready":  # spec 001 R2: no upkeep while building
			upkeep += int(data.facilities[facility["type"]]["upkeep_per_day"])
	var salaries := 0
	if state.technicians_hired > 0:
		salaries = state.technicians_hired * int(data.staff["technician"]["technician_salary_per_day"])
	state.money -= upkeep + salaries
	var events: Array = [_event("daily_costs", {"day": state.day, "upkeep": upkeep, "salaries": salaries})]
	if state.money < 0:
		events.append(_event("negative_balance", {"money": state.money}))
	return events


# --- Queries (read-only helpers, also used by the UI) -----------------------

static func storage_capacity(state: GameState, data: GameData) -> int:
	var capacity := 0
	for facility in state.facilities:
		if facility["status"] == "ready":
			capacity += int(data.facilities[facility["type"]].get("storage_capacity", 0))
	return capacity


static func total_assigned(state: GameState) -> int:
	var total := 0
	for facility in state.facilities:
		total += int(facility["assigned"])
	return total


static func storage_used(state: GameState, data: GameData) -> int:
	var used := 0
	for component_id in state.stock:
		used += int(state.stock[component_id]) * int(data.components[component_id]["storage_units"])
	return used


# --- Events -----------------------------------------------------------------

static func _event(type: String, fields: Dictionary) -> Dictionary:
	var event := fields.duplicate()
	event["type"] = type
	return event


static func _rejected(reason: String, command: Command) -> Dictionary:
	return _event("command_rejected", {"reason": reason, "command": command.to_dict()})

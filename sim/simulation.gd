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
		state.facilities.append(_new_facility(state, type, "ready", state.day, data))
	state.technicians_hired = int(data.start.get("technicians", 0))
	var assignments: Dictionary = data.start.get("assignments", {})
	for type in assignments:
		for facility in state.facilities:
			if facility["type"] == type:  # first instance of that type
				facility["assigned"] = int(assignments[type])
				break
	state.reputation = int(data.contracts.get("reputation_start", 0))
	var rng := SimRng.for_stream(state, SimRng.CONTRACTS)  # day 0
	for i in int(data.contracts.get("initial_offers", 0)):
		_add_offer(state, rng, data, state.day)
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
	if state.game_over:  # spec 004 R4
		return [_rejected("game_over", command)]
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
		Command.SCHEDULE_LAUNCH:
			return _apply_schedule_launch(state, command.args, data)
		Command.RESCHEDULE_LAUNCH:
			return _apply_reschedule_launch(state, command.args)
		Command.CANCEL_LAUNCH:
			return _apply_cancel_launch(state, command.args)
		Command.ACCEPT_CONTRACT:
			return _apply_accept_contract(state, command.args, data)
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
	var instance := _new_facility(state, type, "building", state.day + int(def["build_days"]), data)
	state.facilities.append(instance)
	return [_event("facility_build_started", {
		"facility_id": instance["id"], "facility_type": type, "cost": cost, "ready_day": instance["ready_day"],
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


# --- Launch scheduling (spec 003 R2) ----------------------------------------

## Pad states (facility "pad_state", separate from the build "status" which stays
## building/ready): "free", "occupied" = a launcher stands on it,
## "refurbishing" = unavailable until refurb_until_day.
const PAD_FREE := "free"
const PAD_OCCUPIED := "occupied"
const PAD_REFURBISHING := "refurbishing"


## A launch pad is a facility type that defines a rollout duration.
static func is_pad(facility: Dictionary, data: GameData) -> bool:
	return data.facilities[facility["type"]].has("rollout_days")


static func _find_by_id(items: Array, id: int) -> Dictionary:
	for item in items:
		if item["id"] == id:
			return item
	return {}


static func _launch_for(state: GameState, key: String, id: int) -> Dictionary:
	for launch in state.launches:
		if launch[key] == id:
			return launch
	return {}


static func _apply_schedule_launch(state: GameState, args: Dictionary, data: GameData) -> Array:
	var command := Command.new(Command.SCHEDULE_LAUNCH, args)
	var launcher := _find_by_id(state.launchers, int(args.get("launcher_id", 0)))
	var pad := _find_facility(state, int(args.get("pad_id", 0)))
	var contract := _find_by_id(state.contracts, int(args.get("contract_id", 0)))
	var launch_day := int(args.get("launch_day", 0))
	if launcher.is_empty() or not _launch_for(state, "launcher_id", launcher["id"]).is_empty():
		return [_rejected("launcher_unavailable", command)]
	if pad.is_empty() or not is_pad(pad, data):
		return [_rejected("pad_unavailable", command)]
	var on_pad: bool = pad["launcher_id"] == launcher["id"]
	if pad["status"] != "ready":
		return [_rejected("pad_unavailable", command)]  # still under construction
	if not (pad["pad_state"] == PAD_FREE or (pad["pad_state"] == PAD_OCCUPIED and on_pad)):
		return [_rejected("pad_unavailable", command)]
	if not on_pad and _is_on_a_pad(state, data, launcher):
		return [_rejected("pad_unavailable", command)]  # no moving between pads in phase 2
	if contract.is_empty() or contract["status"] != ContractRules.ACTIVE \
			or not _launch_for(state, "contract_id", contract["id"]).is_empty():
		return [_rejected("contract_unavailable", command)]
	var site := data.active_site()
	var orbit: Dictionary = data.orbits.get(contract["orbit"], {})
	if orbit.is_empty() or not LaunchRules.is_orbit_reachable(orbit, site):
		return [_rejected("orbit_unreachable", command)]
	var model: Dictionary = data.launchers.get(launcher["model"], {})
	if int(contract["payload_kg"]) > LaunchRules.payload_capacity(model, contract["orbit"], site):
		return [_rejected("payload_too_heavy", command)]
	var lead := 1 if on_pad else int(data.facilities[pad["type"]]["rollout_days"])
	if launch_day < state.day + lead:
		return [_rejected("too_early", command)]
	if launch_day > int(contract["deadline_day"]):
		return [_rejected("after_deadline", command)]
	var insured := bool(args.get("insured", false))
	var premium := 0
	if insured:  # spec 003 decision 1: premium debited now, not refunded on cancel
		premium = LaunchRules.insurance_premium(contract, data)
		if premium > state.money:
			return [_rejected("insufficient_funds", command)]

	launcher["location_facility_id"] = pad["id"]  # leaves the hall now (decision 4)
	pad["pad_state"] = PAD_OCCUPIED
	pad["launcher_id"] = launcher["id"]
	var launch := {
		"id": state.next_launch_id, "launcher_id": launcher["id"], "pad_id": pad["id"],
		"contract_id": contract["id"], "launch_day": launch_day, "scrubs": 0, "insured": insured,
	}
	state.next_launch_id += 1
	state.launches.append(launch)
	state.money -= premium
	var events := [_event("launch_scheduled", {"launch_id": launch["id"], "launch_day": launch_day})]
	if insured:
		events.append(_event("insurance_paid", {"launch_id": launch["id"], "premium": premium}))
	return events


static func _is_on_a_pad(state: GameState, data: GameData, launcher: Dictionary) -> bool:
	var location := _find_facility(state, int(launcher["location_facility_id"]))
	return not location.is_empty() and is_pad(location, data)


static func _apply_reschedule_launch(state: GameState, args: Dictionary) -> Array:
	var command := Command.new(Command.RESCHEDULE_LAUNCH, args)
	var launch := _find_by_id(state.launches, int(args.get("launch_id", 0)))
	var launch_day := int(args.get("launch_day", 0))
	if launch.is_empty():
		return [_rejected("unknown_launch", command)]
	if launch_day < state.day + 1:
		return [_rejected("too_early", command)]
	var contract := _find_by_id(state.contracts, launch["contract_id"])
	if launch_day > int(contract["deadline_day"]):
		return [_rejected("after_deadline", command)]
	launch["launch_day"] = launch_day
	return [_event("launch_rescheduled", {"launch_id": launch["id"], "launch_day": launch_day})]


## The launcher stays on its pad (no return to the hall in phase 2).
static func _apply_cancel_launch(state: GameState, args: Dictionary) -> Array:
	var launch_id := int(args.get("launch_id", 0))
	for i in state.launches.size():
		if state.launches[i]["id"] == launch_id:
			var launch: Dictionary = state.launches[i]
			state.launches.remove_at(i)
			return [_event("launch_cancelled", {"launch_id": launch_id, "launch_day": launch["launch_day"]})]
	return [_rejected("unknown_launch", Command.new(Command.CANCEL_LAUNCH, args))]


## Step 5, first part (spec 003 R5): pads whose refurbishment ends tomorrow
## become free again, before the day's launches. Resolved as of tomorrow, like deliveries.
static func _resolve_pads(state: GameState) -> Array:
	var events: Array = []
	for facility in state.facilities:
		if facility.get("pad_state") == PAD_REFURBISHING and facility["refurb_until_day"] <= state.day + 1:
			facility["pad_state"] = PAD_FREE
			events.append(_event("pad_ready", {"pad_id": facility["id"]}))
	return events


## Step 5, second part (spec 003 R3-R5): launches of the day, ascending id.
## Weather is drawn first (WEATHER stream), then reliability (LAUNCH stream).
## Costs are accumulated in `costs` and debited at step 8.
static func _resolve_launches(state: GameState, data: GameData, costs: Dictionary) -> Array:
	var events: Array = []
	var weather := SimRng.for_stream(state, SimRng.WEATHER)
	var launch_rng := SimRng.for_stream(state, SimRng.LAUNCH)
	var site := data.active_site()
	for launch in state.launches.duplicate():  # copy: resolved launches are removed
		if launch["launch_day"] != state.day:
			continue
		var pad := _find_facility(state, launch["pad_id"])
		var pad_type: Dictionary = data.facilities[pad["type"]]
		var season := LaunchRules.season_of(state.day, site)
		if weather.randf() < float(site["scrub_chance_by_season"][season]):
			launch["launch_day"] += int(pad_type["scrub_recycle_days"])
			launch["scrubs"] += 1
			costs["scrub_costs"] += int(pad_type["scrub_cost"])
			events.append(_event("launch_scrubbed", {"launch_id": launch["id"], "season": season,
				"new_launch_day": launch["launch_day"], "scrubs": launch["scrubs"]}))
			continue
		var launcher := _find_by_id(state.launchers, launch["launcher_id"])
		var model_id: String = launcher["model"]
		var stats: Dictionary = state.model_stats.get(model_id, {"successes": 0})
		var reliability := LaunchRules.model_reliability(data.launchers[model_id], int(stats["successes"]))
		var fields := {"launch_id": launch["id"], "contract_id": launch["contract_id"], "reliability": reliability}
		var refurb_days: int
		if launch_rng.randf() < reliability:
			stats["successes"] = int(stats["successes"]) + 1
			state.model_stats[model_id] = stats
			events.append(_event("launch_succeeded", fields))
			events.append_array(complete_contract(state, data, launch["contract_id"]))
			refurb_days = int(pad_type["refurb_days"])
			costs["refurb_costs"] += int(pad_type["refurb_cost"])
		else:  # reliability is unchanged by a failure (decision 3)
			events.append(_event("launch_failed", fields))
			events.append_array(fail_contract(state, data, launch["contract_id"], ContractRules.LAUNCH_FAILED))
			refurb_days = int(pad_type["refurb_days_after_failure"])
			costs["refurb_costs"] += int(pad_type["refurb_cost_after_failure"])
			if bool(launch.get("insured", false)):  # spec 003 decision 1: failure only
				var payout := LaunchRules.insurance_payout(data.launchers[model_id], data)
				state.money += payout
				events.append(_event("insurance_payout", {"launch_id": launch["id"], "amount": payout}))
		state.launchers.erase(launcher)  # consumed in both cases
		state.launches.erase(launch)
		start_refurbishment(pad, state.day + refurb_days)
	return events


## Puts a pad into refurbishment until `until_day` (used by launch resolution, issue #15).
static func start_refurbishment(pad: Dictionary, until_day: int) -> void:
	pad["pad_state"] = PAD_REFURBISHING
	pad["refurb_until_day"] = until_day
	pad["launcher_id"] = 0


## Spec 002 R3. Checks in spec order; the advance is credited immediately.
static func _apply_accept_contract(state: GameState, args: Dictionary, data: GameData) -> Array:
	var command := Command.new(Command.ACCEPT_CONTRACT, args)
	var contract := ContractRules.find(state, int(args.get("contract_id", 0)))
	var error := ContractRules.acceptance_error(state, data, contract)
	if error != "":
		return [_rejected(error, command)]
	contract["status"] = ContractRules.ACTIVE
	state.money += int(contract["advance"])
	return [_event("contract_accepted", {
		"contract_id": contract["id"], "advance": contract["advance"],
	})]


static func _find_facility(state: GameState, facility_id: int) -> Dictionary:
	for facility in state.facilities:
		if facility["id"] == facility_id:
			return facility
	return {}


static func _new_facility(state: GameState, type: String, status: String, ready_day: int, data: GameData) -> Dictionary:
	var instance := {
		"id": state.next_facility_id,
		"type": type,
		"status": status,
		"ready_day": ready_day,
		"assigned": 0,  # technicians assigned (spec 001 R4)
		"jobs": [],     # job queue, see _apply_queue_job (head = active job)
		"launcher_id": 0,       # launch pads: launcher standing on the pad (0 = none), spec 003 R2
		"refurb_until_day": 0,  # launch pads: first day available again after refurbishment (R5)
	}
	if data.facilities[type].has("rollout_days"):
		instance["pad_state"] = PAD_FREE  # pads only; "status" stays building/ready
	state.next_facility_id += 1
	return instance


# --- End of day resolution --------------------------------------------------

static func end_day(state: GameState, data: GameData) -> Array:
	if state.game_over:  # spec 004 R4 : la partie est finie, le jour n'avance plus
		return []
	var events: Array = []
	events.append_array(_resolve_deliveries(state, data))
	events.append_array(_resolve_constructions(state))
	events.append_array(_resolve_production(state, data))
	events.append_array(_resolve_pads(state))
	var launch_costs := {"scrub_costs": 0, "refurb_costs": 0}  # paid at step 8
	events.append_array(_resolve_launches(state, data, launch_costs))
	events.append_array(_resolve_market(state, data))
	events.append_array(_resolve_contract_deadlines(state, data))
	events.append_array(_resolve_finances(state, data, launch_costs))
	events.append_array(_resolve_bankruptcy(state, data))
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
				"facility_id": facility["id"], "facility_type": facility["type"],
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


## Step 7: expire stale offers, then maybe generate one (spec 002 R2).
## Resolved as of tomorrow, like deliveries: the day this step opens.
static func _resolve_market(state: GameState, data: GameData) -> Array:
	var events: Array = []
	if data.contracts.is_empty():
		return events
	var tomorrow := state.day + 1
	for contract in state.contracts:
		if contract["status"] == ContractRules.OFFER and contract["offer_expires_day"] <= tomorrow:
			contract["status"] = ContractRules.EXPIRED
			events.append(_event("offer_expired", {"contract_id": contract["id"]}))
	var rng := SimRng.for_stream(state, SimRng.CONTRACTS)
	if ContractRules.visible_offers(state) < int(data.contracts["offer_slots"]) \
			and rng.randf() < float(data.contracts["offer_spawn_chance"]):
		var offer := _add_offer(state, rng, data, tomorrow)
		if not offer.is_empty():
			events.append(_event("offer_generated", {
				"contract_id": offer["id"], "orbit": offer["orbit"], "payload_kg": offer["payload_kg"],
				"payment": offer["payment"], "deadline_day": offer["deadline_day"],
			}))
	return events


static func _add_offer(state: GameState, rng: RandomNumberGenerator, data: GameData, day: int) -> Dictionary:
	var offer := ContractRules.generate_offer(rng, data, state.reputation, data.active_site(), day)
	if offer.is_empty():
		return offer
	offer["id"] = state.next_contract_id
	state.next_contract_id += 1
	state.contracts.append(offer)
	return offer


## Step 8 (spec 002 R4): active contracts whose deadline day is over fail.
## Launches (step 5) run before, so a success on deadline_day still counts.
static func _resolve_contract_deadlines(state: GameState, data: GameData) -> Array:
	var events: Array = []
	if data.contracts.is_empty():
		return events
	for contract in state.contracts:  # ascending id: stable order
		if contract["status"] == ContractRules.ACTIVE and contract["deadline_day"] <= state.day:
			events.append_array(fail_contract(state, data, contract["id"], ContractRules.DEADLINE_MISSED))
			events.append_array(_cancel_launches_of(state, contract["id"]))
	return events


## A contract that ended takes its pending launch with it; the launcher stays on the pad.
static func _cancel_launches_of(state: GameState, contract_id: int) -> Array:
	var events: Array = []
	for launch in state.launches.duplicate():
		if launch["contract_id"] == contract_id:
			state.launches.erase(launch)
			events.append(_event("launch_cancelled", {"launch_id": launch["id"], "launch_day": launch["launch_day"]}))
	return events


## Public entry point for spec 003 (successful launch). Pays the balance
## (payment - advance), marks the contract completed, applies rep_on_success.
## No-op ([]) if the contract is not active.
static func complete_contract(state: GameState, data: GameData, contract_id: int) -> Array:
	var contract := ContractRules.find(state, contract_id)
	if contract.is_empty() or contract["status"] != ContractRules.ACTIVE:
		return []
	var balance := int(contract["payment"]) - int(contract["advance"])
	state.money += balance
	contract["status"] = ContractRules.COMPLETED
	var events: Array = [_event("contract_completed", {
		"contract_id": contract_id, "balance_paid": balance,
	})]
	events.append(_change_reputation(state, data, int(data.contracts["rep_on_success"])))
	return events


## Public entry point for spec 003 (launcher failure) and the deadline rule.
## launch_failed: advance kept, no penalty. deadline_missed: advance refunded
## plus penalty. No-op ([]) if the contract is not active or the reason unknown.
static func fail_contract(state: GameState, data: GameData, contract_id: int, reason: String) -> Array:
	var contract := ContractRules.find(state, contract_id)
	if contract.is_empty() or contract["status"] != ContractRules.ACTIVE:
		return []
	var debited := 0
	var rep_delta := 0
	match reason:
		ContractRules.LAUNCH_FAILED:
			rep_delta = int(data.contracts["rep_on_launch_failure"])
		ContractRules.DEADLINE_MISSED:
			debited = int(contract["advance"]) + int(contract["penalty"])
			rep_delta = int(data.contracts["rep_on_deadline_missed"])
		_:
			return []
	state.money -= debited  # may go negative, like severance
	contract["status"] = ContractRules.FAILED
	var events: Array = [_event("contract_failed", {
		"contract_id": contract_id, "reason": reason, "amount_debited": debited,
	})]
	events.append(_change_reputation(state, data, rep_delta))
	return events


## Applies `delta` clamped (R5); the event carries the delta actually applied.
static func _change_reputation(state: GameState, data: GameData, delta: int) -> Dictionary:
	var before := state.reputation
	state.reputation = ContractRules.clamp_reputation(data, before + delta)
	return _event("reputation_changed", {
		"delta": state.reputation - before, "reputation": state.reputation,
	})


static func _resolve_finances(state: GameState, data: GameData, launch_costs := {}) -> Array:
	var upkeep := 0
	for facility in state.facilities:
		if facility["status"] == "ready":  # spec 001 R2: no upkeep while building
			upkeep += int(data.facilities[facility["type"]]["upkeep_per_day"])
	var salaries := 0
	if state.technicians_hired > 0:
		salaries = state.technicians_hired * int(data.staff["technician"]["technician_salary_per_day"])
	var scrub_costs: int = launch_costs.get("scrub_costs", 0)
	var refurb_costs: int = launch_costs.get("refurb_costs", 0)
	state.money -= upkeep + salaries + scrub_costs + refurb_costs
	var events: Array = [_event("daily_costs", {"day": state.day, "upkeep": upkeep, "salaries": salaries,
		"scrub_costs": scrub_costs, "refurb_costs": refurb_costs})]
	if state.money < 0:
		events.append(_event("negative_balance", {"money": state.money}))
	return events


# Spec 004 R1-R3. Règle désactivée si rules.json est absent (data.rules vide).
static func _resolve_bankruptcy(state: GameState, data: GameData) -> Array:
	if data.rules.is_empty():
		return []
	if state.money >= 0:
		state.days_in_debt = 0
		return []
	state.days_in_debt += 1
	var events: Array = []
	var grace_days := int(data.rules["bankruptcy_grace_days"])
	if state.days_in_debt == int(data.rules["bankruptcy_warning_days"]):
		events.append(_event("bankruptcy_warning", {"days_left": grace_days - state.days_in_debt}))
	if state.days_in_debt == grace_days:
		state.game_over = true
		events.append(_event("game_over", {"reason": "bankruptcy"}))
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
	assert(not fields.has("type"), "event field 'type' is reserved for the event type")
	var event := fields.duplicate()
	event["type"] = type
	return event


static func _rejected(reason: String, command: Command) -> Dictionary:
	return _event("command_rejected", {"reason": reason, "command": command.to_dict()})

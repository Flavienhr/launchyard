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


static func _new_facility(state: GameState, type: String, status: String, ready_day: int) -> Dictionary:
	var instance := {
		"id": state.next_facility_id,
		"type": type,
		"status": status,
		"ready_day": ready_day,
		"assigned": 0,  # technicians assigned (spec 001 R4)
		"jobs": [],     # job queue: filled by a later issue
	}
	state.next_facility_id += 1
	return instance


# --- End of day resolution --------------------------------------------------

static func end_day(state: GameState, data: GameData) -> Array:
	var events: Array = []
	events.append_array(_resolve_deliveries(state, data))
	events.append_array(_resolve_constructions(state))
	events.append_array(_resolve_market(state, data))
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

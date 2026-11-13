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
	state.facilities = data.start["facilities"].duplicate()
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


# --- End of day resolution --------------------------------------------------

static func end_day(state: GameState, data: GameData) -> Array:
	var events: Array = []
	events.append_array(_resolve_deliveries(state, data))
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


static func _resolve_finances(state: GameState, data: GameData) -> Array:
	var upkeep := 0
	for facility_id in state.facilities:
		upkeep += int(data.facilities[facility_id]["upkeep_per_day"])
	state.money -= upkeep
	var events: Array = [_event("daily_costs", {"day": state.day, "upkeep": upkeep})]
	if state.money < 0:
		events.append(_event("negative_balance", {"money": state.money}))
	return events


# --- Queries (read-only helpers, also used by the UI) -----------------------

static func storage_capacity(state: GameState, data: GameData) -> int:
	var capacity := 0
	for facility_id in state.facilities:
		capacity += int(data.facilities[facility_id].get("storage_capacity", 0))
	return capacity


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

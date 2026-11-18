class_name SupplyRules
extends RefCounted
## Spec 007 R4-R8: supply contracts (framework agreements with a supplier).
## Pure rules on state + data; Simulation calls them at step 1 (commands) and
## step 2 (dispatch of the scheduled deliveries, before the orders in transit).

## Unit of the percentages in supply_contracts.json (not a balance value).
const PCT := 100
## Definition of a game month in spec 007 R4 (monthly_value = catalog value brought back to 28 days): a unit, not a balance value, so it stays out of data/.
const REFERENCE_DAYS := 28

const ACTIVE := "active"
const COMPLETED := "completed"
const TERMINATED := "terminated"
const FIXED := "fixed"
const INDEXED := "indexed"


static func params(data: GameData) -> Dictionary:
	return data.supply_contracts


## Rounded half up, integers only.
static func _pct_of(value: int, pct: int) -> int:
	return (value * pct + PCT / 2) / PCT


static func find(state: GameState, contract_id: int) -> Dictionary:
	for contract in state.supply_contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


static func active_count(state: GameState) -> int:
	var count := 0
	for contract in state.supply_contracts:
		if contract["status"] == ACTIVE:
			count += 1
	return count


## Rejection reason of a signature (R4 order), or "" when acceptable.
static func sign_rejection(state: GameState, data: GameData, args: Dictionary) -> String:
	var p := params(data)
	var supplier_id: String = args.get("supplier_id", "")
	var component_id: String = args.get("component_id", "")
	var entry := data.catalog_entry(supplier_id, component_id)
	if entry.is_empty():
		return "not_in_catalog"
	var terms: Dictionary = entry.get("contract_terms", {})
	if terms.is_empty():
		return "contracts_not_offered"
	var quantity := int(args.get("quantity", 0))
	if quantity < int(terms["min_quantity"]) or quantity > int(terms["max_quantity"]):
		return "invalid_quantity"
	if not int(args.get("period_days", 0)) in p.get("period_options_days", []):
		return "invalid_period"
	var deliveries := int(args.get("deliveries", 0))
	if deliveries < int(p.get("min_deliveries", 1)) or deliveries > int(p.get("max_deliveries", 0)):
		return "invalid_duration"
	if not str(args.get("pricing", "")) in [FIXED, INDEXED]:
		return "invalid_pricing"
	for contract in state.supply_contracts:
		if contract["status"] == ACTIVE and contract["supplier_id"] == supplier_id \
				and contract["component_id"] == component_id:
			return "duplicate_contract"
	if active_count(state) >= int(p.get("max_supply_contracts", 0)):
		return "too_many_supply_contracts"
	return ""


## Volume discount of a contract (R4): largest tier reached, 0 if none.
static func discount_pct(data: GameData, entry: Dictionary, quantity: int, period_days: int) -> int:
	var monthly_value := quantity * int(entry["unit_price"]) * REFERENCE_DAYS / period_days
	var best := 0
	for tier in params(data).get("volume_discount_tiers", []):
		if monthly_value >= int(tier["min_value"]):
			best = maxi(best, int(tier["pct"]))
	return best


## Price percentage applied on the spot price (R4).
static func price_pct(data: GameData, discount: int, pricing: String, priority: bool) -> int:
	var p := params(data)
	var pct := PCT - discount
	if priority:
		pct += int(p["priority_premium_pct"])
	if pricing == FIXED:
		pct += int(p["fixed_premium_pct"])
	return pct


## Unit price the contract would pay today (fixed: frozen price; indexed: spot of the day).
static func current_unit_price(state: GameState, data: GameData, contract: Dictionary) -> int:
	if contract["pricing"] == FIXED:
		return int(contract["contract_unit_price"])
	var entry := data.catalog_entry(contract["supplier_id"], contract["component_id"])
	var spot := MarketRules.spot_price(state, data, int(entry["unit_price"]), contract["component_id"])
	return _pct_of(spot, int(contract["price_pct"]))


## Deliveries still to come (a skipped one not yet due counts as done, R8).
static func remaining_deliveries(contract: Dictionary) -> int:
	return int(contract["deliveries"]) - int(contract["deliveries_done"]) - (1 if contract["skip_next"] else 0)


static func skip_cost(state: GameState, data: GameData, contract: Dictionary) -> int:
	return int(contract["quantity"]) * current_unit_price(state, data, contract) \
		* int(params(data)["take_or_pay_pct"]) / PCT


static func termination_fee(state: GameState, data: GameData, contract: Dictionary) -> int:
	return remaining_deliveries(contract) * int(contract["quantity"]) \
		* current_unit_price(state, data, contract) * int(params(data)["termination_fee_pct"]) / PCT


static func sign(state: GameState, data: GameData, args: Dictionary) -> Array:
	var command := Command.new(Command.SIGN_SUPPLY_CONTRACT, args)
	var reason := sign_rejection(state, data, args)
	if reason != "":
		return [Simulation._rejected(reason, command)]
	var supplier_id: String = args["supplier_id"]
	var component_id: String = args["component_id"]
	var entry := data.catalog_entry(supplier_id, component_id)
	var quantity := int(args["quantity"])
	var period_days := int(args["period_days"])
	var pricing: String = args["pricing"]
	var priority := bool(args.get("priority", false))
	var discount := discount_pct(data, entry, quantity, period_days)
	var contract := {
		"id": state.next_supply_contract_id,
		"supplier_id": supplier_id,
		"component_id": component_id,
		"quantity": quantity,
		"period_days": period_days,
		"deliveries": int(args["deliveries"]),
		"deliveries_done": 0,
		"next_delivery_day": state.day + int(entry["lead_time_days"]),
		"pricing": pricing,
		"priority": priority,
		"price_pct": price_pct(data, discount, pricing, priority),
		"discount_pct": discount,
		"skip_next": false,
		"invoiced_total": 0,  # sum of the shipment invoices (spec 009 R3)
		"status": ACTIVE,
	}
	var unit_price: Variant = null
	if pricing == FIXED:
		var spot := MarketRules.spot_price(state, data, int(entry["unit_price"]), component_id)
		contract["contract_unit_price"] = _pct_of(spot, int(contract["price_pct"]))
		unit_price = contract["contract_unit_price"]
	state.next_supply_contract_id += 1
	state.supply_contracts.append(contract)
	return [Simulation._event("supply_contract_signed", {
		"contract_id": contract["id"], "supplier_id": supplier_id, "component_id": component_id,
		"unit_price": unit_price, "discount_pct": discount,
	})]


static func skip(state: GameState, data: GameData, args: Dictionary) -> Array:
	var command := Command.new(Command.SKIP_SUPPLY_DELIVERY, args)
	var contract := find(state, int(args.get("contract_id", 0)))
	if contract.is_empty() or contract["status"] != ACTIVE:
		return [Simulation._rejected("unknown_contract", command)]
	if contract["skip_next"]:
		return [Simulation._rejected("already_skipped", command)]
	if int(contract["next_delivery_day"]) - state.day < int(params(data)["skip_notice_days"]):
		return [Simulation._rejected("notice_too_short", command)]
	var cost := skip_cost(state, data, contract)
	if cost > state.money:
		return [Simulation._rejected("insufficient_funds", command)]
	state.money -= cost
	contract["skip_next"] = true
	return [Simulation._event("supply_delivery_skipped", {
		"contract_id": contract["id"], "delivery_day": contract["next_delivery_day"], "cost": cost,
	})]


static func terminate(state: GameState, data: GameData, args: Dictionary) -> Array:
	var command := Command.new(Command.TERMINATE_SUPPLY_CONTRACT, args)
	var contract := find(state, int(args.get("contract_id", 0)))
	if contract.is_empty() or contract["status"] != ACTIVE:
		return [Simulation._rejected("unknown_contract", command)]
	var fee := termination_fee(state, data, contract)
	if fee > state.money:
		return [Simulation._rejected("insufficient_funds", command)]
	state.money -= fee
	contract["status"] = TERMINATED
	return [Simulation._event("supply_contract_terminated", {"contract_id": contract["id"], "fee": fee})]


## Step 2, before the orders in transit (R5): ships the deliveries due tomorrow.
## Contracts by ascending id (stable order of the new orders' ids).
static func dispatch_due(state: GameState, data: GameData) -> Array:
	var events: Array = []
	var tomorrow := state.day + 1
	for contract in state.supply_contracts:
		if contract["status"] != ACTIVE or int(contract["next_delivery_day"]) > tomorrow:
			continue
		if contract["skip_next"]:
			contract["skip_next"] = false  # take-or-pay already paid (R7)
		else:
			_ship(state, data, contract, events)
		contract["deliveries_done"] += 1
		if contract["deliveries_done"] == contract["deliveries"]:
			contract["status"] = COMPLETED
			events.append(Simulation._event("supply_contract_completed", {"contract_id": contract["id"]}))
		else:
			contract["next_delivery_day"] += contract["period_days"]
	return events


static func _ship(state: GameState, data: GameData, contract: Dictionary, events: Array) -> void:
	var contracted := int(contract["quantity"])
	var shipped := contracted
	if not contract["priority"] and MarketRules.in_shortage(state, data, contract["component_id"]):
		shipped = contracted * int(params(data)["shortage_fill_pct"]) / PCT
		events.append(Simulation._event("supply_delivery_reduced", {
			"contract_id": contract["id"], "quantity_contracted": contracted, "quantity_shipped": shipped,
		}))
	if shipped <= 0:
		return
	var unit_price := current_unit_price(state, data, contract)
	var invoice := shipped * unit_price
	state.money -= invoice  # even below zero: bankruptcy follows spec 004
	contract["invoiced_total"] = int(contract.get("invoiced_total", 0)) + invoice
	var order := {
		"id": state.next_order_id,
		"supplier_id": contract["supplier_id"],
		"component_id": contract["component_id"],
		"quantity": shipped,
		"arrival_day": state.day + 1,
		"delay_rolled": false,
		"contract_id": contract["id"],
		"scheduled_day": state.day + 1,
		"invoice": invoice,
		"delay_days": 0,
		"waiting_for_space": false,
	}
	state.next_order_id += 1
	state.pending_orders.append(order)
	events.append(Simulation._event("supply_delivery_dispatched", {
		"contract_id": contract["id"], "order_id": order["id"], "quantity": shipped,
		"unit_price": unit_price, "invoice": invoice,
	}))


## Penalty owed by the supplier for a contract delivery received now (R6).
static func late_penalty(data: GameData, order: Dictionary) -> int:
	var p := params(data)
	var pct := mini(int(p["late_penalty_cap_pct"]), int(p["late_penalty_pct_per_day"]) * int(order["delay_days"]))
	return int(order["invoice"]) * pct / PCT


## Holding fees of the day (R6): contract deliveries waiting for warehouse space.
static func holding_fees(state: GameState, data: GameData) -> int:
	var fees := 0
	for order in state.pending_orders:
		if order.has("contract_id") and order.get("waiting_for_space", false):
			fees += int(params(data)["holding_fee_per_unit_per_day"]) * int(order["quantity"]) \
				* int(data.components[order["component_id"]]["storage_units"])
	return fees

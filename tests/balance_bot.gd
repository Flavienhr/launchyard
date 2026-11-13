class_name BalanceBot
extends RefCounted
## Scripted player for `make balance` (issue #20). One instance plays one game on
## the REAL data/, with one of two strategies:
##   buy_all  : chain contracts, buy the whole L1 bill of materials at the cheapest price.
##   workshop : build the tank shop on day 0, staff it, weld the tanks from steel
##              sheets, buy the rest. Until the shop is ready, tanks are bought.
## It only uses the public API (Simulation.apply_command / end_day, read-only
## Queries and state fields): it plays like a player, it does not poke at rules.
##
## Daily routine (identical for both strategies, only the tank sourcing differs):
##   1. sign the best-paying feasible offer while there is room under max_active_contracts;
##   2. workshop: hire / assign / queue the welding jobs once the shop is built;
##   3. order one launcher kit (and queue its assembly) when a signed contract
##      has no launcher in the pipeline and no assembly is still waiting for its parts;
##   4. schedule every unscheduled launcher on a free pad for the earliest deadline;
##   5. end the day.
##
## Feasibility estimate used before signing (all values come from data/, no tuning):
##   kit_lead  = max over the kit's components of ceil(lead_time + delay_chance * delay_days)
##               at the cheapest supplier (expected delay, not the worst case)
##   assembly  = ceil(work_points / (slots * productivity_per_slot)) of the hall
##   cycle     = max(kit_lead, assembly)  (the next kit is ordered when the previous
##                                         assembly starts, so launchers come one cycle apart)
##   ready_day = today + ahead * cycle + kit_lead + assembly + rollout_days
##   with `ahead` = signed contracts that have no scheduled launch yet.
##   An offer is signed only if ready_day <= its deadline_day.

const BUY_ALL := "buy_all"
const WORKSHOP := "workshop"

# Content ids the strategies are about (not balance values).
const LAUNCHER_RECIPE := "assemble_l1"
const TANK_RECIPE := "weld_tank"
const WORKSHOP_TYPE := "tank_shop"

## Events left out of the verbose journal (one per day or pure market noise).
const QUIET := ["daily_costs", "offer_generated", "offer_expired", "reputation_changed", "pad_ready"]

var strategy: String
var data: GameData
var state: GameState

# Results of the run.
var completed := 0
var failed_launch := 0
var failed_deadline := 0
var scrubs := 0
var signed := 0
var first_shot_day := -1
var money_at_shot: Array[int] = []  # money at the end of the day of the n-th shot
var rejections := {}                # reason -> count (a non-empty dict hints at a bot bug)
var log: Array[String] = []

var _tanks_to_weld := 0
var _workshop_id := 0


func _init(p_strategy: String, p_data: GameData, game_seed: int) -> void:
	strategy = p_strategy
	data = p_data
	state = Simulation.new_game(data, game_seed)


## Plays until `days` days have elapsed, or bankruptcy.
func play(days: int) -> void:
	if strategy == WORKSHOP:
		var events := _apply(Command.build(WORKSHOP_TYPE))
		if events[0]["type"] == "facility_build_started":
			_workshop_id = int(events[0]["facility_id"])
	while state.day < days and not state.game_over:
		_sign_contracts()
		if strategy == WORKSHOP:
			_run_workshop()
		_order_kit()
		_schedule_launches()
		_observe_day(Simulation.end_day(state, data))


func _apply(command: Command) -> Array:
	var events := Simulation.apply_command(state, command, data)
	for event in events:
		if event["type"] == "command_rejected":
			var reason: String = event["reason"]
			rejections[reason] = int(rejections.get(reason, 0)) + 1
			log.append("J%-3d REJECTED %s" % [state.day, JSON.stringify(event)])
	return events


## `events` come from end_day, which has already moved state.day to the next day.
func _observe_day(events: Array) -> void:
	var shot := false
	for event in events:
		match event["type"]:
			"launch_scrubbed":
				scrubs += 1
			"contract_completed":
				completed += 1
			"contract_failed":
				if event["reason"] == ContractRules.LAUNCH_FAILED:
					failed_launch += 1
				else:
					failed_deadline += 1
			"launch_succeeded", "launch_failed":
				shot = true
				if first_shot_day < 0:
					first_shot_day = state.day - 1
		if event["type"] in QUIET:
			continue
		var fields: Dictionary = event.duplicate()
		fields.erase("type")
		log.append("J%-3d %s %s" % [state.day - 1, event["type"], JSON.stringify(fields)])
	if shot:
		money_at_shot.append(state.money)


# --- 1. Contracts -------------------------------------------------------------

func _sign_contracts() -> void:
	while ContractRules.active_count(state) < int(data.contracts["max_active_contracts"]):
		var best := {}
		for contract in state.contracts:
			if contract["status"] != ContractRules.OFFER:
				continue
			if not SimQueries.can_accept(state, data, contract)["ok"]:
				continue
			if _ready_day_estimate() > int(contract["deadline_day"]):
				continue
			if best.is_empty() or int(contract["payment"]) > int(best["payment"]):
				best = contract
		if best.is_empty():
			return
		if _apply(Command.accept_contract(best["id"]))[0]["type"] != "contract_accepted":
			return
		signed += 1


## Active contracts with no scheduled launch, earliest deadline first.
func _unscheduled_contracts() -> Array:
	var out: Array = []
	for contract in state.contracts:
		if contract["status"] == ContractRules.ACTIVE and _launch_of("contract_id", int(contract["id"])).is_empty():
			out.append(contract)
	out.sort_custom(func(a, b): return int(a["deadline_day"]) < int(b["deadline_day"]))
	return out


func _launch_of(key: String, id: int) -> Dictionary:
	for launch in state.launches:
		if launch[key] == id:
			return launch
	return {}


## See the header: day on which a contract signed now could fly.
func _ready_day_estimate() -> int:
	var lead := _kit_lead()
	var assembly := _assembly_days()
	var cycle := maxi(lead, assembly)
	var rollout := int(_def_with("rollout_days")["rollout_days"])
	return state.day + _unscheduled_contracts().size() * cycle + lead + assembly + rollout


func _kit_lead() -> int:
	var lead := 0
	for component_id in data.recipes[LAUNCHER_RECIPE]["inputs"]:
		var supplier_id := _cheapest_supplier(component_id)
		var supplier: Dictionary = data.suppliers[supplier_id]
		var entry := data.catalog_entry(supplier_id, component_id)
		var expected := int(entry["lead_time_days"]) + float(supplier["delay_chance"]) * int(supplier["delay_days"])
		lead = maxi(lead, int(ceil(expected)))
	return lead


func _assembly_days() -> int:
	var hall := _def_with("launcher_capacity")
	var rate := int(hall["slots"]) * int(hall["productivity_per_slot"])
	return int(ceil(float(data.recipes[LAUNCHER_RECIPE]["work_points"]) / rate))


## Definition of the first facility type that has `field` (no hard-coded type id).
func _def_with(field: String) -> Dictionary:
	for type in data.facilities:
		if data.facilities[type].has(field):
			return data.facilities[type]
	return {}


func _ready_instance_with(field: String) -> Dictionary:
	for facility in state.facilities:
		if facility["status"] == "ready" and data.facilities[facility["type"]].has(field):
			return facility
	return {}


# --- 2. Workshop ----------------------------------------------------------------

func _workshop() -> Dictionary:
	for facility in state.facilities:
		if facility["id"] == _workshop_id:
			return facility
	return {}


## Once the shop is built: hire what is missing, staff it, queue the welding jobs.
func _run_workshop() -> void:
	var shop := _workshop()
	if shop.is_empty() or shop["status"] != "ready":
		return
	var slots := int(data.facilities[WORKSHOP_TYPE]["slots"])
	if int(shop["assigned"]) < slots:
		var assigned_elsewhere := 0
		for facility in state.facilities:
			if facility["id"] != shop["id"]:
				assigned_elsewhere += int(facility["assigned"])
		var missing := assigned_elsewhere + slots - state.technicians_hired
		if missing > 0:
			_apply(Command.hire(missing))
		_apply(Command.assign_staff(shop["id"], slots))
	var queue_max := int(data.staff["max_queue_length"])
	while _tanks_to_weld > 0 and shop["jobs"].size() < queue_max:
		if _apply(Command.queue_job(shop["id"], TANK_RECIPE, 1))[0]["type"] != "job_queued":
			return
		_tanks_to_weld -= 1


# --- 3. Kit and assembly ----------------------------------------------------------

func _order_kit() -> void:
	var hall := _ready_instance_with("launcher_capacity")
	if hall.is_empty():
		return
	for job in hall["jobs"]:
		if not job["started"]:
			return  # the previous kit is not consumed yet (also keeps the warehouse free)
	var unscheduled_launchers := 0
	for launcher in state.launchers:
		if _launch_of("launcher_id", int(launcher["id"])).is_empty():
			unscheduled_launchers += 1
	if _unscheduled_contracts().size() <= unscheduled_launchers + hall["jobs"].size():
		return
	var purchases := _kit_purchases()
	var cost := 0
	for purchase in purchases:
		var entry := data.catalog_entry(purchase["supplier"], purchase["component"])
		cost += int(purchase["quantity"]) * int(entry["unit_price"])
	if cost > state.money:
		return  # wait for cash: a partial kit would only clog the warehouse
	for purchase in purchases:
		_apply(Command.order(purchase["supplier"], purchase["component"], purchase["quantity"]))
	if _use_workshop():
		_tanks_to_weld += int(data.recipes[LAUNCHER_RECIPE]["inputs"][_tank_component()])
	_apply(Command.queue_job(hall["id"], LAUNCHER_RECIPE, 1))


## [{supplier, component, quantity}] for one launcher. Tanks are replaced by their
## steel sheets when the workshop strategy has a shop ready before the kit's last part.
func _kit_purchases() -> Array:
	var out: Array = []
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	for component_id in inputs:
		var buy_id: String = component_id
		var quantity := int(inputs[component_id])
		if component_id == _tank_component() and _use_workshop():
			buy_id = _sheet_component()
			quantity *= int(data.recipes[TANK_RECIPE]["inputs"][buy_id])
		out.append({"supplier": _cheapest_supplier(buy_id), "component": buy_id, "quantity": quantity})
	return out


func _use_workshop() -> bool:
	if strategy != WORKSHOP:
		return false
	var shop := _workshop()
	return not shop.is_empty() and int(shop["ready_day"]) <= state.day + _kit_lead()


func _tank_component() -> String:
	return data.recipes[TANK_RECIPE]["output"]["component_id"]


func _sheet_component() -> String:
	return data.recipes[TANK_RECIPE]["inputs"].keys()[0]


func _cheapest_supplier(component_id: String) -> String:
	var best_id := ""
	var best_price := 0
	for supplier_id in data.suppliers:
		var entry := data.catalog_entry(supplier_id, component_id)
		if not entry.is_empty() and (best_id == "" or int(entry["unit_price"]) < best_price):
			best_id = supplier_id
			best_price = int(entry["unit_price"])
	return best_id


# --- 4. Launches ------------------------------------------------------------------

func _schedule_launches() -> void:
	var contracts := _unscheduled_contracts()
	for launcher in SimQueries.ready_launchers(state, data):
		if contracts.is_empty():
			return
		var pad_id := int(launcher["pad_id"])
		if pad_id < 0:  # still in the hall: needs a free pad
			for pad in SimQueries.pad_infos(state, data):
				if pad["status"] == "ready" and pad["pad_state"] == "free":
					pad_id = int(pad["id"])
					break
		if pad_id < 0:
			continue
		var day := SimQueries.min_launch_day(state, data, int(launcher["id"]), pad_id)
		var contract: Dictionary = contracts[0]
		if day > int(contract["deadline_day"]):
			continue  # too late for this contract: the player sees it and does not try
		if _apply(Command.schedule_launch(int(launcher["id"]), pad_id, int(contract["id"]), day))[0]["type"] == "launch_scheduled":
			contracts.pop_front()

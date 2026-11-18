class_name BalanceBot
extends RefCounted
## Scripted player for `make balance` (issues #20 and #54). One instance plays one game
## on the REAL data/, with one of five strategies:
##   buy_all  : chain contracts, buy the whole L1 bill of materials at the cheapest price.
##   workshop : build the tank shop on day 0, staff it, weld the tanks from steel
##              sheets, buy the rest. Until the shop is ready, tanks are bought.
##   integrate_staged : spec 006. Builds the next workshop of STAGES (tank_shop, machine_shop,
##              engine_shop, electronics_lab, composite_shop) as soon as
##              money >= build_cost + reserve, reserve = cost of 2 bought L1 kits (from data/).
##   integrate_greedy : same order, as soon as money >= build_cost (no reserve).
##   engines_only : staged rule, limited to tank_shop, machine_shop and engine_shop.
## The integrated strategies make what their ready workshops can make (raw materials bought
## at the cheapest price, intermediate parts chained, scrapped pieces re-queued) and buy
## the rest; see _make_count for the buy/make mix.
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
const INTEGRATE_STAGED := "integrate_staged"
const INTEGRATE_GREEDY := "integrate_greedy"
const ENGINES_ONLY := "engines_only"
# Spec 007 strategies: buy_all's spot buying plus supply contracts.
const CONTRACT_ENGINES := "contract_engines"
const CONTRACT_FULL_KIT := "contract_full_kit"
const CONTRACT_OVERCOMMIT := "contract_overcommit"
const OPPORTUNIST := "opportunist"

## Bot parameters (spec 007, "Découpage" 6: not balance values, they live here).
const OPPORTUNIST_INDEX := 950            # sign when a kit component's index (permille) is below
const OPPORTUNIST_DELIVERIES := 6         # deliveries of the opportunist's contracts
const OVERCOMMIT_SKIP_STORAGE_PCT := 80   # skip a delivery above this warehouse occupancy (%)
const FIXED := "fixed"

## Build order of the integrated strategies and number of stages used by engines_only.
const STAGES := ["tank_shop", "machine_shop", "engine_shop", "electronics_lab", "composite_shop"]
const ENGINES_ONLY_STAGES := 3

## Workshop types grouped by the chain they pay for (report only).
const CHAINS := {
	"tank": ["tank_shop"],
	"engine": ["machine_shop", "engine_shop"],
	"avionics": ["electronics_lab"],
	"fairing": ["composite_shop"],
}
## Bottleneck label when the hall is full / the kit cannot be paid.
const HALL_PAD := "hall_pad"
const CASH := "cash"
const STORAGE := "storage"

# Content ids the strategies are about (not balance values).
const LAUNCHER_RECIPE := "assemble_l1"
const TANK_RECIPE := "weld_tank"
const WORKSHOP_TYPE := "tank_shop"

## Events left out of the verbose journal (one per day or pure market noise).
## Number of bought L1 kits the staged strategies keep in cash (spec 006, "reserve").
const RESERVE_KITS := 2

## Placement policies (spec 008, "Ce que make balance doit montrer"). A bot parameter, not data/.
const POLICY_NAIVE := "naive"
const POLICY_CAREFUL := "careful"

const QUIET := ["daily_costs", "offer_generated", "offer_expired", "reputation_changed", "pad_ready"]

var strategy: String
var policy := POLICY_CAREFUL
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

# Spec 006 metrics.
var built_day := {}                 # facility type -> day it became ready
var scrapped := {}                  # recipe id -> scrapped jobs
var made_units := {}                # component id -> pieces delivered by a workshop
var bought_units := {}              # component id -> pieces bought for the kits
var scrap_floor_day := {}           # recipe id -> first day the scrap rate hit its floor
var chain_econ := {}                # chain -> {saving, material, running, capex}
var chain_net_at_shot := {}         # chain -> Array[int], net economy at each shot
var bottleneck := {"early": {}, "late": {}}  # phase -> resource -> launchers it limited
var cash_wait_days := 0
# Spec 008 placement metrics.
var placements: Array = []          # [{type, x, y, rotation}] positions the bot chose, in order
var lots_bought := 0
var lot_spend := 0
var incidents := 0                  # failed shot with at least one damaged facility (per pad)
var repair_costs := 0
var rollout_costs := 0
var evacuated_facility_days := 0
var lost_work_points := 0           # work points lost to evacuation or lack of service
var traced_spend := 0               # command debits + daily costs (supply invoices not included)
var final_in_zone := 0              # positioned facilities inside a safety zone at the end
var final_unserved := 0             # facilities with slots outside any warehouse radius at the end
var _pending_loss := {}             # facility id -> work points lost today, set before end_day
var reserve := 0                    # cost of 2 bought L1 kits, computed from data/

# Spot capacity (spec 007 R3) metrics and queue.
var capacity_blocked_days := 0      # days on which a wanted purchase was cut by a supplier's capacity
var shortage_orders := 0            # orders placed while their component was in shortage
var shortage_units := 0

# Spec 007 metrics.
var contracts_signed := 0
var deliveries_skipped := 0
var holding_fees_paid := 0
var take_or_pay_paid := 0
var termination_paid := 0
var penalties_earned := 0
var reduced_deliveries := 0          # contract deliveries cut by a shortage
var shortage_blocked_days := 0       # days the next assembly lacked a part that was in shortage
var index_sum := {}                  # component -> sum of the daily market index
var index_days := 0

var _backlog := {}                  # component -> units still to order (capacity ran out)
var _blocked_day := {}              # component -> last day an order of it was rejected / cut
var _capacity_day := -1             # last day counted in capacity_blocked_days
var _tanks_to_weld := 0
var _workshop_id := 0
var _horizon := 0
var _outstanding := {}              # component -> pieces a workshop still owes the kits
var _wait_days := {}                # resource -> days the next assembly waited for it
var _cheapest_price := {}           # component -> cheapest unit price (report accounting)


func _init(p_strategy: String, p_data: GameData, game_seed: int, p_policy: String = POLICY_CAREFUL) -> void:
	strategy = p_strategy
	policy = p_policy
	data = p_data
	state = Simulation.new_game(data, game_seed)
	reserve = RESERVE_KITS * _bought_kit_cost()
	for chain in CHAINS:
		chain_econ[chain] = {"saving": 0, "material": 0, "running": 0, "capex": 0}
		chain_net_at_shot[chain] = []
	for supplier_id in data.suppliers:
		for entry in data.suppliers[supplier_id]["catalog"]:
			var component_id: String = entry["component_id"]
			if not _cheapest_price.has(component_id) or int(entry["unit_price"]) < int(_cheapest_price[component_id]):
				_cheapest_price[component_id] = int(entry["unit_price"])


static func is_integrated(strategy: String) -> bool:
	return strategy in [INTEGRATE_STAGED, INTEGRATE_GREEDY, ENGINES_ONLY]


static func is_contract(strategy: String) -> bool:
	return strategy in [CONTRACT_ENGINES, CONTRACT_FULL_KIT, CONTRACT_OVERCOMMIT, OPPORTUNIST]


## Plays until `days` days have elapsed, or bankruptcy.
func play(days: int) -> void:
	_horizon = days
	if strategy == WORKSHOP:
		var events := _place_and_build(WORKSHOP_TYPE)
		if not events.is_empty() and events[0]["type"] == "facility_build_started":
			_workshop_id = int(events[0]["facility_id"])
	while state.day < days and not state.game_over:
		if LevelRules.is_ended(state):  # temporary until #87: the bot plays on in free play
			_apply(Command.continue_free_play())
		_flush_backlog()
		if is_contract(strategy):
			_manage_supply_contracts()
		if is_integrated(strategy):
			_build_next()
			_staff_workshops()
		_sign_contracts()
		if strategy == WORKSHOP:
			_run_workshop()
		_order_kit()
		if is_integrated(strategy):
			_feed_workshops()
		_schedule_launches()
		_tally_unserved_loss()
		_observe_day(Simulation.end_day(state, data))
	_tally_final_layout()


func _apply(command: Command) -> Array:
	var money_before := state.money
	var events := Simulation.apply_command(state, command, data)
	traced_spend += maxi(0, money_before - state.money)
	for event in events:
		if event["type"] == "command_rejected":
			var reason: String = event["reason"]
			rejections[reason] = int(rejections.get(reason, 0)) + 1
			log.append("J%-3d REJECTED %s" % [state.day, JSON.stringify(event)])
		elif event["type"] == "facility_build_started":
			_add_capex(event["facility_type"], int(event["cost"]))
		elif event["type"] == "lot_bought":
			lots_bought += 1
			lot_spend += int(event["cost"])
	return events


func _chain_of(facility_type: String) -> String:
	for chain in CHAINS:
		if facility_type in CHAINS[chain]:
			return chain
	return ""


func _add_capex(facility_type: String, amount: int) -> void:
	var chain := _chain_of(facility_type)
	if chain != "":
		chain_econ[chain]["capex"] += amount


## Hires `count` technicians for a workshop of `facility_type`. Returns false if rejected.
func _hire_for(facility_type: String, count: int) -> bool:
	if _apply(Command.hire(count))[0]["type"] != "staff_hired":
		return false
	_add_capex(facility_type, count * int(data.staff["technician"]["hire_cost"]))
	return true


## `events` come from end_day, which has already moved state.day to the next day.
func _observe_day(events: Array) -> void:
	var shot := false
	var day := state.day - 1
	var damaged_pads := {}
	for event in events:
		match event["type"]:
			"facility_damaged":
				damaged_pads[event["pad_id"]] = true
			"facility_evacuated":
				evacuated_facility_days += 1
				_pending_loss[int(event["facility_id"])] = SimQueries.facility_rate(
					data, _facility_by_id(int(event["facility_id"])))
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
					first_shot_day = day
			"facility_built":
				built_day[event["facility_type"]] = day
			"daily_costs":
				repair_costs += int(event.get("repair_costs", 0))
				rollout_costs += int(event.get("rollout_costs", 0))
				for key in ["upkeep", "salaries", "scrub_costs", "refurb_costs", "rollout_costs", "repair_costs", "holding_fees"]:
					traced_spend += int(event.get(key, 0))
				holding_fees_paid += int(event.get("holding_fees", 0))
				penalties_earned += int(event.get("supply_penalties", 0))
			"supply_delivery_skipped":
				deliveries_skipped += 1
				take_or_pay_paid += int(event["cost"])
			"supply_contract_terminated":
				termination_paid += int(event["fee"])
			"supply_delivery_reduced":
				reduced_deliveries += 1
			"job_scrapped":
				scrapped[event["recipe_id"]] = int(scrapped.get(event["recipe_id"], 0)) + 1
			"job_completed":
				_on_job_completed(event)
			"job_started":
				_on_job_started(event, day)
		if event["type"] in QUIET:
			continue
		var fields: Dictionary = event.duplicate()
		fields.erase("type")
		log.append("J%-3d %s %s" % [day, event["type"], JSON.stringify(fields)])
	incidents += damaged_pads.size()
	for id in _pending_loss:
		lost_work_points += int(_pending_loss[id])
	_pending_loss.clear()
	_track_running_costs()
	_track_scrap_floor(day)
	_track_wait()
	_track_market()
	if shot:
		money_at_shot.append(state.money)
		for chain in CHAINS:
			chain_net_at_shot[chain].append(chain_net(chain))


## Net economy of a chain so far: purchases avoided minus materials, upkeep, salaries
## of its workshops, construction and hiring. Positive = the chain has paid for itself.
func chain_net(chain: String) -> int:
	var econ: Dictionary = chain_econ[chain]
	return int(econ["saving"]) - int(econ["material"]) - int(econ["running"]) - int(econ["capex"])


func _on_job_completed(event: Dictionary) -> void:
	var output: Dictionary = event["output"]
	if not output.has("component_id"):
		return
	var component_id: String = output["component_id"]
	var qty := int(output["quantity"])
	made_units[component_id] = int(made_units.get(component_id, 0)) + qty
	_outstanding[component_id] = maxi(0, int(_outstanding.get(component_id, 0)) - qty)
	var recipe_id := _recipe_making(component_id)
	var chain := _chain_of(data.recipes[recipe_id]["facility_type"]) if recipe_id != "" else ""
	if chain != "":  # a part with no supplier (turbopump) saves nothing by itself
		chain_econ[chain]["saving"] += qty * int(_cheapest_price.get(component_id, 0))


func _on_job_started(event: Dictionary, day: int) -> void:
	var facility := _facility_by_id(int(event["facility_id"]))
	if facility.is_empty():
		return
	if data.facilities[facility["type"]].has("launcher_capacity"):
		_record_bottleneck(day)
		return
	var chain := _chain_of(facility["type"])
	if chain == "":
		return
	for component_id in event["consumed"]:
		chain_econ[chain]["material"] += int(event["consumed"][component_id]) * int(_cheapest_price.get(component_id, 0))


func _facility_by_id(id: int) -> Dictionary:
	for facility in state.facilities:
		if facility["id"] == id:
			return facility
	return {}


## Salaries and upkeep of the workshops of each chain, for the day that just ended.
func _track_running_costs() -> void:
	var salary := int(data.staff["technician"]["technician_salary_per_day"])
	for facility in state.facilities:
		var chain := _chain_of(facility["type"])
		if chain != "" and facility["status"] == "ready":
			chain_econ[chain]["running"] += int(data.facilities[facility["type"]]["upkeep_per_day"]) \
				+ int(facility["assigned"]) * salary


func _track_scrap_floor(day: int) -> void:
	for recipe_id in data.recipes:
		var recipe: Dictionary = data.recipes[recipe_id]
		if float(recipe.get("scrap_rate_floor", 0.0)) <= 0.0 or scrap_floor_day.has(recipe_id):
			continue
		if SimQueries.scrap_rate(state, data, recipe_id) <= float(recipe["scrap_rate_floor"]):
			scrap_floor_day[recipe_id] = day


## Why the next assembly has not started yet, one day at a time (resource -> days).
func _track_wait() -> void:
	var hall := _ready_instance_with("launcher_capacity")
	if hall.is_empty() or hall["jobs"].is_empty() or hall["jobs"][0]["started"]:
		return
	match hall["jobs"][0]["blocked"]:
		"missing_inputs":
			var inputs: Dictionary = data.recipes[hall["jobs"][0]["recipe_id"]]["inputs"]
			var in_shortage := false
			for component_id in inputs:
				if int(state.stock.get(component_id, 0)) < int(inputs[component_id]):
					_wait_days[component_id] = int(_wait_days.get(component_id, 0)) + 1
					in_shortage = in_shortage or _in_shortage(component_id)
			if in_shortage:
				shortage_blocked_days += 1
		"hall_occupied":
			_wait_days[HALL_PAD] = int(_wait_days.get(HALL_PAD, 0)) + 1


## The resource the launcher waited the longest for before its assembly began.
func _record_bottleneck(day: int) -> void:
	var worst := ""
	var keys := _wait_days.keys()
	keys.sort()
	for key in keys:
		if worst == "" or int(_wait_days[key]) > int(_wait_days[worst]):
			worst = key
	_wait_days.clear()
	if worst == "":
		return
	var phase: Dictionary = bottleneck["early" if day * 2 < _horizon else "late"]
	phase[worst] = int(phase.get(worst, 0)) + 1


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
	return state.day + _unscheduled_contracts().size() * cycle + lead + assembly + rollout + _capacity_delay()


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
			_hire_for(WORKSHOP_TYPE, missing)
		_apply(Command.assign_staff(shop["id"], slots))
	var queue_max := int(data.staff["max_queue_length"])
	while _tanks_to_weld > 0 and shop["jobs"].size() < queue_max:
		if _apply(Command.queue_job(shop["id"], TANK_RECIPE, 1))[0]["type"] != "job_queued":
			return
		_tanks_to_weld -= 1


# --- 3. Kit and assembly ----------------------------------------------------------

## The hall if a new kit is wanted today ({} otherwise).
func _kit_due() -> Dictionary:
	var hall := _ready_instance_with("launcher_capacity")
	if hall.is_empty():
		return {}
	for job in hall["jobs"]:
		if not job["started"]:
			return {}  # the previous kit is not consumed yet (also keeps the warehouse free)
	var unscheduled_launchers := 0
	for launcher in state.launchers:
		if _launch_of("launcher_id", int(launcher["id"])).is_empty():
			unscheduled_launchers += 1
	if _unscheduled_contracts().size() <= unscheduled_launchers + hall["jobs"].size():
		return {}
	return hall


func _order_kit() -> void:
	var hall := _kit_due()
	if hall.is_empty():
		return
	if is_integrated(strategy):
		_order_integrated_kit(hall)
		return
	var purchases := _kit_purchases()
	if is_contract(strategy):
		purchases = _net_of_contracts(purchases)
	var cost := 0
	for purchase in purchases:
		cost += _spot_cost(purchase["component"], int(purchase["quantity"]))
	if cost > state.money:
		return  # wait for cash: a partial kit would only clog the warehouse
	for purchase in purchases:
		_buy(purchase["component"], int(purchase["quantity"]), true)
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


# --- 5. Integration (spec 006) -------------------------------------------------------

## Cost of one L1 kit with every component bought at the cheapest price.
func _bought_kit_cost() -> int:
	var cost := 0
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	for component_id in inputs:
		var supplier_id := _cheapest_supplier(component_id)
		cost += int(inputs[component_id]) * int(data.catalog_entry(supplier_id, component_id)["unit_price"])
	return cost


## Builds the first workshop of the strategy's list that does not exist yet, in order,
## once its prerequisites are ready and the money threshold is met.
func _build_next() -> void:
	var count := ENGINES_ONLY_STAGES if strategy == ENGINES_ONLY else STAGES.size()
	for i in count:
		var type: String = STAGES[i]
		if _any_instance(type):
			continue
		for option in SimQueries.build_options(state, data):
			if option["type"] != type:
				continue
			if not option["missing"].is_empty():
				return  # waits for its prerequisite (e.g. the machine shop)
			var threshold := int(option["cost"]) + (0 if strategy == INTEGRATE_GREEDY else reserve)
			if state.money >= threshold:
				_place_and_build(type)
		return


func _any_instance(type: String) -> bool:
	for facility in state.facilities:
		if facility["type"] == type:
			return true
	return false


## Hires and assigns the technicians of every ready workshop that is not fully staffed.
func _staff_workshops() -> void:
	for facility in state.facilities:
		var def: Dictionary = data.facilities[facility["type"]]
		if facility["status"] != "ready" or not def.has("slots") or int(facility["assigned"]) >= int(def["slots"]):
			continue
		var info := SimQueries.staff_info(state, data)
		var wanted := int(def["slots"]) - int(facility["assigned"])
		var to_hire := maxi(0, wanted - int(info["free"]))
		if to_hire * int(info["hire_cost"]) > state.money:
			continue  # cannot afford the hiring yet: the shop waits, like a player would
		if to_hire > 0 and not _hire_for(facility["type"], to_hire):
			continue
		_apply(Command.assign_staff(facility["id"], int(def["slots"])))


## Recipe whose output is `component_id` ("" if none).
func _recipe_making(component_id: String) -> String:
	var ids: Array = data.recipes.keys()
	ids.sort()
	for recipe_id in ids:
		if data.recipes[recipe_id]["output"].get("component_id", "") == component_id:
			return recipe_id
	return ""


func _buyable(component_id: String) -> bool:
	return _cheapest_price.has(component_id)


## Days a fully staffed workshop needs for one piece of `recipe_id`.
func _piece_days(recipe_id: String) -> int:
	var recipe: Dictionary = data.recipes[recipe_id]
	var def: Dictionary = data.facilities[recipe["facility_type"]]
	return int(ceil(float(recipe["work_points"]) / (int(def["slots"]) * int(def["productivity_per_slot"]))))


## Days before the first piece of `recipe_id` can start its last step (intermediate
## parts are made one after the other in their own workshops, pipelined).
func _lead_before(recipe_id: String) -> int:
	var lead := 0
	for component_id in data.recipes[recipe_id]["inputs"]:
		if not _buyable(component_id):
			var inner := _recipe_making(component_id)
			lead = maxi(lead, _lead_before(inner) + _piece_days(inner))
	return lead


## Every workshop type of the chain of `recipe_id` is ready, or will be within `horizon` days.
func _chain_ready_within(recipe_id: String, horizon: int) -> bool:
	var recipe: Dictionary = data.recipes[recipe_id]
	var ok := false
	for facility in state.facilities:
		if facility["type"] == recipe["facility_type"] and int(facility["ready_day"]) <= state.day + horizon:
			ok = true
	if not ok:
		return false
	for component_id in recipe["inputs"]:
		if not _buyable(component_id) and not _chain_ready_within(_recipe_making(component_id), horizon):
			return false
	return true


## How many of the `quantity` pieces of `component_id` the kit makes itself. A piece is made
## if its workshops are ready (or ready before the kit's bought lead time elapses) and
## the workshop can deliver it within that lead time: the rest is bought, so that making
## never delays a kit that buying would have delivered on time.
func _make_count(component_id: String, quantity: int) -> int:
	var recipe_id := _recipe_making(component_id)
	if recipe_id == "":
		return 0
	var lead := _kit_lead()
	if not _chain_ready_within(recipe_id, lead):
		return 0
	var window := lead - _lead_before(recipe_id)
	return clampi(window / _piece_days(recipe_id), 1, quantity)


## Raw materials (component -> quantity) for `count` pieces of `component_id`.
func _raw_for(component_id: String, count: int, into: Dictionary) -> void:
	var recipe: Dictionary = data.recipes[_recipe_making(component_id)]
	var batches := int(ceil(float(count) / int(recipe["output"]["quantity"])))
	for input_id in recipe["inputs"]:
		var qty: int = batches * int(recipe["inputs"][input_id])
		if _buyable(input_id):
			into[input_id] = int(into.get(input_id, 0)) + qty
		else:
			_raw_for(input_id, qty, into)


## Component -> pieces of the next kit that the workshops make (the rest is bought).
func _kit_makes() -> Dictionary:
	var makes := {}
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	for component_id in inputs:
		var made := _make_count(component_id, int(inputs[component_id]))
		if made > 0:
			makes[component_id] = made
	return makes


func _order_integrated_kit(hall: Dictionary) -> void:
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	var buys: Array = []
	var makes := _kit_makes()
	var raw := {}
	var cost := 0
	for component_id in makes:
		_raw_for(component_id, makes[component_id], raw)
	for component_id in inputs:
		var quantity := int(inputs[component_id]) - int(makes.get(component_id, 0))
		if quantity > 0:
			buys.append({"component": component_id, "quantity": quantity})
	for purchase in buys:
		cost += _spot_cost(purchase["component"], int(purchase["quantity"]))
	for component_id in raw:
		cost += _spot_cost(component_id, int(raw[component_id]))
	var units := 0
	for purchase in buys:
		units += int(purchase["quantity"]) * int(data.components[purchase["component"]]["storage_units"])
	if units > Simulation.storage_capacity(state, data) - Simulation.storage_used(state, data) - _incoming_units():
		_expand_storage(0)
		_wait_days[STORAGE] = int(_wait_days.get(STORAGE, 0)) + 1
		return  # parts left at the gate would jam the warehouse: wait for room
	if cost > state.money:
		cash_wait_days += 1
		_wait_days[CASH] = int(_wait_days.get(CASH, 0)) + 1
		return  # wait for cash: a partial kit would only clog the warehouse
	for purchase in buys:
		var component_id: String = purchase["component"]
		_buy(component_id, int(purchase["quantity"]), true)
		bought_units[component_id] = int(bought_units.get(component_id, 0)) + int(purchase["quantity"])
	for component_id in makes:
		_outstanding[component_id] = int(_outstanding.get(component_id, 0)) + int(makes[component_id])
	_apply(Command.queue_job(hall["id"], LAUNCHER_RECIPE, 1))


func _unscheduled_launcher_count() -> int:
	var count := 0
	for launcher in state.launchers:
		if _launch_of("launcher_id", int(launcher["id"])).is_empty():
			count += 1
	return count


func _ready_instance_of(type: String) -> Dictionary:
	for facility in state.facilities:
		if facility["type"] == type and facility["status"] == "ready":
			return facility
	return {}


func _queued_jobs(facility: Dictionary, recipe_id: String) -> int:
	var count := 0
	for job in facility["jobs"]:
		if job["recipe_id"] == recipe_id:
			count += 1
	return count


## Queues the pieces the kits are still owed (re-queues scrapped ones), then the
## intermediate parts the queued jobs will need, then buys the missing raw materials.
func _feed_workshops() -> void:
	# A workshop holds raw materials and parts next to the kits: when a whole kit no
	# longer fits in the free room, add a warehouse (raw stock would jam the deliveries).
	if _free_room() < _kit_units() and _any_made_work():
		_expand_storage(reserve)
	var queue_max := int(data.staff["max_queue_length"])
	var recipe_ids: Array = data.recipes.keys()
	recipe_ids.sort()
	# 1. made pieces: what the waiting assembly still lacks, plus the next kit's share when
	#    another contract will need it (the shop works ahead instead of idling between kits).
	var demand := {}
	var hall := _ready_instance_with("launcher_capacity")
	var kit_inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	if not hall.is_empty():
		for job in hall["jobs"]:
			if not job["started"]:
				for component_id in kit_inputs:
					demand[component_id] = int(demand.get(component_id, 0)) + int(kit_inputs[component_id])
		if _unscheduled_contracts().size() > _unscheduled_launcher_count() + hall["jobs"].size():
			var next_makes := _kit_makes()
			for component_id in next_makes:
				demand[component_id] = int(demand.get(component_id, 0)) + int(next_makes[component_id])
	var ordered_now := SimQueries.on_order(state)
	for component_id in demand:
		var recipe_id := _recipe_making(component_id)
		if recipe_id == "" or _make_count(component_id, int(kit_inputs[component_id])) <= 0:
			continue
		var shop := _ready_instance_of(data.recipes[recipe_id]["facility_type"])
		if shop.is_empty():
			continue
		var supply := int(state.stock.get(component_id, 0)) + int(ordered_now.get(component_id, 0)) \
			+ int(_backlog.get(component_id, 0)) + _queued_jobs(shop, recipe_id)
		var count := mini(int(demand[component_id]) - supply, queue_max - shop["jobs"].size())
		if count > 0:
			_apply(Command.queue_job(shop["id"], recipe_id, count))
	# 2. intermediate parts (no supplier) needed by jobs that have not started
	for recipe_id in recipe_ids:
		var output: Dictionary = data.recipes[recipe_id]["output"]
		if not output.has("component_id") or _buyable(output["component_id"]):
			continue
		var shop := _ready_instance_of(data.recipes[recipe_id]["facility_type"])
		if shop.is_empty():
			continue
		var part: String = output["component_id"]
		var needed := -int(state.stock.get(part, 0)) - _queued_jobs(shop, recipe_id) * int(output["quantity"])
		for facility in state.facilities:
			for job in facility["jobs"]:
				if not job["started"]:
					needed += int(data.recipes[job["recipe_id"]]["inputs"].get(part, 0))
		var count := mini(int(ceil(float(needed) / int(output["quantity"]))), queue_max - shop["jobs"].size())
		if count > 0:
			_apply(Command.queue_job(shop["id"], recipe_id, count))
	# 3. raw materials for the jobs waiting in workshops (the hall is fed by the kit)
	var required := {}
	for facility in state.facilities:
		if data.facilities[facility["type"]].has("launcher_capacity"):
			continue
		for job in facility["jobs"]:
			if job["started"]:
				continue
			var inputs: Dictionary = data.recipes[job["recipe_id"]]["inputs"]
			for component_id in inputs:
				if _buyable(component_id):
					required[component_id] = int(required.get(component_id, 0)) + int(inputs[component_id])
	# One spare job of raw materials per recipe that scraps and has work queued: after a
	# scrap the re-queued job can start at once instead of waiting for a delivery.
	for facility in state.facilities:
		if data.facilities[facility["type"]].has("launcher_capacity") or facility["jobs"].is_empty():
			continue
		var spare_done := {}
		for job in facility["jobs"]:
			var recipe: Dictionary = data.recipes[job["recipe_id"]]
			if float(recipe.get("scrap_rate_start", 0.0)) <= 0.0 or spare_done.has(job["recipe_id"]):
				continue
			spare_done[job["recipe_id"]] = true
			for component_id in recipe["inputs"]:
				if _buyable(component_id):
					required[component_id] = int(required.get(component_id, 0)) + int(recipe["inputs"][component_id])
	# Standing stock for the next kit's made pieces: their raw materials come from a
	# supplier with a lead time, so a player stocks them before the kit is ordered.
	if not _ready_instance_with("launcher_capacity").is_empty():
		var next_raw := {}
		var next_makes := _kit_makes()
		for component_id in next_makes:
			_raw_for(component_id, next_makes[component_id], next_raw)
		for component_id in next_raw:
			required[component_id] = int(required.get(component_id, 0)) + int(next_raw[component_id])
	var ordered := SimQueries.on_order(state)
	var component_ids := required.keys()
	component_ids.sort()
	for component_id in component_ids:
		var missing := int(required[component_id]) - int(state.stock.get(component_id, 0)) \
				- int(ordered.get(component_id, 0)) - int(_backlog.get(component_id, 0))
		if missing <= 0 or _blocked_day.get(component_id, -1) == state.day:
			continue
		var supplier_id := _cheapest_supplier(component_id)
		var quote := SimQueries.order_quote(state, data, supplier_id, component_id, missing)
		if quote["storage_units"] > quote["free_storage"] - _incoming_units():
			_expand_storage(reserve)
			continue
		if _spot_cost(component_id, missing) > state.money:
			continue
		_buy(component_id, missing, false)


## Builds one more warehouse (when the data allows it and the cash is there) after a
## raw-material order did not fit: parts left at the gate would jam the whole chain.
func _expand_storage(margin: int) -> void:
	for facility in state.facilities:
		if facility["status"] == "building" and data.facilities[facility["type"]].has("storage_capacity"):
			return
	for option in SimQueries.build_options(state, data):
		if data.facilities[option["type"]].has("storage_capacity") and option["remaining"] > 0 \
				and state.money >= int(option["cost"]) + margin:
			_place_and_build(option["type"])
			return


## Storage units of one complete L1 kit.
func _kit_units() -> int:
	var units := 0
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	for component_id in inputs:
		units += int(inputs[component_id]) * int(data.components[component_id]["storage_units"])
	return units


## Free storage units once the orders in transit have arrived.
func _free_room() -> int:
	return Simulation.storage_capacity(state, data) - Simulation.storage_used(state, data) - _incoming_units()


## True once a workshop other than the hall exists.
func _any_made_work() -> bool:
	for facility in state.facilities:
		if _chain_of(facility["type"]) != "":
			return true
	return false


## Storage units of the orders still in transit.
func _incoming_units() -> int:
	var units := 0
	for order in state.pending_orders:
		units += int(order["quantity"]) * int(data.components[order["component_id"]]["storage_units"])
	return units


# --- 6. Spot purchases under supplier capacity (spec 007 R3) -------------------------

## Suppliers of a component, cheapest current spot price first (ties by id).
func _suppliers_by_price(component_id: String) -> Array:
	var ids: Array = []
	for supplier_id in data.suppliers:
		if not data.catalog_entry(supplier_id, component_id).is_empty():
			ids.append(supplier_id)
	ids.sort_custom(func(a, b):
		var pa := SimQueries.spot_price(state, data, a, component_id)
		var pb := SimQueries.spot_price(state, data, b, component_id)
		return pa < pb or (pa == pb and a < b))
	return ids


## Cost of `quantity` units at today's cheapest spot price (capacity ignored: the
## estimate only decides whether the cash is there).
func _spot_cost(component_id: String, quantity: int) -> int:
	var ids := _suppliers_by_price(component_id)
	return quantity * SimQueries.spot_price(state, data, ids[0], component_id)


func _in_shortage(component_id: String) -> bool:
	return bool(SimQueries.market_snapshot(state, data).get(component_id, {}).get("shortage", false))


func _note_capacity_block(component_id: String) -> void:
	_blocked_day[component_id] = state.day
	if _capacity_day != state.day:
		_capacity_day = state.day
		capacity_blocked_days += 1


## Orders `quantity` units, cheapest supplier first, never more than what a supplier
## still sells this period. The rest is kept in the backlog (`keep_rest`) and retried on
## the following days. A rejected order is not retried the same day.
func _buy(component_id: String, quantity: int, keep_rest: bool) -> void:
	var left := quantity
	for supplier_id in _suppliers_by_price(component_id):
		if left <= 0:
			break
		var remaining := SimQueries.spot_capacity_remaining(state, data, supplier_id, component_id)
		var amount := left if remaining < 0 else mini(left, remaining)
		if amount < left:
			_note_capacity_block(component_id)
		if amount <= 0:
			continue
		var in_shortage := _in_shortage(component_id)
		var events := _apply(Command.order(supplier_id, component_id, amount))
		if events[0]["type"] != "order_placed":
			_blocked_day[component_id] = state.day
			break  # no retry today
		left -= amount
		if in_shortage:
			shortage_orders += 1
			shortage_units += amount
	if left > 0 and keep_rest:
		_backlog[component_id] = int(_backlog.get(component_id, 0)) + left


## Orders what the capacity left over on previous days, if the cash is there.
func _flush_backlog() -> void:
	var component_ids := _backlog.keys()
	component_ids.sort()
	for component_id in component_ids:
		var quantity := int(_backlog[component_id])
		if quantity <= 0 or _blocked_day.get(component_id, -1) == state.day:
			continue
		if _spot_cost(component_id, quantity) > state.money:
			continue
		_backlog.erase(component_id)
		_buy(component_id, quantity, true)


## Extra days a contract signed now would wait for parts because of supplier capacity:
## for each bought kit component, units still wanted (backlog + one kit per unscheduled
## contract + this one) beyond what is left this period need further periods of the
## suppliers' combined capacity (cut to shortage_capacity_pct during a shortage).
## 0 when the suppliers are unlimited. Simple on purpose: it ignores price changes.
func _capacity_delay() -> int:
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	var kits := _unscheduled_contracts().size() + 1
	var made := {}
	if is_integrated(strategy):
		made = _kit_makes()
	elif _use_workshop():
		made[_tank_component()] = int(inputs[_tank_component()])
	var worst := 0
	for component_id in inputs:
		var wanted := kits * (int(inputs[component_id]) - int(made.get(component_id, 0))) + int(_backlog.get(component_id, 0))
		if wanted <= 0:
			continue
		var left_now := 0
		var per_period := 0
		var unlimited := false
		for supplier_id in _suppliers_by_price(component_id):
			var remaining := SimQueries.spot_capacity_remaining(state, data, supplier_id, component_id)
			var entry := data.catalog_entry(supplier_id, component_id)
			if remaining < 0 or not entry.has("spot_capacity_per_period"):
				unlimited = true
				break
			left_now += remaining
			var capacity := int(entry["spot_capacity_per_period"])
			if _in_shortage(component_id):
				capacity = capacity * int(data.market["shortage_capacity_pct"]) / 100
			per_period += capacity
		if unlimited or per_period <= 0:
			continue
		var periods := int(ceil(float(maxi(0, wanted - left_now)) / per_period))
		worst = maxi(worst, periods * int(data.market["market_period_days"]))
	return worst


# --- 7. Supply contracts (spec 007) ---------------------------------------------------

func _track_market() -> void:
	var snapshot := SimQueries.market_snapshot(state, data)
	for component_id in snapshot:
		index_sum[component_id] = int(index_sum.get(component_id, 0)) + int(snapshot[component_id]["index"])
	index_days += 1


## Active supply contract of this bot on a component ({} if none).
func _active_contract(component_id: String) -> Dictionary:
	for contract in state.supply_contracts:
		if contract["status"] == SupplyRules.ACTIVE and contract["component_id"] == component_id:
			return contract
	return {}


## Supplier that offers contracts for a component (cheapest catalog price), "" if none.
func _contract_supplier(component_id: String) -> String:
	var best := ""
	for supplier_id in data.suppliers:
		var entry := data.catalog_entry(supplier_id, component_id)
		if entry.is_empty() or not entry.has("contract_terms"):
			continue
		if best == "" or int(entry["unit_price"]) < int(data.catalog_entry(best, component_id)["unit_price"]):
			best = supplier_id
	return best


## Smallest contract period of the data (the strategies sign "every 14 days").
func _contract_period() -> int:
	var options: Array = data.supply_contracts["period_options_days"]
	return int(options.min())


## Kit quantity of a component clamped to the supplier's contract terms.
func _contract_quantity(component_id: String, supplier_id: String) -> int:
	var terms: Dictionary = data.catalog_entry(supplier_id, component_id)["contract_terms"]
	var wanted := int(data.recipes[LAUNCHER_RECIPE]["inputs"][component_id])
	return clampi(wanted, int(terms["min_quantity"]), int(terms["max_quantity"]))


## Signs a contract if the quote is valid and the cash covers its first invoice
## plus one bought kit (the cash a player keeps to keep the hall fed).
func _sign(component_id: String, quantity: int, deliveries: int, priority: bool) -> bool:
	var supplier_id := _contract_supplier(component_id)
	if supplier_id == "" or _active_contract(component_id).size() > 0:
		return false
	if SupplyRules.active_count(state) >= int(data.supply_contracts["max_supply_contracts"]):
		return false
	var args := {"supplier_id": supplier_id, "component_id": component_id, "quantity": quantity,
		"period_days": _contract_period(), "deliveries": deliveries, "pricing": FIXED, "priority": priority}
	var quote := SimQueries.supply_contract_quote(state, data, args)
	if not quote["ok"]:
		return false
	if state.money < int(quote["invoice"]) + _bought_kit_cost():
		return false
	var event: Dictionary = _apply(Command.sign_supply_contract(supplier_id, component_id, quantity,
		_contract_period(), deliveries, FIXED, priority))[0]
	if event["type"] != "supply_contract_signed":
		return false
	contracts_signed += 1
	return true


func _manage_supply_contracts() -> void:
	var max_deliveries := int(data.supply_contracts["max_deliveries"])
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	match strategy:
		CONTRACT_ENGINES:
			var engine := _engine_component()
			_sign(engine, _contract_quantity(engine, _contract_supplier(engine)), max_deliveries, true)
		CONTRACT_FULL_KIT:
			var ids := inputs.keys()
			ids.sort()
			for component_id in ids:
				var supplier_id := _contract_supplier(component_id)
				if supplier_id != "":
					_sign(component_id, _contract_quantity(component_id, supplier_id), max_deliveries, false)
		CONTRACT_OVERCOMMIT:
			var engine := _engine_component()
			var terms: Dictionary = data.catalog_entry(_contract_supplier(engine), engine)["contract_terms"]
			_sign(engine, int(terms["max_quantity"]), max_deliveries, false)
			_skip_when_full()
		OPPORTUNIST:
			var snapshot := SimQueries.market_snapshot(state, data)
			var ids := inputs.keys()
			ids.sort()
			for component_id in ids:
				var supplier_id := _contract_supplier(component_id)
				if supplier_id != "" and snapshot.has(component_id) \
						and int(snapshot[component_id]["index"]) < OPPORTUNIST_INDEX:
					_sign(component_id, _contract_quantity(component_id, supplier_id), OPPORTUNIST_DELIVERIES, false)


## The kit component that is bought by contract in the engine strategies: the one with
## the highest unit price in the kit (the engine), found from the data.
func _engine_component() -> String:
	var best := ""
	var inputs: Dictionary = data.recipes[LAUNCHER_RECIPE]["inputs"]
	for component_id in inputs:
		if best == "" or int(_cheapest_price[component_id]) > int(_cheapest_price[best]):
			best = component_id
	return best


## Overcommit: on the last day a delivery can still be skipped, skip it if the
## warehouse (stock + goods on the way) is above OVERCOMMIT_SKIP_STORAGE_PCT.
func _skip_when_full() -> void:
	var capacity := Simulation.storage_capacity(state, data)
	var used := Simulation.storage_used(state, data) + _incoming_units()
	if capacity <= 0 or used * 100 <= capacity * OVERCOMMIT_SKIP_STORAGE_PCT:
		return
	var notice := int(data.supply_contracts["skip_notice_days"])
	for contract in state.supply_contracts:
		if contract["status"] != SupplyRules.ACTIVE or contract["skip_next"]:
			continue
		if int(contract["next_delivery_day"]) - state.day == notice \
				and SupplyRules.skip_cost(state, data, contract) <= state.money:
			_apply(Command.skip_supply_delivery(int(contract["id"])))


## Units of a component that contracts will bring within the kit's lead time.
func _planned_contract_units(component_id: String) -> int:
	var contract := _active_contract(component_id)
	if contract.is_empty() or contract["skip_next"]:
		return 0
	if int(contract["next_delivery_day"]) <= state.day + _kit_lead():
		return int(contract["quantity"])
	return 0


## Spot purchases of a kit once the supply already in the warehouse, on its way or due
## from a contract within the kit lead time is counted (contracts replace spot buying).
func _net_of_contracts(purchases: Array) -> Array:
	var out: Array = []
	var ordered := SimQueries.on_order(state)
	for purchase in purchases:
		var component_id: String = purchase["component"]
		var have := int(state.stock.get(component_id, 0)) + int(ordered.get(component_id, 0)) \
			+ _planned_contract_units(component_id)
		var need := int(purchase["quantity"]) - have
		if need > 0:
			out.append({"supplier": purchase["supplier"], "component": component_id, "quantity": need})
	return out


# --- Placement (spec 008, "Ce que make balance doit montrer") ---------------------------
# The bot picks every position itself, from SimQueries.placement_check and lot_list only,
# and sends it in build(type, x, y, rotation). Both policies are deterministic.

## Builds `type` at the position the policy chooses (buying a lot when the policy says so).
## Returns the events of the build command, or [] when no position is affordable.
func _place_and_build(type: String) -> Array:
	if not data.has_map():
		return _apply(Command.build(type))
	var cost := int(data.facilities[type]["build_cost"])
	var spot := _choose_naive(type, cost) if policy == POLICY_NAIVE else _choose_careful(type, cost)
	if spot.is_empty():
		return []
	placements.append({"type": type, "x": spot["x"], "y": spot["y"], "rotation": spot["rotation"]})
	return _apply(Command.build(type, spot["x"], spot["y"], spot["rotation"]))


## Cells of the owned lots, scanned by y then x, rotation 0 then 1. Returns the valid
## placements ([{x, y, rotation, check}]); stops at the first one when `first_only`.
func _scan(st: GameState, type: String, first_only: bool) -> Array:
	var owned: Array = []
	for lot in SimQueries.lot_list(st, data):
		if lot["owned"]:
			owned.append(lot)
	var site_map := data.site_map()
	var found: Array = []
	for y in int(site_map["height"]):
		for x in int(site_map["width"]):
			if not _in_lots(owned, x, y):
				continue
			for rotation in 2:
				var check := SimQueries.placement_check(st, data, type, x, y, rotation)
				if check["valid"]:
					found.append({"x": x, "y": y, "rotation": rotation, "check": check})
					if first_only:
						return found
	return found


func _in_lots(lots: Array, x: int, y: int) -> bool:
	for lot in lots:
		if x >= lot["x"] and x < lot["x"] + lot["w"] and y >= lot["y"] and y < lot["y"] + lot["h"]:
			return true
	return false


## Unowned lots, cheapest first (id breaks ties).
func _lots_for_sale(st: GameState) -> Array:
	var lots: Array = []
	for lot in SimQueries.lot_list(st, data):
		if not lot["owned"]:
			lots.append(lot)
	lots.sort_custom(func(a, b): return a["price"] < b["price"] or (a["price"] == b["price"] and a["id"] < b["id"]))
	return lots


## naive: first free spot; when none, buy the cheapest lot as soon as the money allows.
func _choose_naive(type: String, cost: int) -> Dictionary:
	while true:
		var found := _scan(state, type, true)
		if not found.is_empty():
			return found[0]
		var lots := _lots_for_sale(state)
		if lots.is_empty() or state.money < int(lots[0]["price"]) + cost:
			return {}
		_apply(Command.buy_lot(lots[0]["id"]))
	return {}


## careful: lexicographic best placement; buys a lot when the best one is unsafe or unserved
## and a lot would allow a safe, served one (money >= price + build cost + reserve).
func _choose_careful(type: String, cost: int) -> Dictionary:
	var best := _best_placement(state, type)
	if _is_good(best):
		return best
	# Cheapest lot that makes a safe and served placement possible, tried on a copy of the state.
	for lot in _lots_for_sale(state):
		var trial := state.copy()
		Simulation.apply_command(trial, Command.buy_lot(lot["id"]), data)
		if _is_good(_best_placement(trial, type)):
			if state.money >= int(lot["price"]) + cost + reserve:
				_apply(Command.buy_lot(lot["id"]))
				return _best_placement(state, type)
			return best
	if best.is_empty():  # nothing fits anywhere: cheapest lot that gives any placement
		for lot in _lots_for_sale(state):
			var trial := state.copy()
			Simulation.apply_command(trial, Command.buy_lot(lot["id"]), data)
			if not _scan(trial, type, true).is_empty() and state.money >= int(lot["price"]) + cost:
				_apply(Command.buy_lot(lot["id"]))
				return _best_placement(state, type)
	return best


func _is_good(best: Dictionary) -> bool:
	return not best.is_empty() and best["key"][0] == 0 and best["key"][1] == 0


## Best valid placement by key [in_zone, unserved, tie-break, y, x, rotation]; {} if none.
func _best_placement(st: GameState, type: String) -> Dictionary:
	var def: Dictionary = data.facilities[type]
	var unserved: Array = []  # rects of the facilities with slots that no warehouse serves yet
	if def.has("storage_capacity"):
		for facility in SimQueries.map_facilities(st, data):
			if data.facilities[facility["type"]].has("slots") \
					and not SimQueries.facility_spatial(st, data, int(facility["id"]))["served"]:
				unserved.append(facility["rect"])
	var best := {}
	for candidate in _scan(st, type, false):
		var key := _careful_key(def, candidate, unserved)
		if best.is_empty() or _key_less(key, best["key"]):
			best = candidate
			best["key"] = key
	return best


func _careful_key(def: Dictionary, candidate: Dictionary, unserved: Array) -> Array:
	var check: Dictionary = candidate["check"]
	var zone_hit: bool = not check.get("zone_contains", []).is_empty() if def.has("safety_radius_cells") \
		else not check.get("in_safety_zone_of", []).is_empty()
	var not_served: bool = def.has("slots") and not bool(check.get("served", true))
	var tie := 0
	if def.has("launcher_capacity"):  # hall: cheapest roll-out to the closest pad
		var cheapest := -1
		for rollout in check.get("rollout", []):
			if cheapest < 0 or int(rollout["rollout_cost"]) < cheapest:
				cheapest = int(rollout["rollout_cost"])
		tie = maxi(0, cheapest)
	elif def.has("storage_capacity"):  # warehouse: most unserved facilities it would serve
		var radius := int(data.layout.get("service_radius_cells", 0))
		var count := 0
		for rect in unserved:
			if SimQueries.gap_cells(check["rect"], rect) <= radius:
				count += 1
		tie = -count
	return [1 if zone_hit else 0, 1 if not_served else 0, tie, candidate["y"], candidate["x"], candidate["rotation"]]


func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Before each end_day: work points the unserved facilities will lose today.
func _tally_unserved_loss() -> void:
	if not data.has_map() or not data.layout.has("unserved_productivity_pct"):
		return
	for facility in state.facilities:
		if facility["status"] != "ready" or facility["jobs"].is_empty():
			continue
		var rate := SimQueries.facility_rate(data, facility)
		if rate > 0 and not SimQueries.facility_spatial(state, data, int(facility["id"]))["served"]:
			_pending_loss[int(facility["id"])] = rate - rate * int(data.layout["unserved_productivity_pct"]) / 100


## At the end of the game: facilities inside a safety zone, facilities without service.
func _tally_final_layout() -> void:
	if not data.has_map():
		return
	for facility in SimQueries.map_facilities(state, data):
		var spatial := SimQueries.facility_spatial(state, data, int(facility["id"]))
		if not spatial["in_safety_zone_of"].is_empty():
			final_in_zone += 1
		if data.facilities[facility["type"]].has("slots") and not spatial["served"]:
			final_unserved += 1

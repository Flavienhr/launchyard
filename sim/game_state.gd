class_name GameState
extends RefCounted
## The complete state of a game. Pure data: no Node, no IO, no rules.

var game_seed: int = 0
var day: int = 0
var money: int = 0
var stock: Dictionary = {}     # component_id -> quantity
var facilities: Array = []     # facility instances, see Simulation._new_facility
var technicians_hired: int = 0
var next_facility_id: int = 1
var pending_orders: Array = [] # orders in transit, see Simulation._apply_order
var next_order_id: int = 1
var next_job_id: int = 1
var launchers: Array = []      # {id, model, location_facility_id}, see Simulation._finish_job
var next_launcher_id: int = 1
var contracts: Array = []      # see ContractRules / spec 002 R1
var next_contract_id: int = 1
var reputation: int = 0
var launches: Array = []       # {id, launcher_id, pad_id, contract_id, launch_day, scrubs}, spec 003 R2
var next_launch_id: int = 1
var model_stats: Dictionary = {} # model -> {successes}, spec 003 R3
var days_in_debt: int = 0      # consecutive days with money < 0, spec 004 R1
var game_over: bool = false    # bankruptcy reached, spec 004 R3
var recipe_attempts: Dictionary = {} # recipe_id -> jobs that reached quality control, spec 006 R4
var recipe_scrapped: Dictionary = {} # recipe_id -> jobs scrapped at quality control
var market: Dictionary = MarketRules.empty_state() # {index, prev_index, shortages: id -> ends_day, spot_used}, spec 007

var supply_contracts: Array = [] # see SupplyRules, spec 007 R4
var next_supply_contract_id: int = 1
var owned_lots: Array = []     # lot ids bought or owned at start, spec 008 R1

## Cumulative counters, kept in every game (spec 009 R3):
## kit_consumed[component_id] = parts consumed by jobs whose recipe makes a launcher (at job_started),
## components_made[component_id] = parts that actually entered the stock.
var stats: Dictionary = empty_stats()


static func empty_stats() -> Dictionary:
	return {"kit_consumed": {}, "components_made": {}}


func to_dict() -> Dictionary:
	return {
		"game_seed": game_seed,
		"day": day,
		"money": money,
		"stock": stock.duplicate(true),
		"facilities": facilities.duplicate(true),
		"technicians_hired": technicians_hired,
		"next_facility_id": next_facility_id,
		"pending_orders": pending_orders.duplicate(true),
		"next_order_id": next_order_id,
		"next_job_id": next_job_id,
		"launchers": launchers.duplicate(true),
		"next_launcher_id": next_launcher_id,
		"contracts": contracts.duplicate(true),
		"next_contract_id": next_contract_id,
		"reputation": reputation,
		"launches": launches.duplicate(true),
		"next_launch_id": next_launch_id,
		"model_stats": model_stats.duplicate(true),
		"days_in_debt": days_in_debt,
		"game_over": game_over,
		"recipe_attempts": recipe_attempts.duplicate(true),
		"recipe_scrapped": recipe_scrapped.duplicate(true),
		"market": market.duplicate(true),
		"supply_contracts": supply_contracts.duplicate(true),
		"next_supply_contract_id": next_supply_contract_id,
		"owned_lots": owned_lots.duplicate(),
		"stats": stats.duplicate(true),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.game_seed = int(d["game_seed"])
	s.day = int(d["day"])
	s.money = int(d["money"])
	s.stock = d["stock"].duplicate(true)
	for component_id in s.stock:
		s.stock[component_id] = int(s.stock[component_id])
	s.facilities = d["facilities"].duplicate(true)
	for facility in s.facilities:
		# JSON turns ints into floats: recast.
		for key in ["id", "ready_day", "assigned", "launcher_id", "refurb_until_day"]:
			facility[key] = int(facility[key])
		# Spec 008 R2: position (null without a map; absent in older saves).
		for key in ["x", "y", "rotation"]:
			facility[key] = null if facility.get(key) == null else int(facility[key])
		for job in facility["jobs"]:
			job["id"] = int(job["id"])
			job["progress"] = int(job["progress"])
			job["qc_passed"] = bool(job.get("qc_passed", false))
			job["scrap_rate"] = float(job.get("scrap_rate", 0.0))
	s.technicians_hired = int(d["technicians_hired"])
	s.next_facility_id = int(d["next_facility_id"])
	s.pending_orders = d["pending_orders"].duplicate(true)
	for order in s.pending_orders:
		for key in ["id", "quantity", "arrival_day"]:
			order[key] = int(order[key])
		# Optional fields of supply-contract orders (spec 007).
		for key in ["contract_id", "scheduled_day", "invoice", "delay_days"]:
			if order.has(key):
				order[key] = int(order[key])
	s.next_order_id = int(d["next_order_id"])
	s.next_job_id = int(d["next_job_id"])
	s.launchers = d["launchers"].duplicate(true)
	for launcher in s.launchers:
		for key in ["id", "location_facility_id"]:
			launcher[key] = int(launcher[key])
	s.next_launcher_id = int(d["next_launcher_id"])
	s.contracts = d["contracts"].duplicate(true)
	for contract in s.contracts:
		for key in ["id", "payload_kg", "payment", "advance", "penalty", "deadline_day", "offer_expires_day"]:
			contract[key] = int(contract[key])
	s.next_contract_id = int(d["next_contract_id"])
	s.reputation = int(d["reputation"])
	s.launches = d["launches"].duplicate(true)
	for launch in s.launches:
		for key in ["id", "launcher_id", "pad_id", "contract_id", "launch_day", "scrubs"]:
			launch[key] = int(launch[key])
	s.next_launch_id = int(d["next_launch_id"])
	s.model_stats = d["model_stats"].duplicate(true)
	for model in s.model_stats:
		s.model_stats[model]["successes"] = int(s.model_stats[model]["successes"])
	s.days_in_debt = int(d["days_in_debt"])
	s.game_over = bool(d["game_over"])
	s.recipe_attempts = d.get("recipe_attempts", {}).duplicate(true)
	for recipe_id in s.recipe_attempts:
		s.recipe_attempts[recipe_id] = int(s.recipe_attempts[recipe_id])
	s.recipe_scrapped = d.get("recipe_scrapped", {}).duplicate(true)
	for recipe_id in s.recipe_scrapped:
		s.recipe_scrapped[recipe_id] = int(s.recipe_scrapped[recipe_id])
	s.market = _market_from_dict(d.get("market", MarketRules.empty_state()))
	s.supply_contracts = d.get("supply_contracts", []).duplicate(true)
	for contract in s.supply_contracts:
		for key in ["id", "quantity", "period_days", "deliveries", "deliveries_done", "next_delivery_day",
				"price_pct", "discount_pct", "contract_unit_price", "invoiced_total"]:
			if contract.has(key):
				contract[key] = int(contract[key])
		contract["invoiced_total"] = int(contract.get("invoiced_total", 0))
	s.next_supply_contract_id = int(d.get("next_supply_contract_id", 1))
	s.owned_lots = d.get("owned_lots", []).duplicate()
	s.stats = _stats_from_dict(d.get("stats", empty_stats()))
	return s


## JSON turns ints into floats: recast every counter.
static func _stats_from_dict(d: Dictionary) -> Dictionary:
	var out := empty_stats()
	for key in out:
		for id in d.get(key, {}):
			out[key][id] = int(d[key][id])
	return out


## JSON turns ints into floats: recast every number of the market state.
static func _market_from_dict(d: Dictionary) -> Dictionary:
	var out := MarketRules.empty_state()
	for key in out:
		for id in d.get(key, {}):
			out[key][id] = int(d[key][id])
	return out


func copy() -> GameState:
	return GameState.from_dict(to_dict())

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
		for job in facility["jobs"]:
			job["id"] = int(job["id"])
			job["progress"] = int(job["progress"])
	s.technicians_hired = int(d["technicians_hired"])
	s.next_facility_id = int(d["next_facility_id"])
	s.pending_orders = d["pending_orders"].duplicate(true)
	for order in s.pending_orders:
		for key in ["id", "quantity", "arrival_day"]:
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
	return s


func copy() -> GameState:
	return GameState.from_dict(to_dict())

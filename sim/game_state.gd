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
var contracts: Array = []      # see ContractRules / spec 002 R1
var next_contract_id: int = 1
var reputation: int = 0


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
		"contracts": contracts.duplicate(true),
		"next_contract_id": next_contract_id,
		"reputation": reputation,
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.game_seed = int(d["game_seed"])
	s.day = int(d["day"])
	s.money = int(d["money"])
	s.stock = d["stock"].duplicate(true)
	s.facilities = d["facilities"].duplicate(true)
	for facility in s.facilities:
		# JSON turns ints into floats: recast.
		for key in ["id", "ready_day", "assigned"]:
			facility[key] = int(facility[key])
	s.technicians_hired = int(d["technicians_hired"])
	s.next_facility_id = int(d["next_facility_id"])
	s.pending_orders = d["pending_orders"].duplicate(true)
	s.next_order_id = int(d["next_order_id"])
	s.contracts = d["contracts"].duplicate(true)
	for contract in s.contracts:
		for key in ["id", "payload_kg", "payment", "advance", "penalty", "deadline_day", "offer_expires_day"]:
			contract[key] = int(contract[key])
	s.next_contract_id = int(d["next_contract_id"])
	s.reputation = int(d["reputation"])
	return s


func copy() -> GameState:
	return GameState.from_dict(to_dict())

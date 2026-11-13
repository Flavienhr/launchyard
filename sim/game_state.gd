class_name GameState
extends RefCounted
## The complete state of a game. Pure data: no Node, no IO, no rules.

var game_seed: int = 0
var day: int = 0
var money: int = 0
var stock: Dictionary = {}     # component_id -> quantity
var facilities: Array = []     # facility ids built on the site
var pending_orders: Array = [] # orders in transit, see Simulation._apply_order
var next_order_id: int = 1


func to_dict() -> Dictionary:
	return {
		"game_seed": game_seed,
		"day": day,
		"money": money,
		"stock": stock.duplicate(true),
		"facilities": facilities.duplicate(true),
		"pending_orders": pending_orders.duplicate(true),
		"next_order_id": next_order_id,
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.game_seed = int(d["game_seed"])
	s.day = int(d["day"])
	s.money = int(d["money"])
	s.stock = d["stock"].duplicate(true)
	s.facilities = d["facilities"].duplicate(true)
	s.pending_orders = d["pending_orders"].duplicate(true)
	s.next_order_id = int(d["next_order_id"])
	return s


func copy() -> GameState:
	return GameState.from_dict(to_dict())

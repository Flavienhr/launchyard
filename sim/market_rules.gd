class_name MarketRules
extends RefCounted
## Spec 007 R1-R2: price index per component and shortages. Exogenous: only
## the seed and the day drive it (stream SimRng.MARKET), never player actions.
## A component absent from data.market is neutral: index PERMILLE, no shortage.

## Unit of the index (1000 = catalog price), not a balance value.
const PERMILLE := 1000
## Unit of the percentages in market.json (reversion, shortage capacity).
const PERCENT := 100
## Value returned by the spot capacity queries when no cap applies.
const UNLIMITED := -1


static func empty_state() -> Dictionary:
	return {"index": {}, "prev_index": {}, "shortages": {}, "spot_used": {}}


static func is_active(data: GameData) -> bool:
	return not data.market.is_empty()


## Row of data.market.components for a component, or {} when absent.
static func params(data: GameData, component_id: String) -> Dictionary:
	for row in data.market.get("components", []):
		if row["id"] == component_id:
			return row
	return {}


## Initial market state: every listed component at index_base.
static func initial_state(data: GameData) -> Dictionary:
	var market := empty_state()
	if not is_active(data):
		return market
	for row in data.market.get("components", []):
		market["index"][row["id"]] = int(data.market["index_base"])
		market["prev_index"][row["id"]] = int(data.market["index_base"])
	return market


static func index_of(state: GameState, data: GameData, component_id: String) -> int:
	if params(data, component_id).is_empty():
		return PERMILLE
	return int(state.market["index"].get(component_id, data.market["index_base"]))


## Day the active shortage ends, or -1 (none, or component not in market.json).
static func shortage_ends_day(state: GameState, data: GameData, component_id: String) -> int:
	if params(data, component_id).is_empty():
		return -1
	return int(state.market["shortages"].get(component_id, -1))


static func in_shortage(state: GameState, data: GameData, component_id: String) -> bool:
	return shortage_ends_day(state, data, component_id) >= 0


## Index including the shortage surcharge (R1).
static func effective_index(state: GameState, data: GameData, component_id: String) -> int:
	var value := index_of(state, data, component_id)
	if in_shortage(state, data, component_id):
		value += int(data.market["shortage_price_bonus_permille"])
	return value


## Integer price, rounded half up (R1).
static func spot_price(state: GameState, data: GameData, unit_price: int, component_id: String) -> int:
	return (unit_price * effective_index(state, data, component_id) + PERMILLE / 2) / PERMILLE


## Spec 007 R3: delivery delay of a spot order, shortage included.
static func spot_lead_days(state: GameState, data: GameData, lead_time_days: int, component_id: String) -> int:
	if in_shortage(state, data, component_id):
		return lead_time_days + int(data.market["shortage_extra_lead_days"])
	return lead_time_days


## Spot capacity of a catalog entry for the current period (R3): the entry's
## spot_capacity_per_period, scaled by shortage_capacity_pct during a shortage.
## UNLIMITED when the market is inactive, the component is absent from
## market.json, or the entry has no spot_capacity_per_period.
static func spot_capacity(state: GameState, data: GameData, supplier_id: String, component_id: String) -> int:
	if not is_active(data) or params(data, component_id).is_empty():
		return UNLIMITED
	var entry := data.catalog_entry(supplier_id, component_id)
	if not entry.has("spot_capacity_per_period"):
		return UNLIMITED
	var capacity := int(entry["spot_capacity_per_period"])
	if in_shortage(state, data, component_id):
		capacity = capacity * int(data.market["shortage_capacity_pct"]) / PERCENT
	return capacity


## Spot units already bought from this entry in the current period (R3).
static func spot_used(state: GameState, supplier_id: String, component_id: String) -> int:
	return int(state.market["spot_used"].get(spot_key(supplier_id, component_id), 0))


static func spot_key(supplier_id: String, component_id: String) -> String:
	return "%s|%s" % [supplier_id, component_id]


## True on the day whose resolution updates the market (R2): (J + 1) % period == 0.
static func is_update_day(state: GameState, data: GameData) -> bool:
	return is_active(data) and (state.day + 1) % int(data.market["market_period_days"]) == 0


## Weekly update (R2), run at the resolution of state.day. Returns the events;
## `make_event` builds them (Simulation._event).
static func update(state: GameState, data: GameData, make_event: Callable) -> Array:
	var events: Array = []
	var m: Dictionary = data.market
	var period := int(m["market_period_days"])
	var tomorrow := state.day + 1
	var rng := SimRng.for_stream(state, SimRng.MARKET)
	var rows: Array = m["components"].duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	state.market["prev_index"] = state.market["index"].duplicate()
	state.market["spot_used"] = {}
	var shortage_events: Array = []
	for row in rows:
		var id: String = row["id"]
		var vol := int(row["volatility_permille"])
		var shock := rng.randi_range(-vol, vol)
		var current := int(state.market["index"].get(id, m["index_base"]))
		var reversion := ((int(m["index_base"]) - current) * int(m["reversion_pct"])) / 100  # truncates toward 0
		state.market["index"][id] = clampi(current + shock + reversion, int(m["index_min"]), int(m["index_max"]))
		if state.market["shortages"].has(id):
			if tomorrow >= int(state.market["shortages"][id]):
				state.market["shortages"].erase(id)
				shortage_events.append(make_event.call("shortage_ended", {"component_id": id, "ends_day": tomorrow}))
		elif rng.randf() < float(row["shortage_chance"]):
			var periods := rng.randi_range(int(m["shortage_min_periods"]), int(m["shortage_max_periods"]))
			var ends := tomorrow + periods * period
			state.market["shortages"][id] = ends
			shortage_events.append(make_event.call("shortage_started", {"component_id": id, "ends_day": ends}))
	events.append(make_event.call("market_updated", {"index": state.market["index"].duplicate()}))
	events.append_array(shortage_events)
	return events

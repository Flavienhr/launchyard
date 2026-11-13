extends RefCounted
## Inline test data: tests never depend on the real balance values in data/,
## so tuning the game cannot break the rules' tests.

const START_MONEY := 10_000
const UNIT_PRICE := 100
const LEAD_TIME := 3
const DELAY_DAYS := 2
const UPKEEP := 50
const CAPACITY := 20
const SHOP_COST := 1_000
const SHOP_DAYS := 3
const SHOP_UPKEEP := 30


static func data(delay_chance := 0.0) -> GameData:
	return GameData.from_dicts(
		[{"id": "steel", "name": "Steel", "mass_kg": 100, "storage_units": 1}],
		[{
			"id": "acme",
			"name": "Acme",
			"delay_chance": delay_chance,
			"delay_days": DELAY_DAYS,
			"catalog": [{"component_id": "steel", "unit_price": UNIT_PRICE, "lead_time_days": LEAD_TIME}],
		}],
		[{"id": "warehouse", "name": "Warehouse", "upkeep_per_day": UPKEEP, "storage_capacity": CAPACITY},
		{"id": "shop", "name": "Shop", "upkeep_per_day": SHOP_UPKEEP, "slots": 3, "productivity_per_slot": 10,
			"buildable": true, "build_cost": SHOP_COST, "build_days": SHOP_DAYS, "max_count": 1}],
		{"money": START_MONEY, "facilities": ["warehouse"]})


## Runs `days` days, applying `commands_by_day[day]` (if any) on each day.
static func run(state: GameState, data: GameData, days: int, commands_by_day := {}) -> StepResult:
	var result := StepResult.new(state, [])
	var events: Array = []
	for i in days:
		result = Simulation.step(result.state, commands_by_day.get(result.state.day, []), data)
		events.append_array(result.events)
	return StepResult.new(result.state, events)


static func types(events: Array) -> Array:
	return events.map(func(e): return e["type"])

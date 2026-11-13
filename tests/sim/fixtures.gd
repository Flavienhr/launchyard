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
const HIRE_COST := 100
const FIRE_COST := 50
const SALARY := 10
const MAX_TECHS := 5
const MAX_QUEUE := 3
const SITE_ID := "pad_site"
const AZ_MIN := 45
const AZ_MAX := 110
const LEO_AZ := 90
const SSO_AZ := 195
const LEO_KG := 2_000
const SEASON_DAYS := 10
const SCRUB_BY_SEASON := [0.1, 0.2, 0.3, 0.4]


static func data(delay_chance := 0.0) -> GameData:
	return GameData.from_files({
		"components": {"components": [
			{"id": "steel", "name": "Steel", "mass_kg": 100, "storage_units": 1},
			{"id": "tank", "name": "Tank", "mass_kg": 100, "storage_units": 2},
			{"id": "engine", "name": "Engine", "mass_kg": 100, "storage_units": 1}]},
		"suppliers": {"suppliers": [{
			"id": "acme",
			"name": "Acme",
			"delay_chance": delay_chance,
			"delay_days": DELAY_DAYS,
			"catalog": [{"component_id": "steel", "unit_price": UNIT_PRICE, "lead_time_days": LEAD_TIME}],
		}]},
		"facilities": {"facilities": [
			{"id": "warehouse", "name": "Warehouse", "upkeep_per_day": UPKEEP, "storage_capacity": CAPACITY},
			{"id": "shop", "name": "Shop", "upkeep_per_day": SHOP_UPKEEP, "slots": 3, "productivity_per_slot": 10,
				"buildable": true, "build_cost": SHOP_COST, "build_days": SHOP_DAYS, "max_count": 1},
			{"id": "hall", "name": "Hall", "upkeep_per_day": 0, "slots": 2, "productivity_per_slot": 10,
				"launcher_capacity": 1}]},
		"start": {"money": START_MONEY, "facilities": ["warehouse"], "site": SITE_ID},
		"staff": {"technician": {"hire_cost": HIRE_COST, "fire_cost": FIRE_COST,
			"technician_salary_per_day": SALARY, "max_technicians": MAX_TECHS},
			"max_queue_length": MAX_QUEUE},
		"orbits": {"orbits": [{"id": "leo", "azimuth_deg": LEO_AZ}, {"id": "sso", "azimuth_deg": SSO_AZ}]},
		"sites": {"sites": [site()]},
		"launchers": {"launchers": [{"id": "l1", "payload_kg": {"leo": LEO_KG}, "reliability_base": 0.5,
			"reliability_gain_per_success": 0.1, "reliability_max": 1.0}]},
		"recipes": {"recipes": [
			{"id": "weld", "facility_type": "shop", "inputs": {"steel": 2},
				"output": {"component_id": "tank", "quantity": 1}, "work_points": 20},
			{"id": "weld_long", "facility_type": "shop", "inputs": {"steel": 2},
				"output": {"component_id": "tank", "quantity": 1}, "work_points": 25},
			{"id": "assemble", "facility_type": "hall", "inputs": {"tank": 1, "engine": 1},
				"output": {"launcher_model": "l1"}, "work_points": 20}]},
	})


## Launch site fixture: reaches [AZ_MIN, AZ_MAX], 4 seasons of SEASON_DAYS days.
static func site(bonus := {}) -> Dictionary:
	return {"id": SITE_ID, "azimuth_ranges": [[AZ_MIN, AZ_MAX]], "payload_bonus_pct": bonus,
		"season_length_days": SEASON_DAYS, "start_day_offset": 0,
		"season_names": ["a", "b", "c", "d"], "scrub_chance_by_season": SCRUB_BY_SEASON}


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

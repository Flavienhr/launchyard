extends TestCase
## Spec 006 R4, criteria 4 to 12: scrap, learning curve, quality control.
## Data is built here (not in fixtures.gd); rates are forced to 0 or 1 when a
## test must not depend on seeds.

const F := preload("res://tests/sim/fixtures.gd")
const ORDER_MILL_FIRST := ["warehouse", "mill", "forge"]
const ORDER_FORGE_FIRST := ["warehouse", "forge", "mill"]
const SCRAP_HALF := {"scrap_rate_start": 0.5, "scrap_rate_floor": 0.5}


## Warehouse + mill + forge. `order` gives the start order (= instance ids).
## make_engine scrap parameters come from `scrap`.
func _setup(scrap: Dictionary, order := ORDER_MILL_FIRST, seed_value := 1) -> Array:
	var data := F.data()
	data.components["ore"] = {"id": "ore", "name": "Ore", "mass_kg": 1, "storage_units": 1}
	data.components["part"] = {"id": "part", "name": "Part", "mass_kg": 1, "storage_units": 1}
	for type in ["mill", "forge"]:
		data.facilities[type] = {"id": type, "name": type, "upkeep_per_day": 0, "slots": 2,
			"productivity_per_slot": 10, "buildable": true, "build_cost": 1000, "build_days": 2, "max_count": 1}
	data.recipes["make_part"] = {"id": "make_part", "facility_type": "mill", "inputs": {"ore": 1},
		"output": {"component_id": "part", "quantity": 1}, "work_points": 20}
	var engine := {"id": "make_engine", "facility_type": "forge", "inputs": {"part": 1, "ore": 1},
		"output": {"component_id": "engine", "quantity": 1}, "work_points": 20}
	engine.merge(scrap)
	data.recipes["make_engine"] = engine
	data.staff["max_queue_length"] = 10
	data.start = {"money": F.START_MONEY, "facilities": order, "technicians": 4,
		"assignments": {"mill": 2, "forge": 2}}
	return [Simulation.new_game(data, seed_value), data]


func _fid(state: GameState, type: String) -> int:
	for f in state.facilities:
		if f["type"] == type:
			return f["id"]
	return -1


func _jobs(state: GameState, type: String) -> Array:
	for f in state.facilities:
		if f["type"] == type:
			return f["jobs"]
	return []


func _count(events: Array, type: String) -> int:
	return F.types(events).count(type)


func _find(events: Array, type: String) -> Dictionary:
	for e in events:
		if e["type"] == type:
			return e
	return {}


func _queue_engine(state: GameState, n := 1) -> Array:
	return [Command.queue_job(_fid(state, "forge"), "make_engine", n)]


func _queue_part(state: GameState) -> Command:
	return Command.queue_job(_fid(state, "mill"), "make_part", 1)


func test_two_level_chain_mill_first() -> void:
	var s := _setup({})
	var state: GameState = s[0]
	state.stock = {"ore": 2}
	var r := F.run(state, s[1], 1, {0: [_queue_part(state)] + _queue_engine(state)})
	assert_eq(r.state.stock.get("part", 0), 0)
	assert_eq(r.state.stock.get("engine", 0), 1)
	assert_eq(r.state.stock.get("ore", 0), 0)


func test_two_level_chain_forge_first() -> void:
	var s := _setup({}, ORDER_FORGE_FIRST)
	var state: GameState = s[0]
	state.stock = {"ore": 2}
	var r := F.run(state, s[1], 1, {0: [_queue_part(state)] + _queue_engine(state)})
	assert_eq(_find(r.events, "job_blocked").get("reason", ""), "missing_inputs")
	assert_eq(r.state.stock.get("part", 0), 1)
	assert_eq(r.state.stock.get("engine", 0), 0)
	r = F.run(r.state, s[1], 1)
	assert_eq(r.state.stock.get("engine", 0), 1)
	assert_eq(r.state.stock.get("part", 0), 0)
	assert_eq(r.state.stock.get("ore", 0), 0)


func test_certain_scrap() -> void:
	var s := _setup({"scrap_rate_start": 1.0, "scrap_rate_floor": 1.0})
	var state: GameState = s[0]
	state.stock = {"part": 1, "ore": 1}
	var r := F.run(state, s[1], 1, {0: _queue_engine(state)})
	var scrapped := _find(r.events, "job_scrapped")
	assert_eq(scrapped.get("recipe_id", ""), "make_engine")
	assert_eq(scrapped.get("scrap_rate", -1.0), 1.0)
	assert_eq(_count(r.events, "job_completed"), 0)
	assert_eq(r.state.stock.get("engine", 0), 0)
	assert_eq(r.state.stock.get("part", 0), 0)
	assert_eq(r.state.stock.get("ore", 0), 0)
	assert_eq(_jobs(r.state, "forge").size(), 0)
	assert_eq(r.state.recipe_attempts["make_engine"], 1)


func test_recipe_scrapped_counts_and_survives_json() -> void:
	var s := _setup({"scrap_rate_start": 1.0, "scrap_rate_floor": 1.0})
	var state: GameState = s[0]
	state.stock = {"part": 1, "ore": 1}
	var r := F.run(state, s[1], 1, {0: _queue_engine(state)})
	assert_eq(r.state.recipe_scrapped["make_engine"], 1)
	assert_eq(SimQueries.scrap_info(r.state, s[1], "make_engine")["scrapped"], 1)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(r.state.to_dict())))
	assert_eq(restored.recipe_scrapped["make_engine"], 1)
	assert_eq(typeof(restored.recipe_scrapped["make_engine"]), TYPE_INT)


## Scrap results of the forge over 20 seeds, with or without a mill job the same day.
func _forge_outcomes(with_mill: bool) -> Array:
	var out: Array = []
	for seed_value in range(1, 21):
		var s := _setup(SCRAP_HALF, ORDER_MILL_FIRST, seed_value)
		var state: GameState = s[0]
		state.stock = {"ore": 2, "part": 1}
		var cmds := _queue_engine(state)
		if with_mill:
			cmds.append(_queue_part(state))
		var r := F.run(state, s[1], 1, {0: cmds})
		if with_mill:
			assert_eq(_count(r.events, "job_completed") >= 1, true)
		out.append(_count(r.events, "job_scrapped"))
	return out


func test_recipe_without_scrap_draws_nothing() -> void:
	var with_mill := _forge_outcomes(true)
	var without_mill := _forge_outcomes(false)
	assert_eq(with_mill, without_mill)
	assert_true(0 in without_mill and 1 in without_mill, "20 seeds should mix both outcomes")


func test_learning_curve() -> void:
	var s := _setup({"scrap_rate_start": 0.5, "scrap_rate_drop_per_attempt": 0.1, "scrap_rate_floor": 0.1})
	var state: GameState = s[0]
	var expected := {0: 0.5, 3: 0.2, 4: 0.1, 10: 0.1}
	for attempts in expected:
		state.recipe_attempts["make_engine"] = attempts
		var rate := SimQueries.scrap_rate(state, s[1], "make_engine")
		assert_true(absf(rate - expected[attempts]) < 0.000001, "attempts %d -> %f" % [attempts, rate])
	assert_eq(SimQueries.scrap_rate(state, s[1], "make_part"), 0.0)
	assert_eq(SimQueries.scrap_rate(state, s[1], "weld"), 0.0)


func test_scraps_advance_the_curve() -> void:
	var s := _setup({"scrap_rate_start": 1.0, "scrap_rate_drop_per_attempt": 1.0, "scrap_rate_floor": 0.0})
	var state: GameState = s[0]
	state.stock = {"part": 2, "ore": 2}
	var r := F.run(state, s[1], 1, {0: _queue_engine(state, 2)})
	assert_eq(_count(r.events, "job_scrapped"), 1)
	assert_eq(r.state.stock.get("engine", 0), 0)
	r = F.run(r.state, s[1], 1)
	assert_eq(_count(r.events, "job_scrapped"), 0)
	assert_eq(_find(r.events, "job_completed").get("scrap_rate", -1.0), 0.0)
	assert_eq(r.state.stock.get("engine", 0), 1)
	assert_eq(r.state.recipe_attempts["make_engine"], 2)


func test_blocked_output_does_not_redraw() -> void:
	# Warehouse capacity 20: 20 steel fills it once part and ore are consumed.
	for seed_value in range(1, 50):
		var s := _setup(SCRAP_HALF, ORDER_MILL_FIRST, seed_value)
		var state: GameState = s[0]
		state.stock = {"part": 1, "ore": 1, "steel": F.CAPACITY}
		var r := F.run(state, s[1], 1, {0: _queue_engine(state)})
		if _count(r.events, "job_scrapped") > 0:
			continue  # this seed scraps: look for one that passes the check
		assert_eq(_count(r.events, "output_blocked"), 1)
		assert_true(_jobs(r.state, "forge")[0]["qc_passed"])
		assert_eq(r.state.recipe_attempts["make_engine"], 1)
		r.state.stock["steel"] = 0
		var r2 := F.run(r.state, s[1], 1)
		assert_eq(_count(r2.events, "job_scrapped"), 0)
		assert_eq(r2.state.stock.get("engine", 0), 1)
		assert_eq(r2.state.recipe_attempts["make_engine"], 1)
		return
	assert_true(false, "no passing seed found")


func test_scrap_statistics() -> void:
	var scrapped := 0
	for seed_value in range(1, 1001):
		var s := _setup({"scrap_rate_start": 0.3, "scrap_rate_floor": 0.3}, ORDER_MILL_FIRST, seed_value)
		var state: GameState = s[0]
		state.stock = {"part": 1, "ore": 1}
		var r := F.run(state, s[1], 1, {0: _queue_engine(state)})
		scrapped += _count(r.events, "job_scrapped")
	assert_true(scrapped >= 250 and scrapped <= 350, "scrapped %d" % scrapped)


## Same seed and plan, with and without a scrapping workshop: delivery delays
## are identical (ADR 0005). Weather, launch, contract and event streams are
## checked at the stream level below.
func test_production_stream_isolated_from_deliveries() -> void:
	var delivery_types := ["order_placed", "delivery_delayed", "delivery_received"]
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var results: Array = []
		for scrap_rate in [0.0, 1.0]:
			var s := _setup({"scrap_rate_start": scrap_rate, "scrap_rate_floor": scrap_rate}, ORDER_MILL_FIRST, seed_value)
			for supplier in s[1].suppliers.values():
				supplier["delay_chance"] = 0.5
			var state: GameState = s[0]
			state.stock = {"part": 3, "ore": 3}
			var cmds := _queue_engine(state, 3)
			for i in 4:
				cmds.append(Command.order("acme", "steel", 1))
			var r := F.run(state, s[1], 8, {0: cmds})
			results.append(r.events.filter(func(e): return e["type"] in delivery_types))
			assert_eq(_count(r.events, "job_scrapped") > 0, scrap_rate == 1.0)
		assert_eq(results[0], results[1])


func test_production_stream_does_not_shift_other_streams() -> void:
	var s := _setup({})
	var state: GameState = s[0]
	var others := [SimRng.DELIVERIES, SimRng.CONTRACTS, SimRng.WEATHER, SimRng.LAUNCH, SimRng.EVENTS]
	var baseline: Array = []
	for stream in others:
		baseline.append(SimRng.for_stream(state, stream).randi())
	var production := SimRng.for_stream(state, SimRng.PRODUCTION)
	for i in 100:
		production.randf()
	for i in others.size():
		assert_eq(SimRng.for_stream(state, others[i]).randi(), baseline[i])
	assert_true(SimRng.for_stream(state, SimRng.PRODUCTION).randi() not in baseline)


func test_attempts_survive_serialization() -> void:
	var s := _setup({})
	var state: GameState = s[0]
	state.recipe_attempts["make_engine"] = 3
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(copy.recipe_attempts["make_engine"], 3)
	assert_eq(typeof(copy.recipe_attempts["make_engine"]), TYPE_INT)

extends TestCase
## Spec 007 R1-R2, criteria 1-5, 18, 19: price index, weekly update, shortages.
## Market data is built here; shortage chances are forced to 0 or 1.

const F := preload("res://tests/sim/fixtures.gd")
const PERIOD := 7
const BASE := 1000
const MIN_INDEX := 500
const MAX_INDEX := 2000
const BONUS := 500


func _data(volatility := 0, chance := 0.0, reversion := 0, periods := 2) -> GameData:
	var data := F.data()
	data.market = {
		"market_period_days": PERIOD, "index_base": BASE, "index_min": MIN_INDEX, "index_max": MAX_INDEX,
		"reversion_pct": reversion, "shortage_price_bonus_permille": BONUS, "shortage_extra_lead_days": 3,
		"shortage_capacity_pct": 30, "shortage_min_periods": periods, "shortage_max_periods": periods,
		"components": [{"id": "steel", "volatility_permille": volatility, "shortage_chance": chance}],
	}
	return data


func _snapshot(state: GameState) -> Dictionary:
	return {"index": state.market["index"].duplicate(), "shortages": state.market["shortages"].duplicate()}


func test_spot_price_follows_index() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.market["index"]["steel"] = 1200
	assert_eq(SimQueries.spot_price(state, data, "acme", "steel"), 120)
	assert_eq(3 * SimQueries.spot_price(state, data, "acme", "steel"), 360)


func test_spot_price_rounds_half_up() -> void:
	var data := _data()
	data.suppliers["acme"]["catalog"][0]["unit_price"] = 333
	var state := Simulation.new_game(data, 1)
	state.market["index"]["steel"] = 1001
	assert_eq(SimQueries.spot_price(state, data, "acme", "steel"), 333)
	state.market["index"]["steel"] = 1002
	assert_eq(SimQueries.spot_price(state, data, "acme", "steel"), 334)


func test_spot_price_unknown_entry() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	assert_eq(SimQueries.spot_price(state, data, "acme", "gold"), -1)


func test_update_only_on_period_boundary() -> void:
	var data := _data(0, 0.0, 50)
	var state := Simulation.new_game(data, 1)
	state.market["index"]["steel"] = 1400
	var events: Array = []
	for day in PERIOD:
		assert_eq(state.market["index"]["steel"], 1400, "day %d" % day)
		var result := Simulation.step(state, [], data)
		state = result.state
		events.append_array(result.events.map(func(e): return [e["type"], state.day - 1]))
	assert_eq(state.day, PERIOD)
	assert_eq(state.market["index"]["steel"], 1200)
	assert_eq(events.filter(func(e): return e[0] == "market_updated"), [["market_updated", PERIOD - 1]])


func test_index_stays_in_bounds() -> void:
	var data := _data(1000)
	for seed_value in 50:
		var state := Simulation.new_game(data, seed_value)
		for day in 70:
			state = Simulation.step(state, [], data).state
			var index: int = state.market["index"]["steel"]
			assert_true(index >= MIN_INDEX and index <= MAX_INDEX, "seed %d day %d: %d" % [seed_value, day, index])


func test_shortage_lifecycle() -> void:
	var data := _data(0, 1.0)
	var state := Simulation.new_game(data, 1)
	var result := F.run(state, data, PERIOD)
	state = result.state
	assert_true("shortage_started" in F.types(result.events))
	var started: Dictionary = result.events.filter(func(e): return e["type"] == "shortage_started")[0]
	assert_eq(started["component_id"], "steel")
	assert_eq(started["ends_day"], 21)
	assert_eq(state.market["shortages"]["steel"], 21)
	assert_eq(SimQueries.spot_price(state, data, "acme", "steel"), 150)
	var snapshot := SimQueries.market_snapshot(state, data)
	assert_true(snapshot["steel"]["shortage"])
	assert_eq(snapshot["steel"]["ends_day"], 21)
	# Day 20 resolution ends it; no restart at the same update.
	var to_20 := F.run(state, data, 20 - state.day)
	assert_true(to_20.state.market["shortages"].has("steel"))
	var last := Simulation.step(to_20.state, [], data)
	assert_true("shortage_ended" in F.types(last.events))
	assert_true(not "shortage_started" in F.types(last.events))
	assert_eq(last.state.day, 21)
	assert_true(not last.state.market["shortages"].has("steel"))
	assert_eq(SimQueries.spot_price(last.state, data, "acme", "steel"), 100)
	# Next update (resolution of day 27) may start one again.
	var later := F.run(last.state, data, 7)
	assert_eq(later.state.market["shortages"].get("steel", -1), 28 + 2 * PERIOD)


func test_market_independent_of_player_actions() -> void:
	var data := _data(80, 0.1)
	var quiet := Simulation.new_game(data, 7)
	var busy := Simulation.new_game(data, 7)
	for day in 90:
		var commands: Array = []
		if day % 3 == 0:
			commands.append(Command.order("acme", "steel", 1))
		if day % 11 == 0:
			commands.append(Command.hire(1))
		quiet = Simulation.step(quiet, [], data).state
		busy = Simulation.step(busy, commands, data).state
		assert_eq(_snapshot(quiet), _snapshot(busy), "day %d" % day)


func test_market_independent_of_other_streams() -> void:
	var data := _data(80, 0.1)
	var plain := Simulation.new_game(data, 7)
	var noisy := Simulation.new_game(data, 7)
	for day in 28:
		# Consume the other streams in one game only.
		for stream in [SimRng.DELIVERIES, SimRng.CONTRACTS, SimRng.WEATHER, SimRng.LAUNCH, SimRng.EVENTS, SimRng.PRODUCTION]:
			SimRng.for_stream(noisy, stream).randf()
		plain = Simulation.step(plain, [], data).state
		noisy = Simulation.step(noisy, [], data).state
		assert_eq(_snapshot(plain), _snapshot(noisy))


func test_neutral_without_market_data() -> void:
	var data := F.data()  # no market.json
	var state := Simulation.new_game(data, 1)
	var result := F.run(state, data, 30)
	assert_true(not "market_updated" in F.types(result.events))
	assert_eq(SimQueries.spot_price(result.state, data, "acme", "steel"), F.UNIT_PRICE)
	assert_true(SimQueries.market_snapshot(result.state, data).is_empty())


func test_component_absent_from_market_is_neutral() -> void:
	var data := _data(0, 1.0)
	var state := Simulation.new_game(data, 1)
	state = F.run(state, data, PERIOD).state
	data.suppliers["acme"]["catalog"].append({"component_id": "engine", "unit_price": 40, "lead_time_days": 1})
	assert_eq(SimQueries.spot_price(state, data, "acme", "engine"), 40)
	assert_true(not state.market["index"].has("engine"))


func test_market_state_survives_json_roundtrip() -> void:
	var data := _data(80, 1.0)
	var state := F.run(Simulation.new_game(data, 3), data, PERIOD).state
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.market, state.market)
	assert_eq(restored.market["shortages"]["steel"], state.market["shortages"]["steel"])

extends TestCase
## Spec 007 R3, criteria 1, 5, 6: spot orders priced and capped by the market,
## plus the catalog price when there is no market. Market data is built here.

const F := preload("res://tests/sim/fixtures.gd")
const PERIOD := 7
const BASE := 1000
const BONUS := 500
const EXTRA_LEAD := 3
const CAPACITY_PCT := 30
const SPOT_CAPACITY := 10
const SPOT_LEAD := 2
const SHORTAGE_PERIODS := 2
const SHORTAGE_START_DAY := 7  # shortage_started at the resolution of day 6
const SHORTAGE_END_DAY := 21
const NEXT_SHORTAGE_DAY := 28
const UNLIMITED := -1


func _data(chance := 0.0) -> GameData:
	var data := F.data()
	var entry: Dictionary = data.suppliers["acme"]["catalog"][0]
	entry["lead_time_days"] = SPOT_LEAD
	entry["spot_capacity_per_period"] = SPOT_CAPACITY
	data.market = {
		"market_period_days": PERIOD, "index_base": BASE, "index_min": 500, "index_max": 2000,
		"reversion_pct": 0, "shortage_price_bonus_permille": BONUS, "shortage_extra_lead_days": EXTRA_LEAD,
		"shortage_capacity_pct": CAPACITY_PCT, "shortage_min_periods": SHORTAGE_PERIODS,
		"shortage_max_periods": SHORTAGE_PERIODS,
		"components": [{"id": "steel", "volatility_permille": 0, "shortage_chance": chance}],
	}
	return data


func test_order_debits_spot_price_not_catalog_price() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.market["index"]["steel"] = 1200
	var events := Simulation.apply_command(state, Command.order("acme", "steel", 3), data)
	assert_eq(F.types(events), ["order_placed"])
	assert_eq(events[0]["cost"], 360)
	assert_eq(state.money, F.START_MONEY - 360)


func test_shortage_surcharge_lead_time_and_capacity() -> void:
	# Criterion 5.
	var data := _data(1.0)
	var state := F.run(Simulation.new_game(data, 1), data, SHORTAGE_START_DAY).state
	assert_eq(state.day, SHORTAGE_START_DAY)
	assert_true(MarketRules.in_shortage(state, data, "steel"))
	assert_eq(state.market["shortages"]["steel"], SHORTAGE_END_DAY)
	assert_eq(SimQueries.spot_price(state, data, "acme", "steel"), 150)
	var money := state.money  # upkeep runs during the days above

	var rejected := Simulation.apply_command(state, Command.order("acme", "steel", 4), data)
	assert_eq(rejected[0]["reason"], "supplier_capacity")
	assert_eq(rejected[0]["remaining"], 3)
	assert_eq(state.money, money)
	assert_true(state.pending_orders.is_empty())

	var accepted := Simulation.apply_command(state, Command.order("acme", "steel", 3), data)
	assert_eq(F.types(accepted), ["order_placed"])
	assert_eq(state.pending_orders[0]["arrival_day"], SHORTAGE_START_DAY + SPOT_LEAD + EXTRA_LEAD)
	assert_eq(state.money, money - 3 * 150)


func test_shortage_ends_then_next_one_waits_for_next_update() -> void:
	# Criterion 5, second half.
	var data := _data(1.0)
	var state := F.run(Simulation.new_game(data, 1), data, SHORTAGE_START_DAY).state
	var ended := F.run(state, data, SHORTAGE_END_DAY - SHORTAGE_START_DAY)
	assert_eq(ended.state.day, SHORTAGE_END_DAY)
	assert_true(F.types(ended.events).has("shortage_ended"))
	assert_true(not (MarketRules.in_shortage(ended.state, data, "steel")))
	assert_eq(SimQueries.spot_price(ended.state, data, "acme", "steel"), 100)

	var quiet := F.run(ended.state, data, NEXT_SHORTAGE_DAY - 1 - SHORTAGE_END_DAY)
	assert_eq(quiet.state.day, NEXT_SHORTAGE_DAY - 1)
	assert_true(not (MarketRules.in_shortage(quiet.state, data, "steel")))

	var next := F.run(quiet.state, data, 1)
	assert_eq(next.state.day, NEXT_SHORTAGE_DAY)
	assert_eq(next.state.market["shortages"]["steel"], NEXT_SHORTAGE_DAY + SHORTAGE_PERIODS * PERIOD)


func test_order_quote_reports_spot_price_and_remaining_capacity() -> void:
	var data := _data(1.0)
	var state := F.run(Simulation.new_game(data, 1), data, SHORTAGE_START_DAY).state
	var quote := SimQueries.order_quote(state, data, "acme", "steel", 4)
	assert_eq(quote["unit_price"], 150)
	assert_eq(quote["total_cost"], 600)
	assert_eq(quote["spot_capacity_remaining"], 3)
	assert_true(not (quote["within_capacity"]))
	assert_eq(SimQueries.spot_capacity_remaining(state, data, "acme", "steel"), 3)


func test_capacity_per_period_resets_at_market_update() -> void:
	# Criterion 6.
	var data := _data()
	var state := Simulation.new_game(data, 1)
	assert_eq(SimQueries.spot_capacity_remaining(state, data, "acme", "steel"), SPOT_CAPACITY)

	var first := Simulation.apply_command(state, Command.order("acme", "steel", 6), data)
	assert_eq(F.types(first), ["order_placed"])
	var rejected := Simulation.apply_command(state, Command.order("acme", "steel", 5), data)
	assert_eq(rejected[0]["reason"], "supplier_capacity")
	assert_eq(rejected[0]["remaining"], 4)
	assert_eq(SimQueries.spot_capacity_remaining(state, data, "acme", "steel"), 4)

	state = F.run(state, data, PERIOD).state
	assert_eq(state.day, PERIOD)
	assert_eq(SimQueries.spot_capacity_remaining(state, data, "acme", "steel"), SPOT_CAPACITY)
	var later := Simulation.apply_command(state, Command.order("acme", "steel", 5), data)
	assert_eq(F.types(later), ["order_placed"])


func test_without_market_catalog_price_and_no_capacity_limit() -> void:
	var data := F.data()
	data.suppliers["acme"]["catalog"][0]["spot_capacity_per_period"] = 1
	var state := Simulation.new_game(data, 1)
	assert_eq(SimQueries.spot_price(state, data, "acme", "steel"), F.UNIT_PRICE)
	assert_eq(SimQueries.spot_capacity_remaining(state, data, "acme", "steel"), UNLIMITED)
	var events := Simulation.apply_command(state, Command.order("acme", "steel", 50), data)
	assert_eq(F.types(events), ["order_placed"])
	assert_eq(state.money, F.START_MONEY - 50 * F.UNIT_PRICE)

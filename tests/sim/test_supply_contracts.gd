extends TestCase
## Spec 007 R4-R8, criteria 7-17: supply contracts (signature, deliveries,
## guarantees, take-or-pay, termination), plus a 60-day end-to-end run.
## All data is built here (supplier s1/s2/s3 selling steel at 100, lead time 2).

const F := preload("res://tests/sim/fixtures.gd")
const UNIT := 100
const LEAD := 2
const PERIOD := 7
const BASE := 1000
const BONUS := 500
const FILL_PCT := 50
const BIG_WAREHOUSE := 1000
const MONEY := 100_000


func _data(delay_chance := 0.0, delay_days := 3, capacity := BIG_WAREHOUSE) -> GameData:
	var data := F.data()
	data.facilities["warehouse"]["upkeep_per_day"] = 0
	data.facilities["warehouse"]["storage_capacity"] = capacity
	var suppliers := []
	for id in ["s1", "s2", "s3"]:
		suppliers.append({"id": id, "name": id, "delay_chance": delay_chance, "delay_days": delay_days,
			"catalog": [{"component_id": "steel", "unit_price": UNIT, "lead_time_days": LEAD,
				"spot_capacity_per_period": 10, "contract_terms": {"min_quantity": 1, "max_quantity": 50}}]})
	suppliers.append({"id": "plain", "name": "plain", "delay_chance": 0.0, "delay_days": 1,
		"catalog": [{"component_id": "steel", "unit_price": UNIT, "lead_time_days": LEAD}]})
	data.suppliers.clear()
	for s in suppliers:
		data.suppliers[s["id"]] = s
	data.market = {
		"market_period_days": PERIOD, "index_base": BASE, "index_min": 500, "index_max": 2000,
		"reversion_pct": 0, "shortage_price_bonus_permille": BONUS, "shortage_extra_lead_days": 3,
		"shortage_capacity_pct": 30, "shortage_min_periods": 2, "shortage_max_periods": 2,
		"components": [{"id": "steel", "volatility_permille": 0, "shortage_chance": 0.0}],
	}
	data.supply_contracts = {
		"period_options_days": [7, 14], "min_deliveries": 2, "max_deliveries": 6,
		"volume_discount_tiers": [{"min_value": 3000, "pct": 5}],
		"fixed_premium_pct": 6, "priority_premium_pct": 4,
		"late_penalty_pct_per_day": 2, "late_penalty_cap_pct": 20,
		"holding_fee_per_unit_per_day": 10, "shortage_fill_pct": FILL_PCT, "take_or_pay_pct": 70,
		"skip_notice_days": 3, "termination_fee_pct": 40, "max_supply_contracts": 2,
	}
	data.rules = {"bankruptcy_warning_days": 1, "bankruptcy_grace_days": 5}
	return data


func _state(data: GameData, money := MONEY) -> GameState:
	var state := Simulation.new_game(data, 1)
	state.money = money
	return state


func _sign(state: GameState, data: GameData, supplier := "s1", quantity := 10, period := PERIOD,
		deliveries := 3, pricing := "fixed", priority := false) -> Array:
	return Simulation.apply_command(state, Command.sign_supply_contract(
		supplier, "steel", quantity, period, deliveries, pricing, priority), data)


## Steps `days` days; returns {state, events: [[events of day 0], ...]}.
func _run(state: GameState, data: GameData, days: int, commands_by_day := {}) -> Dictionary:
	var by_day: Array = []
	for i in days:
		var result := Simulation.step(state, commands_by_day.get(state.day, []), data)
		state = result.state
		by_day.append(result.events)
	return {"state": state, "events": by_day}


func _find(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)


func _all(by_day: Array, type: String) -> Array:
	var out: Array = []
	for day_events in by_day:
		out.append_array(_find(day_events, type))
	return out


func _days_with(by_day: Array, type: String) -> Array:
	var days: Array = []
	for i in by_day.size():
		if not _find(by_day[i], type).is_empty():
			days.append(i)
	return days


# Criterion 7
func test_fixed_price_frozen_at_signature() -> void:
	var data := _data()
	var state := _state(data)
	state.market["index"]["steel"] = 1100
	var events := _sign(state, data)
	assert_eq(events[0]["type"], "supply_contract_signed")
	assert_eq(events[0]["discount_pct"], 5)
	assert_eq(events[0]["unit_price"], 111)  # (110 * 101 + 50) div 100
	assert_eq(state.money, MONEY, "(nothing debited at signature)")
	state.market["index"]["steel"] = 1500
	var run := _run(state, data, 2)
	assert_eq(_all(run["events"], "supply_delivery_dispatched")[0]["invoice"], 1110)


# Criterion 8
func test_indexed_price_follows_the_day() -> void:
	var data := _data()
	var state := _state(data)
	state.market["index"]["steel"] = 1100
	var events := _sign(state, data, "s1", 10, PERIOD, 3, "indexed")
	assert_eq(events[0]["unit_price"], null)
	state.market["index"]["steel"] = 1500
	var run := _run(state, data, 2)
	assert_eq(_all(run["events"], "supply_delivery_dispatched")[0]["invoice"], 1430)  # (150 * 95 + 50) div 100


# Criterion 9
func test_schedule_invoices_and_receptions() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 17)
	assert_eq(_days_with(run["events"], "supply_delivery_dispatched"), [1, 8, 15])
	assert_eq(_days_with(run["events"], "delivery_received"), [1, 8, 15], "(received at the start of days 2, 9, 16)")
	assert_eq(_days_with(run["events"], "supply_contract_completed"), [15])
	for e in _all(run["events"], "supply_delivery_dispatched"):
		assert_eq(e["invoice"], 1010)
	assert_eq(run["state"].money, MONEY - 3 * 1010)
	assert_eq(run["state"].market["spot_used"].size(), 0, "(spot capacity untouched)")
	assert_eq(run["state"].supply_contracts[0]["status"], "completed")
	assert_eq(run["state"].stock["steel"], 30)


# Criterion 10
func test_full_warehouse_charges_holding_fees() -> void:
	var data := _data(0.0, 3, 20)
	var state := _state(data)
	state.stock["steel"] = 20
	_sign(state, data, "s1", 10, PERIOD, 2)
	var run := _run(state, data, 4)
	var by_day: Array = run["events"]
	assert_eq(_days_with(by_day, "warehouse_full"), [1, 2, 3])
	assert_eq(_find(by_day[1], "warehouse_full")[0]["contract_id"], 1)
	var fees := _all(by_day, "daily_costs").map(func(e): return e["holding_fees"])
	assert_eq(fees, [0, 100, 100, 100], "(10 x 1 x 10 per day of waiting)")
	assert_eq(MONEY - 1010 - 300, run["state"].money, "(invoice at the planned date, then fees)")
	run["state"].stock["steel"] = 10  # freed by hand on day 4
	var next := _run(run["state"], data, 1)
	assert_eq(_days_with(next["events"], "delivery_received"), [0])
	assert_eq(_all(next["events"], "daily_costs")[0]["holding_fees"], 0)
	assert_eq(next["state"].stock["steel"], 20)


# Criteria 11 and 12
func test_late_penalty_is_paid_by_the_supplier() -> void:
	var data := _data(1.0, 3)
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 5)
	assert_eq(_days_with(run["events"], "delivery_delayed"), [1])
	assert_eq(_days_with(run["events"], "supply_penalty_earned"), [4], "(3 days after the planned day 1)")
	var penalty: Dictionary = _all(run["events"], "supply_penalty_earned")[0]
	assert_eq(penalty["amount"], 60)  # 1010 * 6 div 100
	assert_eq(penalty["days_late"], 3)
	assert_eq(_all(run["events"], "daily_costs")[4]["supply_penalties"], 60)
	assert_eq(run["state"].money, MONEY - 1010 + 60)


func test_late_penalty_is_capped() -> void:
	var data := _data(1.0, 15)
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 17)
	assert_eq(_all(run["events"], "supply_penalty_earned")[0]["amount"], 202)  # 1010 * 20 div 100


func test_warehouse_wait_is_not_a_delay() -> void:
	var data := _data(0.0, 3, 20)
	var state := _state(data)
	state.stock["steel"] = 20
	_sign(state, data, "s1", 10, PERIOD, 2)
	var run := _run(state, data, 2)
	run["state"].stock["steel"] = 0
	var next := _run(run["state"], data, 1)
	assert_true(_all(next["events"], "supply_penalty_earned").is_empty())


# Criterion 13
func test_shortage_reduces_unprioritized_deliveries() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data)  # fixed, price 101
	state.market["shortages"]["steel"] = 999
	var run := _run(state, data, 2)
	var reduced: Dictionary = _all(run["events"], "supply_delivery_reduced")[0]
	assert_eq([reduced["quantity_contracted"], reduced["quantity_shipped"]], [10, 5])
	assert_eq(_all(run["events"], "supply_delivery_dispatched")[0]["invoice"], 505)
	assert_eq(run["state"].stock["steel"], 5)


func test_priority_contract_is_not_reduced() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data, "s1", 10, PERIOD, 3, "fixed", true)  # 100 - 5 + 4 + 6 = 105
	state.market["shortages"]["steel"] = 999
	var run := _run(state, data, 2)
	assert_true(_all(run["events"], "supply_delivery_reduced").is_empty())
	assert_eq(_all(run["events"], "supply_delivery_dispatched")[0]["invoice"], 1050)
	assert_eq(run["state"].stock["steel"], 10)


# Criterion 14
func test_skip_pays_take_or_pay_and_ships_nothing() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data)
	state.supply_contracts[0]["next_delivery_day"] = 7
	state.day = 3
	var events := Simulation.apply_command(state, Command.skip_supply_delivery(1), data)
	assert_eq(events[0]["type"], "supply_delivery_skipped")
	assert_eq(events[0]["cost"], 707)  # 10 * 101 * 70 div 100
	assert_eq(events[0]["delivery_day"], 7)
	assert_eq(state.money, MONEY - 707)
	var again := Simulation.apply_command(state, Command.skip_supply_delivery(1), data)
	assert_eq(again[0]["reason"], "already_skipped")
	var run := _run(state, data, 4)
	assert_true(_all(run["events"], "supply_delivery_dispatched").is_empty())
	assert_eq(run["state"].money, MONEY - 707)
	assert_eq(run["state"].supply_contracts[0]["deliveries_done"], 1)
	assert_eq(run["state"].supply_contracts[0]["skip_next"], false)
	assert_eq(run["state"].supply_contracts[0]["next_delivery_day"], 14)
	assert_true(run["state"].pending_orders.is_empty())


func test_skip_rejections() -> void:
	var data := _data()
	var state := _state(data, 500)
	_sign(state, data)
	state.supply_contracts[0]["next_delivery_day"] = 7
	state.day = 5
	var short := Simulation.apply_command(state, Command.skip_supply_delivery(1), data)
	assert_eq(short[0]["reason"], "notice_too_short")
	state.day = 3
	var poor := Simulation.apply_command(state, Command.skip_supply_delivery(1), data)
	assert_eq(poor[0]["reason"], "insufficient_funds")
	var unknown := Simulation.apply_command(state, Command.skip_supply_delivery(9), data)
	assert_eq(unknown[0]["reason"], "unknown_contract")
	assert_eq(state.money, 500)


# Criterion 15
func test_termination_fee_and_transit_goods_still_arrive() -> void:
	var data := _data(1.0, 3)  # the first delivery is delayed, hence still in transit
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 2)
	var state2: GameState = run["state"]
	assert_eq(state2.supply_contracts[0]["deliveries_done"], 1)
	assert_eq(state2.pending_orders.size(), 1)
	var money := state2.money
	var events := Simulation.apply_command(state2, Command.terminate_supply_contract(1), data)
	assert_eq(events[0]["fee"], 808)  # 2 x 10 x 101 x 40 div 100
	assert_eq(state2.money, money - 808)
	assert_eq(state2.supply_contracts[0]["status"], "terminated")
	var next := _run(state2, data, 20)
	assert_true(_all(next["events"], "supply_delivery_dispatched").is_empty())
	assert_eq(next["state"].stock["steel"], 10, "(the goods already shipped arrive)")


func test_termination_counts_a_skipped_delivery_as_done() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data)
	state.supply_contracts[0]["next_delivery_day"] = 7
	Simulation.apply_command(state, Command.skip_supply_delivery(1), data)
	var money := state.money
	var events := Simulation.apply_command(state, Command.terminate_supply_contract(1), data)
	assert_eq(events[0]["fee"], 808)  # (3 - 0 - 1) = 2 remaining x 10 x 101 x 40 div 100
	assert_eq(state.money, money - 808)


func test_termination_rejections() -> void:
	var data := _data()
	var state := _state(data, 100)
	_sign(state, data)
	var poor := Simulation.apply_command(state, Command.terminate_supply_contract(1), data)
	assert_eq(poor[0]["reason"], "insufficient_funds")
	var unknown := Simulation.apply_command(state, Command.terminate_supply_contract(5), data)
	assert_eq(unknown[0]["reason"], "unknown_contract")
	state.money = MONEY
	Simulation.apply_command(state, Command.terminate_supply_contract(1), data)
	var twice := Simulation.apply_command(state, Command.terminate_supply_contract(1), data)
	assert_eq(twice[0]["reason"], "unknown_contract", "(no longer active)")


# Criterion 16
func test_signature_rejections() -> void:
	var data := _data()
	var state := _state(data)
	assert_eq(_sign(state, data, "s1", 0)[0]["reason"], "invalid_quantity")
	assert_eq(_sign(state, data, "s1", 51)[0]["reason"], "invalid_quantity")
	assert_eq(_sign(state, data, "s1", 10, 10)[0]["reason"], "invalid_period")
	assert_eq(_sign(state, data, "s1", 10, PERIOD, 7)[0]["reason"], "invalid_duration")
	assert_eq(_sign(state, data, "s1", 10, PERIOD, 1)[0]["reason"], "invalid_duration")
	assert_eq(_sign(state, data, "s1", 10, PERIOD, 3, "spot")[0]["reason"], "invalid_pricing")
	assert_eq(_sign(state, data, "nobody")[0]["reason"], "not_in_catalog")
	assert_eq(_sign(state, data, "plain")[0]["reason"], "contracts_not_offered")
	assert_true(state.supply_contracts.is_empty())
	assert_eq(_sign(state, data)[0]["type"], "supply_contract_signed")
	assert_eq(_sign(state, data)[0]["reason"], "duplicate_contract")
	assert_eq(_sign(state, data, "s2")[0]["type"], "supply_contract_signed")
	assert_eq(_sign(state, data, "s3")[0]["reason"], "too_many_supply_contracts")
	assert_eq(state.supply_contracts.size(), 2)


func test_rejections_follow_the_spec_order() -> void:
	var data := _data()
	var state := _state(data)
	# Everything wrong at once: the first reason in R4 order wins.
	assert_eq(_sign(state, data, "plain", 0, 10, 7, "spot")[0]["reason"], "contracts_not_offered")
	assert_eq(_sign(state, data, "s1", 0, 10, 7, "spot")[0]["reason"], "invalid_quantity")
	assert_eq(_sign(state, data, "s1", 10, 10, 7, "spot")[0]["reason"], "invalid_period")
	assert_eq(_sign(state, data, "s1", 10, PERIOD, 7, "spot")[0]["reason"], "invalid_duration")


func test_completed_contract_frees_its_slot() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data, "s1", 10, PERIOD, 2)
	_sign(state, data, "s2", 10, PERIOD, 2)
	var run := _run(state, data, 9)
	assert_eq(_sign(run["state"], data)[0]["type"], "supply_contract_signed", "(same pair, contract completed)")


# Criterion 17
func test_invoice_can_push_money_below_zero() -> void:
	var data := _data()
	var state := _state(data, 500)
	_sign(state, data)
	var run := _run(state, data, 2)
	assert_eq(run["state"].money, 500 - 1010)
	assert_eq(_days_with(run["events"], "negative_balance"), [1])
	assert_eq(_days_with(run["events"], "bankruptcy_warning"), [1])
	assert_eq(run["state"].stock["steel"], 10, "(the goods are delivered anyway)")


func test_no_contract_means_no_change() -> void:
	var data := _data()
	data.supply_contracts = {}
	var state := _state(data)
	var run := _run(state, data, 10)
	assert_eq(run["state"].money, MONEY)
	var daily: Dictionary = _all(run["events"], "daily_costs")[0]
	assert_eq([daily["holding_fees"], daily["supply_penalties"]], [0, 0])
	assert_eq(_sign(state, data)[0]["reason"], "invalid_period")


func test_events_have_no_type_collision() -> void:
	var data := _data(1.0, 3)
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 6)
	for day_events in run["events"]:
		for e in day_events:
			assert_true(e["type"] is String)


func test_json_round_trip() -> void:
	var data := _data(1.0, 3)
	var state := _state(data)
	_sign(state, data)
	_sign(state, data, "s2", 5, 14, 2, "indexed", true)
	var run := _run(state, data, 2)  # a contract order is in transit
	var original: GameState = run["state"]
	assert_eq(original.pending_orders.size(), 2)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(original.to_dict())))
	assert_eq(typeof(restored.supply_contracts[0]["id"]), TYPE_INT)
	assert_eq(typeof(restored.supply_contracts[0]["contract_unit_price"]), TYPE_INT)
	assert_eq(typeof(restored.supply_contracts[1]["next_delivery_day"]), TYPE_INT)
	assert_eq(typeof(restored.pending_orders[0]["contract_id"]), TYPE_INT)
	assert_eq(typeof(restored.pending_orders[0]["invoice"]), TYPE_INT)
	assert_eq(restored.next_supply_contract_id, 3)
	assert_eq(JSON.stringify(restored.to_dict()), JSON.stringify(original.to_dict()))
	var a := _run(original, data, 20)
	var b := _run(restored, data, 20)
	assert_eq(JSON.stringify(a["state"].to_dict()), JSON.stringify(b["state"].to_dict()))


func test_zero_lead_time_ships_once_and_advances() -> void:
	var data := _data()
	data.suppliers["s1"]["catalog"][0]["lead_time_days"] = 0
	var state := _state(data)
	_sign(state, data)
	assert_eq(state.supply_contracts[0]["next_delivery_day"], 0)
	var run := _run(state, data, 2)
	assert_eq(_days_with(run["events"], "supply_delivery_dispatched"), [0], "(shipped once)")
	assert_eq(run["state"].supply_contracts[0]["next_delivery_day"], PERIOD)
	assert_eq(run["state"].supply_contracts[0]["deliveries_done"], 1)
	assert_eq(run["state"].money, MONEY - 1010)


func test_missed_due_day_still_ships() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data)
	state.supply_contracts[0]["next_delivery_day"] = -3
	var run := _run(state, data, 1)
	assert_eq(_days_with(run["events"], "supply_delivery_dispatched"), [0])
	assert_eq(run["state"].supply_contracts[0]["next_delivery_day"], PERIOD - 3)


func test_shortage_can_reduce_a_delivery_to_zero() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data, "s1", 1)  # 1 x 50 div 100 = 0
	state.market["shortages"]["steel"] = 999
	var run := _run(state, data, 2)
	var reduced: Dictionary = _all(run["events"], "supply_delivery_reduced")[0]
	assert_eq([reduced["quantity_contracted"], reduced["quantity_shipped"]], [1, 0])
	assert_true(_all(run["events"], "supply_delivery_dispatched").is_empty())
	assert_eq(run["state"].money, MONEY)
	assert_true(run["state"].pending_orders.is_empty())
	assert_eq(run["state"].supply_contracts[0]["deliveries_done"], 1)


func test_late_penalty_below_the_cap() -> void:
	var data := _data(1.0, 7)
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 9)
	var penalty: Dictionary = _all(run["events"], "supply_penalty_earned")[0]
	assert_eq(penalty["days_late"], 7)
	assert_eq(penalty["amount"], 141)  # 1010 * 14 div 100, under the 20 % cap


# --- Queries ---

func test_schedule_exposes_the_drawn_delay() -> void:
	var data := _data(1.0, 3)
	var state := _state(data)
	_sign(state, data)
	var run := _run(state, data, 2)
	var order: Dictionary = run["state"].pending_orders[0]
	assert_true(order["delay_rolled"])
	var rows := SimQueries.supply_schedule(run["state"], data, 10)
	assert_eq(rows[0]["kind"], "transit")
	assert_eq([rows[0]["day"], rows[0]["delay_days"]], [order["arrival_day"], 3])
	assert_eq(rows[1]["delay_days"], 0, "(planned shipment: no delay yet)")

func test_quote_matches_the_signature() -> void:
	var data := _data()
	var state := _state(data)
	state.market["index"]["steel"] = 1100
	var args := {"supplier_id": "s1", "component_id": "steel", "quantity": 10, "period_days": PERIOD,
		"deliveries": 3, "pricing": "fixed", "priority": false}
	var quote := SimQueries.supply_contract_quote(state, data, args)
	assert_true(quote["ok"])
	assert_eq(quote["discount_pct"], 5)
	assert_eq(quote["unit_price"], 111)
	assert_eq(quote["invoice"], 1110)
	assert_eq(quote["storage_units"], 10)
	assert_eq(quote["total_commitment"], 3330)
	assert_eq(quote["termination_fee"], 1332)  # 3330 * 40 div 100
	var events := _sign(state, data)
	assert_eq(events[0]["unit_price"], quote["unit_price"])
	var again := SimQueries.supply_contract_quote(state, data, args)
	assert_eq(again["reason"], "duplicate_contract")
	assert_true(not again["ok"])
	args["period_days"] = 10
	assert_eq(SimQueries.supply_contract_quote(state, data, args)["reason"], "invalid_period")
	args["supplier_id"] = "plain"
	assert_eq(SimQueries.supply_contract_quote(state, data, args)["reason"], "contracts_not_offered")


func test_schedule_lists_contract_and_transit_deliveries() -> void:
	var data := _data()
	var state := _state(data)
	_sign(state, data)
	var rows := SimQueries.supply_schedule(state, data, 30)
	assert_eq(rows.map(func(r): return r["day"]), [2, 9, 16])
	assert_eq(rows.map(func(r): return r["invoice_day"]), [1, 8, 15])
	assert_eq(rows.map(func(r): return r["invoice"]), [1010, 1010, 1010])
	assert_eq(SimQueries.supply_schedule(state, data, 10).size(), 2)
	Simulation.apply_command(state, Command.order("s1", "steel", 3), data)
	state.supply_contracts[0]["next_delivery_day"] = 7
	Simulation.apply_command(state, Command.skip_supply_delivery(1), data)
	rows = SimQueries.supply_schedule(state, data, 30)
	assert_eq(rows.map(func(r): return r["kind"]), ["transit", "contract", "contract", "contract"])
	assert_eq(rows[0]["invoice"], 0)
	assert_eq([rows[1]["day"], rows[1]["skipped"], rows[1]["invoice"]], [7, true, 0])
	assert_eq([rows[2]["day"], rows[2]["invoice"]], [14, 1010])


# --- End to end ---

func test_sixty_day_run_money_day_by_day() -> void:
	var data := _data()
	var state := _state(data)
	var cmds := {
		0: [Command.sign_supply_contract("s1", "steel", 10, PERIOD, 6, "fixed"),
			Command.sign_supply_contract("s2", "steel", 5, 14, 3, "indexed")],
		10: [Command.skip_supply_delivery(1)],
		25: [Command.terminate_supply_contract(1)],
	}
	# Expected debits by day (A fixed at 101, B indexed, no penalty: delay_chance 0).
	var expected := {
		1: 10 * 101 + 5 * UNIT,          # A#1 and B#1 at index 1000
		8: 10 * 101,                     # A#2
		10: 10 * 101 * 70 / 100,         # take-or-pay for A#3 (delivery day 16)
		# day 15: A#3 skipped, B#2 at index 1300: 5 x 130
		15: 5 * 130,
		22: 5 * 101,                     # A#4 reduced by the shortage (5 of 10)
		25: 2 * 10 * 101 * 40 / 100,     # termination, 2 deliveries left
		29: 2 * 180,                     # B#3 reduced (2 of 5) at (1300 + 500) / 1000 x 100
	}
	var money := MONEY
	var received := []
	for d in 60:
		if d == 10:
			state.market["index"]["steel"] = 1300
		if d == 20:
			state.market["shortages"]["steel"] = 100
		var result := Simulation.step(state, cmds.get(d, []), data)
		state = result.state
		money -= expected.get(d, 0)
		assert_eq(state.money, money, "money after day %d" % d)
		if not _find(result.events, "delivery_received").is_empty():
			received.append(d)
	assert_eq(received, [1, 8, 15, 22, 29])
	assert_eq(state.stock["steel"], 10 + 10 + 5 + 5 + 5 + 2)
	assert_eq(state.supply_contracts[0]["status"], "terminated")
	assert_eq(state.supply_contracts[1]["status"], "completed")
	assert_eq(state.supply_contracts[0]["deliveries_done"], 4)

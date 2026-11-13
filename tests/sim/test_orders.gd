extends TestCase

const F := preload("res://tests/sim/fixtures.gd")


func test_order_debits_money_immediately() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.order("acme", "steel", 10), data)
	assert_eq(state.money, F.START_MONEY - 10 * F.UNIT_PRICE)
	assert_eq(F.types(events), ["order_placed"])
	assert_eq(state.pending_orders.size(), 1)


func test_order_rejected_when_insufficient_funds() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.order("acme", "steel", 1000), data)
	assert_eq(state.money, F.START_MONEY)
	assert_eq(events[0]["reason"], "insufficient_funds")
	assert_true(state.pending_orders.is_empty())


func test_order_rejected_when_not_in_catalog() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.order("acme", "gold", 1), data)
	assert_eq(events[0]["reason"], "not_in_catalog")


func test_order_rejected_when_quantity_invalid() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.order("acme", "steel", 0), data)
	assert_eq(events[0]["reason"], "invalid_quantity")


func test_delivery_arrives_after_lead_time() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var order := {0: [Command.order("acme", "steel", 10)]}
	var before := F.run(state, data, F.LEAD_TIME - 1, order)
	assert_eq(before.state.stock.get("steel", 0), 0, "(not yet delivered)")
	var after := F.run(state, data, F.LEAD_TIME, order)
	assert_eq(after.state.stock.get("steel", 0), 10)
	assert_true(after.state.pending_orders.is_empty())


func test_supplier_delay_postpones_delivery() -> void:
	var data := F.data(1.0)  # always late
	var state := Simulation.new_game(data, 1)
	var order := {0: [Command.order("acme", "steel", 10)]}
	var on_time := F.run(state, data, F.LEAD_TIME, order)
	assert_eq(on_time.state.stock.get("steel", 0), 0)
	assert_true("delivery_delayed" in F.types(on_time.events))
	var late := F.run(state, data, F.LEAD_TIME + F.DELAY_DAYS, order)
	assert_eq(late.state.stock.get("steel", 0), 10)


func test_full_warehouse_keeps_order_pending() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var orders := {0: [Command.order("acme", "steel", 15), Command.order("acme", "steel", 15)]}
	var result := F.run(state, data, F.LEAD_TIME, orders)
	assert_eq(result.state.stock["steel"], 15)
	assert_eq(result.state.pending_orders.size(), 1)
	assert_true("warehouse_full" in F.types(result.events))

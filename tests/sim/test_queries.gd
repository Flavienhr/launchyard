extends TestCase
## SimQueries: read-only helpers for the UI.

const F := preload("res://tests/sim/fixtures.gd")


func _state(techs := 2, stock := {}) -> Array:
	var data := F.data()
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "shop", "hall"],
		"technicians": techs, "assignments": {"shop": techs}}
	var state := Simulation.new_game(data, 1)
	state.stock = stock.duplicate()
	return [state, data]


func _fac(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


func test_job_info_progress_and_days_left() -> void:
	var s := _state(1, {"steel": 2})
	var shop := _fac(s[0], "shop")
	var r := F.run(s[0], s[1], 1, {0: [Command.queue_job(shop["id"], "weld", 1)]})
	var rshop := _fac(r.state, "shop")
	var info := SimQueries.job_info(s[1], rshop, rshop["jobs"][0])
	assert_eq(info["progress"], 10)
	assert_eq(info["percent"], 50)
	assert_eq(info["days_left"], 1)
	assert_true(not info["idle"])


func test_job_info_idle_without_staff() -> void:
	var s := _state(0, {"steel": 2})
	var shop := _fac(s[0], "shop")
	var r := F.run(s[0], s[1], 1, {0: [Command.queue_job(shop["id"], "weld", 1)]})
	var rshop := _fac(r.state, "shop")
	var info := SimQueries.job_info(s[1], rshop, rshop["jobs"][0])
	assert_true(info["idle"])
	assert_eq(info["days_left"], -1)


func test_build_options() -> void:
	var s := _state()
	var options := SimQueries.build_options(s[0], s[1])
	assert_eq(options.size(), 1)
	assert_eq(options[0]["type"], "shop")
	assert_eq(options[0]["cost"], F.SHOP_COST)
	assert_eq(options[0]["remaining"], 0)


func test_staff_info() -> void:
	var s := _state(2)
	var info := SimQueries.staff_info(s[0], s[1])
	assert_eq(info["hired"], 2)
	assert_eq(info["assigned"], 2)
	assert_eq(info["free"], 0)
	assert_eq(info["daily_salaries"], 2 * F.SALARY)


func test_bill_of_materials_counts_orders_in_transit() -> void:
	var s := _state(2, {"steel": 1})
	var rows := SimQueries.bill_of_materials(s[0], s[1], "weld")
	assert_eq(rows[0]["required"], 2)
	assert_eq(rows[0]["missing"], 1)
	var r := F.run(s[0], s[1], 1, {0: [Command.order("acme", "steel", 1)]})
	rows = SimQueries.bill_of_materials(r.state, s[1], "weld")
	assert_eq(rows[0]["on_order"], 1)
	assert_eq(rows[0]["missing"], 0)


func test_buy_vs_make() -> void:
	var s := _state(1)
	var cmp := SimQueries.buy_vs_make(s[0], s[1], "tank")
	assert_true(cmp["buy"].is_empty(), "no supplier sells tank in fixtures")
	assert_eq(cmp["make"]["recipe_id"], "weld")
	assert_eq(cmp["make"]["material_cost"], 2 * F.UNIT_PRICE)
	assert_eq(cmp["make"]["days"], 2)
	var steel := SimQueries.buy_vs_make(s[0], s[1], "steel")
	assert_eq(steel["buy"]["unit_price"], F.UNIT_PRICE)
	assert_eq(steel["buy"]["lead_time_days"], F.LEAD_TIME)
	assert_true(steel["make"].is_empty())


func test_hall_occupancy() -> void:
	var s := _state()
	var hall := _fac(s[0], "hall")
	s[0].launchers.append({"id": 1, "model": "l1", "location_facility_id": hall["id"]})
	var occ := SimQueries.hall_occupancy(s[0], s[1], hall)
	assert_eq(occ["used"], 1)
	assert_eq(occ["capacity"], 1)

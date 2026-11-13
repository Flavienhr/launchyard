extends TestCase

const F := preload("res://tests/sim/fixtures.gd")


func _data(techs := 0, assignments := {}) -> GameData:
	var data := F.data()
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "shop"],
		"technicians": techs, "assignments": assignments}
	return data


func _first_of(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


func _reason(events: Array) -> String:
	for e in events:
		if e["type"] == "command_rejected":
			return e["reason"]
	return ""


func _apply(state: GameState, data: GameData, command: Command) -> Array:
	return Simulation.apply_command(state, command, data)


func test_new_game_applies_start_staff() -> void:
	var data := _data(3, {"shop": 2})
	var state := Simulation.new_game(data, 1)
	assert_eq(state.technicians_hired, 3)
	assert_eq(_first_of(state, "shop")["assigned"], 2)
	assert_eq(Simulation.total_assigned(state), 2)


func test_hire_debits_and_rejections() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var ev := _apply(state, data, Command.hire(2))
	assert_eq(ev[0]["type"], "staff_hired")
	assert_eq(state.technicians_hired, 2)
	assert_eq(state.money, F.START_MONEY - 2 * F.HIRE_COST)
	assert_eq(_reason(_apply(state, data, Command.hire(0))), "invalid_quantity")
	assert_eq(_reason(_apply(state, data, Command.hire(F.MAX_TECHS))), "max_technicians")
	state.money = F.HIRE_COST - 1
	assert_eq(_reason(_apply(state, data, Command.hire(1))), "insufficient_funds")
	assert_eq(state.technicians_hired, 2)


func test_fire_cost_and_rejections() -> void:
	var data := _data(3, {"shop": 2})
	var state := Simulation.new_game(data, 1)
	assert_eq(_reason(_apply(state, data, Command.fire(2))), "staff_assigned")
	assert_eq(_reason(_apply(state, data, Command.fire(0))), "invalid_quantity")
	var ev := _apply(state, data, Command.fire(1))
	assert_eq(ev[0]["type"], "staff_fired")
	assert_eq(state.technicians_hired, 2)
	assert_eq(state.money, F.START_MONEY - F.FIRE_COST)


func test_assign_sets_count_and_rejections() -> void:
	var data := _data(2)
	var state := Simulation.new_game(data, 1)
	var shop: int = _first_of(state, "shop")["id"]
	assert_eq(_apply(state, data, Command.assign_staff(shop, 2))[0]["type"], "staff_assigned")
	assert_eq(_apply(state, data, Command.assign_staff(shop, 1))[0]["type"], "staff_assigned")
	assert_eq(Simulation.total_assigned(state), 1)  # sets, does not add
	assert_eq(_reason(_apply(state, data, Command.assign_staff(shop, 4))), "too_many_for_slots")
	assert_eq(_reason(_apply(state, data, Command.assign_staff(shop, -1))), "invalid_quantity")
	assert_eq(_reason(_apply(state, data, Command.assign_staff(shop, 3))), "not_enough_staff")
	assert_eq(_reason(_apply(state, data, Command.assign_staff(999, 1))), "unknown_facility")
	var wh: int = _first_of(state, "warehouse")["id"]
	assert_eq(_reason(_apply(state, data, Command.assign_staff(wh, 1))), "no_slots")


func test_assign_rejected_when_building() -> void:
	var data := _data(2)
	var state := Simulation.new_game(data, 1)
	var shop := _first_of(state, "shop")
	shop["status"] = "building"
	assert_eq(_reason(_apply(state, data, Command.assign_staff(shop["id"], 1))), "facility_not_ready")


func test_salaries_paid_assigned_or_not() -> void:
	var data := _data(3, {"shop": 1})
	var state := Simulation.new_game(data, 1)
	var result := F.run(state, data, 4)
	assert_eq(result.state.money, F.START_MONEY - 4 * (F.UPKEEP + F.SHOP_UPKEEP + 3 * F.SALARY))


func test_staff_serialization_roundtrip() -> void:
	var data := _data(3, {"shop": 2})
	var state := Simulation.new_game(data, 1)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(copy.technicians_hired, 3)
	assert_eq(Simulation.total_assigned(copy), 2)
	assert_true(typeof(copy.technicians_hired) == TYPE_INT)

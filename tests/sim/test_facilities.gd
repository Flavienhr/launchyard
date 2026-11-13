extends TestCase

const F := preload("res://tests/sim/fixtures.gd")


func _status(state: GameState, id: int) -> String:
	for f in state.facilities:
		if f["id"] == id:
			return f["status"]
	return ""


func test_new_game_creates_ready_instances() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	assert_eq(state.facilities.size(), 1)
	assert_eq(state.facilities[0]["type"], "warehouse")
	assert_eq(state.facilities[0]["status"], "ready")
	assert_eq(Simulation.storage_capacity(state, data), F.CAPACITY)


func _started_id(events: Array) -> int:
	for e in events:
		if e["type"] == "facility_build_started":
			return int(e["facility_id"])
	return -1


func _upkeeps(events: Array) -> Array:
	return events.filter(func(e): return e["type"] == "daily_costs").map(func(e): return e["upkeep"])


func test_build_debits_then_becomes_ready_after_build_days() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var cmds := {0: [Command.build("shop")]}
	var first := F.run(state, data, 1, cmds)
	assert_eq(first.state.money, F.START_MONEY - F.SHOP_COST - F.UPKEEP)
	var id := _started_id(first.events)
	var mid := F.run(state, data, F.SHOP_DAYS - 1, cmds)
	assert_eq(_status(mid.state, id), "building")
	assert_true(not ("facility_built" in F.types(mid.events)))
	var done := F.run(state, data, F.SHOP_DAYS, cmds)
	assert_eq(_status(done.state, id), "ready")
	assert_eq(F.types(done.events).count("facility_built"), 1)


func test_no_upkeep_while_building_then_upkeep_once_ready() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var cmds := {0: [Command.build("shop")]}
	var done := F.run(state, data, F.SHOP_DAYS + 1, cmds)
	var upkeeps := _upkeeps(done.events)
	# Days 0..SHOP_DAYS-2: still building. Built during resolution of day SHOP_DAYS-1.
	for i in F.SHOP_DAYS - 1:
		assert_eq(upkeeps[i], F.UPKEEP)
	assert_eq(upkeeps[F.SHOP_DAYS - 1], F.UPKEEP + F.SHOP_UPKEEP)
	assert_eq(upkeeps[F.SHOP_DAYS], F.UPKEEP + F.SHOP_UPKEEP)


func test_step_is_pure_with_build() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var before := state.to_dict()
	Simulation.step(state, [Command.build("shop")], data)
	assert_eq(state.to_dict(), before)


func test_copy_is_deep_for_facilities() -> void:
	var state := Simulation.new_game(F.data(), 1)
	var copy := state.copy()
	copy.facilities[0]["status"] = "building"
	copy.facilities[0]["jobs"].append(1)
	assert_eq(state.facilities[0]["status"], "ready")
	assert_true(state.facilities[0]["jobs"].is_empty())


func test_facilities_survive_json_round_trip() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	Simulation.apply_command(state, Command.build("shop"), data)
	var parsed = JSON.parse_string(JSON.stringify(state.to_dict()))
	var copy := GameState.from_dict(parsed)
	assert_eq(copy.facilities, state.facilities)
	assert_eq(typeof(copy.facilities[1]["id"]), TYPE_INT)
	assert_eq(typeof(copy.facilities[1]["ready_day"]), TYPE_INT)
	assert_eq(typeof(copy.facilities[1]["assigned"]), TYPE_INT)


func test_building_instance_has_no_storage_capacity() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.build("shop"), data)
	assert_eq(F.types(events), ["facility_build_started"])
	assert_eq(state.facilities.size(), 2)
	assert_eq(state.facilities[1]["status"], "building")
	assert_eq(state.facilities[1]["ready_day"], F.SHOP_DAYS)
	assert_eq(Simulation.storage_capacity(state, data), F.CAPACITY)


func test_build_rejected_when_max_count_reached_by_building_instance() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	Simulation.apply_command(state, Command.build("shop"), data)
	var money := state.money
	var events := Simulation.apply_command(state, Command.build("shop"), data)
	assert_eq(events[0]["reason"], "max_count_reached")
	assert_eq(state.money, money)
	assert_eq(state.facilities.size(), 2)


func test_build_rejected_when_not_buildable() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.build("warehouse"), data)
	assert_eq(events[0]["reason"], "not_buildable")
	events = Simulation.apply_command(state, Command.build("nope"), data)
	assert_eq(events[0]["reason"], "not_buildable")


func test_build_rejected_when_insufficient_funds() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	state.money = F.SHOP_COST - 1
	var events := Simulation.apply_command(state, Command.build("shop"), data)
	assert_eq(events[0]["reason"], "insufficient_funds")
	assert_eq(state.money, F.SHOP_COST - 1)


func test_facilities_round_trip_through_dict() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	Simulation.apply_command(state, Command.build("shop"), data)
	var copy := GameState.from_dict(state.to_dict())
	assert_eq(copy.facilities, state.facilities)
	assert_eq(copy.next_facility_id, state.next_facility_id)

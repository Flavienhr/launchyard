extends TestCase
## Spec 008 R8, criteres 11 et 12 : deplacer et demolir. Donnees inline.

const F := preload("res://tests/sim/fixtures.gd")
const SHOP_BUILD_COST := 1_000
const SHOP_BUILD_DAYS := 4
const MOVE_COST := 250
const MOVE_DAYS := 2
const REFUND := 200
const LOW_MONEY := 100


func _data(start_facilities: Array) -> GameData:
	var data := F.data()
	data.sites[F.SITE_ID]["map"] = {
		"width": 20, "height": 10, "terrain": [],
		"lots": [
			{"id": "A", "x": 0, "y": 0, "w": 10, "h": 10, "price": 0},
			{"id": "B", "x": 10, "y": 0, "w": 10, "h": 10, "price": 1_000},
		]}
	data.layout = {"move_cost_pct": 25, "move_days_pct": 50, "demolish_refund_pct": 20}
	var shop: Dictionary = data.facilities["shop"]
	shop["footprint"] = [3, 1]
	shop["max_count"] = 2
	shop["upkeep_per_day"] = 0
	shop["build_cost"] = SHOP_BUILD_COST
	shop["build_days"] = SHOP_BUILD_DAYS
	data.facilities["warehouse"]["footprint"] = [2, 2]
	data.facilities["warehouse"]["upkeep_per_day"] = 0
	data.facilities["warehouse"]["build_cost"] = 100
	data.facilities["hall"]["footprint"] = [2, 2]
	data.facilities["hall"]["upkeep_per_day"] = 0
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 0, "rollout_days": 1,
		"footprint": [2, 2], "build_cost": 400, "build_days": 4}
	data.start = {"money": F.START_MONEY, "facilities": start_facilities, "site": F.SITE_ID,
		"owned_lots": ["A"]}
	return data


func _at(type: String, x: int, y: int) -> Dictionary:
	return {"facility_type": type, "x": x, "y": y, "rotation": 0}


func _cmd(state: GameState, data: GameData, command: Command) -> Array:
	return Simulation.apply_command(state, command, data)


func _reason(events: Array) -> String:
	return events[0].get("reason", "")


## Critere 11.
func test_move_effects_and_completion() -> void:
	var data := _data([_at("shop", 0, 0)])
	var state := Simulation.new_game(data, 1)
	var shop: Dictionary = state.facilities[0]
	state.technicians_hired = 2
	_cmd(state, data, Command.assign_staff(shop["id"], 2))
	_cmd(state, data, Command.queue_job(shop["id"], "weld", 1))
	var money := state.money
	var events := _cmd(state, data, Command.move_facility(shop["id"], 0, 5, 0))
	assert_eq(F.types(events), ["facility_move_started"])
	assert_eq(events[0]["cost"], MOVE_COST)
	assert_eq(events[0]["ready_day"], state.day + MOVE_DAYS)
	assert_eq(state.money, money - MOVE_COST)
	assert_eq(shop["status"], "building")
	assert_eq(shop["ready_day"], state.day + MOVE_DAYS)
	assert_eq(shop["assigned"], 0)
	assert_eq(Simulation.total_assigned(state), 0)
	assert_eq([shop["x"], shop["y"]], [0, 5])
	assert_eq(F.types(_cmd(state, data, Command.build("shop", 0, 0, 0))), ["facility_build_started"])
	var result := F.run(state, data, MOVE_DAYS)
	shop = Simulation._find_facility(result.state, shop["id"])
	var built := result.events.filter(func(e): return e["type"] == "facility_built" and e["facility_id"] == shop["id"])
	assert_eq(built.size(), 1)
	assert_eq(built[0]["moved"], true)
	assert_eq(shop["status"], "ready")
	assert_eq(shop["jobs"].size(), 1)


func test_move_rejections_in_order() -> void:
	var data := _data([_at("shop", 0, 0), _at("warehouse", 0, 3)])
	var state := Simulation.new_game(data, 1)
	var shop_id: int = state.facilities[0]["id"]
	assert_eq(_reason(_cmd(state, data, Command.move_facility(99, 0, 5, 0))), "unknown_facility")
	assert_eq(_reason(_cmd(state, data, Command.move_facility(shop_id, 8, 0, 0))), "out_of_bounds")
	assert_eq(_reason(_cmd(state, data, Command.move_facility(shop_id, 0, 5, 2))), "out_of_bounds")
	# Overlapping itself does not count: shifting by one cell is allowed.
	var wh_id: int = state.facilities[1]["id"]
	var events := _cmd(state, data, Command.move_facility(shop_id, 0, 3, 0))
	assert_eq(_reason(events), "overlap")
	assert_eq(events[0]["facility_id"], wh_id)
	state.money = LOW_MONEY
	assert_eq(_reason(_cmd(state, data, Command.move_facility(shop_id, 1, 0, 0))), "insufficient_funds")
	assert_eq(state.money, LOW_MONEY)
	state.money = F.START_MONEY
	assert_eq(F.types(_cmd(state, data, Command.move_facility(shop_id, 1, 0, 0))), ["facility_move_started"])


func test_busy_started_job() -> void:
	var data := _data([_at("shop", 0, 0)])
	var state := Simulation.new_game(data, 1)
	var shop_id: int = state.facilities[0]["id"]
	state.technicians_hired = 1
	state.stock["steel"] = 2
	_cmd(state, data, Command.assign_staff(shop_id, 1))
	_cmd(state, data, Command.queue_job(shop_id, "weld", 1))
	state = F.run(state, data, 1).state  # job starts
	assert_true(state.facilities[0]["jobs"][0]["started"])
	assert_eq(_reason(_cmd(state, data, Command.move_facility(shop_id, 0, 5, 0))), "facility_busy")
	assert_eq(_reason(_cmd(state, data, Command.demolish_facility(shop_id))), "facility_busy")


func test_busy_hall_with_launcher_and_pad() -> void:
	var data := _data([_at("hall", 0, 0), _at("pad", 5, 5)])
	var state := Simulation.new_game(data, 1)
	var hall_id: int = state.facilities[0]["id"]
	var pad: Dictionary = state.facilities[1]
	assert_eq(F.types(_cmd(state, data, Command.move_facility(hall_id, 0, 3, 0))), ["facility_move_started"])
	state.facilities[0]["status"] = "ready"
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": hall_id})
	assert_eq(_reason(_cmd(state, data, Command.move_facility(hall_id, 0, 6, 0))), "facility_busy")
	assert_eq(_reason(_cmd(state, data, Command.demolish_facility(hall_id))), "facility_busy")
	for pad_state in [Simulation.PAD_OCCUPIED, Simulation.PAD_REFURBISHING]:
		pad["pad_state"] = pad_state
		assert_eq(_reason(_cmd(state, data, Command.demolish_facility(pad["id"]))), "facility_busy")
	pad["pad_state"] = Simulation.PAD_FREE
	state.launches.append({"id": 1, "launcher_id": 1, "pad_id": pad["id"], "contract_id": 1,
		"launch_day": 5, "scrubs": 0, "insured": false})
	assert_eq(_reason(_cmd(state, data, Command.move_facility(pad["id"], 8, 8, 0))), "facility_busy")
	state.launches.clear()
	assert_eq(F.types(_cmd(state, data, Command.demolish_facility(pad["id"]))), ["facility_demolished"])


## Critere 12.
func test_demolish_frees_cells_and_max_count() -> void:
	var data := _data([_at("shop", 0, 0), _at("shop", 0, 5)])
	var state := Simulation.new_game(data, 1)
	var first: Dictionary = state.facilities[0]
	state.technicians_hired = 1
	_cmd(state, data, Command.assign_staff(first["id"], 1))
	_cmd(state, data, Command.queue_job(first["id"], "weld", 1))
	assert_eq(_reason(_cmd(state, data, Command.build("shop", 5, 0, 0))), "max_count_reached")
	var money := state.money
	var events := _cmd(state, data, Command.demolish_facility(first["id"]))
	assert_eq(F.types(events), ["facility_demolished"])
	assert_eq(events[0]["refund"], REFUND)
	assert_eq(events[0]["facility_type"], "shop")
	assert_eq(state.money, money + REFUND)
	assert_eq(state.facilities.size(), 1)
	assert_eq(Simulation.total_assigned(state), 0)
	assert_eq(F.types(_cmd(state, data, Command.build("shop", 0, 0, 0))), ["facility_build_started"])
	assert_eq(_reason(_cmd(state, data, Command.demolish_facility(first["id"]))), "unknown_facility")


func test_storage_overflow() -> void:
	var data := _data([_at("warehouse", 0, 0)])
	var state := Simulation.new_game(data, 1)
	var wh_id: int = state.facilities[0]["id"]
	state.stock["steel"] = 15
	var events := _cmd(state, data, Command.demolish_facility(wh_id))
	assert_eq(_reason(events), "storage_overflow")
	assert_eq(events[0]["excess"], 15)
	events = _cmd(state, data, Command.move_facility(wh_id, 5, 5, 0))
	assert_eq(_reason(events), "storage_overflow")
	assert_eq(events[0]["excess"], 15)
	assert_eq(state.facilities.size(), 1)
	# A second warehouse absorbs the stock: the first one can go.
	data.start["facilities"] = [_at("warehouse", 0, 0), _at("warehouse", 4, 0)]
	state = Simulation.new_game(data, 1)
	state.stock["steel"] = 15
	assert_eq(F.types(_cmd(state, data, Command.demolish_facility(state.facilities[0]["id"]))),
		["facility_demolished"])


func test_no_map_site() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var wh_id: int = state.facilities[0]["id"]
	assert_eq(_reason(_cmd(state, data, Command.move_facility(wh_id, 0, 0, 0))), "out_of_bounds")
	assert_eq(F.types(_cmd(state, data, Command.demolish_facility(wh_id))), ["facility_demolished"])
	assert_eq(state.facilities.size(), 0)

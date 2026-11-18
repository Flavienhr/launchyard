extends TestCase
## Spec 008 R1-R4, R9 (validité) : carte, parcelles, build positionné, buy_lot,
## installations de départ, gap_cells, placement_check. Données inline.

const F := preload("res://tests/sim/fixtures.gd")
const LOT_B_PRICE := 1_000
const LOW_MONEY := 500


func _data(start_facilities: Array = []) -> GameData:
	var data := F.data()
	data.sites[F.SITE_ID]["map"] = {
		"width": 20, "height": 10, "terrain": [],
		"lots": [
			{"id": "A", "x": 0, "y": 0, "w": 10, "h": 10, "price": 0},
			{"id": "B", "x": 10, "y": 0, "w": 10, "h": 10, "price": LOT_B_PRICE},
		]}
	data.facilities["shop"]["footprint"] = [3, 1]
	data.facilities["shop"]["max_count"] = 2
	data.facilities["shop"]["upkeep_per_day"] = 0
	data.facilities["warehouse"]["footprint"] = [2, 2]
	data.facilities["hall"]["footprint"] = [2, 2]
	data.facilities["hall"]["upkeep_per_day"] = 0
	data.start = {"money": F.START_MONEY, "facilities": start_facilities, "site": F.SITE_ID,
		"owned_lots": ["A"]}
	return data


func _build(state: GameState, data: GameData, type: String, x: int, y: int, rotation: int) -> Array:
	return Simulation.apply_command(state, Command.build(type, x, y, rotation), data)


func _rect(x: int, y: int, w: int, h: int) -> Dictionary:
	return {"x": x, "y": y, "w": w, "h": h}


## Critère 1.
func test_placement_and_rotation() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var events := _build(state, data, "shop", 0, 0, 0)
	assert_eq(F.types(events), ["facility_build_started"])
	var first: Dictionary = state.facilities[state.facilities.size() - 1]
	assert_eq([first["x"], first["y"], first["rotation"]], [0, 0, 0])
	events = _build(state, data, "shop", 2, 0, 1)
	assert_eq(events[0]["reason"], "overlap")
	assert_eq(events[0]["facility_id"], first["id"])
	events = _build(state, data, "shop", 8, 0, 0)
	assert_eq(events[0]["reason"], "out_of_bounds")
	events = _build(state, data, "shop", 9, 0, 1)
	assert_eq(F.types(events), ["facility_build_started"])
	var rotated: Dictionary = state.facilities[state.facilities.size() - 1]
	assert_eq(LayoutRules.instance_rect(data, rotated), _rect(9, 0, 1, 3))


## Rejets : hors carte, rotation invalide, overlap avec le plus petit id.
func test_out_of_map_and_bad_rotation() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	assert_eq(_build(state, data, "shop", -1, 0, 0)[0]["reason"], "out_of_bounds")
	assert_eq(_build(state, data, "shop", 0, 0, 2)[0]["reason"], "out_of_bounds")
	assert_eq(_build(state, data, "shop", 18, 9, 0)[0]["reason"], "out_of_bounds")


func test_overlap_reports_smallest_id() -> void:
	var data := _data(["warehouse"])
	data.start["facilities"] = [
		{"facility_type": "warehouse", "x": 0, "y": 0, "rotation": 0},
		{"facility_type": "hall", "x": 2, "y": 0, "rotation": 0}]
	var state := Simulation.new_game(data, 1)
	var events := _build(state, data, "shop", 1, 0, 0)  # x 1-3: touches both
	assert_eq(events[0]["reason"], "overlap")
	assert_eq(events[0]["facility_id"], state.facilities[0]["id"])


## Ordre : not_buildable, max_count_reached, missing_prerequisite, puis spatial.
func test_rejection_order() -> void:
	var data := _data()
	data.facilities["shop"]["requires_facilities"] = ["hall"]
	var state := Simulation.new_game(data, 1)
	assert_eq(_build(state, data, "nope", 99, 99, 0)[0]["reason"], "not_buildable")
	assert_eq(_build(state, data, "shop", 99, 99, 0)[0]["reason"], "missing_prerequisite")
	data.facilities["shop"]["requires_facilities"] = []
	data.facilities["shop"]["max_count"] = 0
	assert_eq(_build(state, data, "shop", 99, 99, 0)[0]["reason"], "max_count_reached")


## Critère 2.
func test_overlap_before_insufficient_funds() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	_build(state, data, "shop", 0, 0, 0)
	state.money = LOW_MONEY
	assert_eq(_build(state, data, "shop", 0, 0, 0)[0]["reason"], "overlap")
	assert_eq(state.money, LOW_MONEY)
	assert_eq(_build(state, data, "shop", 0, 5, 0)[0]["reason"], "insufficient_funds")
	assert_eq(state.money, LOW_MONEY)


## Critère 3.
func test_buy_lot() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.buy_lot("B"), data)
	assert_eq(F.types(events), ["lot_bought"])
	assert_eq(events[0]["lot_id"], "B")
	assert_eq(events[0]["cost"], LOT_B_PRICE)
	assert_eq(state.money, F.START_MONEY - LOT_B_PRICE)
	assert_eq(F.types(_build(state, data, "shop", 8, 0, 0)), ["facility_build_started"])
	assert_eq(Simulation.apply_command(state, Command.buy_lot("B"), data)[0]["reason"], "lot_owned")
	assert_eq(Simulation.apply_command(state, Command.buy_lot("Z"), data)[0]["reason"], "unknown_lot")


func test_buy_lot_insufficient_funds() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.money = LOW_MONEY
	var events := Simulation.apply_command(state, Command.buy_lot("B"), data)
	assert_eq(events[0]["reason"], "insufficient_funds")
	assert_eq(state.money, LOW_MONEY)
	assert_eq(state.owned_lots, ["A"])


## Critère 4 : site sans carte, build sans position accepté, positions nulles.
func test_no_map_changes_nothing() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.build("shop"), data)
	assert_eq(F.types(events), ["facility_build_started"])
	assert_eq(state.facilities[1]["x"], null)
	assert_eq(LayoutRules.placement_check(state, data, "shop", 5, 5, 0)["valid"], true)
	assert_eq(F.types(Simulation.apply_command(state, Command.buy_lot("A"), data)), ["command_rejected"])


## Sur un site avec carte, build sans position : première position valide (y, x, rot 0 puis 1).
func test_build_without_position_autoplaces() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.build("shop"), data)
	assert_eq([events[0]["x"], events[0]["y"], events[0]["rotation"]], [0, 0, 0])
	data.facilities["shop"]["max_count"] = 3
	events = Simulation.apply_command(state, Command.build("shop"), data)
	assert_eq([events[0]["x"], events[0]["y"]], [3, 0])


## Critère 5.
func test_start_facilities_positioned() -> void:
	var data := _data([{"facility_type": "hall", "x": 0, "y": 0, "rotation": 0}])
	var state := Simulation.new_game(data, 1)
	assert_eq(state.facilities[0]["status"], "ready")
	assert_eq([state.facilities[0]["x"], state.facilities[0]["y"]], [0, 0])
	assert_eq(state.owned_lots, ["A"])
	assert_eq(_build(state, data, "shop", 1, 1, 0)[0]["reason"], "overlap")


## R4.
func test_gap_cells() -> void:
	var a := _rect(0, 0, 2, 2)
	assert_eq(SimQueries.gap_cells(a, _rect(2, 0, 2, 2)), 0)  # touch by a side
	assert_eq(SimQueries.gap_cells(a, _rect(2, 2, 1, 1)), 0)  # touch by a corner
	assert_eq(SimQueries.gap_cells(a, _rect(3, 0, 2, 2)), 1)
	assert_eq(SimQueries.gap_cells(_rect(3, 0, 2, 2), a), 1)
	assert_eq(SimQueries.gap_cells(a, _rect(5, 4, 1, 1)), 3)  # Chebyshev: max(3, 2)


## Critère 13 (validité) et lot_list.
func test_placement_check_and_lot_list() -> void:
	var data := _data([{"facility_type": "warehouse", "x": 0, "y": 0, "rotation": 0}])
	var state := Simulation.new_game(data, 1)
	var ok := SimQueries.placement_check(state, data, "shop", 2, 0, 0)
	assert_eq(ok["valid"], true)
	assert_eq(ok["rect"], _rect(2, 0, 3, 1))
	var bad := SimQueries.placement_check(state, data, "shop", 1, 1, 0)
	assert_eq([bad["valid"], bad["reason"], bad["facility_id"]], [false, "overlap", state.facilities[0]["id"]])
	assert_eq(SimQueries.placement_check(state, data, "shop", 8, 0, 0)["reason"], "out_of_bounds")
	var lots := SimQueries.lot_list(state, data)
	assert_eq(lots.size(), 2)
	assert_eq([lots[0]["id"], lots[0]["owned"]], ["A", true])
	assert_eq([lots[1]["id"], lots[1]["owned"], lots[1]["price"]], ["B", false, LOT_B_PRICE])
	assert_eq(lots[1]["x"], 10)


## Aller-retour JSON des positions et de owned_lots ; anciennes sauvegardes.
func test_json_round_trip_and_old_save() -> void:
	var data := _data([{"facility_type": "hall", "x": 3, "y": 4, "rotation": 1}])
	var state := Simulation.new_game(data, 1)
	Simulation.apply_command(state, Command.buy_lot("B"), data)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.owned_lots, ["A", "B"])
	assert_eq([restored.facilities[0]["x"], restored.facilities[0]["y"], restored.facilities[0]["rotation"]], [3, 4, 1])
	assert_eq(restored.to_dict(), state.to_dict())
	var old := state.to_dict()
	old.erase("owned_lots")
	for facility in old["facilities"]:
		for key in ["x", "y", "rotation"]:
			facility.erase(key)
	var loaded := GameState.from_dict(old)
	assert_eq(loaded.owned_lots, [])
	assert_eq(loaded.facilities[0]["x"], null)

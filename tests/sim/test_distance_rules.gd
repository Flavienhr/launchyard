extends TestCase
## Spec 008 R5 à R7, R9 (champs de distance), critères 6 à 10, 13 et 14 :
## desserte, roll-out, évacuation, dégâts, lanceurs détruits. Données inline.

const F := preload("res://tests/sim/fixtures.gd")

const SERVICE_RADIUS := 1
const UNSERVED_PCT := 50
const ROLLOUT_BASE := 1
const CELLS_PER_DAY := 3
const COST_PER_CELL := 10
const REPAIR_DAYS := 5
const REPAIR_PCT := 25
const SAFETY := 2
const WH_COST := 100
const SHOP_BUILD := 1_000
const HALL_COST := 2_000
const SLOW_POINTS := 100
const REFURB_DAYS_FAIL := 6
const REFURB_COST_FAIL := 300
const LAUNCH_DAY := 3
const DEADLINE := 40
const PAYMENT := 100_000
const RECYCLE_DAYS := 5


func _entry(type: String, x: int, y: int, rotation := 0) -> Dictionary:
	return {"facility_type": type, "x": x, "y": y, "rotation": rotation}


func _data(start: Array, scrub := 0.0, reliability := 1.0, with_map := true) -> GameData:
	var data := F.data()
	if with_map:
		data.sites[F.SITE_ID]["map"] = {"width": 20, "height": 10, "terrain": [],
			"lots": [{"id": "A", "x": 0, "y": 0, "w": 20, "h": 10, "price": 0}]}
		data.layout = {"service_radius_cells": SERVICE_RADIUS, "unserved_productivity_pct": UNSERVED_PCT,
			"rollout_base_days": ROLLOUT_BASE, "rollout_cells_per_day": CELLS_PER_DAY,
			"rollout_cost_per_cell": COST_PER_CELL, "damage_repair_days": REPAIR_DAYS,
			"damage_repair_cost_pct": REPAIR_PCT, "move_cost_pct": 25, "move_days_pct": 50,
			"demolish_refund_pct": 20}
	var fac: Dictionary = data.facilities
	fac["warehouse"].merge({"footprint": [2, 2], "upkeep_per_day": 0, "build_cost": WH_COST}, true)
	fac["shop"].merge({"footprint": [3, 1], "slots": 2, "upkeep_per_day": 0, "build_cost": SHOP_BUILD, "max_count": 2}, true)
	fac["hall"].merge({"footprint": [2, 2], "upkeep_per_day": 0, "build_cost": HALL_COST}, true)
	fac["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 0, "footprint": [2, 2],
		"safety_radius_cells": SAFETY, "buildable": true, "build_cost": 4_000, "build_days": 4, "max_count": 3,
		"rollout_days": 2, "scrub_recycle_days": RECYCLE_DAYS, "scrub_cost": 0, "refurb_days": 1,
		"refurb_cost": 0, "refurb_days_after_failure": REFURB_DAYS_FAIL, "refurb_cost_after_failure": REFURB_COST_FAIL}
	data.recipes["slow"] = {"id": "slow", "facility_type": "shop", "inputs": {"steel": 1},
		"output": {"component_id": "tank", "quantity": 1}, "work_points": SLOW_POINTS}
	data.recipes["weld"]["inputs"] = {"steel": 1}
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [scrub, scrub, scrub, scrub]
	data.launchers["l1"]["reliability_base"] = reliability
	data.contracts = {"offer_slots": 2, "initial_offers": 0, "offer_spawn_chance": 1.0,
		"offer_validity_days": 5, "advance_pct": 20, "penalty_pct": 30, "max_active_contracts": 3,
		"payment_rounding": 1_000, "mass_step_kg": 50, "generate_unreachable": false, "reputation_start": 0,
		"reputation_min": -100, "reputation_max": 100, "rep_on_success": 6, "rep_on_launch_failure": -15,
		"rep_on_deadline_missed": -10, "templates": []}
	data.start = {"money": F.START_MONEY, "facilities": start, "site": F.SITE_ID, "owned_lots": ["A"]}
	return data


func _fac(state: GameState, type: String, nth := 0) -> Dictionary:
	var seen := 0
	for f in state.facilities:
		if f["type"] == type:
			if seen == nth:
				return f
			seen += 1
	return {}


func _cmd(state: GameState, data: GameData, command: Command) -> Array:
	return Simulation.apply_command(state, command, data)


func _contract(state: GameState, id: int) -> void:
	state.contracts.append({"id": id, "orbit": "leo", "payload_kg": 1_000, "payment": PAYMENT,
		"advance": 0, "penalty": 0, "deadline_day": DEADLINE, "status": ContractRules.ACTIVE,
		"offer_expires_day": 0})
	state.next_contract_id = id + 1


func _launcher_in(state: GameState, id: int, facility: Dictionary) -> void:
	state.launchers.append({"id": id, "model": "l1", "location_facility_id": facility["id"]})
	state.next_launcher_id = id + 1


func _progress(state: GameState, type := "shop", nth := 0) -> int:
	return int(_fac(state, type, nth)["jobs"][0]["progress"])


func _work(state: GameState, data: GameData, type: String, nth: int, recipe: String, techs: int) -> void:
	state.technicians_hired = 5
	state.stock["steel"] = 5
	var facility := _fac(state, type, nth)
	facility["assigned"] = techs
	assert_eq(F.types(_cmd(state, data, Command.queue_job(facility["id"], recipe, 1))), ["job_queued"])


## Critère 6.
func test_service_by_warehouse() -> void:
	var data := _data([_entry("warehouse", 0, 0), _entry("shop", 3, 0)])
	var state := Simulation.new_game(data, 1)
	_work(state, data, "shop", 0, "weld", 2)
	assert_eq(F.types(F.run(state, data, 1).events).count("job_completed"), 1)
	# Same shop, gap 2 from the warehouse: unserved, 10 points per day.
	data.start["facilities"] = [_entry("warehouse", 0, 0), _entry("shop", 4, 0)]
	state = Simulation.new_game(data, 1)
	_work(state, data, "shop", 0, "weld", 2)
	var r := F.run(state, data, 1)
	assert_eq(F.types(r.events).count("job_completed"), 0)
	assert_eq(_progress(r.state), 10)
	assert_eq(F.types(F.run(r.state, data, 1).events).count("job_completed"), 1)


func test_damaged_warehouse_does_not_serve() -> void:
	var data := _data([_entry("warehouse", 0, 0), _entry("shop", 3, 0)])
	var state := Simulation.new_game(data, 1)
	_work(state, data, "shop", 0, "slow", 2)
	_fac(state, "warehouse")["damaged_until_day"] = state.day + 3
	var r := F.run(state, data, 1)
	assert_eq(_progress(r.state), 10)
	r = F.run(r.state, data, 2)
	assert_eq(_progress(r.state), 30)
	r = F.run(r.state, data, 1)
	assert_eq(_progress(r.state), 50)


func test_no_warehouse_in_range_and_no_map_unaffected() -> void:
	var data := _data([_entry("shop", 3, 0)])
	var state := Simulation.new_game(data, 1)
	_work(state, data, "shop", 0, "slow", 2)
	assert_eq(_progress(F.run(state, data, 1).state), 10)
	# Without a map nothing applies: full rate, everything served.
	var plain := _data(["shop"], 0.0, 1.0, false)
	state = Simulation.new_game(plain, 1)
	_work(state, plain, "shop", 0, "slow", 2)
	assert_eq(_progress(F.run(state, plain, 1).state), 20)


## Critère 7.
func test_rollout_by_distance() -> void:
	var data := _data([_entry("hall", 0, 0), _entry("pad", 7, 0)])
	var state := Simulation.new_game(data, 1)
	_launcher_in(state, 1, _fac(state, "hall"))
	_contract(state, 1)
	var pad_id: int = _fac(state, "pad")["id"]
	var events := _cmd(state, data, Command.schedule_launch(1, pad_id, 1, state.day + 1))
	assert_eq(events[0]["reason"], "too_early")
	events = _cmd(state, data, Command.schedule_launch(1, pad_id, 1, state.day + 2))
	assert_eq(F.types(events), ["launch_scheduled"])
	assert_eq(events[0]["rollout_days"], 2)
	assert_eq(events[0]["rollout_cost"], 50)
	var before := state.money
	var r := F.run(state, data, 1)
	var costs: Dictionary = r.events.filter(func(e): return e["type"] == "daily_costs")[0]
	assert_eq(costs["rollout_costs"], 50)
	assert_eq(r.state.money, before - 50)
	assert_eq(r.state.pending_rollout_costs, 0)
	# Not refunded when the launch is cancelled.
	_cmd(r.state, data, Command.cancel_launch(1))
	assert_eq(F.run(r.state, data, 1).state.money, before - 50)


func test_rollout_adjacent_pad_and_launcher_on_pad() -> void:
	var data := _data([_entry("hall", 0, 0), _entry("pad", 2, 0)])
	var state := Simulation.new_game(data, 1)
	_launcher_in(state, 1, _fac(state, "hall"))
	_contract(state, 1)
	var pad_id: int = _fac(state, "pad")["id"]
	var events := _cmd(state, data, Command.schedule_launch(1, pad_id, 1, state.day + 1))
	assert_eq([events[0]["rollout_days"], events[0]["rollout_cost"]], [1, 0])
	# Launcher already on a far pad: day + 1, nothing to pay.
	var far := _data([_entry("hall", 0, 0), _entry("pad", 9, 0)])
	state = Simulation.new_game(far, 1)
	_launcher_in(state, 1, _fac(state, "hall"))
	_contract(state, 1)
	pad_id = _fac(state, "pad")["id"]
	_cmd(state, far, Command.schedule_launch(1, pad_id, 1, state.day + 4))
	state.launches.clear()  # the launcher stays on the pad
	events = _cmd(state, far, Command.schedule_launch(1, pad_id, 1, state.day + 1))
	assert_eq([events[0]["rollout_days"], events[0]["rollout_cost"]], [1, 0])


func test_rollout_without_map_keeps_fixed_days() -> void:
	var data := _data(["hall", "pad"], 0.0, 1.0, false)
	var state := Simulation.new_game(data, 1)
	_launcher_in(state, 1, _fac(state, "hall"))
	_contract(state, 1)
	var pad_id: int = _fac(state, "pad")["id"]
	assert_eq(_cmd(state, data, Command.schedule_launch(1, pad_id, 1, state.day + 1))[0]["reason"], "too_early")
	var events := _cmd(state, data, Command.schedule_launch(1, pad_id, 1, state.day + 2))
	assert_eq([events[0]["rollout_days"], events[0]["rollout_cost"]], [2, 0])


## Zone layout: pad (6,0) 2x2; shop (3,0) in the zone, served by the warehouse
## (4,1) also in the zone; shop (3,4) out of the zone (gap 2); hall (10,0) with
## the launcher (gap 2: out of the zone); hall (6,3) in the zone.
func _zone_start() -> Array:
	return [_entry("pad", 6, 0), _entry("shop", 3, 0), _entry("warehouse", 4, 1),
		_entry("shop", 3, 4), _entry("hall", 10, 0), _entry("hall", 6, 3)]


func _zone_state(data: GameData, with_second_launcher := false) -> GameState:
	var state := Simulation.new_game(data, 1)
	_launcher_in(state, 1, _fac(state, "hall", 0))
	if with_second_launcher:
		_launcher_in(state, 2, _fac(state, "hall", 1))
	_contract(state, 1)
	var events := _cmd(state, data, Command.schedule_launch(1, _fac(state, "pad")["id"], 1, LAUNCH_DAY))
	assert_eq(F.types(events), ["launch_scheduled"])
	_work(state, data, "shop", 0, "slow", 1)
	_work(state, data, "shop", 1, "slow", 1)
	return state


## Critère 8.
func test_evacuation_on_launch_day() -> void:
	var data := _data(_zone_start(), 1.0)  # scrub 1.0: the launch is postponed
	var state := _zone_state(data)
	var progress: Array = []
	var evacuated: Array = []
	var result := StepResult.new(state, [])
	for i in 5:
		result = Simulation.step(result.state, [], data)
		progress.append([_progress(result.state, "shop", 0), _progress(result.state, "shop", 1)])
		evacuated.append(result.events.filter(func(e): return e["type"] == "facility_evacuated"))
	assert_eq(progress, [[10, 10], [20, 20], [30, 30], [30, 40], [40, 50]])
	assert_eq(evacuated[3].map(func(e): return e["facility_id"]),
		[_fac(result.state, "shop", 0)["id"], _fac(result.state, "warehouse")["id"], _fac(result.state, "hall", 1)["id"]])
	assert_eq(evacuated[3][0]["pad_id"], _fac(result.state, "pad")["id"])
	assert_eq(evacuated[2].size() + evacuated[4].size(), 0)


## Critère 9.
func test_failure_damages_the_zone() -> void:
	var data := _data(_zone_start(), 0.0, 0.0)
	var state := _zone_state(data, true)
	var start := state.money
	var r := F.run(state, data, LAUNCH_DAY + 1)
	assert_eq(F.types(r.events).count("launch_failed"), 1)
	var by_id := {}
	for e in r.events.filter(func(e): return e["type"] == "facility_damaged"):
		by_id[e["facility_id"]] = e
		assert_eq(e["pad_id"], _fac(r.state, "pad")["id"])
	assert_eq(by_id.size(), 3)
	assert_eq(by_id[_fac(r.state, "shop", 0)["id"]]["repair_cost"], 250)
	assert_eq(by_id[_fac(r.state, "shop", 0)["id"]]["until_day"], LAUNCH_DAY + REPAIR_DAYS)
	assert_eq(by_id[_fac(r.state, "warehouse")["id"]]["repair_cost"], 25)
	assert_eq(by_id[_fac(r.state, "hall", 1)["id"]]["repair_cost"], 500)
	assert_true(not by_id.has(_fac(r.state, "shop", 1)["id"]))
	assert_true(not by_id.has(_fac(r.state, "hall", 0)["id"]))
	var destroyed := r.events.filter(func(e): return e["type"] == "launcher_destroyed")
	assert_eq(destroyed.size(), 1)
	assert_eq([destroyed[0]["launcher_id"], destroyed[0]["facility_id"]], [2, _fac(r.state, "hall", 1)["id"]])
	var costs: Dictionary = r.events.filter(func(e): return e["type"] == "daily_costs")[LAUNCH_DAY]
	assert_eq(costs["repair_costs"], 250 + 25 + 500)
	var fixed := 0
	for e in r.events.filter(func(e): return e["type"] == "daily_costs"):
		fixed += e["upkeep"] + e["salaries"] + e["rollout_costs"]
	assert_eq(r.state.money, start - 775 - REFURB_COST_FAIL - fixed)
	# Order of events: launch_failed first, then damages by ascending id.
	var types := F.types(r.events)
	assert_true(types.find("launch_failed") < types.find("facility_damaged"))
	# The shop out of the zone is untouched.
	assert_eq(_progress(r.state, "shop", 1), 40)
	assert_eq(_fac(r.state, "shop", 1)["damaged_until_day"], -1)


func test_damaged_facility_is_frozen_then_repaired() -> void:
	var data := _data(_zone_start(), 0.0, 0.0)
	var state := _zone_state(data)
	_fac(state, "shop", 0)["assigned"] = 2
	var r := F.run(state, data, 4)  # resolutions 0..3 (3 = launch day, evacuated)
	assert_eq(_progress(r.state, "shop", 0), 60)
	r = F.run(r.state, data, 3)  # resolutions 4..6
	assert_eq(_progress(r.state, "shop", 0), 60)
	assert_eq(F.types(r.events).count("facility_repaired"), 0)
	r = F.run(r.state, data, 1)  # resolution 7: repaired (shop, warehouse, hall)
	assert_eq(_progress(r.state, "shop", 0), 60)
	assert_eq(r.events.filter(func(e): return e["type"] == "facility_repaired").size(), 3)
	r = F.run(r.state, data, 1)  # resolution 8: back to work, served again
	assert_eq(_progress(r.state, "shop", 0), 80)


func test_building_instance_in_zone_is_delayed_for_free() -> void:
	var data := _data([_entry("pad", 6, 0), _entry("hall", 10, 0)], 0.0, 0.0)
	data.facilities["shop"]["build_days"] = DEADLINE / 2  # still under construction on launch day
	var state := Simulation.new_game(data, 1)
	_launcher_in(state, 1, _fac(state, "hall"))
	_contract(state, 1)
	_cmd(state, data, Command.schedule_launch(1, _fac(state, "pad")["id"], 1, LAUNCH_DAY))
	var built := _cmd(state, data, Command.build("shop", 3, 4, 0))
	assert_eq(F.types(built), ["facility_build_started"], str(built))
	var built2 := _cmd(state, data, Command.build("shop", 3, 0, 0))
	assert_eq(F.types(built2), ["facility_build_started"], str(built2))
	var far_ready: int = _fac(state, "shop", 0)["ready_day"]
	var near_ready: int = _fac(state, "shop", 1)["ready_day"]
	var money_before := state.money
	var r := F.run(state, data, LAUNCH_DAY + 1)
	assert_eq(_fac(r.state, "shop", 1)["ready_day"], near_ready + REPAIR_DAYS)
	assert_eq(_fac(r.state, "shop", 0)["ready_day"], far_ready)
	assert_eq(r.state.money, money_before - REFURB_COST_FAIL - 2 * COST_PER_CELL)  # roll-out of 2 cells, no repair


## Critère 10.
func test_launcher_destroyed_on_another_pad() -> void:
	var data := _data([_entry("pad", 6, 0), _entry("pad", 6, 3), _entry("hall", 10, 0), _entry("hall", 10, 6)], 0.0, 0.0)
	var state := Simulation.new_game(data, 1)
	_launcher_in(state, 1, _fac(state, "hall", 0))
	_launcher_in(state, 2, _fac(state, "hall", 1))
	_contract(state, 1)
	_contract(state, 2)
	var pad1: int = _fac(state, "pad", 0)["id"]
	var pad2: int = _fac(state, "pad", 1)["id"]
	assert_eq(F.types(_cmd(state, data, Command.schedule_launch(1, pad1, 1, LAUNCH_DAY))), ["launch_scheduled"])
	assert_eq(F.types(_cmd(state, data, Command.schedule_launch(2, pad2, 2, LAUNCH_DAY))), ["launch_scheduled"])
	var r := F.run(state, data, LAUNCH_DAY + 1)
	var types := F.types(r.events)
	assert_eq(types.count("launch_failed"), 1)  # launch 2 is cancelled before its draws
	assert_eq(types.count("launcher_destroyed"), 1)
	assert_eq(r.state.launches.size(), 0)
	assert_eq(r.state.launchers.size(), 0)
	assert_eq(r.state.contracts[0]["status"], ContractRules.FAILED)
	assert_eq(r.state.contracts[1]["status"], ContractRules.ACTIVE)
	var other := _fac(r.state, "pad", 1)
	assert_eq(other["pad_state"], Simulation.PAD_REFURBISHING)
	assert_eq(other["refurb_until_day"], LAUNCH_DAY + REFURB_DAYS_FAIL)
	assert_eq(other["launcher_id"], 0)
	# Pads in the zone are damaged too (repair cost 25% of 4000), but pay no refurbishment.
	assert_eq(r.events.filter(func(e): return e["type"] == "facility_damaged" and e["facility_id"] == pad2)[0]["repair_cost"], 1_000)


func test_no_layout_means_no_distance_rules() -> void:
	var data := _data(_zone_start(), 0.0, 0.0)
	data.layout = {}
	var r := F.run(_zone_state(data, true), data, LAUNCH_DAY + 1)
	var types := F.types(r.events)
	assert_eq(types.count("facility_damaged") + types.count("facility_evacuated") + types.count("launcher_destroyed"), 0)


## Critère 13.
func test_placement_check_fields() -> void:
	var data := _data([_entry("pad", 6, 0), _entry("warehouse", 0, 0)])
	var state := Simulation.new_game(data, 1)
	var pad_id: int = _fac(state, "pad")["id"]
	var check := LayoutRules.placement_check(state, data, "shop", 2, 0, 0)
	assert_true(check["valid"])
	assert_eq(check["in_safety_zone_of"], [pad_id])
	assert_eq(check["served"], true)
	assert_true(not check.has("rollout"))
	check = LayoutRules.placement_check(state, data, "shop", 2, 6, 0)
	assert_eq(check["served"], false)
	assert_eq(check["in_safety_zone_of"], [])
	# Hall (2,4) 2x2 and pad (6,0): gap 2 -> 1 + 2 div 3 = 1 day, 20 credits.
	check = LayoutRules.placement_check(state, data, "hall", 2, 4, 0)
	assert_eq(check["rollout"], [{"pad_id": pad_id, "rollout_days": 1, "rollout_cost": 20}])
	# A pad placed at (4,3): its zone contains the existing pad (gap 0) but not the warehouse (gap 2).
	check = LayoutRules.placement_check(state, data, "pad", 4, 3, 0)
	assert_eq(check["zone_contains"], [pad_id])
	assert_eq(SimQueries.placement_check(state, data, "shop", 2, 0, 0), LayoutRules.placement_check(state, data, "shop", 2, 0, 0))


func test_facility_spatial() -> void:
	var data := _data(_zone_start(), 1.0)
	var state := _zone_state(data)
	var shop_id: int = _fac(state, "shop", 0)["id"]
	var info := SimQueries.facility_spatial(state, data, shop_id)
	assert_eq(info["served"], true)
	assert_eq(info["in_safety_zone_of"], [_fac(state, "pad")["id"]])
	assert_eq(info["evacuated_today"], false)
	assert_eq(info["damaged_until_day"], -1)
	state.day = LAUNCH_DAY
	assert_eq(SimQueries.facility_spatial(state, data, shop_id)["evacuated_today"], true)
	assert_eq(SimQueries.facility_spatial(state, data, _fac(state, "shop", 1)["id"])["evacuated_today"], false)
	_fac(state, "shop", 0)["damaged_until_day"] = LAUNCH_DAY + 2
	assert_eq(SimQueries.facility_spatial(state, data, shop_id)["damaged_until_day"], LAUNCH_DAY + 2)


## Critère 14 : aucun tirage ajouté, la carte ne change aucun résultat aléatoire.
func test_map_does_not_change_random_outcomes() -> void:
	for game_seed in 12:
		var outcomes: Array = []
		for with_map in [true, false]:
			var start: Array = [_entry("hall", 0, 0), _entry("pad", 12, 0)] if with_map else ["hall", "pad"]
			var data := _data(start, 0.3, 0.5, with_map)
			var state := Simulation.new_game(data, game_seed)
			_launcher_in(state, 1, _fac(state, "hall"))
			_contract(state, 1)
			_cmd(state, data, Command.schedule_launch(1, _fac(state, "pad")["id"], 1, 6))
			var r := F.run(state, data, 25)
			outcomes.append(F.types(r.events).filter(func(t): return t in ["launch_scrubbed", "launch_succeeded", "launch_failed"]))
		assert_eq(outcomes[0], outcomes[1], "seed %d" % game_seed)


func test_state_roundtrip_keeps_distance_fields() -> void:
	var data := _data([_entry("shop", 0, 0)])
	var state := Simulation.new_game(data, 1)
	_fac(state, "shop")["damaged_until_day"] = 7
	state.pending_rollout_costs = 30
	state.pending_repair_costs = 40
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(_fac(copy, "shop")["damaged_until_day"], 7)
	assert_eq([copy.pending_rollout_costs, copy.pending_repair_costs], [30, 40])
	var old := state.to_dict()
	old.erase("pending_rollout_costs")
	old["facilities"][0].erase("damaged_until_day")
	var loaded := GameState.from_dict(old)
	assert_eq(_fac(loaded, "shop")["damaged_until_day"], -1)
	assert_eq(loaded.pending_rollout_costs, 0)

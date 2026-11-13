extends TestCase
## Spec 001 R3, R5, R6: recipes, production jobs, launcher in the hall.

const F := preload("res://tests/sim/fixtures.gd")


## State with warehouse + shop + hall, `techs` hired, all assigned to `where`.
func _setup(techs: int, where := "shop", stock := {}) -> Array:
	var data := F.data()
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "shop", "hall"],
		"technicians": techs, "assignments": {where: techs}}
	var state := Simulation.new_game(data, 1)
	state.stock = stock.duplicate()
	return [state, data]


func _id(state: GameState, type: String) -> int:
	for f in state.facilities:
		if f["type"] == type:
			return f["id"]
	return -1


func _fac(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


func _count(events: Array, type: String) -> int:
	return F.types(events).count(type)


func _reason(events: Array) -> String:
	for e in events:
		if e["type"] == "command_rejected":
			return e["reason"]
	return ""


func _queue_run(state: GameState, data: GameData, type: String, recipe: String, count: int, days: int) -> StepResult:
	return F.run(state, data, days, {0: [Command.queue_job(_id(state, type), recipe, count)]})


func test_data_loads_recipes() -> void:
	var data := F.data()
	assert_eq(data.recipes["weld"]["work_points"], 20)


func test_job_full_speed_takes_one_day() -> void:
	var s := _setup(2, "shop", {"steel": 2})
	var r := _queue_run(s[0], s[1], "shop", "weld", 1, 1)
	assert_eq(r.state.stock["tank"], 1)
	assert_eq(r.state.stock["steel"], 0)
	var types := F.types(r.events).filter(func(t): return t.begins_with("job_"))
	assert_eq(types, ["job_queued", "job_started", "job_completed"])


func test_job_duration_follows_staff() -> void:
	var s := _setup(1, "shop", {"steel": 2})
	var state: GameState = s[0]
	var r := _queue_run(state, s[1], "shop", "weld", 1, 1)
	assert_eq(r.state.stock.get("tank", 0), 0)
	assert_eq(r.state.stock["steel"], 0)
	r = F.run(r.state, s[1], 1)
	assert_eq(r.state.stock["tank"], 1)


func test_no_progress_without_staff() -> void:
	var s := _setup(0, "shop", {"steel": 2})
	var r := _queue_run(s[0], s[1], "shop", "weld", 1, 5)
	assert_eq(_fac(r.state, "shop")["jobs"][0]["progress"], 0)
	assert_true(_fac(r.state, "shop")["jobs"][0]["started"])
	assert_eq(r.state.stock.get("tank", 0), 0)


func test_missing_inputs_block_once_then_start_after_delivery() -> void:
	var s := _setup(2, "shop", {"steel": 1})
	var state: GameState = s[0]
	var commands := {0: [Command.queue_job(_id(state, "shop"), "weld", 1),
		Command.order("acme", "steel", 1)]}
	var r := F.run(state, s[1], 1, commands)
	var blocked: Array = r.events.filter(func(e): return e["type"] == "job_blocked")
	assert_eq(blocked.size(), 1)
	assert_eq(blocked[0]["reason"], "missing_inputs")
	assert_eq(blocked[0]["missing"], {"steel": 1})
	assert_eq(r.state.stock["steel"], 1)
	r = F.run(r.state, s[1], 2)  # resolutions of days 1 and 2
	assert_eq(_count(r.events, "job_blocked"), 0)
	assert_eq(r.state.day, 3)
	assert_eq(r.state.stock["tank"], 1)


func test_queue_one_job_completes_per_day() -> void:
	var s := _setup(3, "shop", {"steel": 4})
	var r := _queue_run(s[0], s[1], "shop", "weld", 2, 1)
	assert_eq(r.state.stock["tank"], 1)
	r = F.run(r.state, s[1], 1)
	assert_eq(r.state.stock["tank"], 2)


func test_output_blocked_by_full_warehouse() -> void:
	var s := _setup(1, "shop", {"steel": F.CAPACITY})
	var state: GameState = s[0]
	var data: GameData = s[1]
	data.suppliers["acme"]["catalog"][0]["lead_time_days"] = 2  # arrives day 2
	var commands := {0: [Command.queue_job(_id(state, "shop"), "weld", 1),
		Command.order("acme", "steel", 2)]}
	# Day 0: job starts (18/20).
	var r := F.run(state, data, 1, commands)
	assert_eq(Simulation.storage_used(r.state, data), F.CAPACITY - 2)
	# Day 1 resolution: delivery fills the warehouse (step 2), then the job ends (step 4) without room.
	r = F.run(r.state, data, 1)
	assert_eq(_count(r.events, "delivery_received"), 1)
	assert_eq(_count(r.events, "output_blocked"), 1)
	assert_eq(r.state.stock.get("tank", 0), 0)
	assert_eq(_fac(r.state, "shop")["jobs"].size(), 1)
	# A second job queued behind it does not start.
	Simulation.apply_command(r.state, Command.queue_job(_id(r.state, "shop"), "weld", 1), data)
	r = F.run(r.state, data, 1)
	assert_eq(_count(r.events, "job_started"), 0)
	assert_eq(_count(r.events, "output_blocked"), 0)  # reported once
	# Free 2 units: output delivered at next resolution.
	r.state.stock["steel"] -= 2
	r = F.run(r.state, data, 1)
	assert_eq(r.state.stock["tank"], 1)
	assert_eq(_count(r.events, "job_completed"), 1)


func test_assembly_creates_launcher() -> void:
	var s := _setup(2, "hall", {"tank": 1, "engine": 1})
	var state: GameState = s[0]
	var r := _queue_run(state, s[1], "hall", "assemble", 1, 1)
	assert_eq(r.state.launchers.size(), 1)
	assert_eq(r.state.launchers[0]["model"], "l1")
	assert_eq(r.state.launchers[0]["location_facility_id"], _id(state, "hall"))
	assert_eq(r.state.stock["tank"], 0)
	assert_eq(r.state.stock["engine"], 0)
	assert_eq(_count(r.events, "launcher_assembled"), 1)


func test_hall_occupied_blocks_assembly_once() -> void:
	var s := _setup(2, "hall", {"tank": 1, "engine": 1})
	var state: GameState = s[0]
	state.launchers.append({"id": state.next_launcher_id, "model": "l1",
		"location_facility_id": _id(state, "hall")})
	state.next_launcher_id += 1
	var r := _queue_run(state, s[1], "hall", "assemble", 1, 3)
	var blocked: Array = r.events.filter(func(e): return e["type"] == "job_blocked")
	assert_eq(blocked.size(), 1)
	assert_eq(blocked[0]["reason"], "hall_occupied")
	assert_eq(r.state.stock["tank"], 1)
	assert_eq(r.state.launchers.size(), 1)


func test_launcher_ids_are_unique() -> void:
	var s := _setup(2, "hall", {"tank": 2, "engine": 2})
	var state: GameState = s[0]
	var data: GameData = s[1]
	data.facilities["hall"]["launcher_capacity"] = 2
	var r := _queue_run(state, data, "hall", "assemble", 2, 2)
	assert_eq(r.state.launchers.size(), 2)
	assert_true(r.state.launchers[0]["id"] != r.state.launchers[1]["id"])


func test_lowest_facility_id_wins_stock_contention() -> void:
	var data := F.data()
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "shop", "shop"],
		"technicians": 2, "assignments": {}}
	var state := Simulation.new_game(data, 1)
	state.stock = {"steel": 2}
	var ids: Array = state.facilities.filter(func(f): return f["type"] == "shop").map(func(f): return f["id"])
	for id in ids:
		state.facilities[id - 1]["assigned"] = 1
	var commands := {0: [Command.queue_job(ids[0], "weld", 1), Command.queue_job(ids[1], "weld", 1)]}
	var r := F.run(state, data, 1, commands)
	var started: Array = r.events.filter(func(e): return e["type"] == "job_started")
	assert_eq(started.size(), 1)
	assert_eq(started[0]["facility_id"], ids[0])
	var blocked: Array = r.events.filter(func(e): return e["type"] == "job_blocked")
	assert_eq(blocked.size(), 1)
	var again := F.run(state, data, 1, commands)
	assert_eq(again.events, r.events)


func test_queue_job_rejections() -> void:
	var s := _setup(0)
	var state: GameState = s[0]
	var data: GameData = s[1]
	var shop := _id(state, "shop")
	var ap := func(c: Command) -> String: return _reason(Simulation.apply_command(state, c, data))
	assert_eq(ap.call(Command.queue_job(999, "weld", 1)), "unknown_facility")
	assert_eq(ap.call(Command.queue_job(_id(state, "hall"), "weld", 1)), "wrong_facility")
	assert_eq(ap.call(Command.queue_job(shop, "nope", 1)), "unknown_recipe")
	assert_eq(ap.call(Command.queue_job(shop, "weld", 0)), "invalid_quantity")
	assert_eq(ap.call(Command.queue_job(shop, "weld", F.MAX_QUEUE + 1)), "queue_full")
	assert_eq(ap.call(Command.queue_job(shop, "weld", F.MAX_QUEUE)), "")
	assert_eq(ap.call(Command.queue_job(shop, "weld", 1)), "queue_full")
	state.facilities.append({"id": 50, "type": "shop", "status": "building", "ready_day": 9,
		"assigned": 0, "jobs": []})
	assert_eq(ap.call(Command.queue_job(50, "weld", 1)), "facility_not_ready")
	assert_eq(_fac(state, "shop")["jobs"].size(), F.MAX_QUEUE)  # nothing consumed or added by rejects


func test_cancel_job() -> void:
	var s := _setup(2, "shop", {"steel": 2})
	var state: GameState = s[0]
	var data: GameData = s[1]
	var shop := _id(state, "shop")
	Simulation.apply_command(state, Command.queue_job(shop, "weld", 2), data)
	var first: int = _fac(state, "shop")["jobs"][0]["id"]
	var second: int = _fac(state, "shop")["jobs"][1]["id"]
	assert_eq(_reason(Simulation.apply_command(state, Command.cancel_job(999), data)), "unknown_job")
	var ev := Simulation.apply_command(state, Command.cancel_job(second), data)
	assert_eq(ev[0]["type"], "job_cancelled")
	assert_eq(_fac(state, "shop")["jobs"].size(), 1)
	state.stock["steel"] = 0
	var r := F.run(state, data, 1)  # job blocked on inputs, not started: can still be cancelled
	assert_eq(_reason(Simulation.apply_command(r.state, Command.cancel_job(first), data)), "")
	# A started job cannot be cancelled.
	r.state.stock["steel"] = 2
	Simulation.apply_command(r.state, Command.queue_job(shop, "weld", 1), data)
	var running: int = _fac(r.state, "shop")["jobs"][0]["id"]
	r.state.facilities[1]["assigned"] = 0
	r = F.run(r.state, data, 1)
	assert_eq(_reason(Simulation.apply_command(r.state, Command.cancel_job(running), data)), "job_started")


func test_jobs_and_launchers_round_trip_through_dict() -> void:
	var s := _setup(2, "hall", {"tank": 2, "engine": 2})
	var state: GameState = s[0]
	var r := _queue_run(state, s[1], "hall", "assemble", 2, 1)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(r.state.to_dict())))
	assert_eq(copy.launchers.size(), 1)
	assert_eq(typeof(copy.launchers[0]["id"]), TYPE_INT)
	assert_eq(copy.next_job_id, r.state.next_job_id)
	assert_eq(copy.next_launcher_id, r.state.next_launcher_id)
	var job: Dictionary = _fac(copy, "hall")["jobs"][0]
	assert_eq(typeof(job["id"]), TYPE_INT)
	assert_eq(typeof(job["progress"]), TYPE_INT)
	assert_eq(copy.to_dict(), r.state.to_dict())


func test_duration_is_ceil_of_work_points_over_rate_without_surplus_carry() -> void:
	var s := _setup(2, "shop", {"steel": 4})  # rate 20, weld_long = 25 points -> 2 days
	var r := _queue_run(s[0], s[1], "shop", "weld_long", 2, 1)
	assert_eq(r.state.stock.get("tank", 0), 0)
	r = F.run(r.state, s[1], 1)
	assert_eq(r.state.stock["tank"], 1)
	r = F.run(r.state, s[1], 1)  # second job starts: surplus (15) of the first is lost
	assert_eq(_fac(r.state, "shop")["jobs"][0]["progress"], 20)
	assert_eq(r.state.stock["tank"], 1)
	r = F.run(r.state, s[1], 1)
	assert_eq(r.state.stock["tank"], 2)


func test_fifo_across_recipes_and_cancel_keeps_ids_unique() -> void:
	var s := _setup(3, "shop", {"steel": 6})
	var state: GameState = s[0]
	var data: GameData = s[1]
	var shop := _id(state, "shop")
	Simulation.apply_command(state, Command.queue_job(shop, "weld", 1), data)
	Simulation.apply_command(state, Command.queue_job(shop, "weld_long", 1), data)
	Simulation.apply_command(state, Command.queue_job(shop, "weld", 1), data)
	var jobs: Array = _fac(state, "shop")["jobs"]
	var ids: Array = jobs.map(func(j): return j["id"])
	Simulation.apply_command(state, Command.cancel_job(ids[1]), data)
	var r := F.run(state, data, 2)
	var started: Array = r.events.filter(func(e): return e["type"] == "job_started").map(func(e): return e["job_id"])
	assert_eq(started, [ids[0], ids[2]])
	assert_eq(r.state.stock["tank"], 2)
	assert_eq(r.state.stock["steel"], 2)  # cancelled job consumed nothing
	Simulation.apply_command(r.state, Command.queue_job(shop, "weld", 1), data)
	var new_id: int = _fac(r.state, "shop")["jobs"][0]["id"]
	assert_true(not ids.has(new_id))

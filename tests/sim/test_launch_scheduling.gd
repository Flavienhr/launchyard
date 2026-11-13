extends TestCase
## Spec 003 R2, R5, R6: scheduling a launch, pad states (criteria 2, 3, 9, 12).

const F := preload("res://tests/sim/fixtures.gd")

const ROLLOUT := 2
const PAD_COST := 500
const PAD_DAYS := 4
const PAD_UPKEEP := 7
const DEADLINE := 20
const PAYLOAD := 1_000
const PAYMENT := 100_000
const REFURB_DAYS := 3


func _data() -> GameData:
	var data := F.data()
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": PAD_UPKEEP,
		"buildable": true, "build_cost": PAD_COST, "build_days": PAD_DAYS, "max_count": 2,
		"rollout_days": ROLLOUT, "scrub_recycle_days": 1, "scrub_cost": 10,
		"refurb_days": REFURB_DAYS, "refurb_cost": 100,
		"refurb_days_after_failure": 6, "refurb_cost_after_failure": 300}
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "hall", "pad"], "site": F.SITE_ID}
	return data


## Game with a hall, a pad, one l1 in the hall and one active leo contract.
func _setup(orbit := "leo", payload := PAYLOAD) -> Array:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": _fac(state, "hall")["id"]})
	state.next_launcher_id = 2
	state.contracts.append({"id": 1, "orbit": orbit, "payload_kg": payload, "payment": PAYMENT,
		"advance": 0, "penalty": 0, "deadline_day": DEADLINE, "status": ContractRules.ACTIVE,
		"offer_expires_day": 0})
	return [state, data]


func _fac(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


func _schedule(state: GameState, data: GameData, launch_day: int, launcher := 1, contract := 1) -> Array:
	return Simulation.apply_command(state, Command.schedule_launch(
		launcher, _fac(state, "pad")["id"], contract, launch_day), data)


func _reason(events: Array) -> String:
	for e in events:
		if e["type"] == "command_rejected":
			return e["reason"]
	return ""


func test_too_early_then_accepted_frees_hall() -> void:
	var s := _setup()
	var state: GameState = s[0]
	assert_eq(_reason(_schedule(state, s[1], state.day + ROLLOUT - 1)), "too_early")
	var events := _schedule(state, s[1], state.day + ROLLOUT)
	assert_eq(F.types(events), ["launch_scheduled"])
	var pad := _fac(state, "pad")
	assert_eq(state.launchers[0]["location_facility_id"], pad["id"])
	assert_eq(pad["pad_state"], "occupied")
	assert_eq(pad["launcher_id"], 1)
	assert_eq(state.launches.size(), 1)
	assert_eq(state.launches[0]["launch_day"], state.day + ROLLOUT)
	assert_eq(state.launches[0]["scrubs"], 0)


func test_assembly_blocked_by_hall_starts_after_scheduling() -> void:
	var s := _setup()
	var state: GameState = s[0]
	var data: GameData = s[1]
	state.stock = {"tank": 1, "engine": 1}
	state.technicians_hired = 2
	_fac(state, "hall")["assigned"] = 2
	var hall_id: int = _fac(state, "hall")["id"]
	Simulation.apply_command(state, Command.queue_job(hall_id, "assemble", 1), data)
	var blocked := Simulation.step(state, [], data)
	assert_true("job_blocked" in F.types(blocked.events))
	var r := Simulation.step(state, [Command.schedule_launch(1, _fac(state, "pad")["id"], 1, state.day + ROLLOUT)], data)
	assert_true("job_started" in F.types(r.events))


func test_after_deadline() -> void:
	var s := _setup()
	assert_eq(_reason(_schedule(s[0], s[1], DEADLINE + 1)), "after_deadline")
	assert_eq(F.types(_schedule(s[0], s[1], DEADLINE)), ["launch_scheduled"])


func test_unavailable_launcher_and_contract() -> void:
	var s := _setup()
	var state: GameState = s[0]
	assert_eq(_reason(_schedule(state, s[1], 5, 99)), "launcher_unavailable")
	assert_eq(_reason(_schedule(state, s[1], 5, 1, 99)), "contract_unavailable")
	state.contracts[0]["status"] = ContractRules.OFFER
	assert_eq(_reason(_schedule(state, s[1], 5)), "contract_unavailable")
	state.contracts[0]["status"] = ContractRules.ACTIVE
	_schedule(state, s[1], 5)
	assert_eq(_reason(_schedule(state, s[1], 6)), "launcher_unavailable")
	state.launchers.append({"id": 2, "model": "l1", "location_facility_id": 0})
	assert_eq(_reason(_schedule(state, s[1], 6, 2)), "pad_unavailable")  # pad taken first
	_fac(state, "pad")["pad_state"] = "free"
	_fac(state, "pad")["launcher_id"] = 0
	assert_eq(_reason(_schedule(state, s[1], 6, 2)), "contract_unavailable")  # contract already used


func test_orbit_and_payload() -> void:
	var s := _setup("sso")
	assert_eq(_reason(_schedule(s[0], s[1], 5)), "orbit_unreachable")
	var t := _setup("leo", F.LEO_KG + 1)
	assert_eq(_reason(_schedule(t[0], t[1], 5)), "payload_too_heavy")


func test_one_launch_per_pad() -> void:
	var s := _setup()
	var state: GameState = s[0]
	var data: GameData = s[1]
	state.launchers.append({"id": 2, "model": "l1", "location_facility_id": _fac(state, "hall")["id"]})
	state.contracts.append(state.contracts[0].duplicate())
	state.contracts[1]["id"] = 2
	_schedule(state, data, 5)
	assert_eq(_reason(_schedule(state, data, 6, 2, 2)), "pad_unavailable")


func test_pad_refurb_blocks_then_frees_and_emits_pad_ready() -> void:
	var s := _setup()
	var state: GameState = s[0]
	var data: GameData = s[1]
	Simulation.start_refurbishment(_fac(state, "pad"), state.day + REFURB_DAYS)
	assert_eq(_reason(_schedule(state, data, 9)), "pad_unavailable")
	var events: Array = []
	for i in REFURB_DAYS - 1:
		var r := Simulation.step(state, [], data)
		events.append_array(r.events)
		state = r.state
	assert_eq(F.types(events).count("pad_ready"), 0)
	assert_eq(_reason(_schedule(state, data, 9)), "pad_unavailable")
	var last := Simulation.step(state, [], data)  # resolves the eve of the end day
	assert_eq(F.types(last.events).count("pad_ready"), 1)
	assert_eq(last.state.day, REFURB_DAYS)
	assert_eq(_reason(_schedule(last.state, data, last.state.day + ROLLOUT)), "")
	assert_eq(_fac(last.state, "pad")["pad_state"], "occupied")
	assert_eq(_fac(last.state, "pad")["status"], "ready")


func test_cancel_keeps_launcher_on_pad() -> void:
	var s := _setup()
	var state: GameState = s[0]
	var data: GameData = s[1]
	_schedule(state, data, 5)
	var events := Simulation.apply_command(state, Command.cancel_launch(1), data)
	assert_eq(F.types(events), ["launch_cancelled"])
	assert_eq(state.launches.size(), 0)
	assert_eq(_fac(state, "pad")["launcher_id"], 1)
	assert_eq(F.types(_schedule(state, data, state.day + 1)), ["launch_scheduled"])
	assert_eq(_reason(Simulation.apply_command(state, Command.cancel_launch(99), data)), "unknown_launch")


func test_reschedule() -> void:
	var s := _setup()
	var state: GameState = s[0]
	var data: GameData = s[1]
	_schedule(state, data, 5)
	var id: int = state.launches[0]["id"]
	assert_eq(_reason(Simulation.apply_command(state, Command.reschedule_launch(99, 6), data)), "unknown_launch")
	assert_eq(_reason(Simulation.apply_command(state, Command.reschedule_launch(id, state.day), data)), "too_early")
	assert_eq(_reason(Simulation.apply_command(state, Command.reschedule_launch(id, DEADLINE + 1), data)), "after_deadline")
	var events := Simulation.apply_command(state, Command.reschedule_launch(id, state.day + 1), data)
	assert_eq(F.types(events), ["launch_rescheduled"])
	assert_eq(state.launches[0]["launch_day"], state.day + 1)


func test_build_second_pad_and_upkeep_while_occupied() -> void:
	var s := _setup()
	var state: GameState = s[0]
	var data: GameData = s[1]
	var events := Simulation.apply_command(state, Command.build("pad"), data)
	assert_eq(F.types(events), ["facility_build_started"])
	assert_eq(_reason(Simulation.apply_command(state, Command.build("pad"), data)), "max_count_reached")
	_schedule(state, data, 5)
	var r := Simulation.step(state, [], data)
	for e in r.events:
		if e["type"] == "daily_costs":
			# warehouse + occupied pad (hall has 0 upkeep, new pad still building)
			assert_eq(e["upkeep"], PAD_UPKEEP + F.UPKEEP)


func test_round_trip_json_recasts_ints() -> void:
	var s := _setup()
	var state: GameState = s[0]
	_schedule(state, s[1], 5)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(copy.launches, state.launches)
	assert_eq(copy.next_launch_id, state.next_launch_id)
	assert_eq(typeof(copy.launches[0]["launch_day"]), TYPE_INT)
	assert_eq(typeof(_fac(copy, "pad")["launcher_id"]), TYPE_INT)
	assert_eq(typeof(_fac(copy, "pad")["refurb_until_day"]), TYPE_INT)


func test_pad_under_construction_cannot_be_reserved() -> void:
	var s := _setup()
	var state: GameState = s[0]
	_fac(state, "pad")["status"] = "building"
	assert_eq(_reason(_schedule(state, s[1], 5)), "pad_unavailable")

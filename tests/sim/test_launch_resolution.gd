extends TestCase
## Spec 003 R3-R5: launch day resolution (criteria 4-7, 10, 11).

const F := preload("res://tests/sim/fixtures.gd")

const DEADLINE := 20
const PAYMENT := 100_000
const ADVANCE := 20_000
const PAD_UPKEEP := 7
const LAUNCH_DAY := 2
const SCRUB_COST := 10
const REFURB_DAYS := 3
const REFURB_COST := 100
const REFURB_DAYS_FAIL := 6
const REFURB_COST_FAIL := 300
const REP_SUCCESS := 6
const REP_LAUNCH_FAIL := -15
const SEEDS := 1_000
const RELIABILITY := 0.8
const SEED_TOLERANCE := 40  # criterion 10: 760..840 successes out of 1000
const RUN_DAYS := 12


func _data(scrub := 0.0, reliability := 1.0) -> GameData:
	var data := F.data()
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": PAD_UPKEEP,
		"buildable": true, "build_cost": 500, "build_days": 4, "max_count": 2,
		"rollout_days": 2, "scrub_recycle_days": 1, "scrub_cost": SCRUB_COST,
		"refurb_days": REFURB_DAYS, "refurb_cost": REFURB_COST,
		"refurb_days_after_failure": REFURB_DAYS_FAIL, "refurb_cost_after_failure": REFURB_COST_FAIL}
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "hall", "pad"], "site": F.SITE_ID}
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [scrub, scrub, scrub, scrub]
	data.launchers["l1"]["reliability_base"] = reliability
	data.contracts = {
		"offer_slots": 2, "initial_offers": 0, "offer_spawn_chance": 1.0,
		"offer_validity_days": 5, "advance_pct": 20, "penalty_pct": 30,
		"max_active_contracts": 1, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": 0,
		"reputation_min": -100, "reputation_max": 100,
		"rep_on_success": REP_SUCCESS, "rep_on_launch_failure": REP_LAUNCH_FAIL,
		"rep_on_deadline_missed": -10,
		"templates": [{"id": "t", "orbit": "leo", "mass_min_kg": 100, "mass_max_kg": 1_000,
			"base_payment": PAYMENT, "per_kg_payment": 7, "deadline_min_days": 10,
			"deadline_max_days": 30, "weight": 1, "min_reputation": -100, "clients": ["c"]}]}
	return data


func _fac(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


## One l1 on the pad, an active leo contract, launch planned on `launch_day`.
func _setup(data: GameData, deadline := DEADLINE, launch_day := LAUNCH_DAY, game_seed := 1) -> GameState:
	var state := Simulation.new_game(data, game_seed)
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": _fac(state, "hall")["id"]})
	state.next_launcher_id = 2
	state.contracts.append({"id": 1, "orbit": "leo", "payload_kg": 1_000, "payment": PAYMENT,
		"advance": ADVANCE, "penalty": 0, "deadline_day": deadline, "status": ContractRules.ACTIVE,
		"offer_expires_day": 0})
	state.next_contract_id = 2
	var events := Simulation.apply_command(state, Command.schedule_launch(
		1, _fac(state, "pad")["id"], 1, launch_day), data)
	assert_eq(F.types(events), ["launch_scheduled"])
	return state


func _fixed_costs(events: Array) -> int:
	var total := 0
	for e in events:
		if e["type"] == "daily_costs":
			total += e["upkeep"] + e["salaries"]
	return total


func test_success() -> void:
	var data := _data(0.0, 1.0)
	var state := _setup(data)
	var start := state.money
	var r := F.run(state, data, LAUNCH_DAY + 1)
	var types := F.types(r.events)
	assert_eq(types.count("launch_succeeded"), 1)
	assert_true("contract_completed" in types)
	assert_eq(r.state.contracts[0]["status"], ContractRules.COMPLETED)
	assert_eq(r.state.money, start + PAYMENT - ADVANCE - REFURB_COST - _fixed_costs(r.events))
	assert_eq(r.state.model_stats["l1"]["successes"], 1)
	assert_eq(r.state.launchers.size(), 0)
	assert_eq(r.state.launches.size(), 0)
	var pad := _fac(r.state, "pad")
	assert_eq(pad["pad_state"], Simulation.PAD_REFURBISHING)
	assert_eq(pad["refurb_until_day"], LAUNCH_DAY + REFURB_DAYS)
	assert_eq(pad["launcher_id"], 0)
	assert_eq(r.state.reputation, REP_SUCCESS)


func test_failure_keeps_reliability_and_long_refurb() -> void:
	var data := _data(0.0, 0.0)
	var state := _setup(data)
	var start := state.money
	var r := F.run(state, data, LAUNCH_DAY + 1)
	var types := F.types(r.events)
	assert_eq(types.count("launch_failed"), 1)
	var failed: Dictionary = r.events.filter(func(e): return e["type"] == "contract_failed")[0]
	assert_eq(failed["reason"], ContractRules.LAUNCH_FAILED)
	assert_eq(failed["amount_debited"], 0)
	assert_eq(r.state.contracts[0]["status"], ContractRules.FAILED)
	assert_eq(r.state.money, start - REFURB_COST_FAIL - _fixed_costs(r.events))
	assert_eq(r.state.model_stats.get("l1", {"successes": 0})["successes"], 0)
	assert_eq(r.state.launchers.size(), 0)
	assert_eq(_fac(r.state, "pad")["refurb_until_day"], LAUNCH_DAY + REFURB_DAYS_FAIL)
	assert_eq(r.state.reputation, REP_LAUNCH_FAIL)


func test_scrubs_until_season_changes() -> void:
	var data := _data()
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [1.0, 0.0, 0.0, 0.0]
	var state := _setup(data)
	var start := state.money
	var r := F.run(state, data, F.SEASON_DAYS + 1)
	var scrubs := r.events.filter(func(e): return e["type"] == "launch_scrubbed")
	assert_eq(scrubs.size(), F.SEASON_DAYS - LAUNCH_DAY)  # days 2..9
	assert_eq(scrubs[0]["new_launch_day"], LAUNCH_DAY + 1)
	assert_eq(scrubs[0]["season"], 0)
	assert_eq(scrubs[-1]["scrubs"], scrubs.size())
	assert_eq(F.types(r.events).count("launch_succeeded"), 1)
	var expected := start + PAYMENT - ADVANCE - scrubs.size() * SCRUB_COST - REFURB_COST
	assert_eq(r.state.money, expected - _fixed_costs(r.events))
	# daily_costs carries the costs of the day they happen (step 8).
	var costs := r.events.filter(func(e): return e["type"] == "daily_costs")
	assert_eq(costs[LAUNCH_DAY]["scrub_costs"], SCRUB_COST)
	assert_eq(costs[F.SEASON_DAYS]["refurb_costs"], REFURB_COST)


func test_scrub_past_deadline_fails_contract_same_day() -> void:
	var data := _data(1.0)
	var state := _setup(data, 3, 3)
	var r := F.run(state, data, 4)
	var types := F.types(r.events)
	assert_true(types.find("launch_scrubbed") < types.find("contract_failed"))
	var failed: Dictionary = r.events.filter(func(e): return e["type"] == "contract_failed")[0]
	assert_eq(failed["reason"], ContractRules.DEADLINE_MISSED)
	assert_eq(r.state.launches.size(), 0)
	assert_eq(types.count("launch_cancelled"), 1)
	assert_eq(r.state.launchers.size(), 1)
	assert_eq(_fac(r.state, "pad")["pad_state"], Simulation.PAD_OCCUPIED)
	assert_eq(_fac(r.state, "pad")["launcher_id"], 1)


func test_success_on_deadline_day_beats_deadline_failure() -> void:
	var data := _data(0.0, 1.0)
	var state := _setup(data, 3, 3)
	var r := F.run(state, data, 4)
	assert_eq(r.state.contracts[0]["status"], ContractRules.COMPLETED)
	assert_eq(F.types(r.events).count("contract_failed"), 0)


func test_pad_ready_after_refurb() -> void:
	var data := _data(0.0, 1.0)
	var r := F.run(_setup(data), data, LAUNCH_DAY + REFURB_DAYS)
	assert_eq(F.types(r.events).count("pad_ready"), 1)
	assert_eq(r.state.day, LAUNCH_DAY + REFURB_DAYS)
	assert_eq(_fac(r.state, "pad")["pad_state"], Simulation.PAD_FREE)


func test_reliability_grows_with_successes() -> void:
	var data := _data(0.0, 1.0)
	data.launchers["l1"]["reliability_base"] = 0.5
	var state := _setup(data)
	state.model_stats["l1"] = {"successes": 2}
	var r := F.run(state, data, LAUNCH_DAY + 1)
	var shot: Dictionary = r.events.filter(func(e): return e["type"] == "launch_succeeded" \
			or e["type"] == "launch_failed")[0]
	assert_eq(shot["reliability"], LaunchRules.model_reliability(data.launchers["l1"], 2))


func test_seeded_statistics() -> void:
	var data := _data(0.0, RELIABILITY)
	var successes := 0
	for seed_value in range(1, SEEDS + 1):
		var state := _setup(data, DEADLINE, LAUNCH_DAY, seed_value)
		state.day = LAUNCH_DAY
		var r := Simulation.step(state, [], data)
		if "launch_succeeded" in F.types(r.events):
			successes += 1
	var expected := int(SEEDS * RELIABILITY)
	assert_true(absi(successes - expected) <= SEED_TOLERANCE, "successes %d" % successes)


func test_reproducible() -> void:
	var data := _data(0.5, 0.5)
	var a := F.run(_setup(data, DEADLINE, LAUNCH_DAY, 9), data, RUN_DAYS)
	var b := F.run(_setup(data, DEADLINE, LAUNCH_DAY, 9), data, RUN_DAYS)
	assert_eq(a.events, b.events)
	assert_eq(a.state.to_dict(), b.state.to_dict())


func _market_and_deliveries(state: GameState) -> Array:
	var offers := state.contracts.filter(func(c): return c["status"] == ContractRules.OFFER) \
			.map(func(c): return [c["payload_kg"], c["payment"], c["deadline_day"], c["offer_expires_day"]])
	return [offers, state.pending_orders, state.stock]


## ADR 0005: weather and launch draws never shift deliveries or contract offers.
func test_launch_draws_do_not_alter_deliveries_or_offers() -> void:
	var data := _data(0.5, 0.5)
	data.suppliers["acme"]["delay_chance"] = 0.5
	data.contracts["offer_slots"] = RUN_DAYS * 2  # slots never bind: the launch's contract cannot change spawns
	var order := [Command.order("acme", "steel", 1)]
	var commands := {0: order, 1: order, 2: order, 3: order, 4: order}
	var a := F.run(_setup(data), data, RUN_DAYS, commands)
	var b := F.run(Simulation.new_game(data, 1), data, RUN_DAYS, commands)
	assert_eq(_market_and_deliveries(a.state), _market_and_deliveries(b.state))
	var shots := F.types(a.events).count("launch_scrubbed") + F.types(a.events).count("launch_succeeded") \
			+ F.types(a.events).count("launch_failed")
	assert_true(shots > 0)


func test_model_stats_round_trip_json() -> void:
	var data := _data(0.0, 1.0)
	var r := F.run(_setup(data), data, LAUNCH_DAY + 1)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(r.state.to_dict())))
	assert_eq(copy.model_stats, r.state.model_stats)
	assert_eq(typeof(copy.model_stats["l1"]["successes"]), TYPE_INT)

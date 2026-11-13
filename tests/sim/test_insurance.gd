extends TestCase
## Spec 003 decision 1: launch insurance (issue #17).
## Premium = contract payment * insurance_premium_pct / 100, debited at scheduling.
## Payout = kit purchase cost (cheapest supplier per component) * insurance_payout_pct / 100,
## credited on launch failure only.

const F := preload("res://tests/sim/fixtures.gd")

const PAYMENT := 100_000
const PREMIUM_PCT := 8
const PAYOUT_PCT := 60
const PREMIUM := 8_000  # PAYMENT * PREMIUM_PCT / 100
const TANK_PRICE := 300  # acme
const TANK_PRICE_CHEAP := 250  # beta, the cheapest tank
const ENGINE_PRICE := 500  # acme, the only engine offer
const TANK_QTY := 2  # kit recipe, see _data()
const KIT_COST := TANK_QTY * TANK_PRICE_CHEAP + ENGINE_PRICE  # 1000
const PAYOUT := KIT_COST * PAYOUT_PCT / 100  # 600
const LAUNCH_DAY := 2
const DEADLINE := 20
const RUN_DAYS := 3
const POOR_MONEY := PREMIUM - 1
const RECIPE_ID := "assemble"


func _data(reliability := 1.0) -> GameData:
	var data := F.data()
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 7,
		"buildable": true, "build_cost": 500, "build_days": 4, "max_count": 2,
		"rollout_days": 2, "scrub_recycle_days": 1, "scrub_cost": 10,
		"refurb_days": 3, "refurb_cost": 100,
		"refurb_days_after_failure": 6, "refurb_cost_after_failure": 300}
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "hall", "pad"], "site": F.SITE_ID}
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [0.0, 0.0, 0.0, 0.0]
	# Kit = 2 tanks + 1 engine. Two suppliers for the tank, so the cheapest one must be used.
	data.recipes[RECIPE_ID]["inputs"] = {"tank": TANK_QTY, "engine": 1}
	data.suppliers["acme"]["catalog"].append({"component_id": "tank", "unit_price": TANK_PRICE, "lead_time_days": 3})
	data.suppliers["acme"]["catalog"].append({"component_id": "engine", "unit_price": ENGINE_PRICE, "lead_time_days": 3})
	data.suppliers["beta"] = {"id": "beta", "name": "Beta", "delay_chance": 0.0, "delay_days": 1,
		"catalog": [{"component_id": "tank", "unit_price": TANK_PRICE_CHEAP, "lead_time_days": 3}]}
	data.launchers["l1"]["recipe_id"] = RECIPE_ID
	data.launchers["l1"]["reliability_base"] = reliability
	data.contracts = {
		"offer_slots": 2, "initial_offers": 0, "offer_spawn_chance": 1.0,
		"offer_validity_days": 5, "advance_pct": 20, "penalty_pct": 30,
		"insurance_premium_pct": PREMIUM_PCT, "insurance_payout_pct": PAYOUT_PCT,
		"max_active_contracts": 1, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": 0,
		"reputation_min": -100, "reputation_max": 100,
		"rep_on_success": 6, "rep_on_launch_failure": -15, "rep_on_deadline_missed": -10,
		"templates": [{"id": "t", "orbit": "leo", "mass_min_kg": 100, "mass_max_kg": 1_000,
			"base_payment": PAYMENT, "per_kg_payment": 0, "deadline_min_days": 10,
			"deadline_max_days": 30, "weight": 1, "min_reputation": -100, "clients": ["c"]}]}
	return data


func _fac(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


## One l1 in the hall and one active leo contract. No launch yet.
func _new(data: GameData, game_seed := 1) -> GameState:
	var state := Simulation.new_game(data, game_seed)
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": _fac(state, "hall")["id"]})
	state.next_launcher_id = 2
	state.contracts.append({"id": 1, "orbit": "leo", "payload_kg": 1_000, "payment": PAYMENT,
		"advance": 0, "penalty": 0, "deadline_day": DEADLINE, "status": ContractRules.ACTIVE,
		"offer_expires_day": 0})
	state.next_contract_id = 2
	return state


func _schedule(state: GameState, data: GameData, insured: Variant = null) -> Array:
	var command: Command
	if insured == null:
		command = Command.schedule_launch(1, _fac(state, "pad")["id"], 1, LAUNCH_DAY)
	else:
		command = Command.schedule_launch(1, _fac(state, "pad")["id"], 1, LAUNCH_DAY, insured)
	return Simulation.apply_command(state, command, data)


## Runs `days` days without commands, returns all events; `state` is updated in place.
func _run(state: GameState, data: GameData, days: int) -> Array:
	var events: Array = []
	for i in days:
		events.append_array(Simulation.end_day(state, data))
	return events


func _find_event(events: Array, type: String) -> Dictionary:
	for e in events:
		if e["type"] == type:
			return e
	return {}


## Final money after the launch of `insured` (same seed, same data): used to isolate
## the insurance flows from the daily costs.
func _final_money(insured: bool, reliability: float) -> int:
	var data := _data(reliability)
	var state := _new(data)
	_schedule(state, data, insured)
	_run(state, data, RUN_DAYS)
	return state.money


func test_premium_is_debited_at_scheduling() -> void:
	var data := _data()
	var state := _new(data)
	var before := state.money
	var events := _schedule(state, data, true)
	assert_eq(F.types(events), ["launch_scheduled", "insurance_paid"])
	assert_eq(state.money, before - PREMIUM)
	var paid := _find_event(events, "insurance_paid")
	assert_eq(paid["launch_id"], 1)
	assert_eq(paid["premium"], PREMIUM)
	assert_eq(state.launches[0]["insured"], true)


func test_rejected_when_funds_are_insufficient() -> void:
	var data := _data()
	var state := _new(data)
	state.money = POOR_MONEY
	var events := _schedule(state, data, true)
	assert_eq(F.types(events), ["command_rejected"])
	assert_eq(events[0]["reason"], "insufficient_funds")
	assert_eq(state.money, POOR_MONEY)
	assert_eq(state.launches.size(), 0)
	assert_eq(_fac(state, "pad")["pad_state"], Simulation.PAD_FREE)


func test_premium_exactly_affordable_is_accepted() -> void:
	var data := _data()
	var state := _new(data)
	state.money = PREMIUM
	var events := _schedule(state, data, true)
	assert_eq(F.types(events), ["launch_scheduled", "insurance_paid"])
	assert_eq(state.money, 0)


func test_payout_on_failure_is_exact() -> void:
	var data := _data(0.0)  # reliability 0: the launch always fails
	var state := _new(data)
	_schedule(state, data, true)
	var events := _run(state, data, RUN_DAYS)
	assert_true(_find_event(events, "launch_failed").size() > 0, "launch must fail")
	var payout := _find_event(events, "insurance_payout")
	assert_eq(payout["launch_id"], 1)
	assert_eq(payout["amount"], PAYOUT)
	# Same run uninsured: the only difference is premium paid and payout received.
	assert_eq(state.money - _final_money(false, 0.0), PAYOUT - PREMIUM)


func test_no_payout_on_success() -> void:
	var data := _data(1.0)  # reliability 1: the launch always succeeds
	var state := _new(data)
	_schedule(state, data, true)
	var events := _run(state, data, RUN_DAYS)
	assert_true(_find_event(events, "launch_succeeded").size() > 0, "launch must succeed")
	assert_eq(_find_event(events, "insurance_payout").size(), 0)
	assert_eq(state.money - _final_money(false, 1.0), -PREMIUM)


func test_uninsured_launch_is_unchanged() -> void:
	var data := _data(0.0)
	var state := _new(data)
	var money := state.money
	var events := _schedule(state, data)  # default: not insured
	assert_eq(F.types(events), ["launch_scheduled"])
	assert_eq(state.money, money)
	assert_eq(state.launches[0]["insured"], false)
	var run_events := _run(state, data, RUN_DAYS)
	assert_eq(_find_event(run_events, "insurance_payout").size(), 0)
	assert_eq(state.money, _final_money(false, 0.0))


func test_cancel_does_not_refund_premium() -> void:
	var data := _data()
	var state := _new(data)
	var money := state.money
	_schedule(state, data, true)
	var events := Simulation.apply_command(state, Command.cancel_launch(1), data)
	assert_eq(F.types(events), ["launch_cancelled"])
	assert_eq(state.money, money - PREMIUM)


func test_json_round_trip_keeps_insured_flag() -> void:
	var data := _data()
	var state := _new(data)
	_schedule(state, data, true)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(copy.launches, state.launches)
	assert_eq(typeof(copy.launches[0]["insured"]), TYPE_BOOL)
	assert_eq(copy.launches[0]["insured"], true)
	var command := Command.schedule_launch(1, 2, 3, LAUNCH_DAY, true)
	var restored := Command.from_dict(JSON.parse_string(JSON.stringify(command.to_dict())))
	assert_eq(restored.args["insured"], true)
	assert_eq(typeof(restored.args["insured"]), TYPE_BOOL)

extends TestCase
## Spec 009 R2, R5-R9, criteria 1 (state), 3-5, 9, 11-17, 18 (level part), 19.
## Data built here (small thresholds, short scenarios).

const F := preload("res://tests/sim/fixtures.gd")
const LEVEL_ID := "t_level"
const START_MONEY := 10_000
const DURATION := 20
const WARNING := 5
const PAYMENT := 100_000
const ADVANCE := 20_000
const CASH_TARGET := 50_000
const BIG_MONEY := 60_000
const SHARE_TARGET := 40
const SUPPLY_TARGET := 3_000
const SUPPLY_INVOICED := 3_030
const COMPLETED_FOR_STAR_3 := 3
const SHOT_DAY := 3
const LAST_DAY := 19
const DEADLINE := 30
const GRACE := 3
const DEBT := -1_000_000
const FREE_PLAY_DAYS := 5
const CONSUMED := 5
const MADE := 2  # 100 * 2 div 5 = 40 %
const COMPONENT := "steel"
const SEED := 4


func _obj(id: String, metric: String, op: String, target: int) -> Dictionary:
	return {"id": id, "metric": metric, "op": op, "target": target}


func _level(star1: Dictionary = {}, min_met := 1) -> Dictionary:
	if star1.is_empty():
		star1 = _obj("a", "contracts_completed", "gte", 1)
	return {"id": LEVEL_ID, "name": LEVEL_ID, "duration_days": DURATION, "time_warnings_days": [WARNING],
		"stars": [
			{"name": "1", "objectives": [star1]},
			{"name": "2", "objectives": [_obj("b", "net_cash", "gte", CASH_TARGET)],
				"any_of": {"min_met": min_met, "objectives": [
					_obj("c", "in_house_share_pct", "gte", SHARE_TARGET),
					_obj("d", "supply_completed_value", "gte", SUPPLY_TARGET)]}},
			{"name": "3", "objectives": [_obj("e", "contracts_completed", "gte", COMPLETED_FOR_STAR_3),
				_obj("f", "site_violations", "lte", 0)]}]}


## Hall + pad + warehouse, one contract kind, bankruptcy rules. No upkeep.
func _data(with_level := true, star1: Dictionary = {}, min_met := 1) -> GameData:
	var data := F.data()
	data.facilities["warehouse"]["upkeep_per_day"] = 0
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 0,
		"buildable": true, "build_cost": 500, "build_days": 4, "max_count": 2,
		"rollout_days": 2, "scrub_recycle_days": 1, "scrub_cost": 0,
		"refurb_days": 1, "refurb_cost": 0, "refurb_days_after_failure": 1, "refurb_cost_after_failure": 0}
	data.start = {"money": START_MONEY, "facilities": ["warehouse", "hall", "pad"], "site": F.SITE_ID}
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [0.0, 0.0, 0.0, 0.0]
	data.launchers["l1"]["reliability_base"] = 1.0
	data.rules = {"bankruptcy_grace_days": GRACE, "bankruptcy_warning_days": 1}
	data.contracts = {
		"offer_slots": 2, "initial_offers": 0, "offer_spawn_chance": 0.0,
		"offer_validity_days": 5, "advance_pct": 20, "penalty_pct": 30,
		"max_active_contracts": 1, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": 0,
		"reputation_min": -100, "reputation_max": 100,
		"rep_on_success": 6, "rep_on_launch_failure": -15, "rep_on_deadline_missed": -10,
		"templates": []}
	if with_level:
		data.level = _level(star1, min_met)
	return data


func _fid(state: GameState, type: String) -> int:
	for f in state.facilities:
		if f["type"] == type:
			return f["id"]
	return -1


func _completed_contract(id: int) -> Dictionary:
	return {"id": id, "orbit": "leo", "payload_kg": 1_000, "payment": PAYMENT, "advance": ADVANCE,
		"penalty": 0, "deadline_day": DEADLINE, "status": ContractRules.COMPLETED, "offer_expires_day": 0}


## Active contract, one launcher in the hall, launch planned on `launch_day`.
func _shot(data: GameData, launch_day: int) -> GameState:
	var state := Simulation.new_game(data, SEED)
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": _fid(state, "hall")})
	state.next_launcher_id = 2
	var contract := _completed_contract(1)
	contract["status"] = ContractRules.ACTIVE
	state.contracts.append(contract)
	state.next_contract_id = 2
	var events := Simulation.apply_command(state, Command.schedule_launch(1, _fid(state, "pad"), 1, launch_day), data)
	assert_eq(F.types(events), ["launch_scheduled"])
	return state


## Runs `days` days. Returns {state, by_day: [events of each day]}.
func _run(state: GameState, data: GameData, days: int) -> Dictionary:
	var by_day: Array = []
	for i in days:
		var result := Simulation.step(state, [], data)
		state = result.state
		by_day.append(result.events)
	return {"state": state, "by_day": by_day}


func _all(by_day: Array, type: String) -> Array:
	var out: Array = []
	for events in by_day:
		for e in events:
			if e["type"] == type:
				out.append(e)
	return out


func _reason(events: Array) -> String:
	for e in events:
		if e["type"] == "command_rejected":
			return e["reason"]
	return ""


## Star 1 acquired, big cash: ready for star 2 checks.
func _at_star_1(data: GameData) -> GameState:
	var state := Simulation.new_game(data, SEED)
	state.level["stars"] = 1
	state.level["star_days"][0] = 0
	state.money = BIG_MONEY
	return state


func _ended_state() -> Array:  # [state, data]: level ended by time at day 19
	var data := _data()
	var state := Simulation.new_game(data, SEED)
	state = _run(state, data, DURATION)["state"]
	return [state, data]


# Criterion 1
func test_new_game_level_state() -> void:
	var state := Simulation.new_game(_data(), SEED)
	assert_eq(state.level, {"id": LEVEL_ID, "status": "running", "stars": 0,
		"star_days": [-1, -1, -1], "end_day": -1, "end_reason": ""})


# Criterion 2
func test_no_level_no_level_events() -> void:
	var data := _data(false)
	var state := Simulation.new_game(data, SEED)
	assert_eq(state.level["id"], "")
	assert_eq(state.level["status"], "free_play")
	var r := _run(state, data, 30)
	for type in ["star_earned", "level_time_warning", "level_ended"]:
		assert_eq(_all(r["by_day"], type).size(), 0, type)


# Criterion 3
func test_star_one_at_end_of_day() -> void:
	var data := _data()
	var state := _shot(data, SHOT_DAY)
	var r := _run(state, data, SHOT_DAY + 1)
	for day in SHOT_DAY:
		assert_eq(_all([r["by_day"][day]], "star_earned").size(), 0)
	var types: Array = F.types(r["by_day"][SHOT_DAY])
	assert_true(types.find("contract_completed") < types.find("daily_costs"), "completed before costs")
	assert_true(types.find("daily_costs") < types.find("star_earned"), "star after costs")
	var star: Dictionary = _all(r["by_day"], "star_earned")[0]
	assert_eq([star["star"], star["day"]], [1, SHOT_DAY])
	assert_eq(r["state"].level["stars"], 1)
	assert_eq(r["state"].level["star_days"], [SHOT_DAY, -1, -1])


# Criterion 4
func test_star_is_definitive() -> void:
	var data := _data(true, _obj("a", "net_cash", "gte", 5_000))
	var state := Simulation.new_game(data, SEED)
	var first := _run(state, data, 1)
	assert_eq(_all(first["by_day"], "star_earned").size(), 1)
	state = first["state"]
	state.money = 0
	var second := _run(state, data, 5)
	assert_eq(second["state"].level["stars"], 1)
	assert_eq(_all(second["by_day"], "star_earned").size(), 0)


# Criterion 5
func test_stars_come_in_order_the_same_day() -> void:
	var data := _data()
	var state := Simulation.new_game(data, SEED)
	state.money = BIG_MONEY
	state.supply_contracts.append({"id": 1, "status": SupplyRules.COMPLETED, "invoiced_total": SUPPLY_INVOICED})
	var r := _run(state, data, 1)
	assert_eq(_all(r["by_day"], "star_earned").size(), 0, "no launch contract done: no star")
	state = r["state"]
	state.contracts.append(_completed_contract(1))
	r = _run(state, data, 1)
	var stars: Array = _all(r["by_day"], "star_earned").map(func(e): return e["star"])
	assert_eq(stars, [1, 2])


# Criterion 9
func test_any_of_choice() -> void:
	var data := _data()
	var state := _at_star_1(data)
	assert_eq(_all(_run(state, data, 1)["by_day"], "star_earned").size(), 0, "none of the choices")
	state.stats["kit_consumed"][COMPONENT] = CONSUMED
	state.stats["components_made"][COMPONENT] = MADE
	data.suppliers["acme"]["catalog"][0]["unit_price"] = F.UNIT_PRICE
	assert_eq(ObjectiveRules.metric_value(state, data, "in_house_share_pct"), SHARE_TARGET)
	assert_eq(_all(_run(state, data, 1)["by_day"], "star_earned").size(), 1, "share 40")
	var other := _at_star_1(data)
	other.supply_contracts.append({"id": 1, "status": SupplyRules.COMPLETED, "invoiced_total": SUPPLY_INVOICED})
	assert_eq(_all(_run(other, data, 1)["by_day"], "star_earned").size(), 1, "supply value")
	var strict := _data(true, {}, 2)
	var both_needed := _at_star_1(strict)
	both_needed.stats = state.stats.duplicate(true)
	assert_eq(_all(_run(both_needed, strict, 1)["by_day"], "star_earned").size(), 0, "min_met 2, one met")


# Criterion 11
func test_time_up_and_warning() -> void:
	var data := _data()
	var r := _run(Simulation.new_game(data, SEED), data, DURATION)
	var warnings: Array = _all(r["by_day"], "level_time_warning")
	assert_eq(warnings.size(), 1)
	assert_eq(warnings[0]["days_left"], WARNING)
	assert_eq(_all([r["by_day"][DURATION - WARNING - 1]], "level_time_warning").size(), 1, "day 14")
	var ended: Array = _all([r["by_day"][LAST_DAY]], "level_ended")
	assert_eq(ended.size(), 1)
	assert_eq([ended[0]["reason"], ended[0]["stars"]], ["time_up", 0])
	assert_eq(r["state"].level["status"], "ended")
	assert_eq(r["state"].level["end_day"], LAST_DAY)
	assert_eq(r["state"].day, DURATION)


# Criterion 12
func test_last_day_counts() -> void:
	var data := _data()
	var r := _run(_shot(data, LAST_DAY), data, DURATION)
	var types: Array = F.types(r["by_day"][LAST_DAY])
	assert_true(types.find("star_earned") >= 0 and types.find("star_earned") < types.find("level_ended"))
	var ended: Dictionary = _all(r["by_day"], "level_ended")[0]
	assert_eq([ended["reason"], ended["stars"]], ["time_up", 1])


# Criterion 13
func test_ended_level_freezes_the_game() -> void:
	var pair := _ended_state()
	var state: GameState = pair[0]
	var data: GameData = pair[1]
	var money := state.money
	var events := Simulation.apply_command(state, Command.order("acme", "steel", 1), data)
	assert_eq(_reason(events), "level_over")
	assert_eq(state.money, money)
	assert_eq(Simulation.end_day(state, data), [])
	assert_eq(state.day, DURATION)


# Criterion 14
func test_free_play_resumes_and_freezes_stars() -> void:
	var pair := _ended_state()
	var state: GameState = pair[0]
	var data: GameData = pair[1]
	var events := Simulation.apply_command(state, Command.continue_free_play(), data)
	assert_eq(F.types(events), ["free_play_started"])
	assert_eq(events[0]["level_id"], LEVEL_ID)
	assert_eq(state.level["status"], "free_play")
	state.contracts.append(_completed_contract(1))
	var r := _run(state, data, FREE_PLAY_DAYS)
	assert_eq(r["state"].day, DURATION + FREE_PLAY_DAYS)
	assert_eq(r["state"].level["stars"], 0)
	assert_eq(_all(r["by_day"], "star_earned").size(), 0)
	assert_eq(_all(r["by_day"], "level_ended").size(), 0)


func test_continue_while_running_is_rejected() -> void:
	var data := _data()
	var state := Simulation.new_game(data, SEED)
	assert_eq(_reason(Simulation.apply_command(state, Command.continue_free_play(), data)), "level_not_ended")
	assert_eq(state.level["status"], "running")


# Criterion 15
func test_three_stars_end_the_level() -> void:
	var data := _data()
	var state := Simulation.new_game(data, SEED)
	state.money = BIG_MONEY
	state.supply_contracts.append({"id": 1, "status": SupplyRules.COMPLETED, "invoiced_total": SUPPLY_INVOICED})
	for i in COMPLETED_FOR_STAR_3:
		state.contracts.append(_completed_contract(i + 1))
	var r := _run(state, data, 1)
	var stars: Array = _all(r["by_day"], "star_earned").map(func(e): return e["star"])
	assert_eq(stars, [1, 2, 3])
	var types: Array = F.types(r["by_day"][0])
	assert_eq(types.back(), "level_ended")
	var ended: Dictionary = _all(r["by_day"], "level_ended")[0]
	assert_eq([ended["reason"], ended["stars"]], ["all_stars", 3])
	assert_eq(r["state"].level["status"], "ended")


# Criterion 16
func test_bankruptcy_ends_the_level_without_evaluating() -> void:
	for earned in [0, 1]:
		var data := _data()
		var state := _shot(data, GRACE - 1)
		state.money = DEBT
		if earned == 1:
			state.level["stars"] = 1
			state.level["star_days"][0] = 0
		var r := _run(state, data, GRACE)
		var types: Array = F.types(r["by_day"][GRACE - 1])
		assert_true(types.find("contract_completed") < types.find("game_over"))
		assert_true(types.find("game_over") < types.find("level_ended"))
		assert_eq(_all(r["by_day"], "star_earned").size(), 0, "no evaluation on bankruptcy")
		var ended: Dictionary = _all(r["by_day"], "level_ended")[0]
		assert_eq([ended["reason"], ended["stars"]], ["bankruptcy", earned])
		assert_eq(r["state"].level["stars"], earned, "(acquired star is kept)")
		var events := Simulation.apply_command(r["state"], Command.continue_free_play(), data)
		assert_eq(_reason(events), "game_over")


# Criterion 17
func test_progress_query() -> void:
	var data := _data()
	var state := Simulation.new_game(data, SEED)
	state.money = 45_000 + ADVANCE
	var contract := _completed_contract(1)
	contract["status"] = ContractRules.ACTIVE
	state.contracts.append(contract)
	var p := LevelRules.progress(state, data)
	assert_eq(p["days_left"], DURATION - state.day)
	assert_eq(p["star_list"].size(), 3)
	var star2: Dictionary = p["star_list"][1]
	var cash: Dictionary = star2["objectives"][0]
	assert_eq([cash["metric"], cash["value"], cash["target"], cash["met"]], ["net_cash", 45_000, CASH_TARGET, false])
	assert_eq(star2["any_of"]["met_count"], 0)
	assert_eq(star2["earned"], false)


func test_summary_query() -> void:
	var data := _data()
	var state := Simulation.new_game(data, SEED)
	state.contracts.append(_completed_contract(1))
	var failed := _completed_contract(2)
	failed["status"] = ContractRules.FAILED
	state.contracts.append(failed)
	var s := LevelRules.summary(state, data)
	assert_eq([s["contracts_completed"], s["contracts_failed"], s["money"]], [1, 1, START_MONEY])
	assert_eq(s["star_days"], [-1, -1, -1])


# Criterion 18 (level part)
func test_json_round_trip() -> void:
	var pair := _ended_state()
	var state: GameState = pair[0]
	state.level["stars"] = 1
	state.level["star_days"][0] = SHOT_DAY
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(back.level, state.level)
	assert_true(back.level["stars"] is int and back.level["end_day"] is int and back.level["star_days"][0] is int)


func test_old_save_loads_in_free_play() -> void:
	var data := _data(false)
	var d := Simulation.new_game(data, SEED).to_dict()
	d.erase("level")
	var state := GameState.from_dict(d)
	assert_eq(state.level, {"id": "", "status": "free_play", "stars": 0, "star_days": [-1, -1, -1],
		"end_day": -1, "end_reason": ""})
	var r := _run(state, data, FREE_PLAY_DAYS)
	assert_eq(_all(r["by_day"], "level_ended").size(), 0)


# Criterion 19
func test_level_only_adds_its_own_events() -> void:
	var with_level := _data()
	var without := _data(false)
	var a := _run(_shot(with_level, SHOT_DAY), with_level, DURATION)
	var b := _run(_shot(without, SHOT_DAY), without, DURATION)
	var skip := ["star_earned", "level_time_warning", "level_ended"]
	var strip := func(by_day: Array) -> Array:
		return by_day.map(func(events): return events.filter(func(e): return not (e["type"] in skip)))
	assert_eq(strip.call(a["by_day"]), strip.call(b["by_day"]))
	assert_eq(a["state"].money, b["state"].money)

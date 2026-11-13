extends TestCase
## SimQueries: read-only helpers for the UI.

const F := preload("res://tests/sim/fixtures.gd")


func _state(techs := 2, stock := {}) -> Array:
	var data := F.data()
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "shop", "hall"],
		"technicians": techs, "assignments": {"shop": techs}}
	var state := Simulation.new_game(data, 1)
	state.stock = stock.duplicate()
	return [state, data]


func _fac(state: GameState, type: String) -> Dictionary:
	for f in state.facilities:
		if f["type"] == type:
			return f
	return {}


func test_job_info_progress_and_days_left() -> void:
	var s := _state(1, {"steel": 2})
	var shop := _fac(s[0], "shop")
	var r := F.run(s[0], s[1], 1, {0: [Command.queue_job(shop["id"], "weld", 1)]})
	var rshop := _fac(r.state, "shop")
	var info := SimQueries.job_info(s[1], rshop, rshop["jobs"][0])
	assert_eq(info["progress"], 10)
	assert_eq(info["percent"], 50)
	assert_eq(info["days_left"], 1)
	assert_true(not info["idle"])


func test_job_info_idle_without_staff() -> void:
	var s := _state(0, {"steel": 2})
	var shop := _fac(s[0], "shop")
	var r := F.run(s[0], s[1], 1, {0: [Command.queue_job(shop["id"], "weld", 1)]})
	var rshop := _fac(r.state, "shop")
	var info := SimQueries.job_info(s[1], rshop, rshop["jobs"][0])
	assert_true(info["idle"])
	assert_eq(info["days_left"], -1)


func test_build_options() -> void:
	var s := _state()
	var options := SimQueries.build_options(s[0], s[1])
	assert_eq(options.size(), 1)
	assert_eq(options[0]["type"], "shop")
	assert_eq(options[0]["cost"], F.SHOP_COST)
	assert_eq(options[0]["remaining"], 0)


func test_staff_info() -> void:
	var s := _state(2)
	var info := SimQueries.staff_info(s[0], s[1])
	assert_eq(info["hired"], 2)
	assert_eq(info["assigned"], 2)
	assert_eq(info["free"], 0)
	assert_eq(info["daily_salaries"], 2 * F.SALARY)


func test_bill_of_materials_counts_orders_in_transit() -> void:
	var s := _state(2, {"steel": 1})
	var rows := SimQueries.bill_of_materials(s[0], s[1], "weld")
	assert_eq(rows[0]["required"], 2)
	assert_eq(rows[0]["missing"], 1)
	var r := F.run(s[0], s[1], 1, {0: [Command.order("acme", "steel", 1)]})
	rows = SimQueries.bill_of_materials(r.state, s[1], "weld")
	assert_eq(rows[0]["on_order"], 1)
	assert_eq(rows[0]["missing"], 0)


func test_buy_vs_make() -> void:
	var s := _state(1)
	var cmp := SimQueries.buy_vs_make(s[0], s[1], "tank")
	assert_true(cmp["buy"].is_empty(), "no supplier sells tank in fixtures")
	assert_eq(cmp["make"]["recipe_id"], "weld")
	assert_eq(cmp["make"]["material_cost"], 2 * F.UNIT_PRICE)
	assert_eq(cmp["make"]["days"], 2)
	var steel := SimQueries.buy_vs_make(s[0], s[1], "steel")
	assert_eq(steel["buy"]["unit_price"], F.UNIT_PRICE)
	assert_eq(steel["buy"]["lead_time_days"], F.LEAD_TIME)
	assert_true(steel["make"].is_empty())


func test_hall_occupancy() -> void:
	var s := _state()
	var hall := _fac(s[0], "hall")
	s[0].launchers.append({"id": 1, "model": "l1", "location_facility_id": hall["id"]})
	var occ := SimQueries.hall_occupancy(s[0], s[1], hall)
	assert_eq(occ["used"], 1)
	assert_eq(occ["capacity"], 1)


# --- Contracts ---------------------------------------------------------------

func _contract_state(max_active := 1) -> Array:
	var data := F.data()
	data.orbits["far"] = {"id": "far", "azimuth_deg": F.SSO_AZ}
	data.contracts = {
		"offer_slots": 2, "initial_offers": 0, "offer_spawn_chance": 0.0,
		"offer_validity_days": 5, "advance_pct": 20, "penalty_pct": 30,
		"max_active_contracts": max_active, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": 50,
		"reputation_min": 0, "reputation_max": 100,
		"rep_on_success": 6, "rep_on_launch_failure": -15, "rep_on_deadline_missed": -10,
		"templates": [
			{"id": "a", "orbit": "leo", "mass_min_kg": 1, "mass_max_kg": 1, "base_payment": 1,
				"per_kg_payment": 0, "deadline_min_days": 1, "deadline_max_days": 1, "weight": 1,
				"min_reputation": 0, "clients": ["c"]},
			{"id": "b", "orbit": "leo", "mass_min_kg": 1, "mass_max_kg": 1, "base_payment": 1,
				"per_kg_payment": 0, "deadline_min_days": 1, "deadline_max_days": 1, "weight": 1,
				"min_reputation": 60, "clients": ["c"]}]}
	var state := Simulation.new_game(data, 1)
	state.reputation = 50
	return [state, data]


func _add_contract(state: GameState, orbit: String, kg: int, status: String, deadline := 20) -> int:
	var id := state.next_contract_id
	state.next_contract_id += 1
	state.contracts.append({"id": id, "template_id": "x", "client": "c", "orbit": orbit,
		"payload_kg": kg, "payment": 100, "advance": 20, "penalty": 30,
		"deadline_day": deadline, "status": status, "offer_expires_day": 5})
	return id


func test_contract_offers_days_and_signable() -> void:
	var s := _contract_state()
	_add_contract(s[0], "leo", F.LEO_KG * 9 / 10, ContractRules.OFFER)
	var offers := SimQueries.contract_offers(s[0], s[1])
	assert_eq(offers.size(), 1)
	assert_true(offers[0]["can_accept"])
	assert_eq(offers[0]["deadline_days_left"], 20)
	assert_eq(offers[0]["offer_days_left"], 5)
	assert_eq(offers[0]["capacity_kg"], F.LEO_KG)
	assert_true(offers[0]["near_capacity"])


func test_can_accept_reasons() -> void:
	var s := _contract_state()
	var heavy := _add_contract(s[0], "leo", F.LEO_KG + 1, ContractRules.OFFER)
	var far := _add_contract(s[0], "far", 100, ContractRules.OFFER)
	var ok := _add_contract(s[0], "leo", 100, ContractRules.OFFER)
	assert_eq(SimQueries.can_accept(s[0], s[1], ContractRules.find(s[0], heavy))["reason"], "payload_too_heavy")
	assert_eq(SimQueries.can_accept(s[0], s[1], ContractRules.find(s[0], far))["reason"], "orbit_unreachable")
	assert_true(SimQueries.can_accept(s[0], s[1], ContractRules.find(s[0], ok))["ok"])
	_add_contract(s[0], "leo", 100, ContractRules.ACTIVE)
	assert_eq(SimQueries.can_accept(s[0], s[1], ContractRules.find(s[0], ok))["reason"], "too_many_contracts")


func test_can_accept_matches_simulation() -> void:
	var s := _contract_state()
	var id := _add_contract(s[0], "leo", F.LEO_KG + 1, ContractRules.OFFER)
	var reason: String = SimQueries.can_accept(s[0], s[1], ContractRules.find(s[0], id))["reason"]
	var events := Simulation.apply_command(s[0], Command.accept_contract(id), s[1])
	assert_eq(events[0]["reason"], reason)


func test_active_contracts_sorted_with_launch_and_urgency() -> void:
	var s := _contract_state(3)
	var late := _add_contract(s[0], "leo", 100, ContractRules.ACTIVE, 40)
	var soon := _add_contract(s[0], "leo", 100, ContractRules.ACTIVE, 5)
	s[0].launches.append({"id": 1, "launcher_id": 1, "pad_id": 1, "contract_id": late,
		"launch_day": 12, "scrubs": 0})
	var active := SimQueries.active_contracts(s[0], s[1])
	assert_eq(active[0]["id"], soon)
	assert_true(active[0]["urgent"])
	assert_eq(active[0]["launch_id"], -1)
	assert_eq(active[1]["id"], late)
	assert_eq(active[1]["launch_day"], 12)
	assert_true(not active[1]["urgent"])


func test_contract_history_filters_and_limits() -> void:
	var s := _contract_state()
	_add_contract(s[0], "leo", 100, ContractRules.OFFER)
	var a := _add_contract(s[0], "leo", 100, ContractRules.COMPLETED)
	var b := _add_contract(s[0], "leo", 100, ContractRules.FAILED)
	_add_contract(s[0], "leo", 100, ContractRules.ACTIVE)
	var hist := SimQueries.contract_history(s[0], 5)
	assert_eq(hist.size(), 2)
	assert_eq(hist[0]["id"], b)
	assert_eq(hist[1]["id"], a)
	assert_eq(SimQueries.contract_history(s[0], 1).size(), 1)


func test_reputation_info_next_unlock() -> void:
	var s := _contract_state()
	var info := SimQueries.reputation_info(s[0], s[1])
	assert_eq(info["value"], 50)
	assert_eq(info["max"], 100)
	assert_eq(info["next_unlock_at"], 60)
	s[0].reputation = 70
	assert_eq(SimQueries.reputation_info(s[0], s[1])["next_unlock_at"], -1)


# --- Launch queries (spec 003 UI) ---------------------------------------------

func _launch_setup(orbit := "leo", payload := 1_000) -> Array:
	var data := F.data()
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 0, "rollout_days": 2,
		"scrub_recycle_days": 1, "scrub_cost": 10, "refurb_days": 3, "refurb_cost": 100,
		"refurb_days_after_failure": 6, "refurb_cost_after_failure": 300}
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "hall", "pad"], "site": F.SITE_ID}
	var state := Simulation.new_game(data, 1)
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": _fac(state, "hall")["id"]})
	state.contracts.append({"id": 1, "client": "Acme", "orbit": orbit, "payload_kg": payload, "payment": 100_000,
		"advance": 0, "penalty": 0, "deadline_day": 20, "status": ContractRules.ACTIVE, "offer_expires_day": 0})
	return [state, data]


func test_weather_risk_follows_season_of_the_day() -> void:
	var data := F.data()
	var r := SimQueries.weather_risk(data, 12)
	assert_eq(r["season_name"], "b")
	assert_eq(r["scrub_chance"], F.SCRUB_BY_SEASON[1])
	assert_eq(SimQueries.weather_risk(data, 9)["scrub_chance"], F.SCRUB_BY_SEASON[0])


func test_model_reliability_grows_with_successes() -> void:
	var s := _launch_setup()
	assert_eq(SimQueries.model_reliability(s[0], s[1], "l1"), 0.5)
	s[0].model_stats["l1"] = {"successes": 2}
	assert_eq(SimQueries.model_reliability(s[0], s[1], "l1"), 0.7)


func test_pad_infos_free_occupied_refurbishing() -> void:
	var s := _launch_setup()
	var pad := _fac(s[0], "pad")
	var info := SimQueries.pad_infos(s[0], s[1])
	assert_eq(info.size(), 1)
	assert_eq(info[0]["pad_state"], "free")
	Simulation.apply_command(s[0], Command.schedule_launch(1, pad["id"], 1, 2), s[1])
	info = SimQueries.pad_infos(s[0], s[1])
	assert_eq(info[0]["pad_state"], "occupied")
	assert_eq(info[0]["launcher_model"], "l1")
	assert_eq(info[0]["launch_day"], 2)
	Simulation.start_refurbishment(pad, 9)
	info = SimQueries.pad_infos(s[0], s[1])
	assert_eq(info[0]["pad_state"], "refurbishing")
	assert_eq(info[0]["refurb_until_day"], 9)


func test_ready_launchers_excludes_scheduled_ones() -> void:
	var s := _launch_setup()
	var ready := SimQueries.ready_launchers(s[0], s[1])
	assert_eq(ready.size(), 1)
	assert_eq(ready[0]["pad_id"], -1)
	Simulation.apply_command(s[0], Command.schedule_launch(1, _fac(s[0], "pad")["id"], 1, 2), s[1])
	assert_eq(SimQueries.ready_launchers(s[0], s[1]).size(), 0)


func test_min_launch_day_rollout_then_one_day_on_pad() -> void:
	var s := _launch_setup()
	var pad := _fac(s[0], "pad")
	assert_eq(SimQueries.min_launch_day(s[0], s[1], 1, pad["id"]), 2)
	Simulation.apply_command(s[0], Command.schedule_launch(1, pad["id"], 1, 2), s[1])
	assert_eq(SimQueries.min_launch_day(s[0], s[1], 1, pad["id"]), 1)


func test_launch_contract_options_explain_incompatibility() -> void:
	var s := _launch_setup("sso")
	var options := SimQueries.launch_contract_options(s[0], s[1], 1)
	assert_eq(options.size(), 1)
	assert_true(not options[0]["ok"])
	assert_eq(options[0]["reason"], "orbit_unreachable")
	var heavy := _launch_setup("leo", 5_000)
	assert_eq(SimQueries.launch_contract_options(heavy[0], heavy[1], 1)[0]["reason"], "payload_too_heavy")


func test_launch_plan_matches_schedule_launch() -> void:
	var s := _launch_setup()
	var pad_id: int = _fac(s[0], "pad")["id"]
	var plan := SimQueries.launch_plan(s[0], s[1], 1, pad_id, 1, 12)
	assert_eq(plan["error"], "")
	assert_eq(plan["season_name"], "b")
	assert_eq(plan["scrub_chance"], F.SCRUB_BY_SEASON[1])
	assert_eq(plan["reliability"], 0.5)
	assert_eq(plan["margin_days"], 8)
	assert_eq(SimQueries.launch_plan(s[0], s[1], 1, pad_id, 1, 1)["error"], "too_early")
	assert_eq(SimQueries.launch_plan(s[0], s[1], 1, pad_id, 1, 21)["error"], "after_deadline")
	var events := Simulation.apply_command(s[0], Command.schedule_launch(1, pad_id, 1, 12), s[1])
	assert_eq(events[0]["type"], "launch_scheduled")


func test_scheduled_launches_carry_weather_and_margin() -> void:
	var s := _launch_setup()
	Simulation.apply_command(s[0], Command.schedule_launch(1, _fac(s[0], "pad")["id"], 1, 12), s[1])
	var list := SimQueries.scheduled_launches(s[0], s[1])
	assert_eq(list.size(), 1)
	assert_eq(list[0]["client"], "Acme")
	assert_eq(list[0]["margin_days"], 8)
	assert_eq(list[0]["scrub_chance"], F.SCRUB_BY_SEASON[1])


func test_bankruptcy_status_warning_and_days_left() -> void:
	var s := _launch_setup()
	var data: GameData = s[1]
	data.rules = {"bankruptcy_grace_days": 10, "bankruptcy_warning_days": 7}
	var state: GameState = s[0]
	state.days_in_debt = 6
	assert_true(not SimQueries.bankruptcy_status(state, data)["warning"])
	state.days_in_debt = 7
	var status := SimQueries.bankruptcy_status(state, data)
	assert_true(status["warning"])
	assert_eq(status["days_left"], 3)


func test_order_quote_cost_and_storage() -> void:
	var s := _state(1, {"steel": 3})
	var q := SimQueries.order_quote(s[0], s[1], "acme", "steel", 4)
	assert_eq(q["total_cost"], 4 * F.UNIT_PRICE)
	assert_eq(q["storage_units"], 4)
	assert_eq(q["free_storage"], F.CAPACITY - 3)
	assert_true(q["affordable"] and q["fits"])
	var big := SimQueries.order_quote(s[0], s[1], "acme", "steel", F.CAPACITY)
	assert_true(not big["fits"])
	var rich := SimQueries.order_quote(s[0], s[1], "acme", "steel", F.START_MONEY)
	assert_true(not rich["affordable"])

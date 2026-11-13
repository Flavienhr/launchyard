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

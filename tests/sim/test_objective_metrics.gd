extends TestCase
## Spec 009 R3-R4, criteria 6, 7, 8 and 18 (counters part). Data built here.

const F := preload("res://tests/sim/fixtures.gd")
const PAYMENT := 100_000
const ADVANCE := 20_000
const START_MONEY := 45_000
const LAUNCH_DAY := 2
const PRICE_ENGINE := 1_000
const PRICE_ENGINE_B := 1_200
const PRICE_TANK := 500
const KIT_ENGINES := 2
const SUPPLY_UNIT := 100
const SUPPLY_QTY := 10
const SUPPLY_PERIOD := 7
const SUPPLY_COUNT := 3
const SUPPLY_LEAD := 2
const BIG_WAREHOUSE := 1000


func _supplier(id: String, catalog: Array) -> Dictionary:
	return {"id": id, "name": id, "delay_chance": 0.0, "delay_days": 1, "catalog": catalog}


func _entry(component: String, price: int) -> Dictionary:
	return {"component_id": component, "unit_price": price, "lead_time_days": SUPPLY_LEAD,
		"contract_terms": {"min_quantity": 1, "max_quantity": 50}}


## Production data: forge (ore -> engine), hall (engine x2 + tank -> l1).
func _prod_data(scrap := 0.0) -> GameData:
	var data := F.data()
	data.components["ore"] = {"id": "ore", "name": "Ore", "mass_kg": 1, "storage_units": 1}
	data.facilities["forge"] = {"id": "forge", "name": "Forge", "upkeep_per_day": 0, "slots": 2,
		"productivity_per_slot": 10, "buildable": true, "build_cost": 1000, "build_days": 2, "max_count": 1}
	data.facilities["warehouse"]["upkeep_per_day"] = 0
	data.recipes["make_engine"] = {"id": "make_engine", "facility_type": "forge", "inputs": {"ore": 1},
		"output": {"component_id": "engine", "quantity": 1}, "work_points": 20,
		"scrap_rate_start": scrap, "scrap_rate_floor": scrap}
	data.recipes["assemble_t"] = {"id": "assemble_t", "facility_type": "hall",
		"inputs": {"engine": KIT_ENGINES, "tank": 1}, "output": {"launcher_model": "l1"}, "work_points": 20}
	data.suppliers.clear()
	data.suppliers["sup_a"] = _supplier("sup_a", [_entry("engine", PRICE_ENGINE), _entry("tank", PRICE_TANK), _entry("ore", 10)])
	data.suppliers["sup_b"] = _supplier("sup_b", [_entry("engine", PRICE_ENGINE_B)])
	data.staff["max_queue_length"] = 10
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "forge", "hall"], "technicians": 4,
		"assignments": {"forge": 2, "hall": 2}}
	return data


func _fid(state: GameState, type: String) -> int:
	for f in state.facilities:
		if f["type"] == type:
			return f["id"]
	return -1


func _produce(data: GameData, stock: Dictionary, engines: int, assemble: bool, days: int) -> GameState:
	var state := Simulation.new_game(data, 1)
	state.stock = stock.duplicate()
	var commands := [Command.queue_job(_fid(state, "forge"), "make_engine", engines)]
	if assemble:
		commands.append(Command.queue_job(_fid(state, "hall"), "assemble_t", 1))
	return F.run(state, data, days, {0: commands}).state


func _metric(state: GameState, data: GameData, id: String) -> int:
	return ObjectiveRules.metric_value(state, data, id)


# Criterion 7a
func test_share_is_zero_when_nothing_assembled() -> void:
	var data := _prod_data()
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data, "in_house_share_pct"), 0)
	assert_eq(state.stats["kit_consumed"], {})


# Criterion 7b
func test_share_counts_made_parts_against_the_kit() -> void:
	var data := _prod_data()
	var state := _produce(data, {"ore": 1, "engine": 1, "tank": 1}, 1, true, 2)
	assert_eq(state.stats["kit_consumed"], {"engine": 2, "tank": 1})
	assert_eq(state.stats["components_made"], {"engine": 1})
	assert_eq(_metric(state, data, "in_house_share_pct"), 40)  # 100 * 1000 div 2500


# Criterion 7c
func test_extra_made_parts_do_not_inflate_the_share() -> void:
	var data := _prod_data()
	var state := _produce(data, {"ore": 5, "tank": 1}, 5, true, 7)
	assert_eq(state.stats["components_made"]["engine"], 5)
	assert_eq(state.stats["kit_consumed"]["engine"], 2)
	assert_eq(_metric(state, data, "in_house_share_pct"), 80)  # 100 * 2000 div 2500


# Criterion 7d
func test_scrapped_job_adds_nothing() -> void:
	var data := _prod_data(1.0)
	var state := _produce(data, {"ore": 1}, 1, false, 2)
	assert_eq(state.stats["components_made"], {})


func test_output_blocked_job_adds_nothing() -> void:
	var data := _prod_data()
	data.facilities["warehouse"]["storage_capacity"] = 1
	var state := _produce(data, {"ore": 1, "engine": 1}, 1, false, 2)
	assert_eq(state.stats["components_made"], {}, "(output blocked: nothing entered the stock)")


func test_non_launcher_recipe_does_not_count_as_kit() -> void:
	var data := _prod_data()
	var state := _produce(data, {"ore": 1}, 1, false, 2)
	assert_eq(state.stats["kit_consumed"], {})
	assert_eq(state.stats["components_made"], {"engine": 1})


func test_ref_price_is_the_cheapest_catalog_price() -> void:
	assert_eq(ObjectiveRules.ref_price(_prod_data(), "engine"), PRICE_ENGINE)


# Criterion 6
func test_net_cash_excludes_active_advances() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	state.money = START_MONEY
	state.contracts.append({"id": 1, "status": ContractRules.ACTIVE, "advance": ADVANCE, "payment": PAYMENT})
	assert_eq(_metric(state, data, "net_cash"), START_MONEY - ADVANCE)
	state.contracts[0]["status"] = ContractRules.COMPLETED
	assert_eq(_metric(state, data, "net_cash"), START_MONEY)
	assert_eq(_metric(state, data, "contracts_completed"), 1)


func test_accept_then_success_matches_criterion_6() -> void:
	var data := _launch_data()
	var state := Simulation.new_game(data, 1)
	state.money = START_MONEY
	state.launchers.append({"id": 1, "model": "l1", "location_facility_id": _fid(state, "hall")})
	state.next_launcher_id = 2
	state.contracts.append({"id": 1, "orbit": "leo", "payload_kg": 1_000, "payment": PAYMENT,
		"advance": ADVANCE, "penalty": 0, "deadline_day": 20, "status": ContractRules.OFFER,
		"offer_expires_day": 5})
	state.next_contract_id = 2
	var events := Simulation.apply_command(state, Command.accept_contract(1), data)
	assert_eq(F.types(events), ["contract_accepted"])
	assert_eq(state.money, START_MONEY + ADVANCE)
	assert_eq(_metric(state, data, "net_cash"), START_MONEY)
	assert_eq(_metric(state, data, "contracts_completed"), 0)
	Simulation.apply_command(state, Command.schedule_launch(1, _fid(state, "pad"), 1, LAUNCH_DAY), data)
	var r := F.run(state, data, LAUNCH_DAY + 1)
	assert_eq(r.state.contracts[0]["status"], ContractRules.COMPLETED)
	assert_eq(_metric(r.state, data, "net_cash"), r.state.money)
	assert_true(_metric(r.state, data, "net_cash") > START_MONEY)
	assert_eq(_metric(r.state, data, "contracts_completed"), 1)
	assert_eq(_metric(r.state, data, "reputation"), r.state.reputation)
	assert_true(r.state.reputation != 0, "(the success moved the reputation)")


func _launch_data() -> GameData:
	var data := F.data()
	data.facilities["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 0,
		"buildable": true, "build_cost": 500, "build_days": 4, "max_count": 2,
		"rollout_days": 2, "scrub_recycle_days": 1, "scrub_cost": 0,
		"refurb_days": 1, "refurb_cost": 0, "refurb_days_after_failure": 1, "refurb_cost_after_failure": 0}
	data.start = {"money": F.START_MONEY, "facilities": ["warehouse", "hall", "pad"], "site": F.SITE_ID}
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [0.0, 0.0, 0.0, 0.0]
	data.launchers["l1"]["reliability_base"] = 1.0
	data.contracts = {
		"offer_slots": 2, "initial_offers": 0, "offer_spawn_chance": 0.0,
		"offer_validity_days": 5, "advance_pct": 20, "penalty_pct": 30,
		"max_active_contracts": 1, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": 0,
		"reputation_min": -100, "reputation_max": 100,
		"rep_on_success": 6, "rep_on_launch_failure": -15, "rep_on_deadline_missed": -10,
		"templates": []}
	return data


# --- Supply contracts (criterion 8) -------------------------------------------

func _supply_data() -> GameData:
	var data := F.data()
	data.facilities["warehouse"]["upkeep_per_day"] = 0
	data.facilities["warehouse"]["storage_capacity"] = BIG_WAREHOUSE
	data.suppliers.clear()
	data.suppliers["s1"] = _supplier("s1", [_entry("steel", SUPPLY_UNIT)])
	data.market = {}
	data.supply_contracts = {
		"period_options_days": [SUPPLY_PERIOD], "min_deliveries": 2, "max_deliveries": 6,
		"volume_discount_tiers": [], "fixed_premium_pct": 0, "priority_premium_pct": 0,
		"late_penalty_pct_per_day": 0, "late_penalty_cap_pct": 0,
		"holding_fee_per_unit_per_day": 0, "shortage_fill_pct": 50, "take_or_pay_pct": 70,
		"skip_notice_days": 3, "termination_fee_pct": 40, "max_supply_contracts": 2,
	}
	data.rules = {"bankruptcy_warning_days": 1, "bankruptcy_grace_days": 5}
	return data


func _signed(data: GameData) -> GameState:
	var state := Simulation.new_game(data, 1)
	state.money = 100_000
	var events := Simulation.apply_command(state, Command.sign_supply_contract(
		"s1", "steel", SUPPLY_QTY, SUPPLY_PERIOD, SUPPLY_COUNT, "fixed", false), data)
	assert_eq(events[0]["type"], "supply_contract_signed")
	return state


# Criterion 8a
func test_completed_supply_contract_is_invoiced() -> void:
	var data := _supply_data()
	var invoice := SUPPLY_QTY * SUPPLY_UNIT
	var r := F.run(_signed(data), data, 14)  # resolutions of days 0..13
	assert_eq(r.state.supply_contracts[0]["invoiced_total"], 2 * invoice)
	assert_eq(_metric(r.state, data, "supply_completed_value"), 0, "(not completed yet)")
	r = F.run(r.state, data, 2)  # up to the resolution of day 15
	assert_eq(r.state.supply_contracts[0]["status"], SupplyRules.COMPLETED)
	assert_eq(r.state.supply_contracts[0]["invoiced_total"], SUPPLY_COUNT * invoice)
	assert_eq(_metric(r.state, data, "supply_completed_value"), SUPPLY_COUNT * invoice)


# Criterion 8b
func test_skipped_delivery_is_not_invoiced() -> void:
	var data := _supply_data()
	var r := F.run(_signed(data), data, 2)  # first delivery shipped
	var events := Simulation.apply_command(r.state, Command.skip_supply_delivery(1), data)
	assert_eq(events[0]["type"], "supply_delivery_skipped")
	r = F.run(r.state, data, 15)
	assert_eq(r.state.supply_contracts[0]["status"], SupplyRules.COMPLETED)
	assert_eq(_metric(r.state, data, "supply_completed_value"), (SUPPLY_COUNT - 1) * SUPPLY_QTY * SUPPLY_UNIT)


# Criterion 8c
func test_terminated_supply_contract_counts_for_zero() -> void:
	var data := _supply_data()
	var r := F.run(_signed(data), data, 9)  # two deliveries shipped (days 1 and 8)
	assert_eq(r.state.supply_contracts[0]["invoiced_total"], 2 * SUPPLY_QTY * SUPPLY_UNIT)
	var events := Simulation.apply_command(r.state, Command.terminate_supply_contract(1), data)
	assert_eq(events[0]["type"], "supply_contract_terminated")
	assert_eq(r.state.supply_contracts[0]["status"], SupplyRules.TERMINATED)
	assert_eq(_metric(r.state, data, "supply_completed_value"), 0)


# Criterion 18 (counters part)
func test_save_round_trip_keeps_stats_and_invoiced_total_as_ints() -> void:
	var data := _prod_data()
	var produced := _produce(data, {"ore": 1, "engine": 1, "tank": 1}, 1, true, 2)
	var supply := _supply_data()
	var state := F.run(_signed(supply), supply, 3).state
	state.stats = produced.stats
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(back.stats, produced.stats)
	assert_eq(typeof(back.stats["kit_consumed"]["engine"]), TYPE_INT)
	assert_eq(typeof(back.stats["components_made"]["engine"]), TYPE_INT)
	assert_eq(back.supply_contracts[0]["invoiced_total"], SUPPLY_QTY * SUPPLY_UNIT)
	assert_eq(typeof(back.supply_contracts[0]["invoiced_total"]), TYPE_INT)


func test_old_save_without_the_fields_loads_with_defaults() -> void:
	var supply := _supply_data()
	var d := F.run(_signed(supply), supply, 3).state.to_dict()
	d.erase("stats")
	for contract in d["supply_contracts"]:
		contract.erase("invoiced_total")
	var back := GameState.from_dict(d)
	assert_eq(back.stats, {"kit_consumed": {}, "components_made": {}})
	assert_eq(back.supply_contracts[0]["invoiced_total"], 0)

extends TestCase

const F := preload("res://tests/sim/fixtures.gd")

const PAYMENT := 100_000
const ADVANCE := 20_000
const PENALTY := 30_000
const BALANCE := 80_000
const DEADLINE := 20
const REP_START := 50
const REP_MIN := 0
const REP_MAX := 100
const REP_SUCCESS := 6
const REP_LAUNCH_FAIL := -15
const REP_DEADLINE := -10
const HEAVY_KG := 2_500
const OFFER_VALIDITY := 5


func _data() -> GameData:
	var data := F.data()
	data.orbits["far"] = {"id": "far", "azimuth_deg": F.SSO_AZ}
	data.contracts = {
		"offer_slots": 2, "initial_offers": 1, "offer_spawn_chance": 0.0,
		"offer_validity_days": OFFER_VALIDITY, "advance_pct": 20, "penalty_pct": 30,
		"max_active_contracts": 1, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": REP_START,
		"reputation_min": REP_MIN, "reputation_max": REP_MAX,
		"rep_on_success": REP_SUCCESS, "rep_on_launch_failure": REP_LAUNCH_FAIL,
		"rep_on_deadline_missed": REP_DEADLINE,
		"templates": [{"id": "t_leo", "orbit": "leo", "mass_min_kg": 1_000, "mass_max_kg": 1_000,
			"base_payment": PAYMENT, "per_kg_payment": 0, "deadline_min_days": DEADLINE,
			"deadline_max_days": DEADLINE, "weight": 1, "min_reputation": 0, "clients": ["c"]}]}
	return data


func _inject(state: GameState, orbit: String, kg: int) -> int:
	var id := state.next_contract_id
	state.next_contract_id += 1
	state.contracts.append({"id": id, "template_id": "x", "client": "c", "orbit": orbit,
		"payload_kg": kg, "payment": PAYMENT, "advance": ADVANCE, "penalty": PENALTY,
		"deadline_day": DEADLINE, "status": ContractRules.OFFER, "offer_expires_day": OFFER_VALIDITY})
	return id


func _accept(state: GameState, data: GameData, id: int) -> Array:
	return Simulation.apply_command(state, Command.accept_contract(id), data)


func _reason(events: Array) -> String:
	return events[0]["reason"] if events[0]["type"] == "command_rejected" else ""


func _signed(data: GameData) -> GameState:
	var state := Simulation.new_game(data, 1)
	_accept(state, data, 1)
	return state


func test_accept_credits_advance() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var events := _accept(state, data, 1)
	assert_eq(state.money, F.START_MONEY + ADVANCE)
	assert_eq(state.contracts[0]["status"], ContractRules.ACTIVE)
	assert_eq(events[0]["type"], "contract_accepted")
	assert_eq(events[0]["advance"], ADVANCE)


func test_accept_unknown_or_expired_rejected() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	assert_eq(_reason(_accept(state, data, 99)), "not_an_offer")
	state.contracts[0]["status"] = ContractRules.EXPIRED
	assert_eq(_reason(_accept(state, data, 1)), "not_an_offer")
	assert_eq(state.money, F.START_MONEY)


func test_accept_twice_rejected() -> void:
	var data := _data()
	var state := _signed(data)
	assert_eq(_reason(_accept(state, data, 1)), "not_an_offer")


func test_too_many_contracts() -> void:
	var data := _data()
	var state := _signed(data)
	var money := state.money
	var other := _inject(state, "leo", 1_000)
	assert_eq(_reason(_accept(state, data, other)), "too_many_contracts")
	assert_eq(state.money, money)
	assert_eq(state.contracts[1]["status"], ContractRules.OFFER)


func test_payload_too_heavy() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var id := _inject(state, "leo", HEAVY_KG)
	assert_eq(_reason(_accept(state, data, id)), "payload_too_heavy")
	assert_eq(state.money, F.START_MONEY)


func test_site_bonus_raises_capacity() -> void:
	var data := _data()
	data.sites[F.SITE_ID] = F.site({"leo": 50})  # 2000 * 150 / 100 = 3000
	var state := Simulation.new_game(data, 1)
	var id := _inject(state, "leo", HEAVY_KG)
	assert_eq(_accept(state, data, id)[0]["type"], "contract_accepted")


func test_orbit_unreachable() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var id := _inject(state, "far", 100)
	assert_eq(_reason(_accept(state, data, id)), "orbit_unreachable")
	assert_eq(_reason(_accept(state, data, _inject(state, "nowhere", 100))), "orbit_unreachable")


func test_deadline_missed() -> void:
	var data := _data()
	var state := _signed(data)
	var after_20 := F.run(state, data, DEADLINE).state
	assert_eq(after_20.contracts[0]["status"], ContractRules.ACTIVE)
	var result := F.run(after_20, data, 1)
	assert_eq(result.state.contracts[0]["status"], ContractRules.FAILED)
	assert_eq(result.state.reputation, REP_START + REP_DEADLINE)
	assert_eq(result.state.money,
		F.START_MONEY + ADVANCE - ADVANCE - PENALTY - F.UPKEEP * (DEADLINE + 1))
	var failed := result.events.filter(func(e): return e["type"] == "contract_failed")
	assert_eq(failed.size(), 1)
	assert_eq(failed[0]["reason"], ContractRules.DEADLINE_MISSED)
	assert_eq(failed[0]["amount_debited"], ADVANCE + PENALTY)
	# Failed once: no second penalty afterwards.
	var later := F.run(result.state, data, 3).state
	assert_eq(later.reputation, REP_START + REP_DEADLINE)


func test_unsigned_offer_never_fails_by_deadline() -> void:
	var data := _data()
	data.contracts["offer_validity_days"] = 1000
	var state := F.run(Simulation.new_game(data, 1), data, DEADLINE + 5).state
	assert_eq(state.contracts[0]["status"], ContractRules.OFFER)
	assert_eq(state.reputation, REP_START)


func test_reputation_floor() -> void:
	var data := _data()
	var state := _signed(data)
	state.reputation = 5
	var after := F.run(state, data, DEADLINE + 1).state
	assert_eq(after.reputation, REP_MIN)


func test_reputation_ceiling() -> void:
	var data := _data()
	var state := _signed(data)
	state.reputation = REP_MAX - 2
	var events := Simulation.complete_contract(state, data, 1)
	assert_eq(state.reputation, REP_MAX)
	assert_eq(events[1]["type"], "reputation_changed")
	assert_eq(events[1]["delta"], 2)
	assert_eq(events[1]["reputation"], REP_MAX)


func test_complete_contract() -> void:
	var data := _data()
	var state := _signed(data)
	var money := state.money
	var events := Simulation.complete_contract(state, data, 1)
	assert_eq(state.money, money + BALANCE)
	assert_eq(state.contracts[0]["status"], ContractRules.COMPLETED)
	assert_eq(state.reputation, REP_START + REP_SUCCESS)
	assert_eq(events[0]["type"], "contract_completed")
	assert_eq(events[0]["balance_paid"], BALANCE)
	assert_eq(events[1]["delta"], REP_SUCCESS)


func test_completed_contract_not_failed_by_deadline() -> void:
	var data := _data()
	var state := _signed(data)
	Simulation.complete_contract(state, data, 1)
	var after := F.run(state, data, DEADLINE + 2).state
	assert_eq(after.contracts[0]["status"], ContractRules.COMPLETED)
	assert_eq(after.reputation, REP_START + REP_SUCCESS)


func test_complete_requires_active() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)  # still an offer
	assert_eq(Simulation.complete_contract(state, data, 1), [])
	assert_eq(Simulation.complete_contract(state, data, 99), [])
	assert_eq(state.money, F.START_MONEY)


func test_fail_launch_keeps_advance() -> void:
	var data := _data()
	var state := _signed(data)
	var money := state.money
	var events := Simulation.fail_contract(state, data, 1, ContractRules.LAUNCH_FAILED)
	assert_eq(state.money, money)
	assert_eq(state.contracts[0]["status"], ContractRules.FAILED)
	assert_eq(state.reputation, REP_START + REP_LAUNCH_FAIL)
	assert_eq(events[0]["reason"], ContractRules.LAUNCH_FAILED)
	assert_eq(events[0]["amount_debited"], 0)
	assert_eq(Simulation.fail_contract(state, data, 1, ContractRules.LAUNCH_FAILED), [])
	assert_eq(state.reputation, REP_START + REP_LAUNCH_FAIL)


func test_fail_unknown_reason_is_noop() -> void:
	var data := _data()
	var state := _signed(data)
	assert_eq(Simulation.fail_contract(state, data, 1, "bogus"), [])
	assert_eq(state.contracts[0]["status"], ContractRules.ACTIVE)


func test_serialization_roundtrip_through_json() -> void:
	var data := _data()
	var state := _signed(data)
	Simulation.complete_contract(state, data, 1)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(copy.contracts, state.contracts)
	assert_eq(copy.reputation, state.reputation)
	assert_eq(typeof(copy.reputation), TYPE_INT)
	assert_eq(typeof(copy.contracts[0]["advance"]), TYPE_INT)


func test_step_applies_accept_command() -> void:
	var data := _data()
	var result := Simulation.step(Simulation.new_game(data, 1), [Command.accept_contract(1)], data)
	assert_eq(result.state.contracts[0]["status"], ContractRules.ACTIVE)

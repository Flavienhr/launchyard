extends TestCase

const F := preload("res://tests/sim/fixtures.gd")

const LEO_MASS := 1_000
const PAYMENT := 100_000
const DEADLINE := 20
const VALIDITY := 5
const SLOTS := 2
const INITIAL := 1
const REP_START := 50
const GTO_MIN_REP := 60
const GTO_AZ := 100
const HEAVY_WEIGHT := 1_000
const LONG_RUN := 100


func _template(id: String, orbit: String, min_rep: int, weight: int) -> Dictionary:
	return {"id": id, "orbit": orbit, "mass_min_kg": LEO_MASS, "mass_max_kg": LEO_MASS,
		"base_payment": PAYMENT, "per_kg_payment": 0, "deadline_min_days": DEADLINE,
		"deadline_max_days": DEADLINE, "weight": weight, "min_reputation": min_rep,
		"clients": ["c1", "c2"]}


func _data(spawn := 0.0, gto_weight := 1, delay_chance := 0.0) -> GameData:
	var data := F.data(delay_chance)
	data.orbits["gto"] = {"id": "gto", "azimuth_deg": GTO_AZ}
	data.orbits["sso_far"] = {"id": "sso_far", "azimuth_deg": F.SSO_AZ}
	data.contracts = {
		"offer_slots": SLOTS, "initial_offers": INITIAL, "offer_spawn_chance": spawn,
		"offer_validity_days": VALIDITY, "advance_pct": 20, "penalty_pct": 30,
		"max_active_contracts": 1, "payment_rounding": 1_000, "mass_step_kg": 50,
		"generate_unreachable": false, "reputation_start": REP_START,
		"templates": [
			_template("t_leo", "leo", 0, 1),
			_template("t_gto", "gto", GTO_MIN_REP, gto_weight),
			_template("t_far", "sso_far", 0, HEAVY_WEIGHT),
		]}
	return data


func _offers(state: GameState) -> Array:
	return state.contracts.filter(func(c): return c["status"] == ContractRules.OFFER)


func test_initial_offers() -> void:
	var state := Simulation.new_game(_data(), 1)
	assert_eq(state.contracts.size(), INITIAL)
	var c: Dictionary = state.contracts[0]
	assert_eq(c["template_id"], "t_leo")
	assert_eq(c["payment"], PAYMENT)
	assert_eq(c["deadline_day"], DEADLINE)
	assert_eq(c["offer_expires_day"], VALIDITY)
	assert_eq(state.reputation, REP_START)
	assert_eq(state.next_contract_id, INITIAL + 1)


func test_determinism() -> void:
	var data := _data(0.5)
	var a := F.run(Simulation.new_game(data, 7), data, 60).state
	var b := F.run(Simulation.new_game(data, 7), data, 60).state
	var c := F.run(Simulation.new_game(data, 8), data, 60).state
	assert_eq(a.contracts, b.contracts)
	assert_true(a.contracts != c.contracts, "different seeds must differ")


func test_forced_generation_fills_slots() -> void:
	var data := _data(1.0)
	var result := F.run(Simulation.new_game(data, 1), data, 1)
	assert_eq(_offers(result.state).size(), SLOTS)
	assert_true(F.types(result.events).has("offer_generated"))
	result = F.run(result.state, data, 1)
	assert_eq(_offers(result.state).size(), SLOTS)
	assert_true(not F.types(result.events).has("offer_generated"))


func test_offer_expires() -> void:
	var data := _data(0.0)
	var result := F.run(Simulation.new_game(data, 1), data, VALIDITY)
	assert_eq(result.state.contracts[0]["status"], ContractRules.EXPIRED)
	assert_true(F.types(result.events).has("offer_expired"))
	assert_eq(_offers(result.state).size(), 0)
	var before := F.run(Simulation.new_game(data, 1), data, VALIDITY - 1)
	assert_eq(_offers(before.state).size(), INITIAL)


func _templates_seen(state: GameState, data: GameData, days: int) -> Dictionary:
	var seen := {}
	var current := state
	for i in days:
		current = Simulation.step(current, [], data).state
		for c in current.contracts:
			seen[c["template_id"]] = true
	return seen


func test_reputation_unlocks_template() -> void:
	var data := _data(1.0, HEAVY_WEIGHT)
	var state := Simulation.new_game(data, 3)
	state.reputation = GTO_MIN_REP
	assert_true(_templates_seen(state, data, LONG_RUN).has("t_gto"))
	state = Simulation.new_game(data, 3)
	state.reputation = GTO_MIN_REP - 1
	assert_true(not _templates_seen(state, data, LONG_RUN).has("t_gto"))


func test_no_unreachable_orbit_offers() -> void:
	var data := _data(1.0, HEAVY_WEIGHT)
	var state := Simulation.new_game(data, 4)
	state.reputation = GTO_MIN_REP
	var seen := _templates_seen(state, data, LONG_RUN)
	assert_true(not seen.has("t_far"), "sso_far is outside the site azimuth range")
	assert_true(seen.has("t_leo") or seen.has("t_gto"))


func test_offers_do_not_shift_delivery_draws() -> void:
	var order := Command.new(Command.ORDER, {"supplier_id": "acme", "component_id": "steel", "quantity": 1})
	var commands := {}
	for d in LONG_RUN:
		commands[d] = [order]
	var quiet := _data(0.0, 1, 0.5)
	var busy := _data(1.0, 1, 0.5)
	var a := F.run(Simulation.new_game(quiet, 9), quiet, LONG_RUN, commands)
	var b := F.run(Simulation.new_game(busy, 9), busy, LONG_RUN, commands)
	var keep := func(e): return e["type"] in ["delivery_delayed", "delivery_received"]
	assert_eq(a.events.filter(keep), b.events.filter(keep))


func test_state_roundtrip_recasts_ints() -> void:
	var data := _data(1.0)
	var state := F.run(Simulation.new_game(data, 1), data, 2).state
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(copy.contracts, state.contracts)
	assert_eq(copy.reputation, state.reputation)

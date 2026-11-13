class_name ContractRules
extends RefCounted
## Pure contract offer generation (spec 002 R1, R2). No state, no IO.
## Every random draw comes from the rng passed in (SimRng.CONTRACTS stream).

const OFFER := "offer"
const ACTIVE := "active"
const COMPLETED := "completed"
const FAILED := "failed"
const EXPIRED := "expired"

# Failure reasons (spec 002 R4).
const LAUNCH_FAILED := "launch_failed"
const DEADLINE_MISSED := "deadline_missed"


## Templates a player with `reputation` may be offered from `site`.
static func eligible_templates(data: GameData, reputation: int, site: Dictionary) -> Array:
	var out: Array = []
	for template in data.contracts["templates"]:
		if int(template["min_reputation"]) > reputation:
			continue
		if not bool(data.contracts["generate_unreachable"]):
			var orbit: Dictionary = data.orbits.get(template["orbit"], {})
			if orbit.is_empty() or not LaunchRules.is_orbit_reachable(orbit, site):
				continue
		out.append(template)
	return out


## round(value / step) * step, integers only (halves round up).
static func round_to(value: int, step: int) -> int:
	return (value + step / 2) / step * step


## Draws one offer. `day` is the first day the offer is visible. The id is
## left to the caller. Returns {} when no template is eligible.
## Draw order: template, client, payload, deadline.
static func generate_offer(rng: RandomNumberGenerator, data: GameData,
		reputation: int, site: Dictionary, day: int) -> Dictionary:
	var pool := eligible_templates(data, reputation, site)
	if pool.is_empty():
		return {}
	var total := 0
	for template in pool:
		total += int(template["weight"])
	var roll := rng.randi_range(0, total - 1)
	var chosen: Dictionary = pool[-1]
	for template in pool:
		roll -= int(template["weight"])
		if roll < 0:
			chosen = template
			break
	var clients: Array = chosen["clients"]
	var client: String = clients[rng.randi_range(0, clients.size() - 1)]
	var raw_mass := rng.randi_range(int(chosen["mass_min_kg"]), int(chosen["mass_max_kg"]))
	var payload := round_to(raw_mass, int(data.contracts["mass_step_kg"]))
	var delay := rng.randi_range(int(chosen["deadline_min_days"]), int(chosen["deadline_max_days"]))
	var payment := round_to(
		int(chosen["base_payment"]) + int(chosen["per_kg_payment"]) * payload,
		int(data.contracts["payment_rounding"]))
	return {
		"id": 0,
		"template_id": chosen["id"],
		"client": client,
		"orbit": chosen["orbit"],
		"payload_kg": payload,
		"payment": payment,
		"advance": payment * int(data.contracts["advance_pct"]) / 100,
		"penalty": payment * int(data.contracts["penalty_pct"]) / 100,
		"deadline_day": day + delay,
		"status": OFFER,
		"offer_expires_day": day + int(data.contracts["offer_validity_days"]),
	}


static func visible_offers(state: GameState) -> int:
	var count := 0
	for contract in state.contracts:
		if contract["status"] == OFFER:
			count += 1
	return count


static func active_count(state: GameState) -> int:
	var count := 0
	for contract in state.contracts:
		if contract["status"] == ACTIVE:
			count += 1
	return count


static func find(state: GameState, contract_id: int) -> Dictionary:
	for contract in state.contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


## Largest payload any launcher model can lift to `orbit_id` from `site`.
static func best_capacity(data: GameData, orbit_id: String, site: Dictionary) -> int:
	var best := 0
	for model_id in data.launchers:
		best = maxi(best, LaunchRules.payload_capacity(data.launchers[model_id], orbit_id, site))
	return best


## `value` clamped to [reputation_min, reputation_max] (spec 002 R5).
static func clamp_reputation(data: GameData, value: int) -> int:
	return clampi(value, int(data.contracts["reputation_min"]), int(data.contracts["reputation_max"]))


## Why an offer cannot be signed right now ("" = it can). Spec 002 R3, checks in
## spec order. Single source of truth for the sim (accept_contract) and the UI.
static func acceptance_error(state: GameState, data: GameData, contract: Dictionary) -> String:
	if contract.is_empty() or contract["status"] != OFFER:
		return "not_an_offer"
	if active_count(state) >= int(data.contracts["max_active_contracts"]):
		return "too_many_contracts"
	var site := data.active_site()
	var orbit: Dictionary = data.orbits.get(contract["orbit"], {})
	if orbit.is_empty() or not LaunchRules.is_orbit_reachable(orbit, site):
		return "orbit_unreachable"
	if int(contract["payload_kg"]) > best_capacity(data, contract["orbit"], site):
		return "payload_too_heavy"
	return ""

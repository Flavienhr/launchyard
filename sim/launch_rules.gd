class_name LaunchRules
extends RefCounted
## Pure static queries on orbits, sites and launcher models (spec 003 R1).
## No state, no IO: everything comes from GameData dictionaries.


## An orbit is reachable if its azimuth falls in at least one closed range of the site.
static func is_orbit_reachable(orbit: Dictionary, site: Dictionary) -> bool:
	var azimuth: float = orbit["azimuth_deg"]
	for bounds in site["azimuth_ranges"]:
		if azimuth >= bounds[0] and azimuth <= bounds[1]:
			return true
	return false


## floor(payload_kg[orbit] * (100 + bonus_pct) / 100), missing bonus = 0.
## Integer arithmetic only. Returns 0 when the model cannot fly to that orbit.
static func payload_capacity(model: Dictionary, orbit_id: String, site: Dictionary) -> int:
	var base: int = model["payload_kg"].get(orbit_id, 0)
	var bonus_pct: int = site["payload_bonus_pct"].get(orbit_id, 0)
	return base * (100 + bonus_pct) / 100


## Season index (into season_names / scrub_chance_by_season) for a given day.
static func season_of(day: int, site: Dictionary) -> int:
	var elapsed: int = day + site["start_day_offset"]
	return (elapsed / site["season_length_days"]) % site["season_names"].size()


## base + gain * successes, capped at reliability_max.
static func model_reliability(model: Dictionary, successes: int) -> float:
	var value: float = model["reliability_base"] + model["reliability_gain_per_success"] * successes
	return minf(value, model["reliability_max"])


## Spec 003 decision 1: premium of a launch insured on `contract`, rounded down.
static func insurance_premium(contract: Dictionary, data: GameData) -> int:
	return int(contract["payment"]) * int(data.contracts["insurance_premium_pct"]) / 100


## Spec 003 decision 1: refund on failure = payout_pct of the purchase cost of one kit.
static func insurance_payout(model: Dictionary, data: GameData) -> int:
	return kit_purchase_cost(model, data) * int(data.contracts["insurance_payout_pct"]) / 100


## Cost of one kit: for each recipe input, quantity * cheapest unit price among suppliers.
## A component no supplier offers adds 0 (see open points in the report).
static func kit_purchase_cost(model: Dictionary, data: GameData) -> int:
	var recipe: Dictionary = data.recipes[model["recipe_id"]]
	var total := 0
	for component_id in recipe["inputs"]:
		total += int(recipe["inputs"][component_id]) * _cheapest_unit_price(component_id, data)
	return total


static func _cheapest_unit_price(component_id: String, data: GameData) -> int:
	var best := -1
	for supplier_id in data.suppliers:
		var entry := data.catalog_entry(supplier_id, component_id)
		if not entry.is_empty() and (best < 0 or int(entry["unit_price"]) < best):
			best = int(entry["unit_price"])
	return maxi(best, 0)

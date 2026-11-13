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

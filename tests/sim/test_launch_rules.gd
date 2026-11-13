extends TestCase

const F := preload("res://tests/sim/fixtures.gd")


func test_reachability() -> void:
	var data := F.data()
	var site := F.site()
	assert_true(LaunchRules.is_orbit_reachable(data.orbits["leo"], site))
	assert_true(not LaunchRules.is_orbit_reachable(data.orbits["sso"], site))


func test_reachability_bounds_are_closed() -> void:
	var site := F.site()
	assert_true(LaunchRules.is_orbit_reachable({"azimuth_deg": F.AZ_MIN}, site))
	assert_true(LaunchRules.is_orbit_reachable({"azimuth_deg": F.AZ_MAX}, site))
	assert_true(not LaunchRules.is_orbit_reachable({"azimuth_deg": F.AZ_MAX + 1}, site))


func test_capacity_with_and_without_bonus() -> void:
	var model: Dictionary = F.data().launchers["l1"]
	assert_eq(LaunchRules.payload_capacity(model, "leo", F.site()), F.LEO_KG)
	assert_eq(LaunchRules.payload_capacity(model, "leo", F.site({"leo": 10})), F.LEO_KG * 110 / 100)
	assert_eq(LaunchRules.payload_capacity(model, "sso", F.site()), 0)


func test_capacity_floors() -> void:
	var model := {"payload_kg": {"leo": 1001}}
	assert_eq(LaunchRules.payload_capacity(model, "leo", F.site({"leo": 10})), 1101)


func test_season_of() -> void:
	var site := F.site()
	var n: int = F.SEASON_DAYS
	assert_eq(LaunchRules.season_of(0, site), 0)
	assert_eq(LaunchRules.season_of(n - 1, site), 0)
	assert_eq(LaunchRules.season_of(n, site), 1)
	assert_eq(LaunchRules.season_of(n * 4, site), 0)  # wraps after the last season
	site["start_day_offset"] = n
	assert_eq(LaunchRules.season_of(0, site), 1)


func test_reliability_grows_then_caps() -> void:
	var model := {"reliability_base": 0.5, "reliability_gain_per_success": 0.1, "reliability_max": 0.8}
	assert_true(is_equal_approx(LaunchRules.model_reliability(model, 0), 0.5))
	assert_true(is_equal_approx(LaunchRules.model_reliability(model, 2), 0.7))
	assert_true(is_equal_approx(LaunchRules.model_reliability(model, 50), 0.8))


func test_game_data_exposes_orbits_sites_launchers() -> void:
	var data := F.data()
	assert_true(data.orbits.has("leo") and data.launchers.has("l1"))
	assert_eq(data.active_site()["id"], F.SITE_ID)

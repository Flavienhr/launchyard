extends TestCase
## Spec 009 R1, criteria 1 (loading part), 2 and 20 (validator: tools/validate_data.py,
## checked by deliberate errors, see the issue). Data built here.

const F := preload("res://tests/sim/fixtures.gd")
const LEVEL_ID := "t_level"
const OTHER_ID := "t_level_2"
const LEVEL_MONEY := 10_000
const OTHER_MONEY := 77_000
const TECHS := 2
const HALL_ASSIGNED := 2
const DURATION := 20
const WARNING_DAY := 5
const OTHER_SITE := "other_site"
const FREE_PLAY_DAYS := 30
const SEED := 3


func _objective(id: String, metric: String, op: String, target: int) -> Dictionary:
	return {"id": id, "metric": metric, "op": op, "target": target}


func _level(id: String, order: int, money: int, site: String, requires: Variant, min_stars: int) -> Dictionary:
	return {"id": id, "name": id, "briefing": "", "site": site, "order": order,
		"unlock": {"requires_level": requires, "min_stars": min_stars},
		"duration_days": DURATION, "time_warnings_days": [WARNING_DAY],
		"start": {"money": money, "technicians": TECHS,
			"facilities": [{"facility_type": "warehouse", "x": 1, "y": 2, "rotation": 0},
				{"facility_type": "hall", "x": 5, "y": 6, "rotation": 1}],
			"assignments": {"hall": HALL_ASSIGNED}},
		"stars": [
			{"name": "1", "objectives": [_objective("a", "contracts_completed", "gte", 1)]},
			{"name": "2", "objectives": [_objective("b", "net_cash", "gte", 50_000)],
				"any_of": {"min_met": 1, "objectives": [_objective("c", "in_house_share_pct", "gte", 40)]}},
			{"name": "3", "objectives": [_objective("d", "site_violations", "lte", 0)]}]}


## Same tables as the phase 2 fixtures, but fed through from_files with a levels file.
func _files(levels: Array, default_level: String) -> Dictionary:
	var base := F.data()
	var files := {
		"components": {"components": base.components.values()},
		"suppliers": {"suppliers": base.suppliers.values()},
		"facilities": {"facilities": base.facilities.values()},
		"recipes": {"recipes": base.recipes.values()},
		"orbits": {"orbits": base.orbits.values()},
		"sites": {"sites": base.sites.values() + [_other_site()]},
		"launchers": {"launchers": base.launchers.values()},
		"staff": base.staff,
		"levels": {"default_level": default_level, "levels": levels},
	}
	return files


func _two_levels() -> Array:
	return [_level(OTHER_ID, 2, OTHER_MONEY, OTHER_SITE, LEVEL_ID, 2),
		_level(LEVEL_ID, 1, LEVEL_MONEY, F.SITE_ID, null, 0)]


func _other_site() -> Dictionary:
	var site := F.site()
	site["id"] = OTHER_SITE
	return site


func test_level_loaded_and_new_game() -> void:
	var data := GameData.from_files(_files(_two_levels(), LEVEL_ID))
	assert_eq(data.level["id"], LEVEL_ID)
	assert_eq(data.active_site_id, F.SITE_ID)
	assert_eq(data.active_site()["id"], F.SITE_ID)
	assert_eq(data.start["site"], F.SITE_ID, "start view keeps the old format")
	var state := Simulation.new_game(data, SEED)
	assert_eq(state.money, LEVEL_MONEY)
	assert_eq(state.technicians_hired, TECHS)
	assert_eq(state.facilities.size(), 2)
	assert_eq(state.facilities[0]["id"], 1)
	assert_eq(state.facilities[0]["type"], "warehouse")
	assert_eq(state.facilities[1]["id"], 2)
	assert_eq(state.facilities[1]["type"], "hall")
	assert_eq(state.facilities[1]["status"], "ready")
	assert_eq(state.facilities[1]["assigned"], HALL_ASSIGNED)


func test_selection_is_explicit_not_file_order() -> void:
	# The file lists the second level first: default_level still wins.
	var data := GameData.from_files(_files(_two_levels(), LEVEL_ID))
	assert_eq(data.level["id"], LEVEL_ID)
	assert_eq(data.default_level_id, LEVEL_ID)
	assert_true(data.select_level(OTHER_ID))
	assert_eq(data.level["id"], OTHER_ID)
	assert_eq(data.active_site_id, OTHER_SITE)
	assert_eq(int(data.start["money"]), OTHER_MONEY)
	assert_true(not data.select_level("nope"), "unknown id rejected")
	assert_eq(data.level["id"], OTHER_ID, "selection unchanged after a rejection")


func test_level_list_sorted_and_unlocked_by_profile() -> void:
	var data := GameData.from_files(_files(_two_levels(), LEVEL_ID))
	var list := data.level_list()
	assert_eq(list.size(), 2)
	assert_eq(list[0]["id"], LEVEL_ID)
	assert_eq(list[1]["id"], OTHER_ID)
	assert_true(list[0]["unlocked"])
	assert_true(not list[1]["unlocked"])
	assert_true(not data.level_list({LEVEL_ID: 1})[1]["unlocked"])
	assert_true(data.level_list({LEVEL_ID: 2})[1]["unlocked"])
	assert_eq(data.level_list({LEVEL_ID: 3})[0]["stars"], 3)


func test_no_levels_keeps_inline_start() -> void:
	var data := F.data()
	assert_eq(data.level, {})
	assert_eq(data.levels.size(), 0)
	assert_eq(data.active_site_id, F.SITE_ID)
	assert_eq(int(data.start["money"]), F.START_MONEY)
	var state := Simulation.new_game(data, SEED)
	assert_eq(state.money, F.START_MONEY)
	var result := F.run(state, data, FREE_PLAY_DAYS)
	for event in result.events:
		assert_true(not ["star_earned", "level_time_warning", "level_ended"].has(event["type"]),
			"no level event without a level")

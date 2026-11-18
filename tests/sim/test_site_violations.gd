extends TestCase
## Spec 009 R4b, criterion 10: metric site_violations. Spatial facts come from
## spec 008 (R5 zone, R6 service). Data built inline; no data/ file.

const F := preload("res://tests/sim/fixtures.gd")

const SERVICE_RADIUS := 1
const SAFETY := 2
const MAP_WIDTH := 20
const MAP_HEIGHT := 10
const START_MONEY := 0


func _entry(type: String, x: int, y: int, rotation := 0) -> Dictionary:
	return {"facility_type": type, "x": x, "y": y, "rotation": rotation}


## Site t_site: a pad (2x2, zone radius 2), a warehouse (2x2) and a shop (3x1, 2 slots).
func _data(start: Array, with_map := true) -> GameData:
	var data := F.data()
	if with_map:
		data.sites[F.SITE_ID]["map"] = {"width": MAP_WIDTH, "height": MAP_HEIGHT, "terrain": [],
			"lots": [{"id": "A", "x": 0, "y": 0, "w": MAP_WIDTH, "h": MAP_HEIGHT, "price": 0}]}
		data.layout = {"service_radius_cells": SERVICE_RADIUS, "unserved_productivity_pct": 50,
			"rollout_base_days": 1, "rollout_cells_per_day": 3, "rollout_cost_per_cell": 10,
			"damage_repair_days": 5, "damage_repair_cost_pct": 25, "move_cost_pct": 25,
			"move_days_pct": 50, "demolish_refund_pct": 20}
	var fac: Dictionary = data.facilities
	fac["warehouse"].merge({"footprint": [2, 2], "upkeep_per_day": 0, "build_cost": 100}, true)
	fac["shop"].merge({"footprint": [3, 1], "slots": 2, "upkeep_per_day": 0, "build_cost": 1_000,
		"max_count": 5}, true)
	fac["pad"] = {"id": "pad", "name": "Pad", "upkeep_per_day": 0, "footprint": [2, 2],
		"safety_radius_cells": SAFETY, "buildable": true, "build_cost": 4_000, "build_days": 4,
		"max_count": 3, "rollout_days": 2, "scrub_recycle_days": 5, "scrub_cost": 0, "refurb_days": 1,
		"refurb_cost": 0, "refurb_days_after_failure": 6, "refurb_cost_after_failure": 300}
	data.sites[F.SITE_ID]["scrub_chance_by_season"] = [0.0, 0.0, 0.0, 0.0]
	data.start = {"money": START_MONEY, "facilities": start, "site": F.SITE_ID, "owned_lots": ["A"]}
	return data


## Criterion 10 layout: pad at (6, 0), warehouse at (0, 0).
func _base(extra: Array) -> Array:
	var start := [_entry("pad", 6, 0), _entry("warehouse", 0, 0)]
	start.append_array(extra)
	return start


func _metric(state: GameState, data: GameData) -> int:
	return ObjectiveRules.metric_value(state, data, "site_violations")


func _shop(state: GameState, nth := 0) -> Dictionary:
	var seen := 0
	for facility in state.facilities:
		if facility["type"] == "shop":
			if seen == nth:
				return facility
			seen += 1
	return {}


## Criterion 10: shop ready at (2, 0) -> 1 (in zone, served).
func test_criterion_10_ready_in_zone_counts_one() -> void:
	var data := _data(_base([_entry("shop", 2, 0)]))
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 1)


## Criterion 10: shop ready at (0, 3) -> 0 (outside zone, served).
func test_criterion_10_ready_safe_and_served_counts_zero() -> void:
	var data := _data(_base([_entry("shop", 0, 3)]))
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 0)


## Criterion 10: shop ready at (0, 5) -> 1 (outside zone, not served).
func test_criterion_10_ready_unserved_counts_one() -> void:
	var data := _data(_base([_entry("shop", 0, 5)]))
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 1)


## Criterion 10: shop under construction at (0, 5) -> 0 (unserved only counts when ready).
func test_criterion_10_building_unserved_counts_zero() -> void:
	var data := _data(_base([_entry("shop", 0, 5)]))
	var state := Simulation.new_game(data, 1)
	_shop(state)["status"] = "building"
	assert_eq(_metric(state, data), 0)


## Criterion 10: shop under construction at (2, 0) -> 1 (in zone counts while building).
func test_criterion_10_building_in_zone_counts_one() -> void:
	var data := _data(_base([_entry("shop", 2, 0)]))
	var state := Simulation.new_game(data, 1)
	_shop(state)["status"] = "building"
	assert_eq(_metric(state, data), 1)


## Criterion 10: no map -> 0.
func test_criterion_10_no_map_counts_zero() -> void:
	var data := _data(_base([_entry("shop", 2, 0)]), false)
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 0)


## No violation: warehouse and pad alone. A pad is never counted, and a
## warehouse has no slots, so it never needs service.
func test_no_violation_pad_and_warehouse_count_zero() -> void:
	var data := _data(_base([]))
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 0)


## R4b: a ready shop both in a pad zone and unserved counts twice.
## Shop at (8, 2): gap 0 to the pad (6,0)-(7,1), so in zone; gap 6 to the
## warehouse (0,0)-(1,1) > service radius 1, so unserved. Total 2.
func test_in_zone_and_unserved_counts_twice() -> void:
	var data := _data(_base([_entry("shop", 8, 2)]))
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 2)


## Several violations add up: two unserved shops, one of them also in zone.
func test_violations_add_up_across_instances() -> void:
	var data := _data(_base([_entry("shop", 0, 5), _entry("shop", 8, 2)]))
	var state := Simulation.new_game(data, 1)
	assert_eq(_metric(state, data), 3)


## A damaged warehouse no longer serves (spec 008 R6): the shop at (0, 3),
## served by it until then, becomes unserved -> 1.
func test_damaged_warehouse_leaves_shop_unserved() -> void:
	var data := _data(_base([_entry("shop", 0, 3)]))
	var state := Simulation.new_game(data, 1)
	var warehouse := {}
	for facility in state.facilities:
		if facility["type"] == "warehouse":
			warehouse = facility
	assert_eq(_metric(state, data), 0)
	warehouse["damaged_until_day"] = state.day + 1
	assert_eq(_metric(state, data), 1)

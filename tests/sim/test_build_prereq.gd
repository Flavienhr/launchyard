extends TestCase
## Spec 006 R3 : requires_facilities. Données inline (fixtures.gd + types ajoutés ici),
## entretiens à 0 pour que l'argent ne dépende que des constructions.

const F := preload("res://tests/sim/fixtures.gd")
const MILL_COST := 1_000
const FORGE_COST := 2_000
const BUILD_DAYS := 2


func _data() -> GameData:
	var data := F.data()
	data.facilities["warehouse"]["upkeep_per_day"] = 0
	data.facilities["shop"]["upkeep_per_day"] = 0
	data.facilities["mill"] = {"id": "mill", "name": "Mill", "upkeep_per_day": 0, "slots": 2,
		"productivity_per_slot": 10, "buildable": true, "build_cost": MILL_COST,
		"build_days": BUILD_DAYS, "max_count": 1}
	data.facilities["forge"] = {"id": "forge", "name": "Forge", "upkeep_per_day": 0, "slots": 2,
		"productivity_per_slot": 10, "buildable": true, "build_cost": FORGE_COST,
		"build_days": BUILD_DAYS, "max_count": 1, "requires_facilities": ["mill"]}
	return data


func _rejections(events: Array) -> Array:
	return events.filter(func(e): return e["type"] == "command_rejected")


func _status_of(state: GameState, type: String) -> String:
	for f in state.facilities:
		if f["type"] == type:
			return f["status"]
	return ""


## Critère 1 : prérequis absent -> rejet, argent inchangé.
func test_missing_prerequisite_rejects_build() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var events := Simulation.apply_command(state, Command.build("forge"), data)
	assert_eq(F.types(events), ["command_rejected"])
	assert_eq(events[0]["reason"], "missing_prerequisite")
	assert_eq(events[0]["missing"], ["mill"])
	assert_eq(state.money, F.START_MONEY)
	assert_eq(state.facilities.size(), 1)


## Critère 2 : une instance en construction ne compte pas ; une fois prête, elle compte.
func test_building_prerequisite_does_not_count() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	var cmds := {0: [Command.build("mill")], 1: [Command.build("forge")], 2: [Command.build("forge")]}
	var result := F.run(state, data, BUILD_DAYS + 1, cmds)
	var rejected := _rejections(result.events)
	assert_eq(rejected.size(), 1, "only the day-1 attempt is rejected")
	assert_eq(rejected[0]["reason"], "missing_prerequisite")
	assert_eq(rejected[0]["missing"], ["mill"])
	assert_eq(_status_of(result.state, "mill"), "ready")
	assert_eq(F.types(result.events).count("facility_build_started"), 2)
	assert_eq(result.state.money, F.START_MONEY - MILL_COST - FORGE_COST)


## Critère 3 : le prérequis est contrôlé avant les fonds.
func test_prerequisite_checked_before_funds() -> void:
	var data := _data()
	var state := Simulation.new_game(data, 1)
	state.money = F.SHOP_COST / 2
	var events := Simulation.apply_command(state, Command.build("forge"), data)
	assert_eq(events[0]["reason"], "missing_prerequisite")

	var ready := F.run(Simulation.new_game(data, 1), data, BUILD_DAYS, {0: [Command.build("mill")]})
	assert_eq(_status_of(ready.state, "mill"), "ready")
	ready.state.money = F.SHOP_COST / 2
	var poor := Simulation.apply_command(ready.state, Command.build("forge"), data)
	assert_eq(poor[0]["reason"], "insufficient_funds")


## Plusieurs prérequis : chacun doit être prêt, les manquants sont listés.
func test_every_required_type_must_be_ready() -> void:
	var data := _data()
	data.facilities["forge"]["requires_facilities"] = ["mill", "shop"]
	var result := F.run(Simulation.new_game(data, 1), data, BUILD_DAYS, {0: [Command.build("mill")]})
	var events := Simulation.apply_command(result.state, Command.build("forge"), data)
	assert_eq(events[0]["reason"], "missing_prerequisite")
	assert_eq(events[0]["missing"], ["shop"])

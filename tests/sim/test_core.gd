extends TestCase

const F := preload("res://tests/sim/fixtures.gd")


func test_upkeep_charged_every_day() -> void:
	var data := F.data()
	var result := F.run(Simulation.new_game(data, 1), data, 3)
	assert_eq(result.state.money, F.START_MONEY - 3 * F.UPKEEP)
	assert_eq(result.state.day, 3)


func test_step_does_not_mutate_input_state() -> void:
	var data := F.data()
	var state := Simulation.new_game(data, 1)
	var snapshot := JSON.stringify(state.to_dict())
	Simulation.step(state, [Command.order("acme", "steel", 5)], data)
	assert_eq(JSON.stringify(state.to_dict()), snapshot)


func test_same_seed_same_game() -> void:
	var data := F.data(0.5)
	var a := _random_game(data, 42)
	var b := _random_game(data, 42)
	assert_eq(a, b)


func test_different_seed_different_game() -> void:
	var data := F.data(0.5)
	assert_true(_random_game(data, 42) != _random_game(data, 7))


func test_command_roundtrip_serialization() -> void:
	var command := Command.order("acme", "steel", 3)
	var restored := Command.from_dict(JSON.parse_string(JSON.stringify(command.to_dict())))
	assert_eq(restored.type, Command.ORDER)
	assert_eq(int(restored.args["quantity"]), 3)


## 30 days, one order per day, 50% delay chance: a game sensitive to the RNG.
func _random_game(data: GameData, seed: int) -> String:
	var orders := {}
	for day in 30:
		orders[day] = [Command.order("acme", "steel", 1)]
	var result := F.run(Simulation.new_game(data, seed), data, 30, orders)
	return JSON.stringify([result.state.to_dict(), result.events])

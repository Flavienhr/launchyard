extends TestCase

const F := preload("res://tests/sim/fixtures.gd")


func _draws(state: GameState, stream: StringName, n: int) -> Array:
	var rng := SimRng.for_stream(state, stream)
	var out: Array = []
	for i in n:
		out.append(rng.randi())
	return out


func test_same_seed_day_stream_is_reproducible() -> void:
	var a := Simulation.new_game(F.data(), 42)
	var b := Simulation.new_game(F.data(), 42)
	assert_eq(_draws(a, SimRng.DELIVERIES, 5), _draws(b, SimRng.DELIVERIES, 5))


func test_streams_and_days_differ() -> void:
	var state := Simulation.new_game(F.data(), 42)
	assert_true(_draws(state, SimRng.DELIVERIES, 5) != _draws(state, SimRng.WEATHER, 5))
	var before := _draws(state, SimRng.DELIVERIES, 5)
	state.day += 1
	assert_true(before != _draws(state, SimRng.DELIVERIES, 5))


func test_draw_in_other_stream_does_not_change_deliveries() -> void:
	var state := Simulation.new_game(F.data(), 7)
	var baseline := _draws(state, SimRng.DELIVERIES, 10)
	# Interleave heavy draws in other streams, same seed and same day.
	var weather := SimRng.for_stream(state, SimRng.WEATHER)
	var launch := SimRng.for_stream(state, SimRng.LAUNCH)
	for i in 50:
		weather.randf()
		launch.randf()
	assert_eq(_draws(state, SimRng.DELIVERIES, 10), baseline)

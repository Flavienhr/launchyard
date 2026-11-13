class_name SimRng
extends RefCounted
## One independent RNG stream per subsystem (ADR 0005). Each stream is seeded
## from (game_seed, day, stream), so drawing in one stream never shifts another.
## All randomness in sim/ must go through here.

const DELIVERIES := &"deliveries"
const CONTRACTS := &"contracts"
const WEATHER := &"weather"
const LAUNCH := &"launch"
const EVENTS := &"events"


static func for_stream(state: GameState, stream: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.game_seed, state.day, stream])
	return rng

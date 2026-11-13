class_name GameSession
extends RefCounted
## The single door between the UI and the sim (see ui/CLAUDE.md).
## Holds the current state and records every command per day, so that
## seed + command_log is enough to replay the game exactly.

signal changed(events: Array)

var data: GameData
var state: GameState
var command_log: Dictionary = {}  # day -> Array of Command.to_dict()


func _init(p_data: GameData, game_seed: int) -> void:
	data = p_data
	state = Simulation.new_game(data, game_seed)


func submit(command: Command) -> void:
	command_log.get_or_add(state.day, []).append(command.to_dict())
	changed.emit(Simulation.apply_command(state, command, data))


func end_day() -> void:
	changed.emit(Simulation.end_day(state, data))

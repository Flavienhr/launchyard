class_name StepResult
extends RefCounted
## Output of Simulation.step: the next state and what happened during the day.

var state: GameState
var events: Array


func _init(p_state: GameState, p_events: Array) -> void:
	state = p_state
	events = p_events

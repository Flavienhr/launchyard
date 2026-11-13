class_name GameSession
extends RefCounted
## The single door between the UI and the sim (see ui/CLAUDE.md).
## Holds the current state and records every command per day, so that
## seed + command_log is enough to replay the game exactly.

signal changed(events: Array)

## UI constants (presentation only, not balance values): safety cap of the
## fast-forward (spec 005 R3) and the events that interrupt it (R2). Names are
## the real sim events; "contract_offered" of the spec is "offer_generated".
const FAST_FORWARD_MAX_DAYS := 30
const FAST_FORWARD_STOP_EVENTS := [
	"delivery_received", "delivery_delayed", "warehouse_full",
	"job_completed", "job_blocked", "launcher_assembled",
	"offer_generated", "facility_built", "pad_ready",
	"launch_scrubbed", "launch_succeeded", "launch_failed",
	"contract_completed", "contract_failed",
	"bankruptcy_warning", "game_over",
]

var data: GameData
var state: GameState
var command_log: Dictionary = {}  # day -> Array of Command.to_dict()


func _init(p_data: GameData, game_seed: int) -> void:
	data = p_data
	state = Simulation.new_game(data, game_seed)


func submit(command: Command) -> void:
	if state.game_over:
		return
	command_log.get_or_add(state.day, []).append(command.to_dict())
	changed.emit(Simulation.apply_command(state, command, data))


func end_day() -> void:
	if state.game_over:
		return
	changed.emit(Simulation.end_day(state, data))


## Chains end_day() and stops after the first day that holds a stop event, when
## the money goes below zero, or after FAST_FORWARD_MAX_DAYS. All events of the
## skipped days are emitted in one `changed` (journal). Returns the days played.
func fast_forward() -> int:
	var all_events: Array = []
	var days := 0
	while days < FAST_FORWARD_MAX_DAYS and not state.game_over:
		var was_negative := state.money < 0
		var events := Simulation.end_day(state, data)
		all_events.append_array(events)
		days += 1
		if _has_stop_event(events) or (state.money < 0 and not was_negative):
			break
	if days > 0:
		changed.emit(all_events)
	return days


static func _has_stop_event(events: Array) -> bool:
	for event in events:
		if event["type"] in FAST_FORWARD_STOP_EVENTS:
			return true
	return false

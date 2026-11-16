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
	"shortage_started", "supply_delivery_reduced",
]

var data: GameData
var state: GameState
var command_log: Dictionary = {}  # day -> Array of Command.to_dict()
## Where the end-of-day autosave goes. Empty = no autosave (tests, bots).
var autosave_path := ""


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
	var events := Simulation.end_day(state, data)
	_autosave()
	changed.emit(events)


## Writes the current game. Returns SaveGame.write()'s {ok, reason}.
func save_to(path: String) -> Dictionary:
	return SaveGame.write(path, state, command_log)


## Rebuilds a session from a file. Returns {ok, reason, session}.
static func load_from(path: String, p_data: GameData) -> Dictionary:
	var result := SaveGame.read(path)
	if not result["ok"]:
		return {"ok": false, "reason": result["reason"], "session": null}
	var session := GameSession.new(p_data, 0)
	session.state = result["state"]
	session.command_log = result["command_log"]
	return {"ok": true, "reason": "", "session": session}


## One autosave per call; a finished game deletes it instead.
func _autosave() -> void:
	if autosave_path == "":
		return
	if state.game_over:
		SaveGame.remove(autosave_path)
	else:
		save_to(autosave_path)


## Chains end_day() and stops after the first day that holds a stop event, when
## the money goes below zero, or after FAST_FORWARD_MAX_DAYS. All events of the
## skipped days are emitted in one `changed` (journal). Returns the days played.
func fast_forward() -> int:
	var all_events: Array = []
	var days := 0
	while days < FAST_FORWARD_MAX_DAYS and not state.game_over:
		var was_negative := state.money < 0
		var money_before := state.money
		var events := Simulation.end_day(state, data)
		all_events.append_array(events)
		days += 1
		if _has_stop_event(events) or (state.money < 0 and not was_negative) \
				or _invoices_overdraw(events, money_before):
			break
	if days > 0:
		_autosave()
		changed.emit(all_events)
	return days


static func _has_stop_event(events: Array) -> bool:
	for event in events:
		if event["type"] in FAST_FORWARD_STOP_EVENTS:
			return true
	return false


## True when the contract invoices dispatched during the day exceed the cash
## held at the start of the day (the invoice itself would put the balance below zero).
static func _invoices_overdraw(events: Array, money_before: int) -> bool:
	var invoiced := 0
	for event in events:
		if event["type"] == "supply_delivery_dispatched":
			invoiced += int(event["invoice"])
	return invoiced > 0 and invoiced > money_before

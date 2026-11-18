class_name LevelRules
extends RefCounted
## Spec 009 R2, R5-R9: stars, end of level, free play, progress queries.
## Pure: state + data in, events out. No draw, no IO. Metrics: ObjectiveRules.

const RUNNING := "running"
const ENDED := "ended"
const FREE_PLAY := "free_play"

const ALL_STARS := "all_stars"
const TIME_UP := "time_up"
const BANKRUPTCY := "bankruptcy"

const GTE := "gte"
const LTE := "lte"

## Sentinel of "not earned yet" / "no end yet" / "no limit" (same convention as spec 009 R2).
const NONE := -1


## Level state of a game without level (also the default of an old save, R10).
static func empty_state() -> Dictionary:
	return {"id": "", "status": FREE_PLAY, "stars": 0, "star_days": [NONE, NONE, NONE],
		"end_day": NONE, "end_reason": ""}


## Initial level state for `data` (spec 009 R2): running with a level, free play without.
static func initial_state(data: GameData) -> Dictionary:
	var level := empty_state()
	if data.level.is_empty():
		return level
	level["id"] = str(data.level["id"])
	level["status"] = RUNNING
	level["star_days"] = []
	for star in data.level["stars"]:
		level["star_days"].append(NONE)
	return level


## JSON turns ints into floats: recast every number.
static func from_dict(d: Dictionary) -> Dictionary:
	var out := empty_state()
	out["id"] = str(d.get("id", out["id"]))
	out["status"] = str(d.get("status", out["status"]))
	out["stars"] = int(d.get("stars", out["stars"]))
	out["star_days"] = (d.get("star_days", out["star_days"]) as Array).map(func(v): return int(v))
	out["end_day"] = int(d.get("end_day", out["end_day"]))
	out["end_reason"] = str(d.get("end_reason", out["end_reason"]))
	return out


## True while the game is frozen on the end-of-level screen (R7).
static func is_ended(state: GameState) -> bool:
	return state.level["status"] == ENDED


# --- Commands (step 1) --------------------------------------------------------

## R8. The `game_over` rejection is done before, by Simulation.apply_command.
## Returns the rejection reason ("" if accepted) and the events.
static func continue_free_play(state: GameState) -> Dictionary:
	if state.level["status"] != ENDED:
		return {"reason": "level_not_ended", "events": []}
	state.level["status"] = FREE_PLAY
	return {"reason": "", "events": [Simulation.make_event("free_play_started",
		{"level_id": state.level["id"]})]}


# --- Daily evaluation (step 8, last sub-step) --------------------------------

## R6. Call after finances and bankruptcy. `state.day` is still the day being resolved.
static func evaluate(state: GameState, data: GameData) -> Array:
	var level: Dictionary = state.level
	if level["status"] != RUNNING or data.level.is_empty():
		return []
	if state.game_over:  # end_day is frozen on game_over: it just became true today
		return _end(state, BANKRUPTCY)
	var events: Array = []
	var star_count: int = data.level["stars"].size()
	for n in range(int(level["stars"]) + 1, star_count + 1):
		if not _star_met(state, data, data.level["stars"][n - 1]):
			break
		level["stars"] = n
		level["star_days"][n - 1] = state.day
		events.append(Simulation.make_event("star_earned",
			{"level_id": level["id"], "star": n, "day": state.day}))
	if int(level["stars"]) == star_count:
		events.append_array(_end(state, ALL_STARS))
		return events
	var duration := int(data.level["duration_days"])
	if duration > 0:
		var days_left := duration - (state.day + 1)
		if days_left <= 0:
			events.append_array(_end(state, TIME_UP))
		elif days_left in data.level.get("time_warnings_days", []):
			events.append(Simulation.make_event("level_time_warning", {"days_left": days_left}))
	return events


static func _end(state: GameState, reason: String) -> Array:
	var level: Dictionary = state.level
	level["status"] = ENDED
	level["end_day"] = state.day
	level["end_reason"] = reason
	return [Simulation.make_event("level_ended", {"level_id": level["id"], "reason": reason,
		"stars": level["stars"], "star_days": level["star_days"].duplicate()})]


static func objective_met(state: GameState, data: GameData, objective: Dictionary) -> bool:
	var value := ObjectiveRules.metric_value(state, data, objective["metric"])
	if objective["op"] == LTE:
		return value <= int(objective["target"])
	return value >= int(objective["target"])


static func _met_count(state: GameState, data: GameData, objectives: Array) -> int:
	var n := 0
	for objective in objectives:
		if objective_met(state, data, objective):
			n += 1
	return n


## R5: all required objectives and the any_of block, the same day.
static func _star_met(state: GameState, data: GameData, star: Dictionary) -> bool:
	if _met_count(state, data, star["objectives"]) < star["objectives"].size():
		return false
	var any_of: Dictionary = star.get("any_of", {})
	if any_of.is_empty():
		return true
	return _met_count(state, data, any_of["objectives"]) >= int(any_of["min_met"])


# --- Queries (R9) ---------------------------------------------------------------

static func _objective_info(state: GameState, data: GameData, objective: Dictionary) -> Dictionary:
	return {"id": objective["id"], "metric": objective["metric"], "op": objective["op"],
		"target": int(objective["target"]),
		"value": ObjectiveRules.metric_value(state, data, objective["metric"]),
		"met": objective_met(state, data, objective)}


static func progress(state: GameState, data: GameData) -> Dictionary:
	var level: Dictionary = state.level
	var duration := int(data.level.get("duration_days", 0))
	var star_list: Array = []
	var stars: Array = data.level.get("stars", [])
	for i in stars.size():
		var star: Dictionary = stars[i]
		var any_of := {}
		if star.has("any_of"):
			var infos: Array = star["any_of"]["objectives"].map(
				func(o): return _objective_info(state, data, o))
			any_of = {"min_met": int(star["any_of"]["min_met"]),
				"met_count": infos.filter(func(o): return o["met"]).size(), "objectives": infos}
		var earned_day: int = level["star_days"][i] if i < level["star_days"].size() else NONE
		star_list.append({"star": i + 1, "name": star["name"], "earned": earned_day != NONE,
			"earned_day": earned_day,
			"objectives": star["objectives"].map(func(o): return _objective_info(state, data, o)),
			"any_of": any_of})
	return {"level_id": level["id"], "status": level["status"], "end_reason": level["end_reason"],
		"duration_days": duration, "days_left": duration - state.day if duration > 0 else NONE,
		"stars": level["stars"], "star_days": level["star_days"].duplicate(), "star_list": star_list}


## End-of-level screen. "Played days" = number of resolved days.
static func summary(state: GameState, data: GameData) -> Dictionary:
	var done := 0
	var failed := 0
	for contract in state.contracts:
		if contract["status"] == ContractRules.COMPLETED:
			done += 1
		elif contract["status"] == ContractRules.FAILED:
			failed += 1
	return {"level_id": state.level["id"], "stars": state.level["stars"],
		"star_days": state.level["star_days"].duplicate(), "end_reason": state.level["end_reason"],
		"contracts_completed": done, "contracts_failed": failed, "money": state.money,
		"net_cash": ObjectiveRules.metric_value(state, data, ObjectiveRules.NET_CASH),
		"reputation": state.reputation,
		"in_house_share_pct": ObjectiveRules.in_house_share_pct(state, data),
		"supply_completed_value": ObjectiveRules.metric_value(state, data, ObjectiveRules.SUPPLY_COMPLETED_VALUE),
		"days_played": state.day}

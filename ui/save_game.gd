class_name SaveGame
extends RefCounted
## The only place that reads or writes saved games (sim/ does no IO).
## Every function takes the file path, so tests can use a throwaway one.
## Format: {save_version, saved_day, state: GameState.to_dict(), command_log}.
## Failures never raise: they come back as {ok: false, reason: ...}.

const SAVE_VERSION := 1
const AUTOSAVE_PATH := "user://saves/autosave.json"
const MANUAL_PATH := "user://saves/manual.json"

## Fields that older saves may lack (GameState.from_dict has defaults for them).
const OPTIONAL_STATE_KEYS := ["recipe_attempts", "recipe_scrapped", "market",
	"supply_contracts", "next_supply_contract_id", "stats"]


## Writes the file (temp file then rename, so a crash never leaves half a save).
## Returns {ok, reason}.
static func write(path: String, state: GameState, command_log: Dictionary) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return {"ok": false, "reason": "io"}
	var payload := {
		"save_version": SAVE_VERSION,
		"saved_day": state.day,
		"state": state.to_dict(),
		"command_log": command_log,
	}
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "io"}
	file.store_string(JSON.stringify(payload))
	file.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "reason": "io"}
	return {"ok": true, "reason": ""}


## Returns {ok, reason, state, command_log, saved_day}. reason is one of
## "missing", "unreadable", "corrupt", "version" when ok is false.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("unreadable")
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return _fail("corrupt")
	var payload: Dictionary = json.data
	if not payload.has("save_version") or not _is_number(payload["save_version"]) \
			or int(payload["save_version"]) != SAVE_VERSION:
		return _fail("version")
	if not (payload.get("state") is Dictionary) or not (payload.get("command_log") is Dictionary) \
			or not _state_is_valid(payload["state"]):
		return _fail("corrupt")
	var log = _log_from_json(payload["command_log"])
	if log == null:
		return _fail("corrupt")
	return {"ok": true, "reason": "", "state": GameState.from_dict(payload["state"]),
		"command_log": log, "saved_day": int(payload["state"]["day"])}


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "state": null, "command_log": {}, "saved_day": 0}


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Every required key is present with the right kind of value.
static func _state_is_valid(d: Dictionary) -> bool:
	var reference := GameState.new().to_dict()
	for key in reference:
		if not d.has(key):
			if key in OPTIONAL_STATE_KEYS:
				continue
			return false
		var want: Variant = reference[key]
		var got: Variant = d[key]
		if _is_number(want):
			if not _is_number(got):
				return false
		elif typeof(want) != typeof(got):
			return false
	for facility in d["facilities"]:
		if not (facility is Dictionary) or not (facility.get("jobs") is Array):
			return false
	return true


## JSON keys are strings and numbers are floats: restore int days and int args.
## Returns null when an entry is malformed.
static func _log_from_json(raw: Dictionary) -> Variant:
	var out := {}
	for key in raw:
		if not String(key).is_valid_int() or not (raw[key] is Array):
			return null
		var commands: Array = []
		for entry in raw[key]:
			if not (entry is Dictionary) or not entry.has("type") or not (entry.get("args") is Dictionary):
				return null
			commands.append({"type": entry["type"], "args": _recast(entry["args"])})
		out[int(key)] = commands
	return out


static func _recast(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_ARRAY:
			return v.map(_recast)
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _recast(v[k])
			return out
	return v

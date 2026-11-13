class_name DataLoader
extends RefCounted
## The ONLY file in sim/ allowed to do IO: reads data/*.json once at boot.
## Everything else in sim/ receives a GameData and never touches the disk.

const DATA_DIR := "res://data"


static func load_default() -> GameData:
	return GameData.from_dicts(
		_read("components.json").get("components", []),
		_read("suppliers.json").get("suppliers", []),
		_read("facilities.json").get("facilities", []),
		_read("start.json"),
		_read("staff.json"),
		{
			"orbits": _read("orbits.json").get("orbits", []),
			"sites": _read("sites.json").get("sites", []),
			"launchers": _read("launchers.json").get("launchers", []),
		},
		_read("contracts.json"))


static func _read(file_name: String) -> Dictionary:
	var path := DATA_DIR.path_join(file_name)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("DataLoader: cannot parse %s" % path)
		return {}
	return _normalize(parsed)


## JSON has a single number type, so Godot parses every number as float.
## Integral floats are converted back to int so money and quantities stay exact.
static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _normalize(value[key])
		return out
	if value is Array:
		return value.map(_normalize)
	if value is float and value == floorf(value) and absf(value) < 1e15:
		return int(value)
	return value

class_name GameData
extends RefCounted
## Static game definitions (balance values), loaded once from data/.
## Read-only during a game. Tests build it from inline dictionaries.

var components: Dictionary = {}  # id -> Dictionary
var suppliers: Dictionary = {}   # id -> Dictionary
var facilities: Dictionary = {}  # id -> Dictionary
var start: Dictionary = {}       # starting conditions of the selected level (format of the old start.json)
var levels: Dictionary = {}      # id -> Dictionary (levels.json, spec 009)
var level: Dictionary = {}       # selected level record; {} = game without level
var default_level_id: String = ""  # levels.json "default_level"
var staff: Dictionary = {}       # staff.json: "technician" block, max_queue_length
var recipes: Dictionary = {}     # id -> Dictionary
var orbits: Dictionary = {}      # id -> Dictionary (orbits.json)
var sites: Dictionary = {}       # id -> Dictionary (sites.json)
var launchers: Dictionary = {}   # model id -> Dictionary (launchers.json)
var contracts: Dictionary = {}   # contracts.json (spec 002)
var active_site_id: String = ""  # site of the game; see active_site()
var rules: Dictionary = {}       # rules.json (spec 004: bankruptcy); empty = rule off
var market: Dictionary = {}      # market.json (spec 007: index, shortages); empty = fixed index
var supply_contracts: Dictionary = {}  # supply_contracts.json (spec 007: terms of supply contracts)
var layout: Dictionary = {}      # layout.json (spec 008: global spatial rules); empty = off


## Files made of records with an "id" (file content: {"<stem>": [records]}).
const INDEXED_FILES := ["components", "suppliers", "facilities", "recipes", "orbits", "sites", "launchers", "levels"]
## Files used as a whole object. "start" has no file in data/ any more (levels.json
## replaced start.json): it is only accepted inline by from_files (test fixtures).
const WHOLE_FILES := ["start", "staff", "contracts", "rules", "market", "supply_contracts", "layout"]


## Builds GameData from parsed data files keyed by stem (e.g. "components"),
## each value being the full file content. A missing file is empty.
## Adding a data file = adding its stem to a list above, never a new parameter:
## parallel issues adding data files must not collide on this signature.
static func from_files(files: Dictionary) -> GameData:
	var data := GameData.new()
	for stem in INDEXED_FILES:
		var table: Dictionary = data.get(stem)
		for record in files.get(stem, {}).get(stem, []):
			table[record["id"]] = record
	for stem in WHOLE_FILES:
		data.set(stem, files.get(stem, {}))
	data.default_level_id = str(files.get("levels", {}).get("default_level", ""))
	if not data.levels.is_empty():
		if not data.select_level(data.default_level_id):
			push_error("GameData: unknown default_level '%s'" % data.default_level_id)
	else:
		# Game without level: inline "start" (fixtures), site explicit in it.
		data.active_site_id = data.start.get("site", "")
	return data


## Selects the level played (explicit id, never file order). `start` becomes the
## level's starting conditions plus its "site"; `active_site_id` is its site.
## Returns false, selecting nothing, for an unknown id.
func select_level(level_id: String) -> bool:
	if not levels.has(level_id):
		return false
	level = levels[level_id]
	start = level["start"].duplicate(true)
	start["site"] = level["site"]
	active_site_id = level["site"]
	return true


## Levels sorted by `order`, for the level menu (spec 009, campaign format).
## `best_stars` {level_id: stars} is the player's profile: unlocking is a pure
## function of it, never of file order.
func level_list(best_stars := {}) -> Array:
	var out: Array = []
	for id in levels:
		var record: Dictionary = levels[id]
		var unlock: Dictionary = record.get("unlock", {})
		var required: Variant = unlock.get("requires_level", null)
		var min_stars := int(unlock.get("min_stars", 0))
		out.append({"id": id, "name": record.get("name", ""), "briefing": record.get("briefing", ""),
			"site": record["site"], "order": int(record["order"]), "duration_days": int(record["duration_days"]),
			"requires_level": required, "min_stars": min_stars, "stars": int(best_stars.get(id, 0)),
			"unlocked": required == null or int(best_stars.get(required, 0)) >= min_stars})
	out.sort_custom(func(a, b): return a["order"] < b["order"])
	return out


## Site of the current game, set explicitly (the level's "site"). No implicit
## fallback: with several sites, file order must never become a game rule.
func active_site() -> Dictionary:
	return sites.get(active_site_id, {})


## Returns the catalog entry of a supplier for a component, or {} if absent.
func catalog_entry(supplier_id: String, component_id: String) -> Dictionary:
	var supplier: Dictionary = suppliers.get(supplier_id, {})
	for entry in supplier.get("catalog", []):
		if entry["component_id"] == component_id:
			return entry
	return {}


## Map of the active site (spec 008 R1), or {} when the site has none
## (phase 1-2 fixtures): then the whole spatial model is off.
func site_map() -> Dictionary:
	return active_site().get("map", {})


func has_map() -> bool:
	return not site_map().is_empty()


## Lots of the active site, in file order: [{id, x, y, w, h, price}].
func lots() -> Array:
	return site_map().get("lots", [])


## Lot by id, or {} if unknown.
func lot(lot_id: String) -> Dictionary:
	for candidate in lots():
		if candidate["id"] == lot_id:
			return candidate
	return {}

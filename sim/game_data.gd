class_name GameData
extends RefCounted
## Static game definitions (balance values), loaded once from data/.
## Read-only during a game. Tests build it from inline dictionaries.

var components: Dictionary = {}  # id -> Dictionary
var suppliers: Dictionary = {}   # id -> Dictionary
var facilities: Dictionary = {}  # id -> Dictionary
var start: Dictionary = {}       # starting conditions
var staff: Dictionary = {}       # staff.json: "technician" block, max_queue_length
var recipes: Dictionary = {}     # id -> Dictionary
var orbits: Dictionary = {}      # id -> Dictionary (orbits.json)
var sites: Dictionary = {}       # id -> Dictionary (sites.json)
var launchers: Dictionary = {}   # model id -> Dictionary (launchers.json)
var contracts: Dictionary = {}   # contracts.json (spec 002)
var active_site_id: String = ""  # site of the game; see active_site()


## Files made of records with an "id" (file content: {"<stem>": [records]}).
const INDEXED_FILES := ["components", "suppliers", "facilities", "recipes", "orbits", "sites", "launchers"]
## Files used as a whole object.
const WHOLE_FILES := ["start", "staff", "contracts"]


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
	# Explicit site of the game (start.json "site"), see active_site().
	data.active_site_id = data.start.get("site", "")
	return data


## Site of the current game, set explicitly (start.json "site"). No implicit
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

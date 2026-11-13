class_name GameData
extends RefCounted
## Static game definitions (balance values), loaded once from data/.
## Read-only during a game. Tests build it from inline dictionaries.

var components: Dictionary = {}  # id -> Dictionary
var suppliers: Dictionary = {}   # id -> Dictionary
var facilities: Dictionary = {}  # id -> Dictionary
var start: Dictionary = {}       # starting conditions
var staff: Dictionary = {}       # staff.json: "technician" block, max_queue_length
var orbits: Dictionary = {}      # id -> Dictionary (orbits.json)
var sites: Dictionary = {}       # id -> Dictionary (sites.json)
var launchers: Dictionary = {}   # model id -> Dictionary (launchers.json)
var active_site_id: String = ""  # site of the game; see active_site()


static func from_dicts(
		components_list: Array,
		suppliers_list: Array,
		facilities_list: Array,
		start_dict: Dictionary,
		staff_dict: Dictionary = {},
		launch_dict: Dictionary = {}) -> GameData:  # keys: orbits, sites, launchers (Arrays), site_id
	var data := GameData.new()
	for c in components_list:
		data.components[c["id"]] = c
	for s in suppliers_list:
		data.suppliers[s["id"]] = s
	for f in facilities_list:
		data.facilities[f["id"]] = f
	data.start = start_dict
	data.staff = staff_dict
	for o in launch_dict.get("orbits", []):
		data.orbits[o["id"]] = o
	for site in launch_dict.get("sites", []):
		data.sites[site["id"]] = site
	for l in launch_dict.get("launchers", []):
		data.launchers[l["id"]] = l
	# Explicit site: launch_dict.site_id (tests) or start.json "site" (game).
	data.active_site_id = launch_dict.get("site_id", start_dict.get("site", ""))
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

class_name GameData
extends RefCounted
## Static game definitions (balance values), loaded once from data/.
## Read-only during a game. Tests build it from inline dictionaries.

var components: Dictionary = {}  # id -> Dictionary
var suppliers: Dictionary = {}   # id -> Dictionary
var facilities: Dictionary = {}  # id -> Dictionary
var start: Dictionary = {}       # starting conditions
var staff: Dictionary = {}       # staff.json: "technician" block, max_queue_length


static func from_dicts(
		components_list: Array,
		suppliers_list: Array,
		facilities_list: Array,
		start_dict: Dictionary,
		staff_dict: Dictionary = {}) -> GameData:
	var data := GameData.new()
	for c in components_list:
		data.components[c["id"]] = c
	for s in suppliers_list:
		data.suppliers[s["id"]] = s
	for f in facilities_list:
		data.facilities[f["id"]] = f
	data.start = start_dict
	data.staff = staff_dict
	return data


## Returns the catalog entry of a supplier for a component, or {} if absent.
func catalog_entry(supplier_id: String, component_id: String) -> Dictionary:
	var supplier: Dictionary = suppliers.get(supplier_id, {})
	for entry in supplier.get("catalog", []):
		if entry["component_id"] == component_id:
			return entry
	return {}

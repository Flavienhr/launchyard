extends SceneTree
## Scripted playthrough on the REAL data/ (not the test fixtures).
## Plays one full loop with the simplest strategy, "buy everything":
##   sign the best LEO offer -> order the whole L1 bill of materials from the
##   cheapest suppliers -> assemble in the hall -> schedule on the pad -> launch.
## Prints a short report. Exit code 0 if the loop reached an outcome (a failed
## launch is a game result, not a bug); 1 if it got stuck (no offer, timeout).
##
##   godot --headless --path . -s tests/playthrough.gd -- [seed]   (or: make playthrough SEED=n)
##
## It is an end-to-end check of the whole loop (no tokens, deterministic per
## seed) and the starting point of the balance bot (issue #20).

const MAX_DAYS := 150
const LOGGED := [
	"contract_accepted", "order_placed", "delivery_delayed", "delivery_received",
	"job_started", "launcher_assembled", "launch_scheduled", "launch_scrubbed",
	"launch_succeeded", "launch_failed", "contract_completed", "contract_failed",
	"command_rejected", "job_blocked", "negative_balance",
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var game_seed := int(args[0]) if args.size() > 0 else 1
	var data := DataLoader.load_default()
	var state := Simulation.new_game(data, game_seed)
	var start_money := state.money
	var lines: Array[String] = []

	var contract := _best_offer(state, data)
	if contract.is_empty():
		_finish(lines, "aucune offre signable au jour 0", 1)
		return
	var contract_id: int = contract["id"]
	_apply(state, data, Command.accept_contract(contract_id), lines)

	var recipe: Dictionary = data.recipes["assemble_l1"]
	for component_id in recipe["inputs"]:
		var supplier_id := _cheapest_supplier(data, component_id)
		_apply(state, data, Command.order(supplier_id, component_id, int(recipe["inputs"][component_id])), lines)
	var hall := _facility(state, data, "launcher_capacity")
	var pad := _facility(state, data, "rollout_days")
	_apply(state, data, Command.queue_job(hall["id"], "assemble_l1", 1), lines)

	var scheduled := false
	var outcome := ""
	var min_money := state.money
	while state.day < MAX_DAYS and outcome == "":
		if not scheduled and not state.launchers.is_empty():
			var lead := int(data.facilities[pad["type"]]["rollout_days"])
			var events := _apply(state, data, Command.schedule_launch(
				state.launchers[0]["id"], pad["id"], contract_id, state.day + lead), lines)
			scheduled = events[0]["type"] == "launch_scheduled"
		for event in Simulation.end_day(state, data):
			_log(lines, state.day - 1, event)
			if event["type"] in ["contract_completed", "contract_failed"] and event.get("contract_id") == contract_id:
				outcome = event["type"]
		min_money = mini(min_money, state.money)

	lines.append("")
	lines.append("seed %d · contrat #%d (%s, %d kg, %d cr, limite J%d)" % [
		game_seed, contract_id, contract["orbit"], contract["payload_kg"], contract["payment"], contract["deadline_day"]])
	lines.append("issue : %s au jour %d" % [outcome if outcome != "" else "timeout", state.day])
	lines.append("argent : %d -> %d (delta %+d, minimum %d)" % [start_money, state.money, state.money - start_money, min_money])
	lines.append("réputation : %d" % state.reputation)
	_finish(lines, "", 0 if outcome != "" else 1)


## Highest-paying offer that the starting site and launcher can actually fly.
static func _best_offer(state: GameState, data: GameData) -> Dictionary:
	var best := {}
	for contract in state.contracts:
		if contract["status"] != ContractRules.OFFER:
			continue
		var orbit: Dictionary = data.orbits.get(contract["orbit"], {})
		if orbit.is_empty() or not LaunchRules.is_orbit_reachable(orbit, data.active_site()):
			continue
		if int(contract["payload_kg"]) > ContractRules.best_capacity(data, contract["orbit"], data.active_site()):
			continue
		if best.is_empty() or int(contract["payment"]) > int(best["payment"]):
			best = contract
	return best


static func _cheapest_supplier(data: GameData, component_id: String) -> String:
	var best_id := ""
	var best_price := 0
	for supplier_id in data.suppliers:
		var entry := data.catalog_entry(supplier_id, component_id)
		if not entry.is_empty() and (best_id == "" or int(entry["unit_price"]) < best_price):
			best_id = supplier_id
			best_price = int(entry["unit_price"])
	return best_id


## First ready facility whose type defines `field` (no hard-coded type ids).
static func _facility(state: GameState, data: GameData, field: String) -> Dictionary:
	for facility in state.facilities:
		if facility["status"] == "ready" and data.facilities[facility["type"]].has(field):
			return facility
	return {}


static func _apply(state: GameState, data: GameData, command: Command, lines: Array[String]) -> Array:
	var events := Simulation.apply_command(state, command, data)
	for event in events:
		_log(lines, state.day, event)
	return events


static func _log(lines: Array[String], day: int, event: Dictionary) -> void:
	if event["type"] not in LOGGED:
		return
	var fields := event.duplicate()
	fields.erase("type")
	lines.append("J%-3d %-20s %s" % [day, event["type"], JSON.stringify(fields)])


func _finish(lines: Array[String], error: String, code: int) -> void:
	for line in lines:
		print(line)
	if error != "":
		print("ÉCHEC : ", error)
	quit(code)

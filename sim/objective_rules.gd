class_name ObjectiveRules
extends RefCounted
## Spec 009 R4: objective metrics. Pure queries on state + data, integers only.

const CONTRACTS_COMPLETED := "contracts_completed"
const NET_CASH := "net_cash"
const REPUTATION := "reputation"
const IN_HOUSE_SHARE_PCT := "in_house_share_pct"
const SUPPLY_COMPLETED_VALUE := "supply_completed_value"
## Percent denominator of in_house_share_pct (a unit, not a balance value).
const PCT := 100


## Value of a metric. `site_violations` (spec 009 R4b) belongs to a later issue (#85):
## until then, like any unknown metric, it returns 0.
static func metric_value(state: GameState, data: GameData, metric_id: String) -> int:
	match metric_id:
		CONTRACTS_COMPLETED:
			return _count_contracts(state, ContractRules.COMPLETED)
		NET_CASH:
			return _net_cash(state)
		REPUTATION:
			return state.reputation
		IN_HOUSE_SHARE_PCT:
			return in_house_share_pct(state, data)
		SUPPLY_COMPLETED_VALUE:
			return _supply_completed_value(state)
	return 0


static func _count_contracts(state: GameState, status: String) -> int:
	var n := 0
	for contract in state.contracts:
		if contract["status"] == status:
			n += 1
	return n


## Money minus the advances of active launch contracts (not earned yet).
static func _net_cash(state: GameState) -> int:
	var cash := state.money
	for contract in state.contracts:
		if contract["status"] == ContractRules.ACTIVE:
			cash -= int(contract["advance"])
	return cash


static func _supply_completed_value(state: GameState) -> int:
	var total := 0
	for contract in state.supply_contracts:
		if contract["status"] == SupplyRules.COMPLETED:
			total += int(contract.get("invoiced_total", 0))
	return total


## Cheapest catalog unit_price over all suppliers, without market index (R4a). 0 if not sold.
static func ref_price(data: GameData, component_id: String) -> int:
	var best := -1
	for supplier_id in data.suppliers:
		for entry in data.suppliers[supplier_id]["catalog"]:
			if entry["component_id"] == component_id:
				var price := int(entry["unit_price"])
				if best < 0 or price < best:
					best = price
	return maxi(best, 0)


## R4a: share of the catalog value of the mounted parts that was made in house.
static func in_house_share_pct(state: GameState, data: GameData) -> int:
	var credited_value := 0
	var total_value := 0
	for component_id in state.stats["kit_consumed"]:
		var consumed := int(state.stats["kit_consumed"][component_id])
		var credited := mini(int(state.stats["components_made"].get(component_id, 0)), consumed)
		var price := ref_price(data, component_id)
		credited_value += price * credited
		total_value += price * consumed
	if total_value == 0:
		return 0
	return PCT * credited_value / total_value

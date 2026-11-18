class_name ObjectiveRules
extends RefCounted
## Spec 009 R4: objective metrics. Pure queries on state + data, integers only.

const CONTRACTS_COMPLETED := "contracts_completed"
const NET_CASH := "net_cash"
const REPUTATION := "reputation"
const IN_HOUSE_SHARE_PCT := "in_house_share_pct"
const SUPPLY_COMPLETED_VALUE := "supply_completed_value"
const SITE_VIOLATIONS := "site_violations"
## Percent denominator of in_house_share_pct (a unit, not a balance value).
const PCT := 100


## Value of a metric. Unknown metrics return 0.
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
		SITE_VIOLATIONS:
			return site_violations(state, data)
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


## R4b: infractions of the site. Every instance except the pads, with status
## `ready` or `building`, counts once if it is in the safety zone of at least
## one pad, and once more if it is `ready`, has `slots` and is not served.
## Without rules (no map) the site has no violation: 0. Spatial facts come from
## LayoutRules.facility_spatial (spec 008), not recomputed here.
static func site_violations(state: GameState, data: GameData) -> int:
	if not LayoutRules.rules_on(data):
		return 0
	var count := 0
	for facility in state.facilities:
		var status: String = facility["status"]
		if LayoutRules.is_pad_instance(data, facility):
			continue
		if status != "ready" and status != "building":
			continue
		var spatial := LayoutRules.facility_spatial(state, data, int(facility["id"]))
		if not spatial["in_safety_zone_of"].is_empty():
			count += 1
		if status == "ready" and not spatial["served"]:
			count += 1
	return count

extends SceneTree
## Balance simulation on the REAL data/ (issues #20 and #54, specs 003 and 006).
## Plays N seeds x D days with the scripted strategies of balance_bot.gd and prints a
## short report (add --verbose for the per-seed detail and the journal of seed 1).
## Deterministic, no network, no LLM.
##
##   godot --headless --path . -s tests/balance.gd -- [--seeds=40] [--days=240] [--verbose]
##   (or: make balance [SEEDS=40] [DAYS=240] [VERBOSE=1]; DAYS=360 for the long horizon)
##
## Target (spec 001, "Ordres de grandeur visés"): the tank shop pays for itself
## between the 3rd and the 5th launcher. Payback launcher = first n such that the
## median over seeds of (money_strategy[n] - money_buy_all[n]) is >= 0 and stays so,
## money[n] being the cash at the end of the day of the n-th shot of each strategy.
## Exit code 1 when a bot hit rejected commands (bot bug) or the target is missed.
## The spec 006 sections are informative: they print values next to the spec's
## expectations, they never change the exit code.

const STRATEGIES := [
	BalanceBot.BUY_ALL, BalanceBot.WORKSHOP, BalanceBot.INTEGRATE_STAGED,
	BalanceBot.INTEGRATE_GREEDY, BalanceBot.ENGINES_ONLY,
	BalanceBot.CONTRACT_ENGINES, BalanceBot.CONTRACT_FULL_KIT, BalanceBot.CONTRACT_OVERCOMMIT,
	BalanceBot.OPPORTUNIST,
]
## Strategies that build workshops (the commissioning and chain sections concern them).
const BUILDERS := [
	BalanceBot.WORKSHOP, BalanceBot.INTEGRATE_STAGED, BalanceBot.INTEGRATE_GREEDY, BalanceBot.ENGINES_ONLY,
]
const CONTRACTORS := [
	BalanceBot.CONTRACT_ENGINES, BalanceBot.CONTRACT_FULL_KIT, BalanceBot.CONTRACT_OVERCOMMIT,
	BalanceBot.OPPORTUNIST,
]
## Spec 007 expectations (report only).
const INDEX_MIN := 980
const INDEX_MAX := 1080
const SOLVENT_GAP_PCT := 10
const VARIANCE_CUT_PCT := 25
const OVERCOMMIT_MAX_BANKRUPT := 5
const TARGET_MIN := 3
const TARGET_MAX := 5
const MIN_SAMPLES_PCT := 50  # a launcher index counts only if this % of seeds reached it
const NEVER := -1


func _init() -> void:
	var seeds := 40
	var days := 240
	var verbose := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.trim_prefix("--seeds="))
		elif arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
		elif arg == "--verbose":
			verbose = true
	if seeds <= 0 or days <= 0:
		print("ÉCHEC : --seeds et --days doivent être > 0")
		quit(2)
		return

	var data := DataLoader.load_default()
	var runs := {}  # strategy -> Array[BalanceBot], index = seed - 1
	for strategy in STRATEGIES:
		runs[strategy] = []
		for game_seed in range(1, seeds + 1):
			var bot := BalanceBot.new(strategy, data, game_seed)
			bot.play(days)
			runs[strategy].append(bot)

	print("balance : %d seeds x %d jours, données réelles de data/ (réserve = %d cr, 2 kits L1 achetés)" % [
		seeds, days, runs[BalanceBot.INTEGRATE_STAGED][0].reserve])
	var rejected := false
	_print_summary_table(runs)
	for strategy in STRATEGIES:
		rejected = _report_rejections(strategy, runs[strategy]) or rejected
	_report_commissioning(runs)
	_report_chains(runs)
	_report_scrap(runs, days)
	_report_market(runs)
	_report_contracts(runs)
	_report_bottleneck(runs)
	var payback := _payback_section(runs, verbose)
	_report_spec_checks(runs)
	if verbose:
		_report_verbose(runs)

	var verdict := _verdict(payback)
	print(verdict)
	quit(1 if rejected or not verdict.begins_with("CIBLE ATTEINTE") else 0)


# --- Summary --------------------------------------------------------------------

func _print_summary_table(runs: Dictionary) -> void:
	print("")
	print("%-17s %8s %7s %6s %7s %10s %10s %10s %6s %6s" % [
		"stratégie", "réussis", "ratés", "expir.", "météo", "argent P50", "P10", "P90", "faill.", "1er tir"])
	for strategy in STRATEGIES:
		var bots: Array = runs[strategy]
		var totals := {"completed": 0, "failed_launch": 0, "failed_deadline": 0, "scrubs": 0, "bankrupt": 0}
		var money: Array = []
		var first_shots: Array = []
		for bot: BalanceBot in bots:
			totals["completed"] += bot.completed
			totals["failed_launch"] += bot.failed_launch
			totals["failed_deadline"] += bot.failed_deadline
			totals["scrubs"] += bot.scrubs
			totals["bankrupt"] += 1 if bot.state.game_over else 0
			money.append(bot.state.money)
			if bot.first_shot_day >= 0:
				first_shots.append(bot.first_shot_day)
		var n := bots.size()
		print("%-17s %8.1f %7.1f %6.1f %7.1f %10d %10d %10d %6s %6s" % [
			strategy, float(totals["completed"]) / n, float(totals["failed_launch"]) / n,
			float(totals["failed_deadline"]) / n, float(totals["scrubs"]) / n,
			_percentile(money, 50), _percentile(money, 10), _percentile(money, 90),
			"%d/%d" % [totals["bankrupt"], n],
			"j%d" % _percentile(first_shots, 50) if not first_shots.is_empty() else "-"])
	print("(contrats par partie : réussis, tirs ratés, expirés ; reports météo par partie ; argent final)")


## Returns true if the bot got commands rejected.
func _report_rejections(strategy: String, bots: Array) -> bool:
	var rejections := {}
	for bot: BalanceBot in bots:
		for reason in bot.rejections:
			rejections[reason] = int(rejections.get(reason, 0)) + int(bot.rejections[reason])
	if not rejections.is_empty():
		print("COMMANDES REJETÉES (bug du bot ?) [%s] : %s" % [strategy, JSON.stringify(rejections)])
	return not rejections.is_empty()


# --- Spec 006 metrics -------------------------------------------------------------

## Day each workshop became ready (median over the seeds that built it).
func _report_commissioning(runs: Dictionary) -> void:
	print("")
	print("[mise en service] jour médian (parties où l'atelier existe)")
	for strategy in BUILDERS:
		var parts: Array[String] = []
		for type in BalanceBot.STAGES:
			var days: Array = []
			for bot: BalanceBot in runs[strategy]:
				if bot.built_day.has(type):
					days.append(bot.built_day[type])
			if not days.is_empty():
				parts.append("%s j%d (%d/%d)" % [type, _percentile(days, 50), days.size(), runs[strategy].size()])
		print("  %-17s %s" % [strategy, ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "-"])


## Payback launcher of each chain, from the chain's own accounting (see
## BalanceBot.chain_net): purchases avoided - materials - upkeep and salaries -
## construction and hiring >= 0 and stays so. Same seed = same contracts as buy_all.
func _report_chains(runs: Dictionary) -> void:
	print("")
	print("[rentabilisation par chaîne] lanceur médian où l'économie cumulée couvre construction + entretien + salaires ; net final médian")
	for strategy in BUILDERS:
		var parts: Array[String] = []
		for chain in BalanceBot.CHAINS:
			var paid: Array = []
			var finals: Array = []
			var built := 0
			for bot: BalanceBot in runs[strategy]:
				if not bot.built_day.has(BalanceBot.CHAINS[chain][-1]):
					continue
				built += 1
				finals.append(bot.chain_net(chain))
				var k := _trailing_nonnegative_start(bot.chain_net_at_shot[chain])
				if k != NEVER:
					paid.append(k)
			if built > 0:
				parts.append("%s %s (%d/%d payées, net %+d)" % [
					chain, "L%d" % _percentile(paid, 50) if not paid.is_empty() else "jamais",
					paid.size(), built, _percentile(finals, 50)])
		print("  %-17s %s" % [strategy, "; ".join(PackedStringArray(parts)) if not parts.is_empty() else "-"])


## 1-based index of the first shot of the trailing run of values >= 0, NEVER if the last is < 0.
func _trailing_nonnegative_start(nets: Array) -> int:
	var found := NEVER
	for k in range(nets.size() - 1, -1, -1):
		if nets[k] >= 0:
			found = k + 1
		else:
			break
	return found


func _report_scrap(runs: Dictionary, days: int) -> void:
	print("")
	print("[rebuts] pièces rebutées par partie (moy.), part des pièces du kit fabriquées, jour du plancher de rebut (médiane)")
	for strategy in STRATEGIES:
		if not BalanceBot.is_integrated(strategy):
			continue
		var bots: Array = runs[strategy]
		var scrap_parts: Array[String] = []
		for recipe_id in bots[0].data.recipes:
			var total := 0
			var floors: Array = []
			for bot: BalanceBot in bots:
				total += int(bot.scrapped.get(recipe_id, 0))
				if bot.scrap_floor_day.has(recipe_id):
					floors.append(bot.scrap_floor_day[recipe_id])
			if total > 0:
				scrap_parts.append("%s %.1f%s" % [recipe_id, float(total) / bots.size(),
					" (plancher j%d, %d/%d)" % [_percentile(floors, 50), floors.size(), bots.size()] if not floors.is_empty() else ""])
		var share: Array[String] = []
		for component_id in ["tank", "engine", "avionics", "fairing"]:
			var made := 0
			var bought := 0
			for bot: BalanceBot in bots:
				made += int(bot.made_units.get(component_id, 0))
				bought += int(bot.bought_units.get(component_id, 0))
			if made + bought > 0:
				share.append("%s %d%%" % [component_id, 100 * made / (made + bought)])
		print("  %-17s rebuts : %s ; fabriqué : %s" % [strategy,
			", ".join(PackedStringArray(scrap_parts)) if not scrap_parts.is_empty() else "aucun",
			", ".join(PackedStringArray(share)) if not share.is_empty() else "-"])
	print("  (plancher de rebut sur %d jours : seulement pour les parties où il est atteint)" % days)


## Spec 007: supplier capacity per period and shortages, per game (mean).
func _report_market(runs: Dictionary) -> void:
	print("")
	print("[marché] par partie (moy.) : jours bloqués par la capacité des fournisseurs ; commandes passées en pénurie (unités)")
	for strategy in STRATEGIES:
		var blocked := 0
		var orders := 0
		var units := 0
		var cash := 0
		for bot: BalanceBot in runs[strategy]:
			blocked += bot.capacity_blocked_days
			orders += bot.shortage_orders
			units += bot.shortage_units
			cash += bot.cash_wait_days
		var n: int = runs[strategy].size()
		print("  %-17s %.1f jours bloqués ; %.1f commandes en pénurie (%.1f unités) ; %.1f jours d'attente de trésorerie" % [
			strategy, float(blocked) / n, float(orders) / n, float(units) / n, float(cash) / n])


## Spec 007 contract metrics, per game (mean), and the mean market index per component.
func _report_contracts(runs: Dictionary) -> void:
	print("")
	print("[contrats] par partie (moy.) : signés, livraisons sautées, frais de garde, take-or-pay, résiliation, pénalités perçues ; livraisons réduites ; jours bloqués en pénurie")
	for strategy in STRATEGIES:
		var sums := [0, 0, 0, 0, 0, 0, 0, 0]
		for bot: BalanceBot in runs[strategy]:
			var values := [bot.contracts_signed, bot.deliveries_skipped, bot.holding_fees_paid,
				bot.take_or_pay_paid, bot.termination_paid, bot.penalties_earned,
				bot.reduced_deliveries, bot.shortage_blocked_days]
			for i in sums.size():
				sums[i] += values[i]
		var n: int = runs[strategy].size()
		print("  %-19s %4.1f signés, %4.1f sautées, garde %7.0f, take-or-pay %7.0f, résil. %6.0f, pénalités +%6.0f ; %4.1f réduites ; %5.1f j bloqués" % [
			strategy, float(sums[0]) / n, float(sums[1]) / n, float(sums[2]) / n, float(sums[3]) / n,
			float(sums[4]) / n, float(sums[5]) / n, float(sums[6]) / n, float(sums[7]) / n])
	print("  indice moyen observé (buy_all) : %s" % _index_line(runs[BalanceBot.BUY_ALL]))


func _index_line(bots: Array) -> String:
	var parts: Array[String] = []
	var ids: Array = bots[0].index_sum.keys()
	ids.sort()
	for component_id in ids:
		var total := 0
		var days := 0
		for bot: BalanceBot in bots:
			total += int(bot.index_sum[component_id])
			days += bot.index_days
		parts.append("%s %d" % [component_id, total / maxi(1, days)])
	return ", ".join(PackedStringArray(parts))


## Bottleneck: for each launcher, the resource its assembly waited for the longest.
func _report_bottleneck(runs: Dictionary) -> void:
	print("")
	print("[goulot] ressource qui a retardé le plus longtemps le début de l'assemblage, lanceurs par ressource (1re moitié | 2e moitié)")
	for strategy in STRATEGIES:
		var line: Array[String] = []
		for phase in ["early", "late"]:
			var counts := {}
			for bot: BalanceBot in runs[strategy]:
				for resource in bot.bottleneck[phase]:
					counts[resource] = int(counts.get(resource, 0)) + int(bot.bottleneck[phase][resource])
			line.append(_histogram(counts, runs[strategy].size()))
		print("  %-17s %s | %s" % [strategy, line[0], line[1]])


func _histogram(counts: Dictionary, games: int) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s %.1f" % [key, float(counts[key]) / games])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "-"


# --- Strategies vs buy_all ----------------------------------------------------------

## Prints the curve of the workshop (the spec 001 target) and one line per other
## strategy. Returns the workshop payback ({found, compared}) for the verdict.
func _payback_section(runs: Dictionary, verbose: bool) -> Dictionary:
	var result := {}
	print("")
	print("[écart d'argent vs buy_all] au n-ième tir (médiane) ; lanceur de rentabilisation ; argent final (médiane des écarts par seed)")
	for strategy in STRATEGIES:
		if strategy == BalanceBot.BUY_ALL:
			continue
		var curve := _curve(runs[BalanceBot.BUY_ALL], runs[strategy])
		var found := _first_stable_nonnegative(curve)
		var finals: Array = []
		for i in runs[strategy].size():
			finals.append(runs[strategy][i].state.money - runs[BalanceBot.BUY_ALL][i].state.money)
		print("  %-17s rentabilisé : %s ; écart final %+d" % [
			strategy, "lanceur %d" % found if found > 0 else "jamais (sur %d lanceurs comparables)" % curve.size(),
			_percentile(finals, 50)])
		if strategy == BalanceBot.WORKSHOP:
			result = {"found": found, "compared": curve.size()}
		if verbose or strategy == BalanceBot.WORKSHOP:
			var parts: Array[String] = []
			for point in curve:
				parts.append("%d:%+d" % [point["n"], point["median"]])
			print("    ", " ".join(PackedStringArray(parts)) if not parts.is_empty() else "(pas assez de tirs)")
	return result


## [{n, median, samples}] of (strategy - buy_all) money at the n-th shot.
func _curve(buy_all: Array, other: Array) -> Array:
	var max_n := 0
	for bot: BalanceBot in buy_all + other:
		max_n = maxi(max_n, bot.money_at_shot.size())
	var curve: Array = []
	for n in range(1, max_n + 1):
		var diffs: Array = []
		for i in buy_all.size():
			var a: BalanceBot = buy_all[i]
			var w: BalanceBot = other[i]
			if a.money_at_shot.size() >= n and w.money_at_shot.size() >= n:
				diffs.append(w.money_at_shot[n - 1] - a.money_at_shot[n - 1])
		if diffs.size() * 100 < buy_all.size() * MIN_SAMPLES_PCT:
			break
		curve.append({"n": n, "median": _percentile(diffs, 50), "samples": diffs.size()})
	return curve


func _first_stable_nonnegative(curve: Array) -> int:
	var found := -1
	for k in range(curve.size() - 1, -1, -1):  # last index of the trailing run of >= 0
		if curve[k]["median"] >= 0:
			found = curve[k]["n"]
		else:
			break
	return found


## Values next to the expectations of spec 006 ("Ce que make balance doit montrer").
func _report_spec_checks(runs: Dictionary) -> void:
	var workshop: Array = runs[BalanceBot.WORKSHOP]
	var staged: Array = runs[BalanceBot.INTEGRATE_STAGED]
	var greedy: Array = runs[BalanceBot.INTEGRATE_GREEDY]
	var engines: Array = runs[BalanceBot.ENGINES_ONLY]
	print("")
	print("[contrôles spec 006] valeur mesurée (attendu)")
	print("  staged vs workshop, argent final médian : %+.1f%% (+5 à +15%%) ; workshop meilleur sur %d%% des seeds (>= 20%%)" % [
		_gain_pct(workshop, staged), _share_better(staged, workshop)])
	print("  greedy vs staged, argent final médian : %+.1f%% (< 0) ; faillites greedy %d, workshop %d (greedy >= workshop)" % [
		_gain_pct(staged, greedy), _bankruptcies(greedy), _bankruptcies(workshop)])
	print("  engines_only vs workshop : %+.1f%% ; staged vs engines_only : %+.1f%%" % [
		_gain_pct(workshop, engines), _gain_pct(engines, staged)])
	var fairing_nets: Array = []
	for bot: BalanceBot in staged:
		if bot.built_day.has("composite_shop"):
			fairing_nets.append(int(bot.chain_econ["fairing"]["saving"]) - int(bot.chain_econ["fairing"]["material"]))
	print("  composite_shop, achats évités - matières, cumulé (staged) : médiane %s (< 30000)" % (
		str(_percentile(fairing_nets, 50)) if not fairing_nets.is_empty() else "atelier jamais construit"))
	var floors: Array = []
	for strategy in [BalanceBot.INTEGRATE_STAGED, BalanceBot.INTEGRATE_GREEDY, BalanceBot.ENGINES_ONLY]:
		for bot: BalanceBot in runs[strategy]:
			if bot.scrap_floor_day.has("build_engine") and bot.built_day.has("engine_shop"):
				floors.append(bot.scrap_floor_day["build_engine"])
	_report_contract_checks(runs)
	print("  plancher de rebut moteur : jour %s au plus tôt, médiane %s (pas avant ~120)" % [
		str(floors.min()) if not floors.is_empty() else "-", str(_percentile(floors, 50)) if not floors.is_empty() else "-"])


## Spec 007 expectations ("Ce que make balance doit montrer"), values next to the targets.
func _report_contract_checks(runs: Dictionary) -> void:
	var buy_all: Array = runs[BalanceBot.BUY_ALL]
	var low := 1 << 30
	var high := 0
	var bots: Array = buy_all
	for component_id in bots[0].index_sum:
		var total := 0
		var days := 0
		for bot: BalanceBot in bots:
			total += int(bot.index_sum[component_id])
			days += bot.index_days
		low = mini(low, total / maxi(1, days))
		high = maxi(high, total / maxi(1, days))
	print("  indice moyen par composant : %d à %d (dans [%d, %d])" % [low, high, INDEX_MIN, INDEX_MAX])
	var best := BalanceBot.CONTRACT_ENGINES
	for strategy in CONTRACTORS:
		if _median_money(runs[strategy]) > _median_money(runs[best]):
			best = strategy
	print("  buy_all vs meilleure stratégie à contrats (%s) : %+.1f%% (écart < %d%%)" % [
		best, _gain_pct(runs[best], buy_all), SOLVENT_GAP_PCT])
	var spread_all := _percentile(_money(buy_all), 90) - _percentile(_money(buy_all), 10)
	var engines: Array = runs[BalanceBot.CONTRACT_ENGINES]
	var spread_eng := _percentile(_money(engines), 90) - _percentile(_money(engines), 10)
	print("  contract_engines, écart P90-P10 : %d contre %d pour buy_all (%+.0f%%, cible -%d%% ou mieux) ; P10 %d contre %d" % [
		spread_eng, spread_all, 100.0 * (spread_eng - spread_all) / maxf(1.0, spread_all), VARIANCE_CUT_PCT,
		_percentile(_money(engines), 10), _percentile(_money(buy_all), 10)])
	var lowest := BalanceBot.CONTRACT_ENGINES
	for strategy in CONTRACTORS:
		if _median_money(runs[strategy]) < _median_money(runs[lowest]):
			lowest = strategy
	print("  médiane la plus basse des stratégies à contrats : %s (attendu contract_overcommit) ; faillites overcommit %d (<= %d)" % [
		lowest, _bankruptcies(runs[BalanceBot.CONTRACT_OVERCOMMIT]), OVERCOMMIT_MAX_BANKRUPT])
	print("  opportunist vs buy_all, argent final médian : %+.1f%% (>= 0)" % _gain_pct(buy_all, runs[BalanceBot.OPPORTUNIST]))
	var blocked_staged := 0
	var blocked_all := 0
	for bot: BalanceBot in runs[BalanceBot.INTEGRATE_STAGED]:
		blocked_staged += bot.shortage_blocked_days
	for bot: BalanceBot in buy_all:
		blocked_all += bot.shortage_blocked_days
	print("  jours bloqués en pénurie par partie : integrate_staged %.1f contre buy_all %.1f (moins)" % [
		float(blocked_staged) / runs[BalanceBot.INTEGRATE_STAGED].size(), float(blocked_all) / buy_all.size()])


func _money(bots: Array) -> Array:
	var out: Array = []
	for bot: BalanceBot in bots:
		out.append(bot.state.money)
	return out


func _median_money(bots: Array) -> int:
	return _percentile(_money(bots), 50)


## Relative difference of the median final money, `other` over `base`, in %.
func _gain_pct(base: Array, other: Array) -> float:
	var a: Array = []
	var b: Array = []
	for bot: BalanceBot in base:
		a.append(bot.state.money)
	for bot: BalanceBot in other:
		b.append(bot.state.money)
	var reference := _percentile(a, 50)
	if reference == 0:
		return 0.0
	return 100.0 * float(_percentile(b, 50) - reference) / absf(float(reference))


## % of seeds where `a` ends with more money than `b`.
func _share_better(b_bots: Array, a_bots: Array) -> int:
	var count := 0
	for i in a_bots.size():
		if a_bots[i].state.money > b_bots[i].state.money:
			count += 1
	return 100 * count / a_bots.size()


func _bankruptcies(bots: Array) -> int:
	var count := 0
	for bot: BalanceBot in bots:
		count += 1 if bot.state.game_over else 0
	return count


# --- Verbose --------------------------------------------------------------------------

func _report_verbose(runs: Dictionary) -> void:
	for strategy in STRATEGIES:
		var bots: Array = runs[strategy]
		print("")
		print("[%s] détail par seed" % strategy)
		for i in bots.size():
			var bot: BalanceBot = bots[i]
			print("  seed %2d : %d réussis, %d tirs ratés, %d expirés, argent %d%s" % [
				i + 1, bot.completed, bot.failed_launch, bot.failed_deadline, bot.state.money,
				" FAILLITE j%d" % bot.state.day if bot.state.game_over else ""])
		print("  --- journal de la seed 1 ---")
		for line in bots[0].log:
			print("  ", line)


func _verdict(payback: Dictionary) -> String:
	var found: int = payback["found"]
	if found < 0:
		return "HORS CIBLE : atelier non rentabilisé sur %d lanceurs comparables (cible %d-%d)" % [
			payback["compared"], TARGET_MIN, TARGET_MAX]
	if found > TARGET_MAX:
		return "HORS CIBLE : rentabilisé au lanceur %d (cible %d-%d), écart +%d" % [found, TARGET_MIN, TARGET_MAX, found - TARGET_MAX]
	if found < TARGET_MIN:
		return "HORS CIBLE : rentabilisé au lanceur %d (cible %d-%d), écart %d (trop tôt)" % [found, TARGET_MIN, TARGET_MAX, found - TARGET_MIN]
	return "CIBLE ATTEINTE : rentabilisé au lanceur %d (cible %d-%d), écart 0" % [found, TARGET_MIN, TARGET_MAX]


## Nearest-rank percentile of an Array of ints (sorted copy). 0 for an empty array.
static func _percentile(values: Array, pct: int) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	var rank := int(ceil(float(pct) / 100.0 * sorted.size()))
	return int(sorted[clampi(rank - 1, 0, sorted.size() - 1)])

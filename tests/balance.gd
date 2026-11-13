extends SceneTree
## Balance simulation on the REAL data/ (issue #20, spec 003 decision 7).
## Plays N seeds x D days with two scripted strategies (see balance_bot.gd) and
## prints a short report. Deterministic, no network, no LLM.
##
##   godot --headless --path . -s tests/balance.gd -- [--seeds=40] [--days=240] [--verbose]
##   (or: make balance [SEEDS=40] [DAYS=240] [VERBOSE=1])
##
## Target (spec 001, "Ordres de grandeur visés"): the tank shop pays for itself
## between the 3rd and the 5th launcher. Payback launcher = first n such that the
## median over seeds of (money_workshop[n] - money_buy_all[n]) is >= 0 and stays so,
## money[n] being the cash at the end of the day of the n-th shot of each strategy.
## Exit code 1 when a bot hit rejected commands (bot bug) or the target is missed.

const STRATEGIES := [BalanceBot.BUY_ALL, BalanceBot.WORKSHOP]
const TARGET_MIN := 3
const TARGET_MAX := 5
const MIN_SAMPLES_PCT := 50  # a launcher index counts only if this % of seeds reached it


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

	print("balance : %d seeds x %d jours, données réelles de data/" % [seeds, days])
	var rejected := false
	for strategy in STRATEGIES:
		rejected = _report_strategy(strategy, runs[strategy], verbose) or rejected

	var payback := _payback(runs[BalanceBot.BUY_ALL], runs[BalanceBot.WORKSHOP], verbose)
	var verdict := _verdict(payback)
	print(verdict)
	quit(1 if rejected or not verdict.begins_with("CIBLE ATTEINTE") else 0)


## One summary block; returns true if the bot got commands rejected.
func _report_strategy(strategy: String, bots: Array, verbose: bool) -> bool:
	var completed: Array = []
	var money: Array = []
	var first_shots: Array = []
	var totals := {"failed_launch": 0, "failed_deadline": 0, "scrubs": 0, "signed": 0, "bankrupt": 0, "completed": 0}
	var rejections := {}
	for bot: BalanceBot in bots:
		totals["completed"] += bot.completed
		totals["failed_launch"] += bot.failed_launch
		totals["failed_deadline"] += bot.failed_deadline
		totals["scrubs"] += bot.scrubs
		totals["signed"] += bot.signed
		totals["bankrupt"] += 1 if bot.state.game_over else 0
		completed.append(bot.completed)
		money.append(bot.state.money)
		if bot.first_shot_day >= 0:
			first_shots.append(bot.first_shot_day)
		for reason in bot.rejections:
			rejections[reason] = int(rejections.get(reason, 0)) + int(bot.rejections[reason])
	var n := bots.size()
	print("")
	print("[%s]" % strategy)
	print("  contrats (moy./partie) : %.1f réussis, %.1f échoués (tir raté), %.1f expirés (date limite) ; %.1f signés" % [
		float(totals["completed"]) / n, float(totals["failed_launch"]) / n,
		float(totals["failed_deadline"]) / n, float(totals["signed"]) / n])
	print("  tirs ratés : %d sur %d tirs ; reports météo : %.1f/partie" % [
		totals["failed_launch"], totals["failed_launch"] + totals["completed"], float(totals["scrubs"]) / n])
	print("  argent final : médiane %d, P10 %d, P90 %d" % [_percentile(money, 50), _percentile(money, 10), _percentile(money, 90)])
	print("  faillites : %d/%d ; 1er tir : jour %s (médiane, %d/%d parties)" % [
		totals["bankrupt"], n, str(_percentile(first_shots, 50)) if not first_shots.is_empty() else "-",
		first_shots.size(), n])
	if not rejections.is_empty():
		print("  COMMANDES REJETÉES (bug du bot ?) : ", JSON.stringify(rejections))
	if verbose:
		for i in n:
			var bot: BalanceBot = bots[i]
			print("  seed %2d : %d réussis, %d tirs ratés, %d expirés, argent %d%s" % [
				i + 1, bot.completed, bot.failed_launch, bot.failed_deadline, bot.state.money,
				" FAILLITE j%d" % bot.state.day if bot.state.game_over else ""])
		if n > 0:
			print("  --- journal de la seed 1 ---")
			for line in bots[0].log:
				print("  ", line)
	return not rejections.is_empty()


## Payback launcher index, or -1 if never. Fills `curve` (median diff per index).
func _payback(buy_all: Array, workshop: Array, verbose: bool) -> Dictionary:
	var max_n := 0
	for bot: BalanceBot in buy_all + workshop:
		max_n = maxi(max_n, bot.money_at_shot.size())
	var curve: Array = []  # {n, median, samples}
	for n in range(1, max_n + 1):
		var diffs: Array = []
		for i in buy_all.size():
			var a: BalanceBot = buy_all[i]
			var w: BalanceBot = workshop[i]
			if a.money_at_shot.size() >= n and w.money_at_shot.size() >= n:
				diffs.append(w.money_at_shot[n - 1] - a.money_at_shot[n - 1])
		if diffs.size() * 100 < buy_all.size() * MIN_SAMPLES_PCT:
			break
		curve.append({"n": n, "median": _percentile(diffs, 50), "samples": diffs.size()})
	var found := -1
	for k in range(curve.size() - 1, -1, -1):  # last index of the trailing run of >= 0
		if curve[k]["median"] >= 0:
			found = curve[k]["n"]
		else:
			break
	print("")
	print("[atelier vs tout acheter] écart d'argent médian au n-ième tir (workshop - buy_all)")
	var parts: Array[String] = []
	for point in curve:
		parts.append("%d:%+d" % [point["n"], point["median"]])
	print("  ", " ".join(PackedStringArray(parts)) if not parts.is_empty() else "(pas assez de tirs)")
	if verbose:
		for point in curve:
			print("  n=%d : %+d (sur %d seeds)" % [point["n"], point["median"], point["samples"]])
	print("  lanceur de rentabilisation : %s" % (str(found) if found > 0 else "jamais (sur %d lanceurs comparables)" % curve.size()))
	return {"found": found, "compared": curve.size()}


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

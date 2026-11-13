extends Control
## Main screen: displays the sim state and sends commands. No game rules here:
## every derived number comes from SimQueries / Simulation read-only queries.

const ORDER_QUANTITY := 10  # UI convenience (button size), not a balance value

const COLOR_DIM := "#7A8FA3"
const COLOR_OK := "#5BE49B"
const COLOR_WARN := "#FFB547"
const COLOR_DANGER := "#FF5C6C"
const COLOR_ACCENT := "#4FD1FF"

const REJECT_REASONS := {
	"insufficient_funds": "fonds insuffisants",
	"not_in_catalog": "hors catalogue",
	"invalid_quantity": "quantité invalide",
	"unknown_command": "commande inconnue",
	"not_buildable": "non constructible",
	"max_count_reached": "nombre maximum atteint",
	"max_technicians": "maximum de techniciens atteint",
	"staff_assigned": "techniciens encore affectés",
	"unknown_facility": "installation inconnue",
	"facility_not_ready": "installation pas prête",
	"no_slots": "aucun poste de travail",
	"too_many_for_slots": "plus que de postes disponibles",
	"not_enough_staff": "pas assez de techniciens libres",
	"unknown_recipe": "recette inconnue",
	"wrong_facility": "recette incompatible avec l'installation",
	"queue_full": "file d'attente pleine",
	"job_started": "job déjà démarré",
	"unknown_job": "job inconnu",
}

const BLOCK_REASONS := {
	"missing_inputs": "composants manquants",
	"hall_occupied": "hall occupé",
	"output_blocked": "entrepôt plein",
}

var session: GameSession

@onready var _day_label: Label = %DayLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _tabs: TabContainer = %Tabs
@onready var _facilities_box: VBoxContainer = %FacilitiesBox
@onready var _build_box: VBoxContainer = %BuildBox
@onready var _bom_box: VBoxContainer = %BomBox
@onready var _supply_box: VBoxContainer = %CatalogBox
@onready var _log: RichTextLabel = %LogText


func _ready() -> void:
	randomize()
	session = GameSession.new(DataLoader.load_default(), randi())
	session.changed.connect(_on_session_changed)
	%EndDayButton.pressed.connect(session.end_day)
	var titles := [tr("Installations"), tr("Construction & personnel"), tr("Nomenclature"), tr("Fournisseurs & stock")]
	for i in titles.size():
		_tabs.set_tab_title(i, titles[i])
	_log_line(tr("Nouvelle partie (seed %d)") % session.state.game_seed, COLOR_DIM)
	_refresh()


func _on_session_changed(events: Array) -> void:
	for event in events:
		_log_event(event)
	_refresh()


func _refresh() -> void:
	var state := session.state
	_day_label.text = tr("JOUR %d") % state.day
	_money_label.text = "%s cr" % _fmt(state.money)
	_money_label.theme_type_variation = &"DangerLabel" if state.money < 0 else &"Label"
	_rebuild(_facilities_box, _build_facilities)
	_rebuild(_build_box, _build_construction)
	_rebuild(_bom_box, _build_bom)
	_rebuild(_supply_box, _build_supply)


func _rebuild(box: VBoxContainer, builder: Callable) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	builder.call(box)


# --- Widget helpers ---------------------------------------------------------

func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _label(parent: Control, text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		label.theme_type_variation = variation
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, on_press: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func _send(command: Command) -> void:
	session.submit(command)


func _component_name(component_id: String) -> String:
	return session.data.components[component_id]["name"]


## The "type" field of facility events is overwritten by the event type
## (sim bug), so the name is looked up through the facility id.
func _facility_name(facility_id: int) -> String:
	for facility in session.state.facilities:
		if facility["id"] == facility_id:
			return session.data.facilities[facility["type"]]["name"]
	return "#%d" % facility_id


func _recipe_name(recipe_id: String) -> String:
	var output: Dictionary = session.data.recipes[recipe_id]["output"]
	if output.has("component_id"):
		return tr("Fabriquer : %s") % _component_name(output["component_id"])
	return tr("Assembler : %s") % String(output["launcher_model"]).to_upper()


# --- Installations tab ------------------------------------------------------

func _build_facilities(box: VBoxContainer) -> void:
	var state := session.state
	var data := session.data
	for facility in state.facilities:
		var info := SimQueries.facility_info(data, facility, state.day)
		var card := _card(box)
		var head := _row(card)
		_label(head, "#%d  %s" % [info["id"], info["name"]], &"HeadingLabel")
		if info["status"] == "building":
			_label(head, tr("EN CONSTRUCTION"), &"WarnLabel")
			_label(card, tr("Prête au jour %d (dans %d j)") % [info["ready_day"], info["days_until_ready"]], &"DimLabel")
			continue
		_label(head, tr("PRÊTE"), &"OkLabel")
		if int(data.facilities[info["type"]].get("storage_capacity", 0)) > 0:
			_label(card, tr("Entrepôt : %d / %d unités (toutes installations)") % [
				Simulation.storage_used(state, data), Simulation.storage_capacity(state, data)], &"DimLabel")
		if info["slots"] > 0:
			_build_staff_row(card, info)
			_build_jobs(card, info)
		if data.facilities[info["type"]].has("launcher_capacity"):
			_build_hall(card, facility)


func _build_staff_row(card: VBoxContainer, info: Dictionary) -> void:
	var row := _row(card)
	_label(row, tr("Techniciens : %d / %d postes") % [info["assigned"], info["slots"]])
	var free: int = SimQueries.staff_info(session.state, session.data)["free"]
	_button(row, "−", func() -> void: _send(Command.assign_staff(info["id"], info["assigned"] - 1)),
		info["assigned"] <= 0)
	_button(row, "+", func() -> void: _send(Command.assign_staff(info["id"], info["assigned"] + 1)),
		info["assigned"] >= info["slots"] or free <= 0)


func _build_jobs(card: VBoxContainer, info: Dictionary) -> void:
	if info["jobs"].is_empty():
		_label(card, tr("File vide"), &"DimLabel")
	for i in info["jobs"].size():
		var job: Dictionary = info["jobs"][i]
		var row := _row(card)
		var text := "%d. %s" % [i + 1, _recipe_name(job["recipe_id"])]
		_label(row, text)
		if job["started"]:
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(110, 16)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.value = job["percent"]
			bar.show_percentage = true
			row.add_child(bar)
			if job["blocked"] != "":
				_label(row, tr("bloqué : %s") % tr(BLOCK_REASONS.get(job["blocked"], job["blocked"])), &"WarnLabel")
			elif job["idle"]:
				_label(row, tr("à l'arrêt (aucun technicien)"), &"WarnLabel")
			else:
				_label(row, tr("%d j restants") % job["days_left"], &"DimLabel")
		else:
			var status := tr("en attente")
			if job["blocked"] != "":
				status = tr("bloqué : %s") % tr(BLOCK_REASONS.get(job["blocked"], job["blocked"]))
			_label(row, status, &"WarnLabel" if job["blocked"] != "" else &"DimLabel")
			_button(row, tr("Annuler"), func() -> void: _send(Command.cancel_job(job["id"])))
	var add_row := _row(card)
	for recipe_id in info["recipes"]:
		_button(add_row, "+ " + _recipe_name(recipe_id),
			func() -> void: _send(Command.queue_job(info["id"], recipe_id, 1)))


func _build_hall(card: VBoxContainer, facility: Dictionary) -> void:
	var occupancy := SimQueries.hall_occupancy(session.state, session.data, facility)
	_label(card, tr("Hall : %d / %d lanceur(s)") % [occupancy["used"], occupancy["capacity"]], &"DimLabel")
	for launcher in SimQueries.launchers_in(session.state, facility["id"]):
		_label(card, "▮ %s #%d" % [String(launcher["model"]).to_upper(), launcher["id"]], &"OkLabel")


# --- Construction & staff tab -----------------------------------------------

func _build_construction(box: VBoxContainer) -> void:
	var card := _card(box)
	_label(card, tr("CONSTRUIRE"), &"HeadingLabel")
	for option in SimQueries.build_options(session.state, session.data):
		var row := _row(card)
		_label(row, tr("%s : %s cr · %d j · entretien %s cr/j · %d restant(s)") % [
			option["name"], _fmt(option["cost"]), option["days"], _fmt(option["upkeep"]), option["remaining"]])
		_button(row, tr("Construire"), func() -> void: _send(Command.build(option["type"])),
			option["remaining"] <= 0)

	var staff := SimQueries.staff_info(session.state, session.data)
	var staff_card := _card(box)
	_label(staff_card, tr("PERSONNEL"), &"HeadingLabel")
	_label(staff_card, tr("Techniciens : %d embauchés (max %d) · %d affectés · %d libres") % [
		staff["hired"], staff["max"], staff["assigned"], staff["free"]])
	_label(staff_card, tr("Salaires : %s cr/j"
		) % _fmt(staff["daily_salaries"]), &"DimLabel")
	var row := _row(staff_card)
	_button(row, tr("Embaucher (%s cr)") % _fmt(staff["hire_cost"]), func() -> void: _send(Command.hire(1)))
	_button(row, tr("Licencier (%s cr)") % _fmt(staff["fire_cost"]), func() -> void: _send(Command.fire(1)),
		staff["free"] <= 0)


# --- Bill of materials tab --------------------------------------------------

func _build_bom(box: VBoxContainer) -> void:
	var data := session.data
	for model_id in data.launchers:
		var recipe_id: String = data.launchers[model_id]["recipe_id"]
		var card := _card(box)
		_label(card, tr("NOMENCLATURE %s") % String(model_id).to_upper(), &"HeadingLabel")
		var rows := SimQueries.bill_of_materials(session.state, data, recipe_id)
		_build_bom_grid(card, rows)
		_label(card, tr("Comparateur acheter / fabriquer"), &"HeadingLabel")
		var any := false
		for entry in rows:
			var cmp := SimQueries.buy_vs_make(session.state, data, entry["component_id"])
			if cmp["make"].is_empty():
				continue
			any = true
			_build_compare(card, cmp)
		if not any:
			_label(card, tr("(aucun composant fabricable)"), &"DimLabel")


func _build_bom_grid(card: VBoxContainer, rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	for title in [tr("Composant"), tr("Requis"), tr("Stock"), tr("Commande"), tr("Manque"), ""]:
		_grid_label(grid, title, &"DimLabel", title == tr("Composant"))
	for entry in rows:
		var missing: int = entry["missing"]
		var marker := "● " if missing > 0 else "○ "
		_grid_label(grid, marker + _component_name(entry["component_id"]),
			&"DangerLabel" if missing > 0 else &"OkLabel", true)
		_grid_label(grid, str(entry["required"]))
		_grid_label(grid, str(entry["in_stock"]))
		_grid_label(grid, str(entry["on_order"]))
		_grid_label(grid, str(missing) if missing > 0 else "–", &"DangerLabel" if missing > 0 else &"DimLabel")
		var offers := SimQueries.supplier_offers(session.data, entry["component_id"])
		if missing > 0 and not offers.is_empty():
			var offer: Dictionary = offers[0]
			var button := _button(grid, tr("Commander %d (%s)") % [missing, offer["supplier_name"]],
				func() -> void: _send(Command.order(offer["supplier_id"], entry["component_id"], missing)))
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			_grid_label(grid, "")


func _grid_label(grid: GridContainer, text: String, variation := &"", expand := false) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	return label


func _build_compare(card: VBoxContainer, cmp: Dictionary) -> void:
	_label(card, _component_name(cmp["component_id"]))
	var buy: Dictionary = cmp["buy"]
	if buy.is_empty():
		_label(card, tr("  Acheter : aucun fournisseur"), &"DimLabel")
	else:
		_label(card, tr("  Acheter : %s cr/u · %d j (%s)") % [
			_fmt(buy["unit_price"]), buy["lead_time_days"], buy["supplier_name"]])
	var make: Dictionary = cmp["make"]
	var cost := tr("matière %s cr") % _fmt(make["material_cost"]) if make["material_cost"] >= 0 else tr("matière indisponible")
	var duration := tr("%d j") % make["days"] if make["days"] > 0 else tr("à l'arrêt")
	if not make["ready"]:
		duration = tr("installation non construite")
	_label(card, tr("  Fabriquer : %s · %s") % [cost, duration])


# --- Suppliers & stock tab --------------------------------------------------

func _build_supply(box: VBoxContainer) -> void:
	var state := session.state
	var data := session.data
	var stock_card := _card(box)
	_label(stock_card, tr("STOCK"), &"HeadingLabel")
	_label(stock_card, tr("Occupation : %d / %d") % [
		Simulation.storage_used(state, data), Simulation.storage_capacity(state, data)], &"DimLabel")
	var lines: PackedStringArray = []
	for component_id in state.stock:
		if state.stock[component_id] > 0:
			lines.append("%s : %d" % [_component_name(component_id), state.stock[component_id]])
	_label(stock_card, "\n".join(lines) if lines else tr("(vide)"))

	var transit_card := _card(box)
	_label(transit_card, tr("EN TRANSIT"), &"HeadingLabel")
	var pending: PackedStringArray = []
	for order in state.pending_orders:
		pending.append(tr("#%d · %d × %s · arrivée jour %d") % [
			order["id"], order["quantity"], _component_name(order["component_id"]), order["arrival_day"]])
	_label(transit_card, "\n".join(pending) if pending else tr("(aucune)"))

	var catalog_card := _card(box)
	_label(catalog_card, tr("FOURNISSEURS"), &"HeadingLabel")
	for supplier_id in data.suppliers:
		var supplier: Dictionary = data.suppliers[supplier_id]
		_label(catalog_card, tr("%s · %d %% de retards") % [supplier["name"], roundi(supplier["delay_chance"] * 100)],
			&"DimLabel")
		for entry in supplier["catalog"]:
			_button(catalog_card, tr("Commander %d × %s : %s cr, %d j") % [
				ORDER_QUANTITY, _component_name(entry["component_id"]),
				_fmt(ORDER_QUANTITY * int(entry["unit_price"])), entry["lead_time_days"]],
				func() -> void: _send(Command.order(supplier_id, entry["component_id"], ORDER_QUANTITY)))


# --- Journal ----------------------------------------------------------------

func _log_event(e: Dictionary) -> void:
	var data := session.data
	match e["type"]:
		"order_placed":
			_log_line(tr("Commande #%d passée : -%s cr, arrivée jour %d") % [
				e["order_id"], _fmt(e["cost"]), e["arrival_day"]], COLOR_ACCENT)
		"command_rejected":
			_log_line(tr("Commande refusée : %s") % tr(REJECT_REASONS.get(e["reason"], e["reason"])), COLOR_WARN)
		"delivery_delayed":
			_log_line(tr("Commande #%d retardée de %d j par %s") % [
				e["order_id"], e["delay_days"], data.suppliers[e["supplier_id"]]["name"]], COLOR_WARN)
		"delivery_received":
			_log_line(tr("Commande #%d livrée : %d × %s") % [
				e["order_id"], e["quantity"], _component_name(e["component_id"])], COLOR_OK)
		"warehouse_full":
			_log_line(tr("Entrepôt plein : commande #%d en attente au portail") % e["order_id"], COLOR_WARN)
		"daily_costs":
			_log_line(tr("── Fin du jour %d · entretien -%s cr · salaires -%s cr ──") % [
				e["day"], _fmt(e["upkeep"]), _fmt(e.get("salaries", 0))], COLOR_DIM)
		"negative_balance":
			_log_line(tr("Trésorerie négative !"), COLOR_DANGER)
		"facility_build_started":
			_log_line(tr("Construction : %s (-%s cr), prête au jour %d") % [
				_facility_name(e["facility_id"]), _fmt(e["cost"]), e["ready_day"]], COLOR_ACCENT)
		"facility_built":
			_log_line(tr("Installation prête : %s") % _facility_name(e["facility_id"]), COLOR_OK)
		"staff_hired":
			_log_line(tr("Embauche : %d technicien(s), -%s cr") % [e["count"], _fmt(e["cost"])], COLOR_ACCENT)
		"staff_fired":
			_log_line(tr("Licenciement : %d technicien(s), -%s cr") % [e["count"], _fmt(e["cost"])], COLOR_ACCENT)
		"staff_assigned":
			_log_line(tr("Installation #%d : %d technicien(s) affecté(s)") % [e["facility_id"], e["count"]], COLOR_ACCENT)
		"job_queued":
			_log_line(tr("Job #%d en file : %s") % [e["job_id"], _recipe_name(e["recipe_id"])], COLOR_ACCENT)
		"job_cancelled":
			_log_line(tr("Job #%d annulé") % e["job_id"], COLOR_DIM)
		"job_started":
			_log_line(tr("Job #%d démarré (composants consommés)") % e["job_id"], COLOR_ACCENT)
		"job_blocked":
			var detail := ""
			if e["reason"] == "missing_inputs":
				var parts: PackedStringArray = []
				for component_id in e["missing"]:
					parts.append("%d × %s" % [e["missing"][component_id], _component_name(component_id)])
				detail = " (%s)" % ", ".join(parts)
			_log_line(tr("Job #%d bloqué : %s%s") % [
				e["job_id"], tr(BLOCK_REASONS.get(e["reason"], e["reason"])), detail], COLOR_WARN)
		"output_blocked":
			_log_line(tr("Job #%d : sortie bloquée, entrepôt plein") % e["job_id"], COLOR_WARN)
		"job_completed":
			_log_line(tr("Job #%d terminé") % e["job_id"], COLOR_OK)
		"launcher_assembled":
			_log_line(tr("Lanceur %s #%d assemblé") % [String(e["model"]).to_upper(), e["launcher_id"]], COLOR_OK)
		"offer_generated":
			_log_line(tr("Nouvelle offre de contrat #%d") % e["contract_id"], COLOR_DIM)
		"offer_expired":
			_log_line(tr("Offre de contrat #%d expirée") % e["contract_id"], COLOR_DIM)
		_:
			_log_line(str(e), COLOR_DIM)


func _log_line(text: String, color: String) -> void:
	_log.append_text("[color=%s]%s[/color]\n" % [color, text])


## 1234567 -> "1 234 567"
static func _fmt(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return ("-" if value < 0 else "") + out

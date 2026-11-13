extends Control
## Spike screen: displays the sim state and sends commands. No game rules here.

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
}

var session: GameSession

@onready var _day_label: Label = %DayLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _storage_label: Label = %StorageLabel
@onready var _stock_label: Label = %StockLabel
@onready var _catalog_box: VBoxContainer = %CatalogBox
@onready var _pending_label: Label = %PendingLabel
@onready var _log: RichTextLabel = %LogText


func _ready() -> void:
	randomize()
	session = GameSession.new(DataLoader.load_default(), randi())
	session.changed.connect(_on_session_changed)
	%EndDayButton.pressed.connect(session.end_day)
	_build_catalog()
	_log_line(tr("Nouvelle partie (seed %d)") % session.state.game_seed, COLOR_DIM)
	_refresh()


func _build_catalog() -> void:
	for supplier_id in session.data.suppliers:
		var supplier: Dictionary = session.data.suppliers[supplier_id]
		var name_label := Label.new()
		name_label.text = "%s · %d %% de retards" % [supplier["name"], roundi(supplier["delay_chance"] * 100)]
		name_label.theme_type_variation = &"DimLabel"
		_catalog_box.add_child(name_label)
		for entry in supplier["catalog"]:
			var component: Dictionary = session.data.components[entry["component_id"]]
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.text = tr("Commander %d × %s : %s cr, %d j") % [
				ORDER_QUANTITY, component["name"],
				_fmt(ORDER_QUANTITY * int(entry["unit_price"])), entry["lead_time_days"]]
			button.pressed.connect(func() -> void:
				session.submit(Command.order(supplier_id, entry["component_id"], ORDER_QUANTITY)))
			_catalog_box.add_child(button)


func _on_session_changed(events: Array) -> void:
	for event in events:
		_log_event(event)
	_refresh()


func _refresh() -> void:
	var state := session.state
	_day_label.text = tr("JOUR %d") % state.day
	_money_label.text = "%s cr" % _fmt(state.money)
	_money_label.modulate = Color(COLOR_DANGER) if state.money < 0 else Color.WHITE
	_storage_label.text = tr("Occupation : %d / %d") % [
		Simulation.storage_used(state, session.data), Simulation.storage_capacity(state, session.data)]

	var stock_lines: PackedStringArray = []
	for component_id in state.stock:
		stock_lines.append("%s : %d" % [session.data.components[component_id]["name"], state.stock[component_id]])
	_stock_label.text = "\n".join(stock_lines) if stock_lines else tr("(vide)")

	var pending_lines: PackedStringArray = []
	for order in state.pending_orders:
		pending_lines.append(tr("#%d · %d × %s · arrivée jour %d") % [
			order["id"], order["quantity"], session.data.components[order["component_id"]]["name"],
			order["arrival_day"]])
	_pending_label.text = "\n".join(pending_lines) if pending_lines else tr("(aucune)")


func _log_event(e: Dictionary) -> void:
	match e["type"]:
		"order_placed":
			_log_line(tr("Commande #%d passée : -%s cr, arrivée jour %d") % [
				e["order_id"], _fmt(e["cost"]), e["arrival_day"]], COLOR_ACCENT)
		"command_rejected":
			_log_line(tr("Commande refusée : %s") % REJECT_REASONS.get(e["reason"], e["reason"]), COLOR_WARN)
		"delivery_delayed":
			_log_line(tr("Commande #%d retardée de %d j par %s") % [
				e["order_id"], e["delay_days"], session.data.suppliers[e["supplier_id"]]["name"]], COLOR_WARN)
		"delivery_received":
			_log_line(tr("Commande #%d livrée : %d × %s") % [
				e["order_id"], e["quantity"], session.data.components[e["component_id"]]["name"]], COLOR_OK)
		"warehouse_full":
			_log_line(tr("Entrepôt plein : commande #%d en attente au portail") % e["order_id"], COLOR_WARN)
		"daily_costs":
			_log_line(tr("── Fin du jour %d · entretien -%s cr ──") % [e["day"], _fmt(e["upkeep"])], COLOR_DIM)
		"negative_balance":
			_log_line(tr("Trésorerie négative !"), COLOR_DANGER)
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

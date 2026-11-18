# scenes/main_hub/stats.gd
# Statistics dashboard displaying styled KPI cards, framed vector charts, and opponent history.
class_name StatsScreen extends Control

signal back_requested

const StatsServiceScript = preload("res://core/stats/stats_service.gd")
const VectorChartsScript = preload("res://core/stats/vector_charts.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")
const I18nServiceScript = preload("res://core/i18n/i18n_service.gd")

const GAME_DISPLAY_NAMES: Dictionary = {
	"uno": "Alle Ablegen!"
}

var _stats_svc: RefCounted

@onready var matches_card: PanelContainer = $VBoxContainer/SummaryRow/MatchesCard
@onready var wins_card: PanelContainer = $VBoxContainer/SummaryRow/WinsCard
@onready var winrate_card: PanelContainer = $VBoxContainer/SummaryRow/WinRateCard
@onready var streak_card: PanelContainer = $VBoxContainer/SummaryRow/StreakCard
@onready var playtime_card: PanelContainer = $VBoxContainer/SummaryRow/PlayTimeCard

@onready var matches_val: Label = $VBoxContainer/SummaryRow/MatchesCard/Box/Val
@onready var wins_val: Label = $VBoxContainer/SummaryRow/WinsCard/Box/Val
@onready var winrate_val: Label = $VBoxContainer/SummaryRow/WinRateCard/Box/Val
@onready var streak_val: Label = $VBoxContainer/SummaryRow/StreakCard/Box/Val
@onready var playtime_val: Label = $VBoxContainer/SummaryRow/PlayTimeCard/Box/Val

@onready var donut_host: CenterContainer = $VBoxContainer/ChartsRow/DonutPanel/DonutVBox/DonutBox
@onready var bar_host: CenterContainer = $VBoxContainer/ChartsRow/BarPanel/BarVBox/BarBox
@onready var opponents_list: VBoxContainer = $VBoxContainer/OpponentsPanel/OpponentsVBox/OpponentsScroll/OpponentsList

var _donut_chart: Control
var _bar_chart: Control

func _ready() -> void:
	theme = UIThemeScript.create_theme()
	_apply_kpi_card_styles()
	_stats_svc = StatsServiceScript.new()
	_init_charts()
	apply_language()

func _set_rel_text(rel_path: String, key: String) -> void:
	var n = get_node_or_null(rel_path)
	if n != null and "text" in n:
		n.text = I18nServiceScript.t(key)

func apply_language() -> void:
	_set_rel_text("VBoxContainer/HeaderPanel/Header/Title", "stats.title")
	_set_rel_text("VBoxContainer/HeaderPanel/Header/RefreshButton", "stats.refresh")
	_set_rel_text("VBoxContainer/HeaderPanel/Header/BackButton", "stats.back")
	_set_rel_text("VBoxContainer/SummaryRow/MatchesCard/Box/Title", "stats.matches")
	_set_rel_text("VBoxContainer/SummaryRow/WinsCard/Box/Title", "stats.wins")
	_set_rel_text("VBoxContainer/SummaryRow/WinRateCard/Box/Title", "stats.winrate")
	_set_rel_text("VBoxContainer/SummaryRow/StreakCard/Box/Title", "stats.streak")
	_set_rel_text("VBoxContainer/SummaryRow/PlayTimeCard/Box/Title", "stats.playtime")
	_set_rel_text("VBoxContainer/ChartsRow/DonutPanel/DonutVBox/ChartTitle", "stats.donut_title")
	_set_rel_text("VBoxContainer/ChartsRow/BarPanel/BarVBox/ChartTitle", "stats.bar_title")
	_set_rel_text("VBoxContainer/OpponentsPanel/OpponentsVBox/OpponentsLabel", "stats.opponents_title")
	if _stats_svc != null:
		refresh_stats()

func _apply_kpi_card_styles() -> void:
	var card_accents = {
		matches_card: Color(0.32, 0.74, 1.0, 0.55),
		wins_card: Color(0.24, 0.88, 0.52, 0.65),
		winrate_card: Color(0.28, 0.82, 1.0, 0.65),
		streak_card: UIThemeScript.COL_BORDER_GOLD,
		playtime_card: Color(0.68, 0.45, 1.0, 0.55)
	}
	for card in card_accents.keys():
		if card != null:
			card.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(UIThemeScript.COL_GLASS_SURFACE, card_accents[card], 14, 14))

func _init_charts() -> void:
	if donut_host and VectorChartsScript != null:
		_donut_chart = VectorChartsScript.DonutChart.new()
		_donut_chart.custom_minimum_size = Vector2(240, 230)
		donut_host.add_child(_donut_chart)

	if bar_host and VectorChartsScript != null:
		_bar_chart = VectorChartsScript.BarChart.new()
		_bar_chart.custom_minimum_size = Vector2(380, 230)
		bar_host.add_child(_bar_chart)

func refresh_stats() -> void:
	var summary = _stats_svc.get_summary_stats()

	var total_m = summary.get("total_matches", 0)
	var total_w = summary.get("total_wins", 0)
	var total_l = summary.get("total_losses", 0)
	var wr = summary.get("win_rate", 0.0)
	var cur_streak = summary.get("current_win_streak", 0)
	var best_streak = summary.get("best_win_streak", 0)
	var play_s = summary.get("total_play_time_seconds", 0)

	if matches_val:
		matches_val.text = str(total_m)
	if wins_val:
		wins_val.text = str(total_w)
	if winrate_val:
		winrate_val.text = "%.1f%%" % wr
	if streak_val:
		streak_val.text = I18nServiceScript.t("stats.streak_fmt", {"cur": cur_streak, "best": best_streak})
	if playtime_val:
		var mins = play_s / 60
		playtime_val.text = "%d min" % mins

	# Update Donut Chart
	if _donut_chart:
		_donut_chart.set("empty_label_1", I18nServiceScript.t("stats.donut_empty_1"))
		_donut_chart.set("empty_label_2", I18nServiceScript.t("stats.donut_empty_2"))
		_donut_chart.set("center_title", "%.0f%%" % wr)
		_donut_chart.set("center_subtitle", I18nServiceScript.t("stats.winrate").replace("📈 ", ""))
		_donut_chart.set("chart_data", [
			{"label": I18nServiceScript.t("stats.wins_short"), "value": float(total_w), "color": Color(0.22, 0.85, 0.48)},
			{"label": I18nServiceScript.t("stats.losses_short"), "value": float(total_l), "color": Color(0.92, 0.30, 0.34)}
		])

	# Update Bar Chart with games breakdown
	if _bar_chart:
		_bar_chart.set("empty_message", I18nServiceScript.t("stats.bar_empty"))
		var games: Dictionary = _stats_svc._data.get("games", {})
		var bar_data: Array = []
		if games.is_empty():
			bar_data.append({"label": I18nServiceScript.t("stats.game_uno"), "value": float(total_m), "color": Color(0.28, 0.72, 0.98)})
		else:
			for g_id in games:
				var m_count = float(games[g_id].get("total_matches", 0))
				var g_label = I18nServiceScript.t("stats.game_uno") if str(g_id).to_lower() == "uno" else str(GAME_DISPLAY_NAMES.get(str(g_id).to_lower(), str(g_id).to_upper()))
				bar_data.append({"label": g_label, "value": m_count, "color": Color(0.28, 0.72, 0.98)})
		_bar_chart.set("chart_data", bar_data)

	# Populate Opponents List
	if opponents_list:
		for child in opponents_list.get_children():
			child.queue_free()

		var opps: Dictionary = _stats_svc._data.get("opponents", {})
		if opps.is_empty():
			var empty_lbl = Label.new()
			empty_lbl.text = I18nServiceScript.t("stats.no_opponents")
			empty_lbl.modulate = Color(0.68, 0.75, 0.86)
			opponents_list.add_child(empty_lbl)
		else:
			for opp_id in opps:
				var opp = opps[opp_id]
				var pill = PanelContainer.new()
				pill.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.06, 0.09, 0.16, 0.85), Color(0.28, 0.72, 1.0, 0.25), 10, 8))
				var row = HBoxContainer.new()
				var lbl_id = Label.new()
				lbl_id.text = "Spieler " + str(opp.get("opponent_uuid", opp_id)).substr(0, 8) + "..."
				lbl_id.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(lbl_id)

				var lbl_stat = Label.new()
				lbl_stat.text = "%d Runden • %d Siege (%0.1f%%)" % [
					opp.get("matches_against", 0),
					opp.get("wins_against", 0),
					opp.get("win_rate", 0.0)
				]
				lbl_stat.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
				row.add_child(lbl_stat)
				pill.add_child(row)
				opponents_list.add_child(pill)

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_refresh_pressed() -> void:
	refresh_stats()

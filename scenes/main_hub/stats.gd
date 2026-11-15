# scenes/main_hub/stats.gd
# Statistics dashboard displaying summary cards, vector charts, and opponent history.
class_name StatsScreen extends Control

signal back_requested

const StatsServiceScript = preload("res://core/stats/stats_service.gd")
const VectorChartsScript = preload("res://core/stats/vector_charts.gd")

var _stats_svc: RefCounted

@onready var matches_val: Label = $VBoxContainer/SummaryRow/MatchesCard/Box/Val
@onready var wins_val: Label = $VBoxContainer/SummaryRow/WinsCard/Box/Val
@onready var winrate_val: Label = $VBoxContainer/SummaryRow/WinRateCard/Box/Val
@onready var streak_val: Label = $VBoxContainer/SummaryRow/StreakCard/Box/Val
@onready var playtime_val: Label = $VBoxContainer/SummaryRow/PlayTimeCard/Box/Val

@onready var donut_host: CenterContainer = $VBoxContainer/ChartsRow/DonutBox
@onready var bar_host: CenterContainer = $VBoxContainer/ChartsRow/BarBox
@onready var opponents_list: VBoxContainer = $VBoxContainer/OpponentsScroll/OpponentsList

var _donut_chart: Control
var _bar_chart: Control

func _ready() -> void:
	_stats_svc = StatsServiceScript.new()
	_init_charts()
	refresh_stats()

func _init_charts() -> void:
	if donut_host and VectorChartsScript != null:
		_donut_chart = VectorChartsScript.DonutChart.new()
		_donut_chart.custom_minimum_size = Vector2(220, 220)
		donut_host.add_child(_donut_chart)

	if bar_host and VectorChartsScript != null:
		_bar_chart = VectorChartsScript.BarChart.new()
		_bar_chart.custom_minimum_size = Vector2(360, 220)
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
		streak_val.text = "%d (Best: %d)" % [cur_streak, best_streak]
	if playtime_val:
		var mins = play_s / 60
		playtime_val.text = "%d min" % mins

	# Update Donut Chart
	if _donut_chart:
		_donut_chart.set("center_title", "%.0f%%" % wr)
		_donut_chart.set("center_subtitle", "Win Rate")
		_donut_chart.set("chart_data", [
			{"label": "Wins", "value": float(total_w), "color": Color(0.2, 0.8, 0.4)},
			{"label": "Losses", "value": float(total_l), "color": Color(0.9, 0.25, 0.25)}
		])

	# Update Bar Chart with games breakdown
	if _bar_chart:
		var games: Dictionary = _stats_svc._data.get("games", {})
		var bar_data: Array = []
		if games.is_empty():
			bar_data.append({"label": "UNO", "value": float(total_m), "color": Color(0.3, 0.6, 0.9)})
		else:
			for g_id in games:
				var m_count = float(games[g_id].get("total_matches", 0))
				bar_data.append({"label": g_id.to_upper(), "value": m_count, "color": Color(0.3, 0.6, 0.9)})
		_bar_chart.set("chart_data", bar_data)

	# Populate Opponents List
	if opponents_list:
		for child in opponents_list.get_children():
			child.queue_free()

		var opps: Dictionary = _stats_svc._data.get("opponents", {})
		if opps.is_empty():
			var empty_lbl = Label.new()
			empty_lbl.text = "No opponent matches recorded yet."
			empty_lbl.modulate = Color(0.6, 0.6, 0.65)
			opponents_list.add_child(empty_lbl)
		else:
			for opp_id in opps:
				var opp = opps[opp_id]
				var row = HBoxContainer.new()
				var lbl_id = Label.new()
				lbl_id.text = str(opp.get("opponent_uuid", opp_id)).substr(0, 8) + "..."
				lbl_id.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(lbl_id)

				var lbl_stat = Label.new()
				lbl_stat.text = "%d Matches | %d Wins (%0.1f%%)" % [
					opp.get("matches_against", 0),
					opp.get("wins_against", 0),
					opp.get("win_rate", 0.0)
				]
				row.add_child(lbl_stat)
				opponents_list.add_child(row)

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_refresh_pressed() -> void:
	refresh_stats()

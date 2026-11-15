# core/stats/vector_charts.gd
# Pure GDScript vector charts (DonutChart and BarChart) rendered via CanvasItem._draw().
class_name VectorCharts extends Control

# ==============================================================================
# Vector Donut Chart
# ==============================================================================
class DonutChart extends Control:
	var chart_data: Array = [] : set = _set_chart_data
	var inner_radius_ratio: float = 0.6
	var center_title: String = ""
	var center_subtitle: String = ""
	var animation_progress: float = 1.0
	var start_angle: float = -PI / 2.0

	func _set_chart_data(p_data: Array) -> void:
		chart_data = p_data
		queue_redraw()

	func get_total_value() -> float:
		var sum: float = 0.0
		for item in chart_data:
			if item is Dictionary and item.has("value"):
				sum += maxf(0.0, float(item["value"]))
		return sum

	func calculate_slice_angles() -> Array[float]:
		var total = get_total_value()
		var angles: Array[float] = []
		if total <= 0.0:
			return angles
		for item in chart_data:
			var val = maxf(0.0, float(item.get("value", 0.0)))
			angles.append((val / total) * TAU)
		return angles

	func _draw() -> void:
		var center = size / 2.0
		var min_dim = minf(size.x, size.y)
		var outer_r = maxf(10.0, (min_dim / 2.0) - 8.0)
		var inner_r = outer_r * inner_radius_ratio
		var thickness = outer_r - inner_r
		var mid_r = (outer_r + inner_r) / 2.0

		var total = get_total_value()

		if total <= 0.0 or chart_data.is_empty():
			# Empty state: muted gray ring
			draw_arc(center, mid_r, 0.0, TAU, 48, Color(0.3, 0.3, 0.35, 0.4), thickness, true)
			var font = ThemeDB.fallback_font
			var font_size = maxi(12, int(min_dim * 0.08))
			var msg = "No Data"
			var text_size = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, center - Vector2(text_size.x / 2.0, -text_size.y / 3.0), msg, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.6, 0.6, 0.65))
			return

		var current_ang = start_angle
		var clamped_anim = clampf(animation_progress, 0.0, 1.0)

		for item in chart_data:
			var val = maxf(0.0, float(item.get("value", 0.0)))
			if val <= 0.0:
				continue
			var slice_sweep = (val / total) * TAU * clamped_anim
			var col: Color = item.get("color", Color.WHITE)
			draw_arc(center, mid_r, current_ang, current_ang + slice_sweep, 36, col, thickness, true)
			current_ang += slice_sweep

		# Center typography
		var font = ThemeDB.fallback_font
		if font != null:
			if not center_title.is_empty():
				var t_size = maxi(14, int(min_dim * 0.12))
				var str_size = font.get_string_size(center_title, HORIZONTAL_ALIGNMENT_CENTER, -1, t_size)
				draw_string(font, center - Vector2(str_size.x / 2.0, str_size.y * 0.1), center_title, HORIZONTAL_ALIGNMENT_CENTER, -1, t_size, Color.WHITE)
			if not center_subtitle.is_empty():
				var s_size = maxi(10, int(min_dim * 0.07))
				var str_size2 = font.get_string_size(center_subtitle, HORIZONTAL_ALIGNMENT_CENTER, -1, s_size)
				draw_string(font, center + Vector2(-str_size2.x / 2.0, str_size2.y * 1.2), center_subtitle, HORIZONTAL_ALIGNMENT_CENTER, -1, s_size, Color(0.7, 0.7, 0.75))

# ==============================================================================
# Vector Bar Chart
# ==============================================================================
class BarChart extends Control:
	var chart_data: Array = [] : set = _set_chart_data
	var show_grid: bool = true
	var show_values: bool = true
	var bar_spacing: float = 8.0
	var margin: Rect2 = Rect2(30, 20, 20, 25)
	var animation_progress: float = 1.0

	func _set_chart_data(p_data: Array) -> void:
		chart_data = p_data
		queue_redraw()

	func get_max_value() -> float:
		var max_v: float = 0.0
		for item in chart_data:
			if item is Dictionary and item.has("value"):
				max_v = maxf(max_v, float(item["value"]))
		return max_v if max_v > 0.0 else 1.0

	func calculate_normalized_heights(plot_height: float) -> Array[float]:
		var max_v = get_max_value()
		var heights: Array[float] = []
		for item in chart_data:
			var val = maxf(0.0, float(item.get("value", 0.0)))
			heights.append(val / max_v)
		return heights

	func _draw() -> void:
		var plot_x = margin.position.x
		var plot_y = margin.position.y
		var plot_w = maxf(10.0, size.x - margin.position.x - margin.size.x)
		var plot_h = maxf(10.0, size.y - margin.position.y - margin.size.y)
		var baseline = plot_y + plot_h

		# Gridlines
		if show_grid:
			var grid_steps = 4
			for i in range(grid_steps + 1):
				var gy = baseline - (plot_h * float(i) / float(grid_steps))
				draw_line(Vector2(plot_x, gy), Vector2(plot_x + plot_w, gy), Color(0.3, 0.35, 0.4, 0.3), 1.0)

		# Baseline axis
		draw_line(Vector2(plot_x, baseline), Vector2(plot_x + plot_w, baseline), Color(0.6, 0.65, 0.7, 0.8), 1.5)

		if chart_data.is_empty():
			return

		var count = chart_data.size()
		var total_spacing = bar_spacing * float(count - 1)
		var bar_w = maxf(4.0, (plot_w - total_spacing) / float(count))
		var max_v = get_max_value()
		var clamped_anim = clampf(animation_progress, 0.0, 1.0)
		var font = ThemeDB.fallback_font

		for i in range(count):
			var item = chart_data[i]
			var val = maxf(0.0, float(item.get("value", 0.0)))
			var norm = val / max_v
			var bar_h = norm * plot_h * clamped_anim
			var bx = plot_x + i * (bar_w + bar_spacing)
			var by = baseline - bar_h

			var col: Color = item.get("color", Color(0.3, 0.6, 0.9))
			draw_rect(Rect2(bx, by, bar_w, bar_h), col, true)

			# Values and Labels
			if font != null:
				if show_values and val > 0:
					var v_str = str(int(val) if val == floorf(val) else "%.1f" % val)
					var v_size = font.get_string_size(v_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
					draw_string(font, Vector2(bx + (bar_w - v_size.x) / 2.0, by - 4), v_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

				var label_str = str(item.get("label", ""))
				if not label_str.is_empty():
					var l_size = font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
					draw_string(font, Vector2(bx + (bar_w - l_size.x) / 2.0, baseline + 14), label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.75, 0.75, 0.8))

# ==============================================================================
# Container Helper
# ==============================================================================
var donut: DonutChart
var bar: BarChart

func _init() -> void:
	donut = DonutChart.new()
	bar = BarChart.new()
	add_child(donut)
	add_child(bar)

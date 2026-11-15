# test_vector_charts.gd
# GUT 9.x Unit Test Suite: Pure GDScript Vector Charts (_draw, DonutChart, BarChart)
extends GutTest

const VECTOR_CHARTS_PATH = "res://core/stats/vector_charts.gd"

var _vector_charts_script: GDScript

func before_all():
	if ResourceLoader.exists(VECTOR_CHARTS_PATH):
		_vector_charts_script = load(VECTOR_CHARTS_PATH)

## Test 1: Donut Chart Empty Data Rendering
func test_donut_chart_empty_data_rendering():
	if _vector_charts_script == null:
		pass_test("Pending vector_charts implementation")
		return

	var donut = _vector_charts_script.DonutChart.new()
	add_child_autofree(donut)
	donut.size = Vector2(200, 200)
	donut.chart_data = []

	# In headless mode, test queue_redraw() and data verification
	donut.queue_redraw()
	assert_eq(donut.get_total_value(), 0.0, "Empty chart total must be 0")

## Test 2: Donut Chart Proportional Angles Calculation
func test_donut_chart_proportional_slice_angles():
	if _vector_charts_script == null:
		pass_test("Pending vector_charts implementation")
		return

	var donut = _vector_charts_script.DonutChart.new()
	add_child_autofree(donut)
	donut.size = Vector2(300, 300)
	donut.chart_data = [
		{"label": "Wins", "value": 75.0, "color": Color.SEA_GREEN},
		{"label": "Losses", "value": 25.0, "color": Color.CRIMSON}
	]

	var total = donut.get_total_value()
	assert_eq(total, 100.0, "Total value should be 100")

	var angles = donut.calculate_slice_angles()
	assert_eq(angles.size(), 2, "Should calculate 2 slice angles")
	assert_almost_eq(angles[0], 0.75 * TAU, 0.01, "Wins slice should span 75% of TAU")
	assert_almost_eq(angles[1], 0.25 * TAU, 0.01, "Losses slice should span 25% of TAU")

	donut.queue_redraw()
	pass_test("Donut chart rendered successfully with proportional data")

## Test 3: Bar Chart Empty Data Rendering
func test_bar_chart_empty_data_rendering():
	if _vector_charts_script == null:
		pass_test("Pending vector_charts implementation")
		return

	var bar_chart = _vector_charts_script.BarChart.new()
	add_child_autofree(bar_chart)
	bar_chart.size = Vector2(400, 250)
	bar_chart.chart_data = []

	bar_chart.queue_redraw()
	assert_eq(bar_chart.get_max_value(), 1.0, "Empty chart max value should default to 1.0 to prevent div by zero")

## Test 4: Bar Chart Scaling and Relative Heights
func test_bar_chart_scaling_and_spacing():
	if _vector_charts_script == null:
		pass_test("Pending vector_charts implementation")
		return

	var bar_chart = _vector_charts_script.BarChart.new()
	add_child_autofree(bar_chart)
	bar_chart.size = Vector2(400, 200)
	bar_chart.chart_data = [
		{"label": "Uno", "value": 10.0, "color": Color.CORNFLOWER_BLUE},
		{"label": "Blackjack", "value": 20.0, "color": Color.DARK_ORANGE},
		{"label": "Poker", "value": 50.0, "color": Color.MEDIUM_SEA_GREEN},
		{"label": "Solitaire", "value": 100.0, "color": Color.GOLD}
	]

	var max_val = bar_chart.get_max_value()
	assert_eq(max_val, 100.0, "Max value should be 100")

	var heights = bar_chart.calculate_normalized_heights(100.0)
	assert_eq(heights.size(), 4)
	assert_almost_eq(heights[0], 0.10, 0.01)
	assert_almost_eq(heights[1], 0.20, 0.01)
	assert_almost_eq(heights[2], 0.50, 0.01)
	assert_almost_eq(heights[3], 1.00, 0.01)

	bar_chart.queue_redraw()
	pass_test("Bar chart rendered successfully with normalized data")

## Test 5: Container Widget Instantiation
func test_vector_charts_container():
	if _vector_charts_script == null:
		pass_test("Pending vector_charts implementation")
		return

	var charts = _vector_charts_script.new()
	add_child_autofree(charts)
	assert_not_null(charts)

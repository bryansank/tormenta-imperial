extends GdUnitTestSuite
## El cartel de estado de los edificios en 2D no se pisa con el de al lado
## (feat/vista2d-y-prologo): en reposo es una ficha compacta ("Zzz" y el
## pictograma del motivo) que nunca sale de la huella de su edificio; el texto
## entero sale solo con el edificio seleccionado.

const Badge2D := preload("res://scripts/view2d/StatusBadge2D.gd")
const Badge3D := preload("res://scripts/buildings/BuildingStatusBadge.gd")

const REASONS := ["unstaffed", "workers_off", "no_road", "no_vein", "ruined", "full", "other"]

func test_the_chip_never_grows_past_its_footprint() -> void:
	var w: float = Badge2D.chip_width(Badge3D.Status.IDLE)
	assert_float(w).is_greater(0.0)
	# Con cualquier zoom (escala de rotulo), la ficha cabe en su huella, asi que
	# dos vecinos parados no se tocan.
	for inv in [0.6, 1.0, 1.8, 3.0, 6.0]:
		for fp_w in [64.0, 96.0, 32.0]:
			var s: float = Badge2D.chip_scale(inv, w, fp_w)
			assert_float(s * w).is_less_equal(fp_w * Badge2D.CHIP_MAX_FRACTION + 0.001)
			assert_float(s).is_less_equal(inv)

func test_a_chip_that_fits_keeps_the_label_scale() -> void:
	var w: float = Badge2D.chip_width(Badge3D.Status.IDLE)
	assert_float(Badge2D.chip_scale(0.5, w, 640.0)).is_equal(0.5)

func test_the_core_at_rest_and_sites_show_no_badge() -> void:
	assert_bool(Badge2D.shows(Badge3D.Status.IDLE, "idle")).is_false()
	assert_bool(Badge2D.shows(Badge3D.Status.IDLE, "construction")).is_false()
	assert_bool(Badge2D.shows(Badge3D.Status.NONE, "")).is_false()
	assert_bool(Badge2D.shows(Badge3D.Status.IDLE, "unstaffed")).is_true()
	assert_bool(Badge2D.shows(Badge3D.Status.WORKING, "")).is_true()

func test_every_reason_chip_draws() -> void:
	var drawn := [0]
	var canvas := Node2D.new()
	canvas.draw.connect(func():
		for r in REASONS:
			Badge2D.draw_chip(canvas, String(r))
			Badge2D.draw_reason_glyph(canvas, String(r), Rect2(0, 0, 11, 11), Color.WHITE)
		drawn[0] += 1)
	add_child(canvas)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(drawn[0]).is_greater(0)
	canvas.queue_free()

func test_selecting_expands_and_releasing_folds_it_back() -> void:
	var badge: Node2D = auto_free(Badge2D.new())
	add_child(badge)
	assert_bool(badge.is_expanded()).is_false()
	badge.set_expanded(true)
	assert_bool(badge.is_expanded()).is_true()
	badge.set_expanded(false)
	assert_bool(badge.is_expanded()).is_false()

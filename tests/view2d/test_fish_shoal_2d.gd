extends GdUnitTestSuite
## Los bancos de peces en 2D se leen como peces en el agua
## (feat/vista2d-y-prologo): la isla abre una cala en su arena sobre cada banco
## (la orilla se estrecha ahi) y el banco ya no es un ovalo con borde.

const Island2D := preload("res://scripts/view2d/Island2D.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

func test_a_cove_covers_the_shoal_and_reaches_the_sea() -> void:
	var center := Vector2(300, 200)
	var half := Vector2(32, 32)
	var dir := Vector2.DOWN
	var cove: PackedVector2Array = Island2D.cove_polygon(center, half, dir, 100.0, 32.0)
	assert_int(cove.size()).is_greater(3)
	assert_bool(Geometry2D.is_point_in_polygon(center, cove)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(center + dir * 100.0, cove)).is_true()
	# Las esquinas del banco tambien quedan dentro (con margen).
	for c in [center - half * 0.95, center + half * 0.95, center + Vector2(half.x, -half.y) * 0.95, center + Vector2(-half.x, half.y) * 0.95]:
		assert_bool(Geometry2D.is_point_in_polygon(c, cove)).is_true()
	# Y no se mete hacia tierra mas alla del margen.
	assert_bool(Geometry2D.is_point_in_polygon(center - dir * (half.y + 32.0), cove)).is_false()

func test_the_sand_opens_over_a_shoal() -> void:
	var island: Node2D = auto_free(Island2D.new())
	add_child(island)
	# Un banco en plena playa: un punto de la mitad de la franja de arena.
	var on_sand: Vector2 = island.polygon_px(Island2D.SHORE_WIDTH * 0.5)[0]
	var world := on_sand / View2D.PX_PER_UNIT
	island.set_sand_holes([Vector4(world.x, world.y, 2.0, 2.0)])
	assert_int(island.coves().size()).is_equal(1)
	var covered := false
	for p in island._shore_ring(Island2D.SHORE_WIDTH - 0.8):
		if Geometry2D.is_point_in_polygon(on_sand, p):
			covered = true
	assert_bool(covered).is_false()
	# Sin bancos, la arena vuelve entera.
	island.set_sand_holes([])
	assert_int(island.coves().size()).is_equal(0)
	var back := false
	for p in island._shore_ring(Island2D.SHORE_WIDTH - 0.8):
		if Geometry2D.is_point_in_polygon(on_sand, p):
			back = true
	assert_bool(back).is_true()

func test_the_shoal_draws_with_fish_at_every_size() -> void:
	var drawn := [0]
	var canvas := Node2D.new()
	canvas.draw.connect(func():
		for size in [Vector2(64, 64), Vector2(96, 64), Vector2(64, 96)]:
			for sv in 3:
				Art.draw_deposit(canvas, "fish_shoal", size, sv)
		drawn[0] += 1)
	add_child(canvas)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(drawn[0]).is_greater(0)
	canvas.queue_free()

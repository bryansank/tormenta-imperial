extends "res://scripts/map/MapGenerator.gd"
## MapGenerator de la vista 2D. Hereda TODO de MapGenerator —sorteo, registro en
## la rejilla, usos, agotamiento, guardado, regla de alcance— y solo cambia los
## cinco ganchos de dibujo: el yacimiento es un Deposit2D (maqueta horneada, con su etapa de agotamiento) y el aviso de
## "agotado" es una etiqueta 2D. Un save hecho en 3D trae los mismos yacimientos
## en las mismas celdas.

const Deposit2D := preload("res://scripts/view2d/Deposit2D.gd")
const FloatingText2D := preload("res://scripts/view2d/FloatingText2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

func _make_container() -> Node:
	var n := Node2D.new()
	n.z_index = 0
	return n

## Las marcas de las amenazas de costa (feat/amenazas-costa), dibujadas en 2D.
func _make_threat_marks() -> Node:
	return preload("res://scripts/view2d/ThreatMarks2D.gd").new()

func _build_deposit_node(deposit_id: String, info: Dictionary, dep_size: Vector2i) -> Node:
	var node: Node2D = Deposit2D.new()
	node.setup(deposit_id, Tr.t(info["display_name"]), dep_size)
	return node

func _place_deposit_node(root: Node, cell: Vector2i, dep_size: Vector2i) -> void:
	(root as Node2D).global_position = View2D.footprint_center_px(cell, dep_size)
	root.set("seed_val", DepositMesh.seed_for(cell))
	(root as Node2D).queue_redraw()

## La etapa de agotamiento (la misma regla que la 3D): el dibujo pierde arboles,
## cristales o mineral al minarlo. Solo se repinta si la etapa cambio.
func _refresh_deposit_look(root: Node) -> void:
	var stage := DepositMesh.stage_of(int(root.get_meta("uses_remaining", 1)), int(root.get_meta("max_uses", 1)))
	if int(root.get_meta("look_stage", -1)) == stage:
		return
	root.set_meta("look_stage", stage)
	root.set("stage", stage)
	(root as Node2D).queue_redraw()

## La arena no tapa los bancos, tambien en 2D (feat/vista2d-y-prologo): la isla
## 2D se llama "Island" (no "IslandGenerator") y abre una cala en su arena sobre
## cada banco (Island2D.set_sand_holes, mismos rectangulos de mundo).
func _push_sand_holes() -> void:
	_sand_holes_queued = false
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	var island := get_tree().current_scene.get_node_or_null("Island")
	if island != null and island.has_method("set_sand_holes"):
		island.set_sand_holes(sea_deposit_rects())

func _show_depleted_text(node: Node) -> void:
	FloatingText2D.spawn(node as Node2D, Tr.t("LBL_DEPOSIT_DEPLETED"), Color(0.8, 0.3, 0.2))

extends "res://scripts/map/MapGenerator.gd"
## MapGenerator de la vista 2D. Hereda TODO de MapGenerator —sorteo, registro en
## la rejilla, usos, agotamiento, guardado, regla de alcance— y solo cambia los
## cuatro ganchos de dibujo: el yacimiento es un Deposit2D plano y el aviso de
## "agotado" es una etiqueta 2D. Un save hecho en 3D trae los mismos yacimientos
## en las mismas celdas.

const Deposit2D := preload("res://scripts/view2d/Deposit2D.gd")
const FloatingText2D := preload("res://scripts/view2d/FloatingText2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

func _make_container() -> Node:
	var n := Node2D.new()
	n.z_index = 0
	return n

func _build_deposit_node(deposit_id: String, info: Dictionary, dep_size: Vector2i) -> Node:
	var node: Node2D = Deposit2D.new()
	node.setup(deposit_id, Tr.t(info["display_name"]), dep_size)
	return node

func _place_deposit_node(root: Node, cell: Vector2i, dep_size: Vector2i) -> void:
	(root as Node2D).global_position = View2D.footprint_center_px(cell, dep_size)
	root.set("seed_val", cell.x * 73856093 ^ cell.y * 19349663)
	(root as Node2D).queue_redraw()

func _show_depleted_text(node: Node) -> void:
	FloatingText2D.spawn(node as Node2D, Tr.t("LBL_DEPOSIT_DEPLETED"), Color(0.8, 0.3, 0.2))

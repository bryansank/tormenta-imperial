extends RefCounted
## Encuentra en pantalla el control real del que habla una ayuda o un paso del
## tutorial: el boton CONSTRUIR, el ☰, el objetivo, una tarjeta de la lista de
## edificios... Devuelve el Control (o su rectangulo) o null si ahora no esta.
##
## Lo que busca lo buscan por nombres estables, no por rutas de escena, porque
## esos controles son de otros paneles y cambian de sitio:
##   - grupo "hud_build_button" / "hud_menu_button" (lo pone quien crea el boton);
##   - si no hay grupo, HudRegistry (ConstructionMenu.button, NotificationPanel.objective...);
##   - como ultimo recurso, el nodo del panel por su nombre en Main.tscn.
## Una busqueda que no encuentra nada no es un error: el tutorial sigue con su
## texto y sin foco.

const BUILD_GROUP := "hud_build_button"
const MENU_GROUP := "hud_menu_button"
const View2D := preload("res://scripts/view2d/View2D.gd")

## El control de `target_name`, visible, o null.
static func control(tree: SceneTree, target_name: String) -> Control:
	var c := _find(tree, target_name)
	if c != null and is_instance_valid(c) and c.is_visible_in_tree():
		return c
	return null

## Rectangulo en coordenadas del lienzo (las de un CanvasLayer sin transformar),
## o un Rect2 vacio si no esta.
static func rect(tree: SceneTree, target_name: String) -> Rect2:
	var c := control(tree, target_name)
	if c == null:
		return Rect2()
	return c.get_global_rect()

static func _find(tree: SceneTree, target_name: String) -> Control:
	if tree == null or target_name == "":
		return null
	match target_name:
		"build_button":
			var g := _first_in_group(tree, BUILD_GROUP)
			if g != null:
				return g
			return HudRegistry.control_of("ConstructionMenu.button")
		"menu_button":
			var m := _first_in_group(tree, MENU_GROUP)
			if m != null:
				return m
			var market := _scene_node(tree, "MarketPanel")
			if market != null:
				var t: Variant = market.get("_sidebar_toggle")
				if t is Control:
					return t
			return null
		"objective":
			return HudRegistry.control_of("NotificationPanel.objective")
		"resources":
			return HudRegistry.control_of("ResourceHUD")
		"status":
			return HudRegistry.control_of("NotificationPanel.status")
		"storm":
			return HudRegistry.control_of("StormHUD")
	if target_name.begins_with("card:"):
		return building_card(tree, target_name.substr(5))
	return null

static func _first_in_group(tree: SceneTree, group: String) -> Control:
	for n in tree.get_nodes_in_group(group):
		if n is Control and is_instance_valid(n):
			return n
	return null

static func _scene_node(tree: SceneTree, node_name: String) -> Node:
	var scene := tree.current_scene
	if scene != null:
		var n := scene.get_node_or_null(node_name)
		if n != null:
			return n
	return tree.root.find_child(node_name, true, false)

## La tarjeta de un edificio dentro de la lista de CONSTRUIR. Las tarjetas no
## tienen nombre: se busca el PanelContainer cuyo texto es el nombre del edificio
## (el que lee el jugador). Si ConstructionMenu les pone la meta "building_id",
## se usa esa, que no depende del idioma.
static func building_card(tree: SceneTree, building_id: String) -> Control:
	var menu := _scene_node(tree, "ConstructionMenu")
	if menu == null:
		return null
	var display := ""
	var path := "res://data/buildings/%s.tres" % building_id
	if ResourceLoader.exists(path):
		var data: Resource = load(path)
		if data != null and data.has_method("get_display_name"):
			display = String(data.get_display_name())
	return _search_card(menu, building_id, display)

static func _search_card(node: Node, building_id: String, display: String) -> Control:
	for child in node.get_children():
		if child is PanelContainer and (child as Control).is_visible_in_tree():
			if child.has_meta("building_id") and String(child.get_meta("building_id")) == building_id:
				return child
			if display != "" and _has_label(child, display):
				# La tarjeta de la rejilla, no el detalle: el detalle tiene mas
				# texto que el nombre y un boton; la tarjeta solo el nombre.
				if child.find_children("*", "Button", true, false).is_empty():
					return child
		var found := _search_card(child, building_id, display)
		if found != null:
			return found
	return null

static func _has_label(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Label and (child as Label).text == text:
			return true
		if not (child is PanelContainer) and _has_label(child, text):
			return true
	return false

## Punto de pantalla (lienzo) de una celda del mapa, en 3D o en 2D. `ok` en el
## diccionario dice si cae dentro de la pantalla.
static func cell_screen_point(viewport: Viewport, cell: Vector2i, cell_size: Vector2i = Vector2i.ONE) -> Dictionary:
	var world: Vector3 = GridManager.building_center(cell, cell_size)
	var cam3 := viewport.get_camera_3d()
	var p := Vector2.ZERO
	if cam3 != null:
		if cam3.is_position_behind(world):
			return {"ok": false, "point": Vector2.ZERO}
		# unproject_position ya devuelve coordenadas del lienzo logico (el
		# visible_rect del viewport, con el estirado canvas_items aplicado).
		p = cam3.unproject_position(world)
	else:
		p = viewport.get_canvas_transform() * View2D.world_to_px(world)
	var vis: Rect2 = viewport.get_visible_rect()
	return {"ok": vis.has_point(p), "point": p}

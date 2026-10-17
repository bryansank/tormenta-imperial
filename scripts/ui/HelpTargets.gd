extends RefCounted
## Encuentra en pantalla el control real del que habla una ayuda o un paso del
## tutorial: el boton CONSTRUIR, el ☰, ¿QUE HACER?, una tarjeta de la lista de
## edificios... Devuelve el Control (o su rectangulo) o null si ahora no esta.
##
## Lo que busca lo buscan por nombres estables, no por rutas de escena, porque
## esos controles son de otros paneles y cambian de sitio:
##   - grupo "hud_build_button" / "hud_menu_button" (lo pone quien crea el boton);
##   - si no hay grupo, HudRegistry (ConstructionMenu.button, StormHUD...);
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
			# El boton "☰ MENÚ" del menu unico (PauseMenu).
			return _first_in_group(tree, MENU_GROUP)
		"objective":
			# El siguiente paso vive en ¿QUE HACER? (la franja de objetivo del HUD
			# se quito el 2026-10-05): su entrada del menu si esta a la vista, y
			# si no, el boton "☰ MENÚ" que lleva a ella.
			return objective_entry(tree)
		"resources":
			return HudRegistry.control_of("ResourceHUD")
		# Obreros y moral son fichas de la fila de recursos. "status" era la
		# tarjeta de estado que ya no existe: ahora senala a los obreros.
		"workers", "status":
			return _resource_hud_chip(tree, "workers_chip")
		"morale":
			return _resource_hud_chip(tree, "morale_chip")
		"storm":
			return HudRegistry.control_of("StormHUD")
		# Novedades (2026-10-14): el boton x1/x2 y la insignia de rango.
		"speed_button":
			return HudRegistry.control_of("GameSpeedButton")
		"rank_badge":
			return HudRegistry.control_of("RankPanel")
		# Tutorial claro (2026-10-16): girar, mover, derribar y reparar. Los
		# botones de la ficha del edificio y el ↻ de la pantalla (solo se ve en
		# tablet y movil, y solo colocando: en PC no hay nada que senalar, es R).
		"info_move":
			return _first_in_group(tree, "hud_info_move")
		"info_demolish":
			return _first_in_group(tree, "hud_info_demolish")
		"info_demolish_confirm":
			return _first_in_group(tree, "hud_info_demolish_confirm")
		"info_repair":
			return _first_in_group(tree, "hud_info_repair")
		"rotate_button":
			return _first_in_group(tree, "hud_rotate_building")
	if target_name.begins_with("card:"):
		return card_or_build(tree, target_name.substr(5))
	return null

## ¿QUE HACER?: la entrada del menu ☰ abierto o, cerrado, el boton del menu.
static func objective_entry(tree: SceneTree) -> Control:
	var menu := _scene_node(tree, "PauseMenu")
	if menu != null and menu.has_method("entry"):
		var e: Control = menu.entry("Colony_objectives")
		if e != null and is_instance_valid(e) and e.is_visible_in_tree():
			return e
	return _first_in_group(tree, MENU_GROUP)

## La ficha de obreros o de moral del panel de recursos (ResourceHUD).
static func _resource_hud_chip(tree: SceneTree, getter: String) -> Control:
	var hud := _scene_node(tree, "ResourceHUD")
	if hud != null and hud.has_method(getter):
		return hud.call(getter)
	return null

## El paso "elige la Vivienda": mientras no este elegida, su tarjeta, desplazada
## a la vista (es la ultima de la lista y quedaba fuera del scroll: el marco
## salia donde no habia nada). Ya elegida, el boton CONSTRUIR del detalle, que es
## lo siguiente que hay que pulsar.
static func card_or_build(tree: SceneTree, building_id: String) -> Control:
	var menu := _scene_node(tree, "ConstructionMenu")
	if menu != null and menu.has_method("selected_building_id") \
			and menu.selected_building_id() == building_id:
		var btn: Control = menu.detail_build_button()
		if btn != null and btn.is_visible_in_tree():
			return btn
	var card := building_card(tree, building_id)
	if card != null:
		scroll_into_view(card)
	return card

## Desplaza el ScrollContainer que contiene a `c` hasta que se vea entero. Si ya
## se ve no toca el scroll: el tutorial lo pregunta varias veces por segundo y no
## debe pelear con el dedo que arrastra la lista.
static func scroll_into_view(c: Control) -> void:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			var sc := p as ScrollContainer
			if not sc.get_global_rect().encloses(c.get_global_rect()):
				sc.ensure_control_visible(c)
			return
		p = p.get_parent()

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
	# Lo directo: ConstructionMenu guarda sus tarjetas por id. Recorrer todo el
	# arbol del menu buscando etiquetas queda para quien no lo tenga.
	if menu.has_method("card_for"):
		var card: Control = menu.card_for(building_id)
		if card != null and is_instance_valid(card) and card.is_visible_in_tree():
			return card
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

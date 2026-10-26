class_name FloatingText
## Static utility for spawning floating text labels that animate upward and fade out.
##
## Los servicios no saben en que vista corre la partida: piden el texto "sobre
## este edificio" con `spawn_on()` / `spawn_resource_on()` y es el tipo del nodo
## el que decide. Un Node3D recibe el Label3D de siempre; un Node2D (la vista 2D,
## docs/18-vista-2d.md) recibe una etiqueta 2D que sube por el mapa plano.

const FloatingText2D := preload("res://scripts/view2d/FloatingText2D.gd")

## Cuanto se agranda el texto 3D segun el perfil: en telefono la camara cubre
## el mapa en una pantalla de ~6 pulgadas y 0,0125 daba unos 8 px (QA 30). Solo
## cambia pixel_size: ni mas mallas ni mas llamadas de dibujo.
const PROFILE_SIZE := {"phone": 2.0, "tablet": 1.4}

static func size_factor(profile: String) -> float:
	return float(PROFILE_SIZE.get(profile, 1.0))

static func spawn(scene_tree: SceneTree, world_pos: Vector3, text: String, color: Color) -> void:
	if not scene_tree or not scene_tree.current_scene:
		return
	var label := Label3D.new()
	label.text = text
	# Del tamano del rotulo de obras (BuildingStatusBadge): a 20 px y 0.005 no se
	# leia desde la camara de siempre (ronda de pruebas 1.0).
	label.font_size = 36
	label.pixel_size = 0.0125 * size_factor(DeviceProfile.current())
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	label.modulate = color
	var start_pos := world_pos + Vector3(randf_range(-0.3, 0.3), 2.5, randf_range(-0.3, 0.3))
	# La posicion global y el tween solo existen dentro del arbol: se ponen al
	# colgarla, sea ahora o al final del frame (attach).
	attach(scene_tree.current_scene, label, func() -> void:
		label.global_position = start_pos
		var tween := label.create_tween()
		tween.tween_property(label, "global_position:y", world_pos.y + 5.0, 1.8).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(label, "modulate:a", 0.0, 1.8).set_delay(0.4)
		tween.tween_callback(label.queue_free))

## Cuelga `label` de `parent` y llama a `on_attached` ya dentro del arbol. Si
## `parent` aun esta montando sus hijos (una carga que termina obras dentro del
## _ready de la escena), add_child fallaria con "Parent node is busy setting up
## children": se difiere al final del frame. Si para entonces `parent` ya no esta,
## la etiqueta se libera en vez de quedar huerfana. La usa tambien FloatingText2D.
static func attach(parent: Node, label: Node, on_attached: Callable) -> void:
	if parent == null or not is_instance_valid(parent):
		label.free()
		return
	if parent.is_node_ready():
		parent.add_child(label)
		on_attached.call()
	else:
		_attach_now.call_deferred(parent, label, on_attached)

## Sin tipos: al final del frame `parent` puede ser ya un objeto liberado, y un
## parametro `Node` rechazaria la llamada diferida antes de poder comprobarlo.
static func _attach_now(parent, label, on_attached: Callable) -> void:
	if not is_instance_valid(label):
		return
	if not is_instance_valid(parent) or not (parent as Node).is_inside_tree():
		(label as Node).free()
		return
	(parent as Node).add_child(label)
	on_attached.call()

static func spawn_resource(scene_tree: SceneTree, world_pos: Vector3, amount: int, res_name: String) -> void:
	var color: Color = GameConfig.resource_colors.get(res_name, Color.WHITE)
	spawn(scene_tree, world_pos, "+%d %s" % [amount, Tr.res_name(res_name)], color)

## Texto flotante encima de `node`, sea de la vista 3D o de la 2D. `offset` es
## el desplazamiento lateral en unidades de mundo (varios recursos del mismo
## edificio no se pisan).
static func spawn_on(node: Node, text: String, color: Color, offset: float = 0.0) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	# Durante la carga (obras que la progresion offline termina dentro del _ready
	# de la escena) la escena no admite hijos todavia y la etiqueta quedaria
	# huerfana. Ese texto no lo veria nadie: lo resume el informe offline.
	var scene := node.get_tree().current_scene
	if scene == null or not scene.is_node_ready():
		return
	if node is Node3D:
		spawn(node.get_tree(), (node as Node3D).global_position + Vector3(offset, 0, 0), text, color)
	elif node is Node2D:
		FloatingText2D.spawn(node as Node2D, text, color, offset)

static func spawn_resource_on(node: Node, amount: int, res_name: String, offset: float = 0.0) -> void:
	var color: Color = GameConfig.resource_colors.get(res_name, Color.WHITE)
	spawn_on(node, "+%d %s" % [amount, Tr.res_name(res_name)], color, offset)

# ── Lo recogido vuela a la bolsa (V2, rediseno 2026-10-14) ───────────

## Capa de pantalla de los vuelos: encima del HUD de recursos (10), debajo de
## los menus. Una por escena, creada al primer vuelo.
const FLY_LAYER := 12
const FLY_TIME := 0.6
const FLY_STAGGER := 0.09
static var _fly_layer: CanvasLayer = null

## Al recoger: por cada recurso, su icono y "+N" salen de `from_px` (posicion de
## pantalla, en el lienzo) y vuelan en arco hasta su ficha de la bolsa del HUD
## (ResourceHUD, "Chip_<id>" o "Mat_<id>"), que da un saltito al llegar. Solo
## Tweens: nada por frame cuando no se recoge. Si la ficha no se ve (HUD
## escondido o recurso aun bloqueado), ese recurso no vuela.
static func fly_to_hud(tree: SceneTree, from_px: Vector2, collected: Dictionary) -> void:
	if tree == null or tree.current_scene == null or not tree.current_scene.is_node_ready():
		return
	var hud := tree.current_scene.get_node_or_null("ResourceHUD")
	if hud == null:
		return
	var delay := 0.0
	for res_name in collected:
		var amount := int(collected[res_name])
		if amount <= 0:
			continue
		var target := _hud_target(hud, String(res_name))
		if target == null:
			continue
		_fly_one(_layer(tree.current_scene), from_px, target, String(res_name), amount, delay)
		delay += FLY_STAGGER

static func _hud_target(hud: Node, res_name: String) -> Control:
	for node_name in ["Chip_" + res_name, "Mat_" + res_name]:
		var c := hud.find_child(node_name, true, false) as Control
		if c != null and c.is_visible_in_tree():
			return c
	return null

static func _layer(scene: Node) -> CanvasLayer:
	if _fly_layer == null or not is_instance_valid(_fly_layer) or not _fly_layer.is_inside_tree():
		_fly_layer = CanvasLayer.new()
		_fly_layer.name = "HarvestFlyLayer"
		_fly_layer.layer = FLY_LAYER
		scene.add_child(_fly_layer)
	return _fly_layer

static func _fly_one(layer: CanvasLayer, from_px: Vector2, target: Control, res_name: String, amount: int, delay: float) -> void:
	var item := HBoxContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_constant_override("separation", 2)
	var tex := UITheme.icon_texture(res_name, 42)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
	var lbl := Label.new()
	lbl.text = "+%d" % amount
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", GameConfig.resource_colors.get(res_name, Color.WHITE))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	item.add_child(lbl)
	layer.add_child(item)
	item.reset_size()
	var half := item.size * 0.5
	item.pivot_offset = half
	item.modulate.a = 0.0
	var to: Vector2 = target.get_global_transform_with_canvas() * (target.size * 0.5)
	# Arco: sube un poco antes de caer en la ficha.
	var ctrl := (from_px + to) * 0.5 + Vector2(0.0, -minf(140.0, absf(from_px.y - to.y) * 0.5 + 40.0))
	var place := func(t: float) -> void:
		var a := from_px.lerp(ctrl, t)
		var b := ctrl.lerp(to, t)
		item.position = a.lerp(b, t) - half
		var s := lerpf(1.15, 0.6, t)
		item.scale = Vector2(s, s)
	place.call(0.0)
	var tw := item.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(item, "modulate:a", 1.0, 0.08)
	tw.tween_method(place, 0.0, 1.0, FLY_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _pop(target))
	tw.tween_callback(item.queue_free)

## Saltito de la ficha al recibir lo recogido (y su cifra se ilumina un momento).
static func _pop(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	var old: Tween = target.get_meta("_pop_tween") if target.has_meta("_pop_tween") else null
	if old != null and old.is_valid():
		old.kill()
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2.ONE
	target.modulate = Color(1.5, 1.5, 1.2)
	var tw := target.create_tween()
	tw.tween_property(target, "scale", Vector2(1.18, 1.18), 0.08).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(target, "modulate", Color.WHITE, 0.35)
	tw.tween_property(target, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	target.set_meta("_pop_tween", tw)

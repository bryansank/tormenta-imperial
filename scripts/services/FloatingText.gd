class_name FloatingText
## Static utility for spawning floating text labels that animate upward and fade out.
##
## Los servicios no saben en que vista corre la partida: piden el texto "sobre
## este edificio" con `spawn_on()` / `spawn_resource_on()` y es el tipo del nodo
## el que decide. Un Node3D recibe el Label3D de siempre; un Node2D (la vista 2D,
## docs/18-vista-2d.md) recibe una etiqueta 2D que sube por el mapa plano.

const FloatingText2D := preload("res://scripts/view2d/FloatingText2D.gd")

static func spawn(scene_tree: SceneTree, world_pos: Vector3, text: String, color: Color) -> void:
	if not scene_tree or not scene_tree.current_scene:
		return
	var label := Label3D.new()
	label.text = text
	label.font_size = 20
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 3
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

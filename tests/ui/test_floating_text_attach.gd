extends GdUnitTestSuite
## B10: el texto flotante no se cuelga de una escena que aun monta sus hijos.
##
## Al cargar una partida, una obra que termina dentro del _ready de la escena
## pedia su "Construccion completa" con un add_child sobre un padre ocupado:
## "Parent node is busy setting up children", la etiqueta huerfana y el tween
## sin arbol. FloatingText.attach() difiere el enganche al final del frame y
## crea la posicion y el tween ya dentro del arbol.

## Un hijo que, en su _ready, cuelga una etiqueta de su padre: el mismo momento
## en que el padre esta montando sus hijos.
const _CHILD_SRC := """extends Node
var label: Node = null
var attached_inside := false
func _ready() -> void:
	label = Node.new()
	FloatingText.attach(get_parent(), label, func() -> void:
		attached_inside = label.is_inside_tree())
"""

func _child_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = _CHILD_SRC
	script.reload()
	return script

func test_attach_to_a_ready_parent_is_immediate() -> void:
	var parent: Node = auto_free(Node.new())
	add_child(parent)
	var label := Node.new()
	var inside := [false]
	FloatingText.attach(parent, label, func() -> void: inside[0] = label.is_inside_tree())
	assert_bool(inside[0]).is_true()
	assert_object(label.get_parent()).is_same(parent)

func test_attach_while_the_parent_sets_up_its_children_waits_for_the_frame() -> void:
	var parent: Node = auto_free(Node.new())
	var child := Node.new()
	child.set_script(_child_script())
	parent.add_child(child)
	# Entrar al arbol dispara el _ready del hijo con el padre aun montando.
	add_child(parent)
	assert_object(child.label).is_not_null()
	assert_bool(child.label.is_inside_tree()).is_false()
	await get_tree().process_frame
	assert_object(child.label.get_parent()).is_same(parent)
	assert_bool(child.attached_inside).is_true()

func test_a_parent_gone_before_the_frame_frees_the_label() -> void:
	var parent := Node.new()
	var child := Node.new()
	child.set_script(_child_script())
	parent.add_child(child)
	add_child(parent)
	var label: Node = child.label
	parent.free()
	await get_tree().process_frame
	assert_bool(is_instance_valid(label)).is_false()

func test_a_deferred_label_3d_gets_its_position_once_inside_the_tree() -> void:
	# El caso real de la vista 3D: spawn() sobre una escena actual que aun no
	# esta lista. Se simula con un padre sin _ready todavia.
	var parent: Node3D = auto_free(Node3D.new())
	var label := Label3D.new()
	var pos := Vector3(4, 0, 2)
	FloatingText.attach(parent, label, func() -> void: label.global_position = pos)
	# El padre aun no esta en el arbol (no esta listo): se difiere.
	assert_bool(label.is_inside_tree()).is_false()
	add_child(parent)
	await get_tree().process_frame
	assert_bool(label.is_inside_tree()).is_true()
	assert_vector(label.global_position).is_equal(pos)

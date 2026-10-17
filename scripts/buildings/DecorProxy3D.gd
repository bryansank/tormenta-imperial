extends MeshInstance3D
## El modelo de una decoracion pequena (DecorMesh) cuando la dibuja el lote
## (DecorBatch3D): el MeshInstance3D de siempre, con su malla compartida (para
## medir, encajar en la parcela, crecer de nivel, hundirse en ruina, colgar la
## bandera de su FlagAnchor), pero que no se dibuja: capas 0 y sin sombra. Lo
## que se ve es su instancia en el MultiMesh de su tipo.
##
## Nada por frame: solo avisa al lote cuando se mueve (NOTIFICATION_TRANSFORM_CHANGED,
## tambien cuando se mueve su edificio), cuando cambia si se ve (obra, mover)
## y cuando entra o sale del arbol. El lote junta los avisos de un frame.

var batch: Node = null
var decor_id := ""
## Su indice en el MultiMesh de su tipo (-1 = no se dibuja ahora).
var batch_index := -1

func _init() -> void:
	layers = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _enter_tree() -> void:
	set_notify_transform(true)
	if batch != null and is_instance_valid(batch):
		batch.mark_dirty(decor_id)

func _exit_tree() -> void:
	if batch != null and is_instance_valid(batch):
		batch.mark_dirty(decor_id)

func _notification(what: int) -> void:
	if batch == null or not is_instance_valid(batch):
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		batch.mark_moved(self)
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		batch.mark_dirty(decor_id)

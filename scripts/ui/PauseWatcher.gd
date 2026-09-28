extends Node
## Avisa a su panel cuando el arbol entra o sale de pausa (menu de pausa, menu
## principal). Corre con PROCESS_MODE_ALWAYS; el panel no tiene que hacerlo.
## El panel tiene que tener `_refresh_callouts()`.

var owner_panel: Node = null
var _was_paused := false

func _process(_delta: float) -> void:
	var paused := get_tree().paused
	if paused == _was_paused:
		return
	_was_paused = paused
	if owner_panel != null and is_instance_valid(owner_panel) and owner_panel.has_method("_refresh_callouts"):
		owner_panel._refresh_callouts()

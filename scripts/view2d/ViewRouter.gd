extends Node
## Raiz de Main.tscn y Main2D.tscn. Al arrancar como escena principal mira que
## vista toca (ViewMode.requested) y, si no es la suya, se va a la otra ANTES de
## que empiece la partida: GameManager.hold_start() impide que el colocador de
## esta escena, que muere en este mismo frame, arranque o cargue nada.
##
## Por eso el proyecto puede seguir teniendo Main.tscn como escena principal y
## aun asi abrir en 2D: basta la preferencia o `-- --view=2d`. Hacer la 2D la de
## serie es cambiar el valor por defecto de GameConfig.ui_view_mode.
##
## Una escena instanciada a mano (tests, herramientas) no es la current_scene y
## no enruta nada.

const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

## La vista que pinta esta escena.
@export var view_mode := "3d"

func _enter_tree() -> void:
	if get_tree().current_scene != self:
		return
	var wanted := ViewMode.requested()
	if wanted != view_mode and ResourceLoader.exists(ViewMode.scene_for(wanted)):
		GameManager.hold_start()
		get_tree().change_scene_to_file.call_deferred(ViewMode.scene_for(wanted))
		return
	GameManager.release_start()

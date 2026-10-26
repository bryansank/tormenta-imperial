extends Node
## La escena principal del proyecto (Boot.tscn): no trae nada mas que esto, asi
## que se pinta en el primer fotograma, y pone la pantalla de carga
## (LoadingScreen), que carga por hilos la escena de la vista elegida (Main o
## Main2D, ViewMode.requested()) y cambia a ella. Desde ahi todo sigue igual que
## antes: ViewRouter ve que es su vista y GameManager arranca la partida.
##
## Abrir Main.tscn o Main2D.tscn a mano (F6, tests, sondas -s) se salta esto.

const LoadingScreenScript := preload("res://scripts/boot/LoadingScreen.gd")

func _ready() -> void:
	BootTrace.mark("escena de arranque lista")
	var screen: CanvasLayer = LoadingScreenScript.new()
	# En la raiz y no aqui: esta escena muere al cambiar a Main, la pantalla no.
	get_tree().root.add_child.call_deferred(screen)

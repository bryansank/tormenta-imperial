extends SceneTree
## Lanzador de la sonda de textos de los paneles (ver texto_probe_runner.gd):
## abre cada panel y overlay con una partida sembrada y lo fotografia, para medir
## cuanto texto ensena antes y despues de recortarlo.
##
##     godot --path . -s tools/texto_probe.gd -- --shot-size=1280x800 --profile=tablet --prefix=antes
##     godot --path . -s tools/texto_probe.gd -- --shot-size=1280x800 --profile=pc --prefix=despues
##
## Con ventana y SIEMPRE con un override.cfg de carpeta propia: siembra una
## partida. Aun asi aparca guardado y ajustes y los devuelve al terminar.
## Capturas en docs/media/dev/<prefijo>_<perfil>_<panel>.png (ignorada por git).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/texto_probe_runner.gd").new())

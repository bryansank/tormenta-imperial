extends SceneTree
## Lanzador de la sonda del recorrido de una partida nueva (ver
## recorrido_probe_runner.gd): menu, modo, pais y bandera, prologo, los 12 pasos
## del tutorial jugados de verdad y la leccion de reparar.
##
##     godot --path . -s tools/recorrido_probe.gd -- --shot-size=1280x800 --profile=tablet
##     godot --path . -s tools/recorrido_probe.gd -- --shot-size=1920x1080 --profile=pc --view=2d
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/recorrido_probe_runner.gd").new())

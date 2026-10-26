extends SceneTree
## Lanzador de la sonda de las recetas (ver recetas_probe_runner.gd): la seccion
## FABRICAR del Aserradero, la Mina, la Fundicion y el Nucleo.
##
##     godot --path . -s tools/recetas_probe.gd -- --shot-size=640x360 --profile=phone
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/recetas_probe_runner.gd").new())

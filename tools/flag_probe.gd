extends SceneTree
## Lanzador de la sonda de la bandera y el nombre del pais (flag_probe_runner.gd).
##
##     godot --path . -s tools/flag_probe.gd -- --shot-size=1280x800 --profile=tablet
##     godot --path . -s tools/flag_probe.gd -- --shot-size=1280x720 --profile=pc --view=2d
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/flag_probe_runner.gd").new())

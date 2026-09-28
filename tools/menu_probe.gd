extends SceneTree
## Lanzador de la sonda del menu unico, Ajustes y HUD (ver menu_probe_runner.gd).
##
##     godot --path . -s tools/menu_probe.gd -- --shot-size=1280x800 --profile=tablet
##     godot --path . -s tools/menu_probe.gd -- --shot-size=1280x720 --profile=pc --view=2d
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/menu_probe_runner.gd").new())

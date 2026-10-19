extends SceneTree
## Lanzador de la sonda de la carretera larga (ver road_line_probe_runner.gd).
##
##     godot --path . -s tools/road_line_probe.gd -- --no-title
##     godot --path . -s tools/road_line_probe.gd -- --no-title --view=2d
##
## Con ventana y con un override.cfg propio (custom_user_dir_name): siembra una
## partida nueva en esa carpeta. Un script de -s se compila antes de que existan
## los autoloads, asi que la sonda de verdad es un Node que se carga aqui.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/road_line_probe_runner.gd").new())

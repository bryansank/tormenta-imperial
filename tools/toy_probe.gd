extends SceneTree
## Lanzador de la sonda de los modelos "maqueta" (ver toy_probe_runner.gd).
##
##     godot --path . -s tools/toy_probe.gd                      # los edificios
##     godot --path . -s tools/toy_probe.gd -- --ids=house,farm  # solo esos
##     godot --path . -s tools/toy_probe.gd -- --pieces=kk:tent,kn:detail-tank
##
## Con ventana y SIEMPRE con un override.cfg propio (no guarda partida, pero
## los autoloads arrancan). Capturas en docs/media/dev/toy_probe_*.png.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/toy_probe_runner.gd").new())

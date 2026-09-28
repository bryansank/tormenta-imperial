extends SceneTree
## Lanzador de la sonda de la vista 2D (ver view2d_probe_runner.gd).
##
##     godot --path . -s tools/view2d_probe.gd -- --view=2d
##     godot --path . -s tools/view2d_probe.gd -- --view=2d --shot-size=400x720
##
## Un script de -s se compila antes de que existan los autoloads, asi que la
## sonda de verdad es un Node que se carga aqui, cuando ya estan.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/view2d_probe_runner.gd").new())

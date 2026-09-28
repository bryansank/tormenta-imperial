extends SceneTree
## Lanzador de la sonda de interfaz y dispositivos (ver interfaz_probe_runner.gd).
##
##     godot --path . -s tools/interfaz_probe.gd -- --shot-size=1280x800 --profile=tablet
##     godot --path . -s tools/interfaz_probe.gd -- --view=2d --shot-size=400x720 --scale=150
##
## Un script de -s se compila antes de que existan los autoloads, asi que la
## sonda de verdad es un Node que se carga aqui, cuando ya estan.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/interfaz_probe_runner.gd").new())

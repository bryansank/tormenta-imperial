extends SceneTree
## Lanzador de la sonda del rediseno de la fase 2 (ver ui2_probe_runner.gd):
## las pantallas que las otras sondas no sacan (Mercado, Investigar, Encargos,
## Partidas, Victoria, la barra bloqueada, fichas dañada / Nucleo / Granja,
## Ejercito por pestañas, el Ataque Final en MISIONES, los partes de guerra...).
##
##     godot --path . -s tools/ui2_probe.gd -- --shot-size=800x360 --profile=phone
##     godot --path . -s tools/ui2_probe.gd -- --shot-size=1280x720 --profile=pc --view=2d
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/ui2_probe_runner.gd").new())

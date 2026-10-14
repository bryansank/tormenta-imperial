extends SceneTree
## Lanzador de la sonda de los yacimientos (ver deposito_probe_runner.gd): los
## cuatro yacimientos (bosque, oro, hierro, petroleo) junto a su edificio de
## maqueta, enteros y medio gastados, en 3D de dia, en la Tormenta y de noche, y
## en 2D de dia y en la Tormenta. Mide tambien lo que cuesta montarlos.
##
##     godot --path . -s tools/deposito_probe.gd -- --no-title --no-dev --tag=despues
##
## `--tag=` pone el prefijo de las capturas (docs/media/dev/dep_<tag>_*.png,
## git-ignored). Con ventana (headless no pinta) y SIEMPRE con un override.cfg
## que apunte a otra carpeta de datos: siembra una partida (la que hubiera se
## aparca y se devuelve).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/deposito_probe_runner.gd").new())

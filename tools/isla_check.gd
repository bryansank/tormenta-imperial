extends SceneTree
## Repaso de tierra de la isla irregular (docs/02 "Mapa aleatorio"): para diez
## semillas, el mapa que haria una partida nueva (rejilla, isla, Nucleo con su
## acera, yacimientos) y una tabla con lo que importa para jugar: celdas de
## tierra, area construible libre, vetas por tipo, si todas son trabajables y
## cuantas celdas libres quedan sin camino a la acera (encerradas).
##
##     godot --headless --path . -s tools/isla_check.gd
##     godot --headless --path . -s tools/isla_check.gd -- --seeds=1,2,3
##
## No escribe nada en user:// (no hay partida: solo GridManager y un
## MapGenerator sueltos), pero corre igual con el override.cfg del worktree.

func _initialize() -> void:
	# Un script de -s se compila antes que los autoloads: la sonda de verdad se
	# carga aqui, cuando ya estan.
	root.add_child.call_deferred(load("res://tools/isla_check_runner.gd").new())

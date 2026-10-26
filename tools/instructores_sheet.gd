extends SceneTree
## Hoja de contacto de los instructores (docs/23 §9): las seis caras de la
## Capitana Remache y del Sargento Bombarda a 2x, a tamano de serie (112x140),
## a tamano de telefono (88x110 y su 62 %), con la boca abierta, mirando al
## otro lado, y la cara recortada en circulo (CartoonTheme.CaptainFace /
## InstructorFace). Se pinta en un SubViewport fijo, asi no depende de la
## ventana ni del estirado del proyecto.
##
##     godot --path . -s tools/instructores_sheet.gd [-- --out=res://ruta.png]
##
## Con ventana (el modo headless no pinta) y con un override.cfg propio: los
## autoloads arrancan. Por defecto escribe docs/media/dev/instructores/hoja_contacto.png.

## La hoja la pinta tools/instructores_sheet_runner.gd (un Node: los
## autoloads como Tr y UITheme no existen al compilar un script de -s).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/instructores_sheet_runner.gd").new())

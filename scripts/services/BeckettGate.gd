extends Node
## Portero del puente de desarrollo Beckett (addons/beckett).
##
## El autoload se sigue llamando "BeckettRuntime" a propósito: el plugin de Beckett,
## al abrir el editor, solo registra su autoload si no existe uno con ese nombre. Con
## este portero ocupando el nombre, el plugin no vuelve a apuntarlo a su script.
##
## Desde el editor (F5, sondas) carga el runtime real como hijo y todo funciona igual
## que antes. En un exportado no hace nada: el addon ni siquiera viaja en el .pck
## (export_presets.cfg lo excluye), y por eso se carga con load() por ruta y nunca
## con preload, que arrastraría la dependencia al export o fallaría al no encontrarla.

const RUNTIME_SCRIPT := "res://addons/beckett/runtime/mcp_runtime.gd"


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()
		return
	if not ResourceLoader.exists(RUNTIME_SCRIPT):
		return
	var script := load(RUNTIME_SCRIPT) as Script
	if script == null:
		return
	var runtime: Node = script.new()
	runtime.name = "Runtime"
	add_child(runtime)

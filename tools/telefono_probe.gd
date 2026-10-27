extends SceneTree
## QA de teléfono pequeño: lanza otra sonda de capturas (--base=ui2, construir,
## ficha, revision, recorrido, menu, interfaz...) y, a la vez, el auditor
## tools/telefono_audit.gd, que anota botones de menos de 48, letra de menos de
## 12, textos cortados y cosas que se salen del lienzo.
##
##     godot --path . -s tools/telefono_probe.gd -- --base=ui2 --shot-size=640x360 --profile=phone
##
## Los demás argumentos van a la sonda base. Con ventana y SIEMPRE con un
## override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	var base := "ui2"
	var tag := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--base="):
			base = a.substr(7)
		elif a.begins_with("--shot-size="):
			tag += a.substr(12)
		elif a.begins_with("--view="):
			tag += "_" + a.substr(7)
		elif a.begins_with("--theme="):
			tag += "_" + a.substr(8)
	var audit: Node = load("res://tools/telefono_audit.gd").new()
	audit.tag = "%s_%s" % [base, tag]
	root.add_child.call_deferred(audit)
	root.add_child.call_deferred(load("res://tools/%s_probe_runner.gd" % base).new())

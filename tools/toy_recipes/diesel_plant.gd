extends RefCounted
## Central diesel (industrial, acento rojo; feat/edificios-economia). Todo
## propio, sin piezas CC0: nave de chapa con lucernario, la CHIMENEA alta con
## franjas rojas (su boca es el FxAnchor del humo), el volante de laton, el
## tanque de combustible y las tuberias con valvula. Presupuesto ~1.300 triangulos.
const E := preload("res://scripts/buildings/EconomyToys.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	return E.build_core(mk, "diesel_plant")

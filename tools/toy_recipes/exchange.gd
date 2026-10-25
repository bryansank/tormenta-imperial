extends RefCounted
## Casa de cambio (civico, acento laton; feat/edificios-economia). Todo propio,
## sin piezas CC0: cuerpo de dos plantas, escalinata, portico de cuatro
## columnas con fronton, estandartes rojos y la GRAN moneda de laton encima.
## Presupuesto ~1.200 triangulos.
const E := preload("res://scripts/buildings/EconomyToys.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	return E.build_core(mk, "exchange")

extends RefCounted
## Puerto comercial (civico, acento laton; feat/edificios-economia). Todo propio,
## sin piezas CC0: el cuerpo entero sale de EconomyToys (tinglado de piedra y
## pizarra, muelle de tablones con su canto, norays y la GRUA de laton que saca
## una caja por encima del agua). El muelle (+Z) es el lado que da al mar: el
## Puerto se orienta solo al colocarlo (PlacementRules.FACES_WATER).
## Presupuesto ~1.100 triangulos.
const E := preload("res://scripts/buildings/EconomyToys.gd")

func build(mk, _kit, _ctx: Dictionary) -> Dictionary:
	return E.build_core(mk, "trade_port")

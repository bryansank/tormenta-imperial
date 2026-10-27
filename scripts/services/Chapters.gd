extends RefCounted
## Los tres capitulos de la Campana (feat/ritmo-colono, decision de Bryan
## 2026-10-25; docs/06 §Capitulos). Son los tres actos del lore (contexto 03 §7):
##
##   I   Nadie nos mira  (Era Frontera)    se cierra al levantar la Fundicion (era 2)
##   II  La cuenta       (Era Industrial)  la Refineria (era 3) y la pieza de Tierra
##                                          (Planos del Bastion, el jefe de Tierra)
##   III El libro        (Era Petrolera)   las piezas de Mar y Aire, el CG nivel 3 y
##                                          aguantar el Ataque Final
##
## Sin estado y sin senales, como Objectives: solo pregunta a los servicios. Lo
## unico que se guarda (que capitulos ya se cerraron, para no repetir la pantalla)
## vive en ProgressionManager. Colono los recorre en 3-4 h; Gobernador, en 6-8.
##
## Solo hay capitulos donde hay Ataque Final (Campana y Supervivencia): sin
## Tormenta el lore no cuadra.

const COUNT := 3

## ¿Tiene capitulos esta partida?
static func enabled() -> bool:
	return GameMode.audit_enabled() and GameMode.victory_enabled()

## El capitulo en curso (1..3), o COUNT + 1 con la partida ganada.
static func current() -> int:
	for n in range(1, COUNT + 1):
		if not is_done(n):
			return n
	return COUNT + 1

## ¿Esta cumplido el capitulo `n`? Se mira solo, sin los anteriores.
static func is_done(n: int) -> bool:
	for goal in goals(n):
		if not bool(goal["done"]):
			return false
	return true

## Las metas del capitulo `n`, en orden: [{"key": clave de Tr, "done": bool}].
## La pieza de una campana sale si el modo pide piezas (siempre en Campana).
static func goals(n: int) -> Array:
	var era: int = ProgressionManager.current_era
	var pieces: bool = GameMode.audit_needs_campaigns()
	match n:
		1:
			return [{"key": "CHAPTER_GOAL_FOUNDRY", "done": era >= 2}]
		2:
			var out: Array = [{"key": "CHAPTER_GOAL_REFINERY", "done": era >= 3}]
			if pieces:
				out.append({"key": "CHAPTER_GOAL_PIECE_LAND", "done": CombatManager.has_campaign_piece("land")})
			return out
		3:
			var out: Array = []
			if pieces:
				out.append({"key": "CHAPTER_GOAL_PIECE_SEA", "done": CombatManager.has_campaign_piece("sea")})
				out.append({"key": "CHAPTER_GOAL_PIECE_AIR", "done": CombatManager.has_campaign_piece("air")})
			out.append({"key": "CHAPTER_GOAL_HQ3", "done": ProgressionManager.is_milestone_completed("hq_max")})
			out.append({"key": "CHAPTER_GOAL_AUDIT", "done": StormManager.is_halted()})
			return out
	return []

## "Capitulo II", "Chapter II".
static func number_text(n: int) -> String:
	return Tr.t("CHAPTER_N") % ["I", "II", "III"][clampi(n, 1, COUNT) - 1]

## "La cuenta".
static func title(n: int) -> String:
	return Tr.t("CHAPTER_%d_TITLE" % clampi(n, 1, COUNT))

## "Capitulo II · La cuenta".
static func heading(n: int) -> String:
	return "%s · %s" % [number_text(n), title(n)]

## La frase de lo que pide el capitulo, una linea.
static func goal_text(n: int) -> String:
	return Tr.t("CHAPTER_%d_GOAL" % clampi(n, 1, COUNT))

## Las metas con su marca: "✓ Levanta la Refineria", "· Gana al jefe de Tierra".
static func goal_lines(n: int) -> Array:
	var out: Array = []
	for goal in goals(n):
		out.append(("✓ " if bool(goal["done"]) else "· ") + Tr.t(String(goal["key"])))
	return out

## La frase del cierre (lore, corta).
static func close_text(n: int) -> String:
	return Tr.t("CHAPTER_%d_CLOSE" % clampi(n, 1, COUNT))

extends RefCounted
## El nombre y la bandera del pais del jugador, sin estado: lo que se puede
## elegir por rango, nombres y banderas al azar (estables con una semilla), el
## filtro de palabras y la traduccion de las banderas de antes.
##
## El estado (el nombre y la receta de ESTA partida) vive en RankManager; aqui
## solo hay funciones puras, para que el editor (ColonyIdentityPanel), las
## pruebas y la lista de partidas las usen sin tocar la partida.
##
## Se carga por preload (sin class_name), como Objectives.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

## Tipos de pieza, como las claves de GameConfig.rank_rewards.
const KINDS := ["patterns", "emblems", "colors"]

# ── Nombres al azar: "<forma> de <lugar>" o el lugar solo ──

const FORMS := {
	"es": ["República de", "Liga de", "Unión de", "Ducado de", "Colonia de", "Federación de",
		"Cantón de", "Comuna de", "Estado Libre de", "Gremio de"],
	"en": ["Republic of", "League of", "Union of", "Duchy of", "Colony of", "Federation of",
		"Canton of", "Commune of", "Free State of", "Guild of"],
}
const PLACES := {
	"es": ["Puerto Hierro", "Vaporia", "Roca Remache", "Cobrevalle", "Hollinar", "Engranaria",
		"Bahía Tuerca", "Monte Biela", "Ferrocosta", "Caldera Alta", "Nueva Fragua", "Islaforja",
		"Pistonia", "Latonia", "Punta Vapor", "Vado Carbón", "Valvulia", "Cabo Caldera",
		"Brumaria", "Remachia", "Torrehumo", "Ancla Vieja"],
	"en": ["Port Iron", "Steamia", "Rivet Rock", "Copperdale", "Sootmoor", "Gearholm",
		"Bolt Bay", "Crank Hill", "Ironcoast", "High Boiler", "New Forge", "Forge Isle",
		"Pistonia", "Brassia", "Steam Point", "Coal Ford", "Valvia", "Boiler Cape",
		"Mistmark", "Rivetia", "Smokespire", "Old Anchor"],
}
## Una de cada tantas sale solo el lugar ("Vaporia").
const PLACE_ONLY_CHANCE := 0.15

# ── Filtro de palabras (publico infantil) ──
# Dos listas cortas ES/EN en base64, para que no se lean de pasada en el codigo.
# _SUB se busca dentro del texto (tambien sin espacios); _WORD solo como palabra
# entera (evita falsos positivos como "calculo" o "disputa").
const _SUB := "ZnVjayxzaGl0LG1pZXJkYSxjYWJyb24sZ2lsaXBvbGwsbmlnZ2VyLG5pZ2dhLGhpdGxlcixuYXppLGpvZGVyLGZvbGxhcixhc3Nob2xlLGJpdGNoLHBlbmRlaixoaWpvcHV0YSxtYXJpY29uLGNoaW5nYSxwdXRpdGEsd2hvcmUscGVuaXMscG9ybm8scmFwaXN0LG1vdGhlcmYsY29qb24sY2/DsW8="
const _WORD := "cHV0YSxwdXRhcyxwdXRvLHB1dG9zLGN1bG8scGVuZSxjb8Oxbyx2ZXJnYSx6b3JyYSxtYW1vbixtYXJpY2EscGluZ2EscG9sbGEsaWRpb3RhLGltYmVjaWwsZXN0dXBpZG8sc3Vibm9ybWFsLHJldGFyZCxyZXRyYXNhZG8sY3VudCxkaWNrLGNvY2sscHVzc3ksYXNzLGFyc2UsY3VtLHNleCxzZXhvLHNsdXQsZmFnLGtrayxwb3JuLHJhcGUsdGl0cyxib29icyxiYXN0YXJkLHdhbmssdHdhdCxjcmFwLGRhbW4sZmFydCxwaXNzLGNhY2EscGVkbyx0ZXRhLHRldGFz"
const _ACCENTS := {"á": "a", "à": "a", "ä": "a", "â": "a", "é": "e", "è": "e", "ë": "e", "ê": "e",
	"í": "i", "ì": "i", "ï": "i", "î": "i", "ó": "o", "ò": "o", "ö": "o", "ô": "o",
	"ú": "u", "ù": "u", "ü": "u", "û": "u", "ç": "c"}
const _LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"}

static var _sub_words: PackedStringArray = []
static var _whole_words: PackedStringArray = []

# ── Piezas por rango ──

## El rango que abre una pieza (0 = ninguno la abre: no existe).
static func piece_rank(kind: String, id: String) -> int:
	for r in GameConfig.rank_rewards:
		if id in GameConfig.rank_rewards[r].get(kind, []):
			return int(r)
	return 0

## ¿Esta abierta la pieza con este rango? `all` = todo abierto (Sandbox).
static func is_piece_open(kind: String, id: String, rank: int, all: bool = false) -> bool:
	var r := piece_rank(kind, id)
	if r <= 0:
		return false
	return all or r <= rank

## Las piezas abiertas de un tipo, en el orden de la galeria.
static func open_pieces(kind: String, rank: int, all: bool = false) -> Array:
	var out: Array = []
	for id in catalog(kind):
		if is_piece_open(kind, id, rank, all):
			out.append(id)
	return out

static func catalog(kind: String) -> Array:
	match kind:
		"patterns":
			return GameConfig.COLONY_PATTERNS
		"emblems":
			return GameConfig.COLONY_EMBLEMS
		"colors":
			return GameConfig.COLONY_COLOR_ORDER
	return []

## ¿Todas las piezas de la receta estan abiertas con este rango?
static func is_spec_open(spec: Dictionary, rank: int, all: bool = false) -> bool:
	var s := ColonyFlag.normalized(spec)
	if not is_piece_open("patterns", s["pattern"], rank, all):
		return false
	if not is_piece_open("emblems", s["emblem"], rank, all):
		return false
	for c in used_colors(s):
		if not is_piece_open("colors", c, rank, all):
			return false
	return true

## Los colores que de verdad se ven (un fondo liso no usa el segundo, sin
## emblema no hay tercero).
static func used_colors(spec: Dictionary) -> Array:
	var s := ColonyFlag.normalized(spec)
	var out: Array = [s["colors"][0]]
	if ColonyFlag.fields_of(s["pattern"]) == 2:
		out.append(s["colors"][1])
	if s["emblem"] != "none":
		out.append(s["colors"][2])
	return out

## La receta con cada pieza cerrada cambiada por la de serie (o la primera
## abierta), y arreglada para que se lea. Para guardados y cambios de rango.
static func clamp_spec(spec: Dictionary, rank: int, all: bool = false) -> Dictionary:
	var s := ColonyFlag.normalized(spec)
	var def: Dictionary = GameConfig.COLONY_DEFAULT_SPEC
	if not is_piece_open("patterns", s["pattern"], rank, all):
		s["pattern"] = def["pattern"] if is_piece_open("patterns", def["pattern"], rank, all) else open_pieces("patterns", rank, all)[0]
	if not is_piece_open("emblems", s["emblem"], rank, all):
		s["emblem"] = def["emblem"] if is_piece_open("emblems", def["emblem"], rank, all) else "none"
	var colors: Array = s["colors"]
	for i in 3:
		if not is_piece_open("colors", colors[i], rank, all):
			colors[i] = def["colors"][i]
	s["colors"] = colors
	return ColonyFlag.fix_spec(s, open_pieces("colors", rank, all))

# ── Al azar ──

## Una bandera al azar con las piezas abiertas. Misma semilla, misma bandera.
static func random_spec(seed_value: int, rank: int = 1, all: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var patterns := open_pieces("patterns", rank, all)
	var emblems := open_pieces("emblems", rank, all)
	emblems.erase("none")
	var colors := open_pieces("colors", rank, all)
	var pattern: String = patterns[rng.randi() % patterns.size()]
	var emblem := "none"
	if not emblems.is_empty() and rng.randf() > 0.1:
		emblem = emblems[rng.randi() % emblems.size()]
	var c0: String = colors[rng.randi() % colors.size()]
	var second: Array = colors.filter(func(c): return ColonyFlag.fields_distinct(c0, c))
	var c1: String = second[rng.randi() % second.size()] if not second.is_empty() else c0
	var base := [c0, c1, c0]
	var third: Array = colors.filter(func(c): return ColonyFlag.emblem_legible(pattern, base, c))
	var c2: String = third[rng.randi() % third.size()] if not third.is_empty() else c0
	return ColonyFlag.fix_spec({"pattern": pattern, "emblem": emblem, "colors": [c0, c1, c2]}, colors)

## Un nombre al azar en el tono del juego ("Liga de Vaporia"). Misma semilla y
## mismo idioma, mismo nombre.
static func random_name(seed_value: int, locale: String = "es") -> String:
	var lang := locale if FORMS.has(locale) else "es"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var forms: Array = FORMS[lang]
	var places: Array = PLACES[lang]
	for _try in 12:
		var place: String = places[rng.randi() % places.size()]
		var name := place
		if rng.randf() >= PLACE_ONLY_CHANCE:
			name = "%s %s" % [forms[rng.randi() % forms.size()], place]
		if name.length() <= GameConfig.COLONY_NAME_MAX and is_name_allowed(name):
			return name
	return places[0]

## Semilla estable para una partida vieja sin nombre: la de la isla.
static func seed_for_island(island_seed: int) -> int:
	return hash("colony:%d" % island_seed)

# ── Nombre: limpiar y filtrar ──

## Sin espacios de mas ni caracteres de control, y como mucho COLONY_NAME_MAX.
static func clean_name(text: String) -> String:
	var out := ""
	var last_space := true
	for ch in text:
		var code := ch.unicode_at(0)
		if code < 32 or code == 127:
			continue
		if ch == " " or ch == "\t":
			if last_space:
				continue
			out += " "
			last_space = true
		else:
			out += ch
			last_space = false
	out = out.strip_edges()
	if out.length() > GameConfig.COLONY_NAME_MAX:
		out = out.substr(0, GameConfig.COLONY_NAME_MAX).strip_edges()
	return out

## ¿Vale como nombre? Dos letras como poco y nada de la lista de palabras.
static func is_name_allowed(text: String) -> bool:
	var name := clean_name(text)
	if name.length() < 2:
		return false
	return not is_offensive(name)

static func is_offensive(text: String) -> bool:
	_load_words()
	var norm := _normalize(text)
	var squeezed := _squeeze(norm)
	var letters := norm.replace(" ", "")
	var letters_sq := squeezed.replace(" ", "")
	for w in _sub_words:
		if letters.contains(w) or letters_sq.contains(_squeeze(w)):
			return true
	var tokens := norm.split(" ", false)
	var tokens_sq := squeezed.split(" ", false)
	for w in _whole_words:
		if w in tokens:
			return true
		var wsq := _squeeze(w)
		if wsq.length() >= 3 and wsq in tokens_sq:
			return true
	return false

## Minusculas, sin tildes, numeros "leet" a letras y todo lo que no sea letra a
## espacio. La ñ se queda (no es una n).
static func _normalize(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		var c: String = _ACCENTS.get(ch, _LEET.get(ch, ch))
		if (c >= "a" and c <= "z") or c == "ñ":
			out += c
		else:
			out += " "
	return out

## Las letras repetidas seguidas, una sola vez ("fuuuck" -> "fuck").
static func _squeeze(text: String) -> String:
	var out := ""
	var last := ""
	for ch in text:
		if ch != last:
			out += ch
		last = ch
	return out

static func _load_words() -> void:
	if not _sub_words.is_empty():
		return
	_sub_words = Marshalls.base64_to_utf8(_SUB).split(",", false)
	_whole_words = Marshalls.base64_to_utf8(_WORD).split(",", false)

# ── Las banderas de antes ──

## Una bandera de las seis de antes ("rank": {"flag", "color"}) en piezas: su
## dibujo, el color de la colonia de fondo y marfil para lo demas (como antes).
static func legacy_spec(flag_id: String, color_id: String) -> Dictionary:
	var parts: Array = GameConfig.COLONY_LEGACY_FLAGS.get(flag_id, GameConfig.COLONY_LEGACY_FLAGS["band"])
	var c0 := color_id if GameConfig.colony_colors.has(color_id) else "brass"
	var light := "ivory" if c0 != "ivory" else "soot"
	return ColonyFlag.fix_spec({"pattern": parts[0], "emblem": parts[1], "colors": [c0, light, light]})

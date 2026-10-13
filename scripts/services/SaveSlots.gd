extends RefCounted
## Las partidas guardadas (2026-10-12): hasta MAX_SLOTS, cada una en su archivo
## de user://partidas/, y un indice pequeno (indice.json) para pintar la lista
## sin abrir cada partida.
##
##   user://partidas/partida_<id>.json                 la partida (el formato de siempre)
##   user://partidas/partida_<id>.corrupt-<fecha>.json copia de una ilegible
##   user://partidas/partida_<id>.v1-<fecha>.json      copia de una de formato viejo
##   user://partidas/indice.json                       {"version", "slots": [resumen...]}
##
## El indice es una cache: si falta, esta roto o no casa con los archivos, se
## rehace leyendo las partidas (list() lo concilia cada vez). La verdad son los
## archivos. Que partida esta activa NO va aqui: es del dispositivo y vive en
## settings.cfg ([partidas] activa, GameConfig.saves_active_slot).
##
## Sin estado propio: funciones estaticas, con `preload` (como TextKit).

const DIR := "user://partidas"
const INDEX_PATH := "user://partidas/indice.json"
## El guardado unico de antes de las partidas. Si aparece, se migra (migrate_legacy).
const LEGACY_PATH := "user://save_game.json"
const MAX_SLOTS := 5
const INDEX_VERSION := 1

# ── Rutas ────────────────────────────────────────────────────────────

static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

## La ruta de la partida `id`. Crea la carpeta si falta: quien la pide va a
## escribir en ella.
static func path_of(id: int) -> String:
	ensure_dir()
	return "%s/partida_%d.json" % [DIR, id]

## Patron para las copias apartadas de la partida `id` ("corrupt", "v1"): un
## %s para la fecha.
static func backup_fmt(id: int, kind: String) -> String:
	ensure_dir()
	return "%s/partida_%d.%s-%%s.json" % [DIR, id, kind]

## El id de un nombre de archivo de partida, o 0 si no lo es (el indice, las
## copias .corrupt / .v1).
static func id_of_file(file_name: String) -> int:
	if not file_name.begins_with("partida_") or not file_name.ends_with(".json"):
		return 0
	var mid := file_name.trim_prefix("partida_").trim_suffix(".json")
	if not mid.is_valid_int():
		return 0
	return maxi(0, int(mid))

## Los ids que tienen archivo, de menor a mayor.
static func file_ids() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return ids
	for f in dir.get_files():
		var id := id_of_file(f)
		if id > 0:
			ids.append(id)
	ids.sort()
	return ids

static func exists(id: int) -> bool:
	return id > 0 and FileAccess.file_exists("%s/partida_%d.json" % [DIR, id])

static func count() -> int:
	return file_ids().size()

static func is_full() -> bool:
	return count() >= MAX_SLOTS

## El id para una partida nueva: uno mas que el mayor que haya.
static func next_id() -> int:
	var ids := file_ids()
	return 1 if ids.is_empty() else int(ids.back()) + 1

## La partida guardada mas recientemente, o 0 si no hay ninguna.
static func most_recent_id() -> int:
	var all := list()
	return 0 if all.is_empty() else int(all[0]["id"])

# ── Leer ─────────────────────────────────────────────────────────────

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data

## Lo que hay en la partida `id`, o {} si no existe o no se puede leer.
static func read(id: int) -> Dictionary:
	var data: Variant = _read_json("%s/partida_%d.json" % [DIR, id])
	return data if data is Dictionary else {}

# ── Resumen e indice ─────────────────────────────────────────────────

## Lo que la lista ensena de una partida, sacado de su guardado. Los campos que
## el guardado no trae (una partida sin nombre de pais) quedan vacios y la lista
## pone "Colonia N".
static func summary_of(data: Dictionary, id: int) -> Dictionary:
	var mode: Dictionary = data.get("game_mode", {}) if data.get("game_mode", {}) is Dictionary else {}
	var prog: Dictionary = data.get("progression", {}) if data.get("progression", {}) is Dictionary else {}
	var rank: Dictionary = data.get("rank", {}) if data.get("rank", {}) is Dictionary else {}
	# La rama de bandera y pais guarda "rank": {"colony": {"name", "flag"}}; los
	# guardados de antes traian "color" suelto.
	var colony: Dictionary = rank.get("colony", {}) if rank.get("colony", {}) is Dictionary else {}
	var spec: Variant = colony.get("flag", {})
	var colors: Variant = (spec as Dictionary).get("colors", []) if spec is Dictionary else []
	var first_color := String((colors as Array)[0]) if colors is Array and not (colors as Array).is_empty() else String(rank.get("color", String(GameConfig.COLONY_DEFAULT_SPEC["colors"][0])))
	return {
		"id": id,
		"colony_name": String(colony.get("name", "")),
		"flag_spec": spec if spec is Dictionary else {},
		"color": first_color,
		"mode": String(mode.get("mode", "campaign")),
		"tier": String(mode.get("tier", "colonist")),
		"era": int(prog.get("current_era", 1)),
		"played_seconds": float(prog.get("played_seconds", 0.0)),
		"saved_at": float(data.get("saved_at", 0.0)),
		"sealed": String(mode.get("result", "")) == "defeat",
	}

## Resumen leyendo el archivo. Uno ilegible sale igual en la lista (se puede
## borrar; al cargarlo, GameManager lo aparta como .corrupt y empieza otra).
static func summary_from_file(id: int) -> Dictionary:
	var data := read(id)
	var s := summary_of(data, id)
	if data.is_empty():
		s["broken"] = true
		s["saved_at"] = float(FileAccess.get_modified_time("%s/partida_%d.json" % [DIR, id]))
	return s

static func _read_index() -> Dictionary:
	var out := {}
	var raw: Variant = _read_json(INDEX_PATH)
	if not (raw is Dictionary) or not ((raw as Dictionary).get("slots", null) is Array):
		return out
	for e in raw["slots"]:
		if e is Dictionary and int(e.get("id", 0)) > 0:
			var entry: Dictionary = e
			entry["id"] = int(entry["id"])
			out[int(entry["id"])] = entry
	return out

static func _write_index(entries: Dictionary) -> void:
	ensure_dir()
	var ids := entries.keys()
	ids.sort()
	var slots: Array = []
	for id in ids:
		slots.append(entries[id])
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": INDEX_VERSION, "slots": slots}, "\t"))
		f.close()

## Las partidas, la mas reciente primero. Concilia el indice con los archivos:
## una partida sin entrada se resume leyendola, una entrada sin archivo se tira.
static func list() -> Array:
	var entries := _read_index()
	var ids := file_ids()
	var changed := false
	for id in ids:
		if not entries.has(id):
			entries[id] = summary_from_file(id)
			changed = true
	for id in entries.keys():
		if not (id in ids):
			entries.erase(id)
			changed = true
	if changed:
		_write_index(entries)
	var out: Array = entries.values()
	out.sort_custom(func(a, b):
		var ta := float(a.get("saved_at", 0.0))
		var tb := float(b.get("saved_at", 0.0))
		if ta != tb:
			return ta > tb
		return int(a["id"]) > int(b["id"]))
	return out

static func entry(id: int) -> Dictionary:
	for e in list():
		if int(e["id"]) == id:
			return e
	return {}

## Anota (o pisa) el resumen de la partida `id` en el indice.
static func record(id: int, summary: Dictionary) -> void:
	var entries := _read_index()
	var s := summary.duplicate(true)
	s["id"] = id
	entries[id] = s
	# Lo que haya en disco y no en el indice tambien entra (indice perdido).
	for other in file_ids():
		if not entries.has(other):
			entries[other] = summary_from_file(other)
	_write_index(entries)

## Borra la partida `id` (archivo y entrada). Sus copias .corrupt / .v1 se
## quedan: no son la partida, son lo que se aparto de ella.
static func remove(id: int) -> bool:
	var path := "%s/partida_%d.json" % [DIR, id]
	var ok := true
	if FileAccess.file_exists(path):
		ok = DirAccess.remove_absolute(path) == OK
	var entries := _read_index()
	if entries.has(id):
		entries.erase(id)
		_write_index(entries)
	return ok

# ── Migracion ────────────────────────────────────────────────────────

## Un user://save_game.json de antes pasa a ser una partida mas (la 1 si no hay
## otras). Se copia, se comprueba byte a byte que la copia es igual y solo
## entonces se borra el original. Devuelve el id nuevo, o 0 si no habia nada
## (o la copia fallo: el original se queda donde estaba, intacto).
static func migrate_legacy() -> int:
	if not FileAccess.file_exists(LEGACY_PATH):
		return 0
	var id := next_id()
	var target := path_of(id)
	if DirAccess.copy_absolute(LEGACY_PATH, target) != OK:
		push_warning("SaveSlots: no se pudo copiar %s a %s; se deja donde estaba" % [LEGACY_PATH, target])
		return 0
	var original := FileAccess.get_file_as_bytes(LEGACY_PATH)
	var copy := FileAccess.get_file_as_bytes(target)
	if original != copy:
		push_warning("SaveSlots: la copia de %s no coincide; se deja el original" % LEGACY_PATH)
		DirAccess.remove_absolute(target)
		return 0
	DirAccess.remove_absolute(LEGACY_PATH)
	record(id, summary_from_file(id))
	return id

# ── Utilidades ───────────────────────────────────────────────────────

## Borra una carpeta con todo lo que tenga dentro (save_parking y pruebas).
static func remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		remove_dir_recursive(path.path_join(d))
	DirAccess.remove_absolute(path)

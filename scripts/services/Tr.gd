extends Node
## Centralized translation service.
## Usage: Tr.t("KEY"), Tr.res_name("gold"), Tr.res_upper("gold")
## Change locale with Tr.set_locale("en")

var _locale := "es"

const _RESOURCES := {
	"es": {"gold": "oro", "steel": "acero", "oil": "petroleo", "wood": "madera"},
	"en": {"gold": "gold", "steel": "steel", "oil": "oil", "wood": "wood"},
}

const _RESOURCES_UPPER := {
	"es": {"gold": "ORO", "steel": "ACERO", "oil": "PETROLEO", "wood": "MADERA"},
	"en": {"gold": "GOLD", "steel": "STEEL", "oil": "OIL", "wood": "WOOD"},
}

const _RESOURCES_CAP := {
	"es": {"gold": "Oro", "steel": "Acero", "oil": "Petroleo", "wood": "Madera"},
	"en": {"gold": "Gold", "steel": "Steel", "oil": "Oil", "wood": "Wood"},
}

const _STRINGS := {
	"es": {
		# Buttons
		"BTN_BUILD": "CONSTRUIR",
		"BTN_CLOSE": "Cerrar",
		"BTN_MOVE": "Mover",
		"BTN_DEMOLISH": "Demoler",
		"BTN_RENAME": "Renombrar",
		"BTN_CLEAR": "LIMPIAR",

		# Labels
		"LBL_ACTIONS": "Acciones",
		"LBL_NO_ACTIONS": "Sin acciones disponibles",
		"LBL_BUILDINGS_AVAILABLE": "Edificios disponibles",
		"LBL_BUILDING_NAME_PLACEHOLDER": "Nombre del edificio...",
		"LBL_FREE": "Gratis",
		"LBL_NATURAL_RESOURCE": "Recurso natural disponible para extraccion.",

		# Formats
		"FMT_COST": "Costo: %s",
		"FMT_PRODUCES": "Produce: %s",
		"FMT_PRODUCES_EVERY": "Produce: %s cada %ds",
		"FMT_PROGRESS": "%s — %ds restantes",
		"FMT_CONSTRUCTION": "En construccion: %d%% — %ds restantes",
		"FMT_CONSTRUCTING": "Construyendo %d%%",
		"FMT_CONSTRUCTION_COMPLETE": "Construccion completa!",
		"FMT_DURATION": "Duracion: %ds",
		"FMT_OFFLINE_TITLE": "Mientras estuviste fuera (%s)",
		"LBL_DEPOSIT_USES": "%d usos restantes",
		"LBL_DEPOSIT_DEPLETED": "Deposito agotado!",

		# Deposits
		"DEP_GOLD_VEIN": "Veta de Oro",
		"DEP_IRON": "Hierro",
		"DEP_OIL": "Petroleo",
		"DEP_FOREST": "Bosque",

		# Processes
		"PROC_WOOD_PLANKS": "Laminas de Madera",
		"PROC_IRON_SHEETS": "Laminas de Hierro",
		"PROC_WATER_PIPES": "Tubos de Agua",
		"PROC_MINE_GOLD": "Minar Oro",
		"PROC_MINE_IRON": "Minar Hierro",
		"PROC_MINE_OIL": "Extraer Petroleo",
		"PROC_MINE_WOOD": "Talar Arboles",
	},
	"en": {
		"BTN_BUILD": "BUILD",
		"BTN_CLOSE": "Close",
		"BTN_MOVE": "Move",
		"BTN_DEMOLISH": "Demolish",
		"BTN_RENAME": "Rename",
		"BTN_CLEAR": "CLEAR",

		"LBL_ACTIONS": "Actions",
		"LBL_NO_ACTIONS": "No actions available",
		"LBL_BUILDINGS_AVAILABLE": "Available buildings",
		"LBL_BUILDING_NAME_PLACEHOLDER": "Building name...",
		"LBL_FREE": "Free",
		"LBL_NATURAL_RESOURCE": "Natural resource available for extraction.",

		"FMT_COST": "Cost: %s",
		"FMT_PRODUCES": "Produces: %s",
		"FMT_PRODUCES_EVERY": "Produces: %s every %ds",
		"FMT_PROGRESS": "%s — %ds remaining",
		"FMT_CONSTRUCTION": "Building: %d%% — %ds remaining",
		"FMT_CONSTRUCTING": "Building %d%%",
		"FMT_CONSTRUCTION_COMPLETE": "Construction complete!",
		"FMT_DURATION": "Duration: %ds",
		"FMT_OFFLINE_TITLE": "While you were away (%s)",
		"LBL_DEPOSIT_USES": "%d uses remaining",
		"LBL_DEPOSIT_DEPLETED": "Deposit depleted!",

		"DEP_GOLD_VEIN": "Gold Vein",
		"DEP_IRON": "Iron",
		"DEP_OIL": "Oil Well",
		"DEP_FOREST": "Forest",

		"PROC_WOOD_PLANKS": "Wood Planks",
		"PROC_IRON_SHEETS": "Iron Sheets",
		"PROC_WATER_PIPES": "Water Pipes",
		"PROC_MINE_GOLD": "Mine Gold",
		"PROC_MINE_IRON": "Mine Iron",
		"PROC_MINE_OIL": "Extract Oil",
		"PROC_MINE_WOOD": "Chop Trees",
	},
}

func t(key: String) -> String:
	return _STRINGS.get(_locale, {}).get(key, key)

func res_name(res_id: String) -> String:
	return _RESOURCES.get(_locale, {}).get(res_id, res_id)

func res_upper(res_id: String) -> String:
	return _RESOURCES_UPPER.get(_locale, {}).get(res_id, res_id)

func res_cap(res_id: String) -> String:
	return _RESOURCES_CAP.get(_locale, {}).get(res_id, res_id)

func set_locale(locale: String) -> void:
	_locale = locale

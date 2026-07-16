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
		"BTN_UPGRADE": "Mejorar",
		"BTN_CONFIRM": "Confirmar",
		"BTN_CANCEL": "Cancelar",

		# Labels
		"LBL_ACTIONS": "Acciones",
		"LBL_NO_ACTIONS": "Sin acciones disponibles",
		"LBL_BUILDINGS_AVAILABLE": "Edificios disponibles",
		"LBL_BUILDING_NAME_PLACEHOLDER": "Nombre del edificio...",
		"LBL_FREE": "Gratis",
		"LBL_NATURAL_RESOURCE": "Recurso natural disponible para extraccion.",
		"LBL_LEVEL": "Nivel %d",
		"LBL_MAX_LEVEL": "Nivel maximo",
		"LBL_UPGRADE_TO": "Mejorar a Nivel %d",
		"LBL_STORAGE_CAP": "Almacenamiento: %d/%d",
		"LBL_LIMIT_REACHED": "Limite alcanzado (%d/%d)",
		"LBL_REQUIRES": "Requiere: %s",
		"LBL_REQUIRES_DEPOSIT": "Debe colocarse sobre un deposito de petroleo",
		"LBL_NOT_ENOUGH_RESOURCES": "Recursos insuficientes!",
		"LBL_UPGRADE_COMPLETE": "Mejora completa!",

		# Formats
		"FMT_COST": "Costo: %s",
		"FMT_PRODUCES": "Produce: %s",
		"FMT_PRODUCES_EVERY": "Produce: %s cada %ds",
		"FMT_PROGRESS": "%s — %ds restantes",
		"FMT_CONSTRUCTION": "En construccion: %d%% — %ds restantes",
		"FMT_CONSTRUCTING": "Construyendo %d%%",
		"FMT_UPGRADING": "Mejorando %d%%",
		"FMT_CONSTRUCTION_COMPLETE": "Construccion completa!",
		"FMT_DURATION": "Duracion: %ds",
		"FMT_OFFLINE_TITLE": "Mientras estuviste fuera (%s)",
		"FMT_DEMOLISH_CONFIRM": "Demoler %s?\nReembolso: %d%%",
		"LBL_DEPOSIT_USES": "%d usos restantes",
		"LBL_DEPOSIT_DEPLETED": "Deposito agotado!",

		# Deposits
		"DEP_GOLD_VEIN": "Veta de Oro",
		"DEP_IRON": "Hierro",
		"DEP_OIL": "Petroleo",
		"DEP_FOREST": "Bosque",

		# Processes - Nucleo
		"PROC_WOOD_PLANKS": "Laminas de Madera",
		"PROC_IRON_SHEETS": "Laminas de Hierro",
		"PROC_WATER_PIPES": "Tubos de Agua",
		# Processes - Sawmill
		"PROC_REFINED_LUMBER": "Madera Refinada",
		"PROC_CHARCOAL": "Carbon Vegetal",
		# Processes - Gold Mine
		"PROC_DEEP_MINING": "Mineria Profunda",
		"PROC_GEM_EXTRACTION": "Extraccion de Gemas",
		# Processes - Foundry
		"PROC_ALLOY_SMELTING": "Fundicion de Aleacion",
		"PROC_ARMOR_PLATES": "Placas de Armadura",
		# Processes - Refinery
		"PROC_FUEL_DISTILLATION": "Destilacion de Combustible",
		"PROC_CHEMICAL_PROCESSING": "Procesamiento Quimico",
		# Mining
		"PROC_MINE_GOLD": "Minar Oro",
		"PROC_MINE_IRON": "Minar Hierro",
		"PROC_MINE_OIL": "Extraer Petroleo",
		"PROC_MINE_WOOD": "Talar Arboles",

		# Market
		"BTN_MARKET": "MERCADO",
		"BTN_BUY": "Comprar",
		"BTN_SELL": "Vender",
		"LBL_MARKET_TITLE": "Mercado Imperial",
		"LBL_RESOURCE": "Recurso",
		"LBL_BUY_PRICE": "Compra",
		"LBL_SELL_PRICE": "Venta",
		"LBL_AMOUNT": "Cant.",
		"LBL_YOUR_GOLD": "Tu oro: %d",

		# Progression
		"BTN_PROGRESS": "PROGRESO",
		"LBL_PROGRESS_TITLE": "Progreso Imperial",
		"LBL_CURRENT_ERA": "Era actual",

		# Eras
		"ERA_FRONTIER": "Frontera",
		"ERA_INDUSTRIAL": "Industrial",
		"ERA_PETROLEUM": "Petrolera",

		# Milestones
		"MILE_PIONEER": "Pionero — Construir Aserradero",
		"MILE_PROSPECTOR": "Buscador — Construir Mina de Oro",
		"MILE_STOCKPILER": "Almacenista — Construir Deposito",
		"MILE_INDUSTRIALIST": "Industrialista — Construir Fundicion",
		"MILE_OIL_BARON": "Baron del Petroleo — Construir Refineria",
		"MILE_MERCHANT": "Mercader — 10 intercambios",
		"MILE_COMMANDER": "Comandante — Cuartel + 2 Torres",
		"MILE_GENERAL": "General — Construir Cuartel General",
		"MILE_VICTORY": "Victoria Imperial — Cuartel General Nv.3",
		"FMT_MILESTONE_COMPLETE": "Hito completado: %s",
		"FMT_ERA_UNLOCKED": "Nueva era: %s",

		# Victory
		"LBL_VICTORY_TITLE": "VICTORIA IMPERIAL",
		"LBL_VICTORY_SUBTITLE": "Tu imperio dieselpunk ha alcanzado la cima del poder. La tormenta es tuya.",
		"LBL_STAT_TIME": "Tiempo jugado:",
		"LBL_STAT_BUILDINGS": "Edificios construidos:",
		"LBL_STAT_TRADES": "Intercambios:",
		"LBL_STAT_MILESTONES": "Hitos completados:",
		"BTN_CONTINUE": "Seguir jugando",
		"BTN_NEW_GAME": "Nueva partida",

		# Locked resources
		"LBL_LOCKED_RESOURCE": "Recurso bloqueado",
		"LBL_DEPOSIT_LOCKED": "Recurso aun no desbloqueado. Avanza de era para acceder.",

		# Population & Workers
		"LBL_POPULATION": "Poblacion: %d/%d",
		"LBL_WORKERS": "Trabajadores: %d/%d",
		"LBL_MORALE": "Moral: %d%%",
		"LBL_WORKERS_NEEDED": "Requiere %d trabajadores",
		"LBL_NO_WORKERS": "Sin trabajadores disponibles",
		"LBL_NO_WORKERS_SHORT": "SIN TRABAJADORES",
		"NOTIF_POP_GREW": "Poblacion crecio: %d/%d",
		"NOTIF_NO_WOOD": "Falta madera para la poblacion!",
		"NOTIF_NO_GOLD": "Falta oro para pagar salarios!",
		"NOTIF_LOW_MORALE": "La moral esta muy baja! Produccion reducida.",
		"NOTIF_BUILT": "%s construido!",
		"NOTIF_UPGRADE_DONE": "%s mejorado a Nv.%d!",
		"NOTIF_DEPOSIT_GONE": "%s agotado.",

		# Notifications / Log
		"BTN_LOG": "LOG",
		"LBL_LOG_TITLE": "Registro de Actividad",

		# Random Events
		"EVENT_STORM": "Tormenta",
		"EVENT_STORM_DESC": "Vientos fuertes danan las reservas de madera.",
		"EVENT_RESOURCE_FIND": "Hallazgo de Recursos",
		"EVENT_RESOURCE_FIND_DESC": "Exploradores encuentran recursos abandonados.",
		"EVENT_MINING_ACCIDENT": "Accidente Minero",
		"EVENT_MINING_ACCIDENT_DESC": "Un derrumbe en la mina. Pierdes un trabajador.",
		"EVENT_TRADE_CARAVAN": "Caravana Comercial",
		"EVENT_TRADE_CARAVAN_DESC": "Una caravana pasa por tu base y deja oro.",
		"EVENT_FESTIVAL": "Festival Popular",
		"EVENT_FESTIVAL_DESC": "Los habitantes celebran. Gran impulso a la moral.",
		"EVENT_PLAGUE": "Plaga",
		"EVENT_PLAGUE_DESC": "Una enfermedad se extiende. Moral cae drasticamente.",
		"EVENT_PLAGUE_OVER": "La plaga ha pasado.",
		"EVENT_GOOD_HARVEST": "Buena Cosecha",
		"EVENT_GOOD_HARVEST_DESC": "Los bosques cercanos dan madera extra.",
		"EVENT_BANDIT_RAID": "Ataque de Bandidos",
		"EVENT_BANDIT_RAID_DESC": "Bandidos saquean parte de tu oro.",

		# Tech Tree
		"BTN_TECH": "TECNOLOGIA",
		"LBL_TECH_TITLE": "Arbol Tecnologico",
		"FMT_RESEARCHING": "%s — %d%%",
		"NOTIF_RESEARCH_STARTED": "Investigando: %s",
		"NOTIF_RESEARCH_DONE": "Investigacion completa: %s",
		"TECH_BRANCH_INDUSTRIAL": "Industrial",
		"TECH_BRANCH_MILITARY": "Militar",
		"TECH_BRANCH_LOGISTICS": "Logistica",
		"TECH_IND_1": "Eficiencia Basica",
		"TECH_IND_2": "Almacenes Ampliados",
		"TECH_IND_3": "Produccion Avanzada",
		"TECH_IND_4": "Racionamiento",
		"TECH_IND_5": "Automatizacion",
		"TECH_MIL_1": "Disciplina",
		"TECH_MIL_2": "Entrenamiento",
		"TECH_MIL_3": "Tacticas Avanzadas",
		"TECH_MIL_4": "Fortificacion",
		"TECH_MIL_5": "Supremacia Militar",
		"TECH_LOG_1": "Rutas Comerciales",
		"TECH_LOG_2": "Red de Depositos",
		"TECH_LOG_3": "Construccion Rapida",
		"TECH_LOG_4": "Monopolio Comercial",
		"TECH_LOG_5": "Imperio Logistico",
		"LBL_PRODUCTION": "produccion",
		"LBL_STORAGE": "almacenamiento",
		"LBL_MORALE_WORD": "moral",

		# Construction Categories
		"LBL_CAT_ALL": "Todos",
		"LBL_CAT_PRODUCTION": "Produccion",
		"LBL_CAT_SUPPORT": "Soporte",
		"LBL_CAT_MILITARY": "Militar",
		"LBL_CAT_DECORATION": "Decoracion",
		"LBL_SEARCH": "Buscar...",
		"LBL_SELECT_BUILDING": "Selecciona un edificio",

		# Phase notifications (shown when a phase unlocks)
		"PHASE_1": "Tu asentamiento crece. La poblacion ahora consume recursos.",
		"PHASE_2": "El Mercado Imperial esta disponible. La moral ahora sube y baja.",
		"PHASE_3": "Eventos aleatorios comienzan. Las decoraciones ahora mejoran la moral.",
		"PHASE_4": "La era industrial ha llegado. Todos los sistemas activos.",

		# Objective hints (shown at top-center)
		"OBJ_PHASE_0": "Construye un Aserradero para empezar a producir madera.",
		"OBJ_PHASE_1": "Bien! Ahora construye una Mina de Oro para generar ingresos.",
		"OBJ_PHASE_1_DONE": "Construye un Deposito para almacenar mas recursos.",
		"OBJ_PHASE_2": "Construye un Deposito. El Mercado ya esta disponible para comerciar.",
		"OBJ_PHASE_2_DONE": "Construye una Fundicion para avanzar a la Era Industrial.",
		"OBJ_PHASE_3": "Construye una Fundicion para desbloquear el acero.",
		"OBJ_PHASE_3_DONE": "Sigue expandiendo tu imperio. Objetivo: Cuartel General Nv.3",
		"OBJ_PHASE_4": "Avanza hacia la Victoria Imperial. Construye el Cuartel General y mejoralo.",

		# Cloud Save
		"NOTIF_CLOUD_NOT_CONFIGURED": "Supabase no configurado. Usa guardado local.",
		"NOTIF_CLOUD_AUTH_FAILED": "Error de autenticacion en la nube.",
		"NOTIF_CLOUD_CONNECTED": "Conectado a la nube.",
		"NOTIF_CLOUD_SAVED": "Guardado en la nube.",
		"NOTIF_CLOUD_LOAD_FAILED": "Error al cargar desde la nube.",
		"NOTIF_CLOUD_NO_SAVE": "No hay guardado en la nube.",
		"NOTIF_CLOUD_LOADED": "Cargado desde la nube.",

		# Objective Panel
		"LBL_OBJ_TITLE": "¿QUE HACER? - OBJETIVOS",
		"LBL_OBJ_MISSION": "TU MISION",
		"LBL_OBJ_MISSION_DESC": "Transforma un asentamiento remoto en una Potencia Industrial Monumental. Debes gestionar recursos, energia y poblacion para expandir tu base.",
		"LBL_OBJ_STEPS": "PASOS INICIALES",
		"LBL_OBJ_STEP_1": "1. ENERGIA: Construye un NUCLEO para dar energia a tus edificios.",
		"LBL_OBJ_STEP_2": "2. EXTRACCION: Construye SERRERIAS y MINAS para obtener recursos basicos.",
		"LBL_OBJ_STEP_3": "3. POBLACION: Construye CASAS. Sin gente, las fabricas no funcionan.",
		"LBL_OBJ_STEP_4": "4. LOGISTICA: Conecta edificios con ALMACENES para guardar tu produccion.",
		"LBL_OBJ_STEP_5": "5. PROGRESO: Usa el Arbol Tecnologico para desbloquear edificios avanzados.",
		"LBL_OBJ_TIP": "TIP: Usa el menu de construccion (abajo a la derecha) para empezar.",
		"BTN_UNDERSTOOD": "ENTENDIDO!",
		"BTN_OBJECTIVES": "¿QUE HACER?",

		# Settings Panel
		"BTN_SETTINGS": "AJUSTES",
		"LBL_SETTINGS_TITLE": "AJUSTES",
		"LBL_SETTINGS_AUDIO": "AUDIO",
		"LBL_VOL_MASTER": "Volumen general",
		"LBL_VOL_MUSIC": "Musica",
		"LBL_VOL_SFX": "Efectos de sonido",
		"LBL_SETTINGS_UI": "INTERFAZ",
		"LBL_SHOW_GRID": "Mostrar cuadricula del mapa",

		# Army / Units
		"BTN_ARMY": "EJERCITO",
		"LBL_ARMY_TITLE": "CUARTEL - EJERCITO",
		"UNIT_INFANTRY": "Infanteria",
		"UNIT_ARTILLERY": "Artilleria",
		"UNIT_VEHICLE": "Vehiculo Blindado",
		"LBL_MILITARY_POWER": "Poder Militar: %d",
		"LBL_ARMY_CAPACITY": "Capacidad: %d / %d",
		"LBL_ARMY_SLOTS": "Entrenamiento: %d / %d ranuras",
		"LBL_ARMY_OWNED": "Tienes: %d",
		"LBL_ARMY_TIER": "Nivel %d",
		"LBL_ARMY_POWER_EACH": "Poder %d",
		"LBL_ARMY_UPKEEP": "Mantenimiento %d oro",
		"LBL_ARMY_IN_TRAINING": "En entrenamiento",
		"BTN_TRAIN": "ENTRENAR",
		"LBL_ARMY_NO_UNIT": "Unidad desconocida",
		"LBL_ARMY_NEED_BARRACKS": "Necesitas un Cuartel",
		"LBL_ARMY_LOCKED": "Bloqueada (era superior)",
		"LBL_ARMY_SLOTS_FULL": "Ranuras de entrenamiento llenas",
		"LBL_ARMY_AT_CAP": "Ejercito al maximo",
		"LBL_ARMY_EMPTY": "Aun no tienes tropas. Entrena unidades en el Cuartel.",
		"NOTIF_UPKEEP_UNPAID": "Sin oro para el ejercito: faltan %d oro",

		# Building Info extras
		"LBL_POP_CAPACITY": "+%d poblacion",
		"LBL_MORALE_BONUS": "+%d moral",
		"LBL_ROTATE_BUILDING": "Rotar edificio (R)",

		# Tech bonuses
		"FMT_SPREAD_REDUCTION": "-%d%% margen",
		"FMT_CONSUMPTION_REDUCTION": "-%d%% consumo",
		"FMT_BUILD_SPEED": "+%d%% velocidad",
	},
	"en": {
		"BTN_BUILD": "BUILD",
		"BTN_CLOSE": "Close",
		"BTN_MOVE": "Move",
		"BTN_DEMOLISH": "Demolish",
		"BTN_RENAME": "Rename",
		"BTN_CLEAR": "CLEAR",
		"BTN_UPGRADE": "Upgrade",
		"BTN_CONFIRM": "Confirm",
		"BTN_CANCEL": "Cancel",

		"LBL_ACTIONS": "Actions",
		"LBL_NO_ACTIONS": "No actions available",
		"LBL_BUILDINGS_AVAILABLE": "Available buildings",
		"LBL_BUILDING_NAME_PLACEHOLDER": "Building name...",
		"LBL_FREE": "Free",
		"LBL_NATURAL_RESOURCE": "Natural resource available for extraction.",
		"LBL_LEVEL": "Level %d",
		"LBL_MAX_LEVEL": "Max level",
		"LBL_UPGRADE_TO": "Upgrade to Level %d",
		"LBL_STORAGE_CAP": "Storage: %d/%d",
		"LBL_LIMIT_REACHED": "Limit reached (%d/%d)",
		"LBL_REQUIRES": "Requires: %s",
		"LBL_REQUIRES_DEPOSIT": "Must be placed on an oil deposit",
		"LBL_NOT_ENOUGH_RESOURCES": "Not enough resources!",
		"LBL_UPGRADE_COMPLETE": "Upgrade complete!",

		"FMT_COST": "Cost: %s",
		"FMT_PRODUCES": "Produces: %s",
		"FMT_PRODUCES_EVERY": "Produces: %s every %ds",
		"FMT_PROGRESS": "%s — %ds remaining",
		"FMT_CONSTRUCTION": "Building: %d%% — %ds remaining",
		"FMT_CONSTRUCTING": "Building %d%%",
		"FMT_UPGRADING": "Upgrading %d%%",
		"FMT_CONSTRUCTION_COMPLETE": "Construction complete!",
		"FMT_DURATION": "Duration: %ds",
		"FMT_OFFLINE_TITLE": "While you were away (%s)",
		"FMT_DEMOLISH_CONFIRM": "Demolish %s?\nRefund: %d%%",
		"LBL_DEPOSIT_USES": "%d uses remaining",
		"LBL_DEPOSIT_DEPLETED": "Deposit depleted!",

		"DEP_GOLD_VEIN": "Gold Vein",
		"DEP_IRON": "Iron",
		"DEP_OIL": "Oil Well",
		"DEP_FOREST": "Forest",

		"PROC_WOOD_PLANKS": "Wood Planks",
		"PROC_IRON_SHEETS": "Iron Sheets",
		"PROC_WATER_PIPES": "Water Pipes",
		"PROC_REFINED_LUMBER": "Refined Lumber",
		"PROC_CHARCOAL": "Charcoal",
		"PROC_DEEP_MINING": "Deep Mining",
		"PROC_GEM_EXTRACTION": "Gem Extraction",
		"PROC_ALLOY_SMELTING": "Alloy Smelting",
		"PROC_ARMOR_PLATES": "Armor Plates",
		"PROC_FUEL_DISTILLATION": "Fuel Distillation",
		"PROC_CHEMICAL_PROCESSING": "Chemical Processing",
		"PROC_MINE_GOLD": "Mine Gold",
		"PROC_MINE_IRON": "Mine Iron",
		"PROC_MINE_OIL": "Extract Oil",
		"PROC_MINE_WOOD": "Chop Trees",

		# Market
		"BTN_MARKET": "MARKET",
		"BTN_BUY": "Buy",
		"BTN_SELL": "Sell",
		"LBL_MARKET_TITLE": "Imperial Market",
		"LBL_RESOURCE": "Resource",
		"LBL_BUY_PRICE": "Buy",
		"LBL_SELL_PRICE": "Sell",
		"LBL_AMOUNT": "Qty.",
		"LBL_YOUR_GOLD": "Your gold: %d",

		# Progression
		"BTN_PROGRESS": "PROGRESS",
		"LBL_PROGRESS_TITLE": "Imperial Progress",
		"LBL_CURRENT_ERA": "Current era",

		# Eras
		"ERA_FRONTIER": "Frontier",
		"ERA_INDUSTRIAL": "Industrial",
		"ERA_PETROLEUM": "Petroleum",

		# Milestones
		"MILE_PIONEER": "Pioneer — Build Sawmill",
		"MILE_PROSPECTOR": "Prospector — Build Gold Mine",
		"MILE_STOCKPILER": "Stockpiler — Build Warehouse",
		"MILE_INDUSTRIALIST": "Industrialist — Build Foundry",
		"MILE_OIL_BARON": "Oil Baron — Build Refinery",
		"MILE_MERCHANT": "Merchant — 10 trades",
		"MILE_COMMANDER": "Commander — Barracks + 2 Towers",
		"MILE_GENERAL": "General — Build Headquarters",
		"MILE_VICTORY": "Imperial Victory — Headquarters Lv.3",
		"FMT_MILESTONE_COMPLETE": "Milestone complete: %s",
		"FMT_ERA_UNLOCKED": "New era: %s",

		# Victory
		"LBL_VICTORY_TITLE": "IMPERIAL VICTORY",
		"LBL_VICTORY_SUBTITLE": "Your dieselpunk empire has reached the pinnacle of power. The storm is yours.",
		"LBL_STAT_TIME": "Time played:",
		"LBL_STAT_BUILDINGS": "Buildings built:",
		"LBL_STAT_TRADES": "Trades:",
		"LBL_STAT_MILESTONES": "Milestones completed:",
		"BTN_CONTINUE": "Keep playing",
		"BTN_NEW_GAME": "New game",

		# Locked resources
		"LBL_LOCKED_RESOURCE": "Resource locked",
		"LBL_DEPOSIT_LOCKED": "Resource not yet unlocked. Advance your era to access.",

		# Population & Workers
		"LBL_POPULATION": "Population: %d/%d",
		"LBL_WORKERS": "Workers: %d/%d",
		"LBL_MORALE": "Morale: %d%%",
		"LBL_WORKERS_NEEDED": "Requires %d workers",
		"LBL_NO_WORKERS": "No workers available",
		"LBL_NO_WORKERS_SHORT": "NO WORKERS",
		"NOTIF_POP_GREW": "Population grew: %d/%d",
		"NOTIF_NO_WOOD": "Not enough wood for the population!",
		"NOTIF_NO_GOLD": "Not enough gold to pay wages!",
		"NOTIF_LOW_MORALE": "Morale is very low! Production reduced.",
		"NOTIF_BUILT": "%s built!",
		"NOTIF_UPGRADE_DONE": "%s upgraded to Lv.%d!",
		"NOTIF_DEPOSIT_GONE": "%s depleted.",

		# Notifications / Log
		"BTN_LOG": "LOG",
		"LBL_LOG_TITLE": "Activity Log",

		# Random Events
		"EVENT_STORM": "Storm",
		"EVENT_STORM_DESC": "Strong winds damage wood reserves.",
		"EVENT_RESOURCE_FIND": "Resource Find",
		"EVENT_RESOURCE_FIND_DESC": "Scouts discover abandoned resources.",
		"EVENT_MINING_ACCIDENT": "Mining Accident",
		"EVENT_MINING_ACCIDENT_DESC": "A cave-in at the mine. You lose a worker.",
		"EVENT_TRADE_CARAVAN": "Trade Caravan",
		"EVENT_TRADE_CARAVAN_DESC": "A caravan passes through and leaves gold.",
		"EVENT_FESTIVAL": "Festival",
		"EVENT_FESTIVAL_DESC": "The people celebrate. Big morale boost.",
		"EVENT_PLAGUE": "Plague",
		"EVENT_PLAGUE_DESC": "Disease spreads. Morale drops drastically.",
		"EVENT_PLAGUE_OVER": "The plague has passed.",
		"EVENT_GOOD_HARVEST": "Good Harvest",
		"EVENT_GOOD_HARVEST_DESC": "Nearby forests yield extra wood.",
		"EVENT_BANDIT_RAID": "Bandit Raid",
		"EVENT_BANDIT_RAID_DESC": "Bandits loot some of your gold.",

		# Tech Tree
		"BTN_TECH": "TECH",
		"LBL_TECH_TITLE": "Tech Tree",
		"FMT_RESEARCHING": "%s — %d%%",
		"NOTIF_RESEARCH_STARTED": "Researching: %s",
		"NOTIF_RESEARCH_DONE": "Research complete: %s",
		"TECH_BRANCH_INDUSTRIAL": "Industrial",
		"TECH_BRANCH_MILITARY": "Military",
		"TECH_BRANCH_LOGISTICS": "Logistics",
		"TECH_IND_1": "Basic Efficiency",
		"TECH_IND_2": "Expanded Storage",
		"TECH_IND_3": "Advanced Production",
		"TECH_IND_4": "Rationing",
		"TECH_IND_5": "Automation",
		"TECH_MIL_1": "Discipline",
		"TECH_MIL_2": "Training",
		"TECH_MIL_3": "Advanced Tactics",
		"TECH_MIL_4": "Fortification",
		"TECH_MIL_5": "Military Supremacy",
		"TECH_LOG_1": "Trade Routes",
		"TECH_LOG_2": "Depot Network",
		"TECH_LOG_3": "Rapid Construction",
		"TECH_LOG_4": "Trade Monopoly",
		"TECH_LOG_5": "Logistics Empire",
		"LBL_PRODUCTION": "production",
		"LBL_STORAGE": "storage",
		"LBL_MORALE_WORD": "morale",

		# Construction Categories
		"LBL_CAT_ALL": "All",
		"LBL_CAT_PRODUCTION": "Production",
		"LBL_CAT_SUPPORT": "Support",
		"LBL_CAT_MILITARY": "Military",
		"LBL_CAT_DECORATION": "Decoration",
		"LBL_SEARCH": "Search...",
		"LBL_SELECT_BUILDING": "Select a building",

		# Phase notifications
		"PHASE_1": "Your settlement grows. Population now consumes resources.",
		"PHASE_2": "The Imperial Market is open. Morale now rises and falls.",
		"PHASE_3": "Random events begin. Decorations now improve morale.",
		"PHASE_4": "The industrial era has arrived. All systems active.",

		# Objective hints
		"OBJ_PHASE_0": "Build a Sawmill to start producing wood.",
		"OBJ_PHASE_1": "Good! Now build a Gold Mine to generate income.",
		"OBJ_PHASE_1_DONE": "Build a Warehouse to store more resources.",
		"OBJ_PHASE_2": "Build a Warehouse. The Market is now open for trade.",
		"OBJ_PHASE_2_DONE": "Build a Foundry to advance to the Industrial Era.",
		"OBJ_PHASE_3": "Build a Foundry to unlock steel.",
		"OBJ_PHASE_3_DONE": "Keep expanding. Goal: Headquarters Level 3.",
		"OBJ_PHASE_4": "Push for Imperial Victory. Build and upgrade Headquarters.",

		# Cloud Save
		"NOTIF_CLOUD_NOT_CONFIGURED": "Supabase not configured. Using local save.",
		"NOTIF_CLOUD_AUTH_FAILED": "Cloud authentication failed.",
		"NOTIF_CLOUD_CONNECTED": "Connected to cloud.",
		"NOTIF_CLOUD_SAVED": "Saved to cloud.",
		"NOTIF_CLOUD_LOAD_FAILED": "Failed to load from cloud.",
		"NOTIF_CLOUD_NO_SAVE": "No cloud save found.",
		"NOTIF_CLOUD_LOADED": "Loaded from cloud.",

		# Objective Panel
		"LBL_OBJ_TITLE": "WHAT TO DO? - OBJECTIVES",
		"LBL_OBJ_MISSION": "YOUR MISSION",
		"LBL_OBJ_MISSION_DESC": "Transform a remote settlement into a Monumental Industrial Power. Manage resources, energy, and population to expand your base.",
		"LBL_OBJ_STEPS": "INITIAL STEPS",
		"LBL_OBJ_STEP_1": "1. ENERGY: Build a CORE to power your buildings.",
		"LBL_OBJ_STEP_2": "2. EXTRACTION: Build SAWMILLS and MINES to obtain basic resources.",
		"LBL_OBJ_STEP_3": "3. POPULATION: Build HOUSES. Without people, factories don't work.",
		"LBL_OBJ_STEP_4": "4. LOGISTICS: Connect buildings with WAREHOUSES to store production.",
		"LBL_OBJ_STEP_5": "5. PROGRESS: Use the Tech Tree to unlock advanced buildings.",
		"LBL_OBJ_TIP": "TIP: Use the construction menu (bottom right) to get started.",
		"BTN_UNDERSTOOD": "GOT IT!",
		"BTN_OBJECTIVES": "WHAT TO DO?",

		# Settings Panel
		"BTN_SETTINGS": "SETTINGS",
		"LBL_SETTINGS_TITLE": "SETTINGS",
		"LBL_SETTINGS_AUDIO": "AUDIO",
		"LBL_VOL_MASTER": "Master volume",
		"LBL_VOL_MUSIC": "Music",
		"LBL_VOL_SFX": "Sound effects",
		"LBL_SETTINGS_UI": "INTERFACE",
		"LBL_SHOW_GRID": "Show map grid",

		# Army / Units
		"BTN_ARMY": "ARMY",
		"LBL_ARMY_TITLE": "BARRACKS - ARMY",
		"UNIT_INFANTRY": "Infantry",
		"UNIT_ARTILLERY": "Artillery",
		"UNIT_VEHICLE": "Armored Vehicle",
		"LBL_MILITARY_POWER": "Military Power: %d",
		"LBL_ARMY_CAPACITY": "Capacity: %d / %d",
		"LBL_ARMY_SLOTS": "Training: %d / %d slots",
		"LBL_ARMY_OWNED": "Owned: %d",
		"LBL_ARMY_TIER": "Tier %d",
		"LBL_ARMY_POWER_EACH": "Power %d",
		"LBL_ARMY_UPKEEP": "Upkeep %d gold",
		"LBL_ARMY_IN_TRAINING": "In training",
		"BTN_TRAIN": "TRAIN",
		"LBL_ARMY_NO_UNIT": "Unknown unit",
		"LBL_ARMY_NEED_BARRACKS": "Requires a Barracks",
		"LBL_ARMY_LOCKED": "Locked (higher era)",
		"LBL_ARMY_SLOTS_FULL": "Training slots full",
		"LBL_ARMY_AT_CAP": "Army at capacity",
		"LBL_ARMY_EMPTY": "No troops yet. Train units at the Barracks.",
		"NOTIF_UPKEEP_UNPAID": "No gold for the army: %d gold short",

		# Building Info extras
		"LBL_POP_CAPACITY": "+%d population",
		"LBL_MORALE_BONUS": "+%d morale",
		"LBL_ROTATE_BUILDING": "Rotate building (R)",

		# Tech bonuses
		"FMT_SPREAD_REDUCTION": "-%d%% spread",
		"FMT_CONSUMPTION_REDUCTION": "-%d%% consumption",
		"FMT_BUILD_SPEED": "+%d%% build speed",
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

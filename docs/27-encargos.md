# 27 · Encargos

Rama `feat/encargos` (2026-10-14), fila 2.4 del rediseño (contexto privado, doc 21
§2.3, que retoma el doc 14 §P3). Contenido de la 1.1. **Sin probar todavía**: se
escribió sin lanzar Godot; los tests están escritos y pendientes del pase final.

## 1. Qué es

Un **tablón de 3 encargos** con plazo y premio a la vista: "entrega X antes de que
se acabe el tiempo y te dan Z". Hay un hueco por fuente:

| Fuente | Desde | Qué pide | Qué paga |
|---|---|---|---|
| **La Regencia** (`regency`) | Era 2 (con el acero) | Acero, vigas, lingotes; en la era 3 petróleo y combustible | **Rebaja del próximo Diezmo** (10-15 %) |
| **Los vecinos** (`neighbors`) | Era 1 | Madera, comida, oro, tablones | **Moral**; **colonos** cuando exista `PopulationManager.add_colonists` (rama 2.3) |
| **El contrabandista** (`smuggler`) | Era 1 | Madera y materiales del taller (tablones, lingotes, vigas, combustible) | **Oro**, o lo que aún escasea (acero a cambio de madera, petróleo a cambio de acero) |

- Los encargos **usan los materiales**, que antes solo servían para construir.
- **Premios fijos y visibles**: el premio se decide al aparecer el encargo y no
  cambia hasta que se entrega o se va. Nada de cajas sorpresa.
- **Colono**: dejar pasar o rechazar un encargo no castiga.
- **Gobernador**: dejar pasar o rechazar baja en 1 la reputación con quien lo pidió
  (suelo `contract_reputation_min` = −3). Cada punto recorta los premios del
  siguiente encargo de esa fuente un 15 % (`contract_reputation_step`). Cumplir uno
  la sube en 1, hasta 0. El panel lo dice: "Pagan el 70 %".

## 2. Piezas

| Pieza | Archivo | Qué hace |
|---|---|---|
| Modelo puro | `scripts/economy/ContractBoard.gd` | Tres huecos, esperas, plazos, sorteo con su propio `RandomNumberGenerator`, reputación. Sin nodos ni señales: `advance()`, `deliver()` y `discard()` devuelven eventos (`offered`, `delivered`, `expired`, `discarded`). Sin `class_name`: se usa con `preload` |
| Servicio | `scripts/services/ContractManager.gd` (autoload, el último) | Hace avanzar el tablón con el tiempo de juego (`sim_delta`; parado sin partida, en Sandbox y con un combate abierto), cobra lo pedido, paga el premio y publica en el EventBus |
| Panel | `scripts/ui/ContractPanel.gd`, `scenes/ui/ContractPanel.tscn` | ENCARGOS: una tarjeta por fuente con reloj, "Piden" (en rojo lo que falta), "Dan" (iconos y cifras), ENTREGAR y "No, gracias". Botones a dedo (170×52). Se abre desde ☰ MENÚ → COLONIA → ENCARGOS |
| ¿QUÉ HACER? | `Objectives.contract_step()` + una línea en `ObjectivePanel` | Paso aparte, **fuera de `next_step()`** (la línea y `line_probe` no cambian): "Entrega el encargo: Los vecinos" cuando uno ya se puede entregar |

El panel está en `Main.tscn` y `Main2D.tscn` (justo antes de `PauseMenu`) y en la
lista de `tests/view2d/test_view_mode.gd`. Su hueco es `ContractPanel.modal` →
`center_modal`, 620 px de ancho (`UILayoutConfig`). No es un elemento del HUD, así
que no va en `HudRegistry`.

## 3. Cómo se paga cada premio

| Clase | Dónde va |
|---|---|
| `gold`, `wood`, `steel`, `oil`, `food`, materiales | `ResourceManager.add()` (lo que no cabe en la bolsa se pierde con el aviso de siempre) |
| `morale` | `PopulationManager.adjust_morale()`. Solo se sortean encargos con moral desde la fase ECONOMÍA: antes la moral está fija y el premio sería mentira (`ctx.morale_ok`) |
| `colonists` | `PopulationManager.add_colonists()` **si existe** (`has_method`). Mientras no exista, esas plantillas no salen (`ctx.colonists_ok`) |
| `tithe_discount` | Un único método aditivo de StormManager: `add_tithe_discount(source: String, pct: float, notify := true) -> float`, de la rama `feat/orden-regencia` (PR #53). Se llama con `source` = `"contrato"` y `pct` en fracción (10 % → 0,10); es aditiva, con tope 0,5, y dura hasta el próximo Diezmo. Si devuelve −1 (no la apuntó) se paga `contract_tithe_fallback_gold` en oro. Se llama con `has_method`, así que esta rama compila sin ella. Mientras no exista, o sin Diezmo (Constructor), la Regencia **paga en oro** (`contract_tithe_fallback_gold`, con la escala de era): el cambio se hace al sortear, así el premio que se ve es el que se cobra |

Además, cada encargo cumplido suma `contract_rank_xp` (20) de rango (doc 21 §2.5) y
suena `milestone` (AudioManager escucha `contract_delivered`).

## 4. Valores (`GameConfig`, todos `contract_*`, al final del archivo)

| Clave | Valor | Para qué |
|---|---|---|
| `contract_source_era` | Regencia 2, vecinos 1, contrabandista 1 | Era desde la que encarga cada fuente |
| `contract_first_delay` | Regencia 45 s, vecinos 90 s, contrabandista 360 s | Primera espera, contada desde que la fuente se abre |
| `contract_cooldown` | 120 s | Espera tras entregar, dejar pasar o rechazar |
| `contract_retry_delay` | 30 s | Si ninguna plantilla cabe aún, se vuelve a mirar tras esto |
| `contract_era_step` | 0,5 | Lo pedido y lo pagado en recursos crece ×1,5 por cada era por encima de la de la plantilla. Moral, colonos y rebaja no crecen |
| `contract_reputation_min` / `_step` | −3 / 0,15 | Solo Gobernador |
| `contract_tithe_fallback_gold` | 150 | La Regencia sin Diezmo |
| `contract_rank_xp` | 20 | XP por encargo cumplido |
| `contract_templates` | 6 vecinos, 7 contrabandista, 5 Regencia | `id`, `era`, `ask`, `minutes`, `reward` |

Todas las duraciones pasan por `GameConfig.get_duration()` (modo dev ×0,2).
**Sin medir con `tools/line_probe.gd`**: el contrabandista convierte madera y
materiales en oro por encima del mercado a propósito, y eso puede adelantar la era 1
(hoy la Fundición llega en el minuto 4,6-4,9). Por eso su primer encargo espera 6
minutos. Medir antes de dar los valores por buenos.

## 5. Por modo

`GameConfig.game_mode_rules` lleva `"contracts"`: `true` en la Campaña (y por
herencia en Constructor y Supervivencia), `false` en Sandbox (con recursos infinitos
un encargo no pide nada). Se pregunta con `GameMode.contracts_enabled()`. En
Constructor la Regencia sigue encargando pero paga en oro (no hay Diezmo).

## 6. Guardado

Clave `"contracts"` en `save_game.json` (`ContractBoard.to_dict()`): los tres
huecos con su encargo tal cual se vio, las esperas, la reputación, el último
modelo de cada fuente y contadores (`delivered`, `failed`, `next_id`).

- `ContractManager.load_save_data()` **reemplaza** el tablón por el guardado:
  cargar dos veces da lo mismo.
- Sin clave (guardado de antes) o con basura: tablón nuevo, con la primera espera
  de cada fuente. Un encargo guardado sin `ask`/`reward`/plazo se descarta.
- `reset()` en los tres sitios de `GameManager` (`_new_game()`, `clear_save()`,
  `clear_save_and_reload_from()`), sin avisos.
- El dado no se guarda (como `StormCycle`): lo que ya salió está guardado; lo que
  salga después no tiene por qué repetirse.

## 7. Tests (escritos, sin correr)

- `tests/economy/test_contract_board.gd`: el modelo (huecos, era de la Regencia,
  premio fijo, plazos, reputación y su suelo, oro sin Diezmo, nada bloqueado,
  escala por era, misma semilla, ida y vuelta por JSON, guardado roto).
- `tests/economy/test_contract_manager.gd`: cobrar y pagar, sin alcanzar no se
  mueve nada, rechazar, carga idempotente, guardado viejo, reset, Sandbox sin
  tablón, el paso de ¿QUÉ HACER?, el contexto en Gobernador.
- `tests/ui/test_contract_panel.gd`: tres tarjetas, ENTREGAR apagado si falta
  algo, premio con icono, entrada en ☰ MENÚ.
- `tests/view2d/test_view_mode.gd`: `ContractPanel` en las dos escenas.

## 8. Pendiente

- Probarlo: `--import` (genera los `.uid` de los archivos nuevos), las cuatro
  suites de arriba y la suite entera; el panel en tablet (3 tarjetas con scroll).
- Medir el ritmo con `line_probe` (su jugador no entrega encargos todavía).
- Colonos y "una decoración gratis" de los vecinos, y repuestos/planos del
  contrabandista, cuando existan (ramas 2.3 y 1.7).
- La Orden de la Regencia (rama 2.1) puede citar el encargo de la Regencia como su
  opción 2: `ContractManager.get_contract("regency")`.

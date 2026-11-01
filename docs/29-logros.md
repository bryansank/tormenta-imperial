# 29 · Logros y estadísticas

Rama `feat/logros-estadisticas` (2026-11-01). Sin probar todavía en partida: el
dueño prueba al final (regla "implementar primero, probar al final").

## 1. Qué es

Dos cosas distintas que se ven en la misma ventana:

| | Logros | Estadísticas |
|---|---|---|
| De quién son | Del **jugador en este dispositivo** (perfil) | De la **partida** |
| Dónde viven | `settings.cfg` → `[perfil] achievements` (id → hora unix) | Guardado, clave `stats` |
| Partida nueva | Se quedan | Vuelven a cero |
| Sandbox | No se gana ninguno | Se cuentan igual |

Un logro es siempre "este contador de la partida llega a esta meta". Por eso casi
todos dicen "en una partida": empezar otra no suma a lo de antes. Los totales de
por vida no existen todavía (ver §7).

## 2. Piezas

- **`AchievementManager`** (`scripts/services/AchievementManager.gd`, autoload, el
  último de `project.godot`). Escucha el EventBus, sube contadores y, cuando uno
  llega a la meta de un logro, lo apunta en el perfil
  (`GameConfig.record_achievement`), emite `EventBus.achievement_unlocked(id)` y
  manda el aviso "Nuevo logro: …" por `notification_posted` con categoría
  `"achievement"` (la misma cola que hitos, eras y ascensos: espera si hay una
  ventana o el tablero abiertos). Sin `_process`: solo mira los logros del
  contador que acaba de cambiar.
- **Datos** en `GameConfig` (bloque "Logros y estadisticas" al final):
  `achievement_definitions` (id, grupo, contador, meta, icono, secreto),
  `achievement_groups` (orden de los grupos) y `achievement_stat_rows` (las cifras
  de la pestaña Estadísticas). El perfil: `profile_achievements`, leído y escrito
  con el resto de `[perfil]`.
- **Regla de modo** `achievements` en `game_mode_rules` (la añade
  `_register_achievements()`): Campaña, Constructor y Supervivencia sí; Sandbox no.
  Se pregunta con `GameMode.achievements_enabled()`, nunca comparando el modo.
- **Sonido**: `AudioManager` toca `milestone` al oír `achievement_unlocked` (sin
  sonido nuevo).
- **Ventana** `AchievementsPanel` (`scripts/ui/AchievementsPanel.gd`): ver §5.

## 3. Los 31 logros

| Grupo | Id | Nombre (ES) | Qué pide | Contador ≥ meta |
|---|---|---|---|---|
| Construir | `first_stone` | Primera piedra | Termina tu primer edificio | `buildings_built` 1 |
| | `builder_25` | Manos a la obra | 25 edificios en una partida | `buildings_built` 25 |
| | `roads_150` | Todos los caminos | 150 tramos de carretera | `roads_built` 150 |
| | `level_3` | Al máximo | Un edificio a nivel 3 | `max_level` 3 |
| | `demolish_20` *(secreto)* | Cambio de planes | Derriba 20 construcciones | `buildings_demolished` 20 |
| Economía | `era_2` | Humo de fundición | Era Industrial | `era` 2 |
| | `era_3` | Oro negro | Era Petrolera | `era` 3 |
| | `trader_50` | Buen regateo | 50 tratos en el Mercado | `trades` 50 |
| | `harvest_5000` | Despensa llena | Recoge 5.000 recursos | `resources_collected` 5000 |
| | `tech_15` | Sabelotodo | Las 15 tecnologías | `techs_researched` 15 |
| | `contracts_10` | Palabra cumplida | 10 encargos entregados | `contracts_delivered` 10 |
| | `smuggler_5` *(secreto)* | Yo no he visto nada | 5 tratos con el contrabandista | `smuggler_deals` 5 |
| Tormenta | `storm_1` | Después de la ceniza | Tu primera Tormenta | `storms` 1 |
| | `storm_10` | Piel curtida | 10 Tormentas | `storms` 10 |
| | `tithe_repel_1` | Hoy no se cobra | Echa a los Cobradores sin pagar | `tithes_repelled` 1 |
| | `tithe_repel_5` | Puerta cerrada | Échalos 5 veces | `tithes_repelled` 5 |
| | `tax_payer` *(secreto)* | Contribuyente modelo | Paga el Impuesto 10 veces | `tithes_paid` 10 |
| Combate | `win_1` | Primera victoria | Gana tu primer combate | `fights_won` 1 |
| | `win_50` | Veterano | 50 combates | `fights_won` 50 |
| | `flawless` | Sin un rasguño | Gana sin perder ni una unidad | `flawless_wins` 1 |
| | `routed` | ¡Que corran! | El enemigo huye del tablero | `routs` 1 |
| | `campaign_land` | Dueño de la tierra | Campaña de Tierra | `campaign_land` 1 |
| | `campaign_sea` | Dueño del mar | Campaña de Mar | `campaign_sea` 1 |
| | `campaign_air` | Dueño del cielo | Campaña de Aire | `campaign_air` 1 |
| | `deserters` *(secreto)* | ¿Y la paga? | Tus soldados se van sin paga | `deserters` 1 |
| El final | `audit_won` | La Tormenta calla | Sobrevive al Ataque Final | `audits_won` 1 |
| | `ending_sign` | Ahora cobras tú | Firma el libro del Impuesto | `ending_sign` 1 |
| | `ending_burn` | Que arda | Quema el libro | `ending_burn` 1 |
| | `archipelago` | Señor de las islas | Las seis islas vecinas | `archipelago` 1 |
| | `rank_18` | Lo más alto | Rango 18 | `rank` 18 |
| | `governor_win` | Gobernador de verdad | Gana el Ataque Final en Gobernador | `governor_wins` 1 |

Textos: `ACH_<ID>_NAME` / `ACH_<ID>_DESC` en `Tr.gd` (ES y EN), bloque "Logros y
estadisticas". Un secreto sin ganar se ve como "???" / "Logro secreto. Sigue
jugando.".

## 4. De dónde sale cada contador

| Contador | Señal | Nota |
|---|---|---|
| `buildings_built` | `construction_completed` | Sin Núcleo ni carreteras |
| `roads_built` | `building_placed` con `road` | Incluye la carretera automática pagada |
| `upgrades`, `max_level` | `building_upgrade_completed` | `max_level` es un máximo |
| `buildings_demolished` | `building_demolished` | Cuenta también tramos de carretera |
| `resources_collected` | `production_collected` | Suma de lo que entró en la bolsa |
| `trades` | `market_trade_completed` | |
| `techs_researched` | `milestone_completed` con `tech_*` | TechTreeManager las anuncia así |
| `contracts_delivered` | `contract_delivered` | |
| `smuggler_deals` | `smuggler_offer_taken` | |
| `units_trained` | `unit_trained` | |
| `deserters` | `army_deserted` | Suma las unidades que se fueron |
| `units_lost` / `enemies_defeated` | `unit_died` (lado 0 / 1) | Solo en tablero |
| `fights_won` / `fights_lost` | `encounter_ended`, `defense_auto_resolved` | |
| `flawless_wins` | `encounter_ended` ganado sin `unit_died` propio desde `encounter_started` | El conteo de la pelea no se guarda (las peleas tampoco) |
| `routs` | `enemy_routed` | |
| `expeditions_won` | `expedition_ended` con 0 | |
| `campaign_missions` | `campaign_mission_won` | |
| `campaign_land/sea/air` | `campaign_completed` | |
| `storms` | `storm_ended` | También la de prueba de la era 1 |
| `tithes_repelled` / `tithes_paid` | `tithe_resolved` | No cuenta sin Impuesto en el modo ni durante el Ataque Final (esos emiten `(true, {})` sin pelea) |
| `audits_won` | `storm_halted_forever` | |
| `governor_wins` | `victory_achieved` en Gobernador | |
| `ending_sign` / `ending_burn` | `ending_chosen` | |
| `islands_conquered`, `archipelago` | `island_conquered`, `archipelago_conquered` | |
| `era`, `rank` | `era_advanced`, `governor_xp_changed` | Máximos; al cargar se derivan de ProgressionManager y RankManager |
| Tiempo jugado | — | Se lee de `ProgressionManager.get_played_seconds()`, no se duplica |

Al cargar o empezar partida (`game_load_completed`, `game_new_started`) se
repasan todos los logros: uno añadido en una versión posterior puede estar ya
cumplido por la partida que se carga.

## 5. La ventana

**LOGROS Y ESTADÍSTICAS** se abre desde la tarjeta de la colonia (tocar el rango
→ fila `ColonyHub` → **LOGROS**, icono de copa `trophy`, nuevo en `CartoonIcon`).
No está en `Main.tscn` ni en `Main2D.tscn`: `RankPanel` la crea de hermana al
arrancar (`_mount_achievements`, igual que `VictoryScreen` con el archipiélago),
así que la lista de `tests/view2d/test_view_mode.gd` no cambia. Se construye al
abrirla por primera vez; sin `_process`.

- Ventana de `CartoonTheme.modal_window` (piel dieselpunk), slot `center_modal`
  (`AchievementsPanel.modal` en `UILayoutConfig.PANEL_SLOTS`), tope 980x600 en PC,
  pantalla completa en teléfono.
- Arriba: pestañas **Logros** / **Estadísticas** (`CartoonTheme.tab`, 48 dp en
  teléfono) y "12 de 31 logros".
- **Logros**: por grupos, una ficha por logro: icono, nombre, qué pide y, si no
  está ganado, barra y "12/25" con lo que lleva esta partida; ganado, sello verde
  "Conseguido". Dos columnas en PC, una en teléfono.
- **Estadísticas**: "En esta partida" (las cifras de `achievement_stat_rows`) y
  "En este dispositivo" (logros, partidas terminadas, campañas ganadas). Tres
  columnas en PC, dos en teléfono.
- Pie: de qué van los logros (en teléfono, al mantener la cinta) o, en Sandbox,
  "En Sandbox no se ganan logros." siempre visible.

## 6. Guardado

- `stats` en el guardado: `{contador: entero}`. `load_save_data()` es idempotente
  (sustituye, no suma), ignora contadores desconocidos y valores ≤ 0; sin la clave,
  todo a cero. `reset()` se llama en los tres sitios de GameManager (`_new_game`,
  `clear_save`, `clear_save_and_reload_from`) y nunca toca el perfil.
- `[perfil] achievements` en `settings.cfg`: se escribe en cuanto se gana un logro.
  Al leerlo se tiran los ids que ya no existen (`GameConfig._clean_achievements`).
  `tests/save/settings_parking.gd` aparca también `profile_achievements`.

## 7. Pendiente y decisiones abiertas

- **Sin probar en partida.** Tests nuevos (sin ejecutar):
  `tests/economy/test_achievements.gd`, `tests/ui/test_achievements_panel.gd`.
- **Totales de por vida** (edificios de todas las partidas, etc.): no están. Si se
  quieren, irían en `[perfil]` y se escribirían al guardar, no en cada contador.
- **Los hitos ya dicen "Logro conseguido: …"** (`FMT_MILESTONE_COMPLETE`). Los
  logros nuevos dicen "Nuevo logro: …". Conviene que los hitos digan "Hito" para no
  confundir.
- **Otros tests que emiten señales** (obras, peleas, Impuestos) ahora también
  pueden ganar logros y escribir `settings.cfg` en la carpeta de pruebas, y un aviso
  "achievement" más. Si alguna suite cuenta avisos o compara `settings.cfg`, puede
  necesitar ajuste.
- **Teléfono**: la fila `ColonyHub` tiene una pastilla más; hay que mirar con
  `tools/desborde_probe.gd` que la tarjeta de la colonia sigue cabiendo en 360 de
  alto.
- Metas sin medir con `line_probe` (por ejemplo, si 150 tramos o 5.000 recursos
  llegan en una partida normal de Colono).

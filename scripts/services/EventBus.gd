extends Node
## Global signal bus for decoupled communication between systems.
## All game-wide events flow through here. Systems emit signals, others subscribe.
## Signals are emitted/connected from external scripts, so we suppress unused warnings.

# ── Camera ──
@warning_ignore("unused_signal")
signal camera_pan_requested(direction: Vector2)
@warning_ignore("unused_signal")
signal camera_zoom_requested(amount: float)
@warning_ignore("unused_signal")
signal camera_drag_moved(delta: Vector2)
## World-space grab-pan: move the camera's ground target by an XZ delta (in world units).
@warning_ignore("unused_signal")
signal camera_drag_world_requested(delta: Vector2)
@warning_ignore("unused_signal")
signal camera_rotate_requested(amount: float)
## Discrete camera rotation: snap the yaw by a fixed number of degrees per press.
@warning_ignore("unused_signal")
signal camera_rotate_step_requested(degrees: float)

# ── Resources ──
@warning_ignore("unused_signal")
signal resource_changed(resource_type: String, new_amount: int, delta: int)
@warning_ignore("unused_signal")
signal resources_insufficient(resource_type: String, required: int, available: int)
## La bolsa compartida estaba llena y `lost` unidades de `resource_type` no cupieron:
## se han perdido. Un jugador que pierde cosecha sin verlo cree que el juego esta roto.
@warning_ignore("unused_signal")
signal storage_overflow(resource_type: String, lost: int, cap: int)

# ── Buildings ──
@warning_ignore("unused_signal")
signal building_selected_for_placement(building_data: Resource)
@warning_ignore("unused_signal")
signal building_placement_cancelled()  # ESC, right-click or the on-screen CANCEL; BuildingPlacer._cancel listens
@warning_ignore("unused_signal")
signal building_placed(building_data: Resource, cell: Vector2i)
## Una tanda de building_placed del mismo gesto (los tramos del auto-road,
## PlacementRules.pave_route). Quien hace trabajo caro por building_placed
## (guardar, recontar) lo aplaza hasta `placement_batch_finished` y lo hace una vez.
@warning_ignore("unused_signal")
signal placement_batch_started()
@warning_ignore("unused_signal")
signal placement_batch_finished(count: int)
@warning_ignore("unused_signal")
signal building_moved(from_cell: Vector2i, to_cell: Vector2i)
@warning_ignore("unused_signal")
signal building_removed(cell: Vector2i)  # reserved: future use

# ── Selection ──
@warning_ignore("unused_signal")
signal building_clicked(building_node: Node, building_data: Resource)
@warning_ignore("unused_signal")
signal building_deselected()
@warning_ignore("unused_signal")
signal deposit_clicked(deposit_node: Node, deposit_id: String, cell: Vector2i)
@warning_ignore("unused_signal")
signal request_move_building(building_node: Node)
@warning_ignore("unused_signal")
signal building_renamed(building_node: Node, new_name: String)
@warning_ignore("unused_signal")
signal building_rotate_requested()

# ── Processes & Mining ──
@warning_ignore("unused_signal")
signal process_started(building_node: Node, process_id: String)
@warning_ignore("unused_signal")
signal process_completed(building_node: Node, process_id: String)
@warning_ignore("unused_signal")
signal mining_started(deposit_node: Node, deposit_id: String)
@warning_ignore("unused_signal")
signal mining_completed(deposit_node: Node, deposit_id: String)
## Cancelado a mano por el jugador. `refunded` es recurso -> cantidad devuelta,
## ya aplicada: lo que la UI prometio antes de confirmar y lo que se cobro.
@warning_ignore("unused_signal")
signal process_cancelled(building_node: Node, process_id: String, refunded: Dictionary)

# ── Construction ──
@warning_ignore("unused_signal")
signal construction_started(building_node: Node)
@warning_ignore("unused_signal")
signal construction_completed(building_node: Node)

# ── Production ──
@warning_ignore("unused_signal")
signal production_tick(building_node: Node)

# ── Upgrades ──
@warning_ignore("unused_signal")
signal building_upgrade_started(building_node: Node, new_level: int)
@warning_ignore("unused_signal")
signal building_upgrade_completed(building_node: Node, new_level: int)

# ── Demolish ──
@warning_ignore("unused_signal")
signal request_demolish_building(building_node: Node)
@warning_ignore("unused_signal")
signal building_demolished(building_node: Node, cell: Vector2i)

# ── Deposits ──
@warning_ignore("unused_signal")
signal deposit_depleted(deposit_node: Node, deposit_id: String)

# ── Map ──
## La rejilla cambio de tamano (partida nueva o carga de un guardado con otro
## tamano). La isla, la rejilla dibujada y las camaras se reajustan al oirla.
## GridManager.set_grid_size() la emite solo si el tamano cambia de verdad.
@warning_ignore("unused_signal")
signal grid_resized(width: int, height: int)

# ── Ground Interaction (reserved: future terrain interaction) ──
@warning_ignore("unused_signal")
signal ground_clicked(world_pos: Vector3, cell: Vector2i)
@warning_ignore("unused_signal")
signal ground_hover(world_pos: Vector3, cell: Vector2i)

# ── Market ──
@warning_ignore("unused_signal")
signal market_prices_updated(prices: Dictionary)
@warning_ignore("unused_signal")
signal market_trade_completed(resource: String, amount: int, is_buy: bool, total_price: int)

# ── Progression ──
@warning_ignore("unused_signal")
signal resource_unlocked(resource_name: String)
@warning_ignore("unused_signal")
signal era_advanced(new_era: int)
@warning_ignore("unused_signal")
signal milestone_completed(milestone_id: String)
@warning_ignore("unused_signal")
signal phase_advanced(new_phase: int)
@warning_ignore("unused_signal")
signal victory_achieved(stats: Dictionary)

# ── Population & Morale ──
@warning_ignore("unused_signal")
signal population_changed(current: int, max_pop: int)
@warning_ignore("unused_signal")
signal workers_changed(used: int, total: int)
@warning_ignore("unused_signal")
signal morale_changed(new_morale: int)
@warning_ignore("unused_signal")
signal consumption_failed(resource: String)
## Hambruna: el impago ya no se perdona y muere gente. `deaths` es cuanta murio
## de verdad, `population` lo que queda despues (nunca por debajo del suelo).
@warning_ignore("unused_signal")
signal population_starved(deaths: int, population: int)
## Una vivienda recien terminada (obra o mejora) recibe a su gente de golpe.
## `count` es cuanta entro de verdad (lo que cabia). La escuchan los caminantes,
## que hacen salir de esa casa a los recien llegados.
@warning_ignore("unused_signal")
signal residents_arrived(home: Node, count: int)

# ── Army ──
@warning_ignore("unused_signal")
signal unit_training_started(unit_id: String, duration: float)
@warning_ignore("unused_signal")
signal unit_trained(unit_id: String)
@warning_ignore("unused_signal")
signal army_changed()
@warning_ignore("unused_signal")
signal army_upkeep_unpaid(gold_short: int)
## Entrenamiento cancelado a mano. `refunded` es recurso -> cantidad devuelta.
@warning_ignore("unused_signal")
signal unit_training_cancelled(unit_id: String, refunded: Dictionary)
## Desercion: al ejercito sin paga se le va la tropa, la mas cara primero.
@warning_ignore("unused_signal")
signal army_deserted(unit_id: String, count: int)
## El regimiento cambio de nombre, color, emblema o pintura, o gano una
## estrella. Solo cosmetico (ArmyManager.get_regiment_look()).
@warning_ignore("unused_signal")
signal regiment_changed()

# ── Combat ──
## Emitted only by CombatManager. `side`: 0 = player, 1 = enemy.
## `result` on expedition_ended: 0 = victory, 1 = defeat, 2 = abandoned.
@warning_ignore("unused_signal")
signal expedition_started(expedition_id: int, node_count: int)
@warning_ignore("unused_signal")
signal expedition_node_selected(node_index: int)
@warning_ignore("unused_signal")
signal encounter_started(encounter_index: int, is_boss: bool)
@warning_ignore("unused_signal")
signal turn_started(side: int, unit_uid: int)
@warning_ignore("unused_signal")
signal unit_moved(unit_uid: int, from: Vector2i, to: Vector2i)
@warning_ignore("unused_signal")
signal unit_attacked(attacker_uid: int, target_uid: int, damage: int)
@warning_ignore("unused_signal")
signal unit_defended(unit_uid: int)
@warning_ignore("unused_signal")
signal unit_died(unit_uid: int, side: int)
@warning_ignore("unused_signal")
signal encounter_ended(victory: bool, turns_used: int)
## El tablero se cerro (CombatManager.end_encounter): el parte ya se leyo. Lo
## que esperaba a que terminara la pelea (los avisos de la colonia retenidos)
## sale ahora, salvo que otro tablero se haya abierto en la misma llamada (la
## oleada siguiente del asedio): por eso quien escucha vuelve a mirar
## CombatManager.is_board_open().
@warning_ignore("unused_signal")
signal encounter_closed()
@warning_ignore("unused_signal")
signal draft_offered(options: Array)
@warning_ignore("unused_signal")
signal draft_applied(option: Dictionary)
@warning_ignore("unused_signal")
signal expedition_ended(result: int, rewards: Dictionary, casualties: Dictionary)
## Al cargar una partida con campana en marcha: la UI abre el mapa en el nodo
## actual. El tablero no se guarda (D6), asi que aqui nunca hay encuentro abierto.
@warning_ignore("unused_signal")
signal expedition_resumed(expedition_id: int)
## Salidas (doc 21 §3, 2026-10-14). El tablon cambio: oferta nueva, lanzada,
## vuelta, vista, o la rebaja del Diezmo se gano o se gasto. El boton
## ESCARAMUZAS repinta su punto rojo con esto.
@warning_ignore("unused_signal")
signal sortie_offers_changed()
## Lo que la columna trajo de fuera al volver: "parts", "colonists",
## "tithe_pct", "blueprints" (Array). Ya aplicado a la colonia.
@warning_ignore("unused_signal")
signal sortie_loot_gained(loot: Dictionary)
## Un plano nuevo: el edificio `building_id` ya se puede construir.
@warning_ignore("unused_signal")
signal blueprint_unlocked(building_id: String)
## Tres campanas (feat/tres-campanas). Emitidas solo por CombatManager. El libro
## de campanas cambio (mision ganada, perdida, vista, partida cargada): el panel
## de MISIONES y el punto rojo repintan con esto.
@warning_ignore("unused_signal")
signal campaign_changed()
## Una mision de campana ganada (`domain`: land / sea / air; `mission` desde 0;
## `is_boss`: era la del jefe de campana). Ya cobrada.
@warning_ignore("unused_signal")
signal campaign_mission_won(domain: String, mission: int, is_boss: bool)
## Una campana entera completa (su jefe derrotado). ProgressionManager mira si
## con esto ya se puede llamar al Ataque Final.
@warning_ignore("unused_signal")
signal campaign_completed(domain: String)
## El enemigo se retiro con poca vida y el combate se gano (D7 = B).
@warning_ignore("unused_signal")
signal enemy_routed()

# ── Amenazas de costa (feat/amenazas-costa, docs/15 §14) ──
## Solo botin opcional: aparecen, se van solas sin dano, y atacarlas o explorar
## el pecio da botin. Las emite solo ThreatManager (salvo threat_clicked).
## Las marcas cambiaron (aparecio, se fue, atacada, explorada, vista, cargada):
## las marcas 3D/2D, la tarjeta y MISIONES repintan con esto.
@warning_ignore("unused_signal")
signal threats_changed()
## Una marca nueva en la costa (`threat_type`: raiders / vanguard / wreck).
@warning_ignore("unused_signal")
signal threat_appeared(threat_id: int, threat_type: String, water: bool)
## Echada: la columna gano su combate (el botin ya lo cobro CombatManager).
@warning_ignore("unused_signal")
signal threat_cleared(threat_id: int, threat_type: String)
## Se fue sola, sin hacer nada (se le acabo el tiempo).
@warning_ignore("unused_signal")
signal threat_left(threat_id: int, threat_type: String)
## Los trabajadores volvieron del pecio con esto (ya en la colonia).
@warning_ignore("unused_signal")
signal wreck_explored(threat_id: int, rewards: Dictionary, loot: Dictionary)
## El jugador toco una marca en el mapa (la emiten los dos BuildingPlacer).
@warning_ignore("unused_signal")
signal threat_clicked(threat_id: int)

# ── Building Health ──
## Emitidas solo por BuildingHealth. Un edificio en ruinas sigue en su sitio y
## deja de producir hasta que se paga la reparacion; nunca se destruye solo.
@warning_ignore("unused_signal")
signal building_damaged(building_node: Node, health: int, max_health: int)
@warning_ignore("unused_signal")
signal building_ruined(building_node: Node)
@warning_ignore("unused_signal")
signal building_repaired(building_node: Node)

# ── Day and night ──
## Emitted only by DayClock when the day clock enters a phase. `phase` follows
## DayCycle.Phase (DAWN, DAY, DUSK, NIGHT); `hour` is the time of day, 0-1.
## Not emitted on load or new game: a consumer re-derives from
## `DayClock.get_phase()` on `game_load_completed` / `game_new_started`.
@warning_ignore("unused_signal")
signal day_phase_changed(phase: int, hour: float)

# ── Imperial Storm ──
## Emitted only by StormManager. The storm is dispatched on a schedule, not rolled
## at random — the player is meant to see it coming and prepare (see the design in
## the private context folder).
## `phase` values follow StormCycle.Phase.
@warning_ignore("unused_signal")
signal storm_phase_changed(phase: int, seconds_left: float)
## The warning window opens: ash on the horizon, time to decide. No severity in
## it on purpose — the size of the bill is only announced with `storm_started`.
@warning_ignore("unused_signal")
signal storm_incoming(seconds_until: float)
## The warning came to nothing. `deferred` is the severity the next real storm
## inherits for it: postponed, not forgiven.
@warning_ignore("unused_signal")
signal storm_false_alarm(deferred: int)
## Ash starts falling: production halves, morale bleeds, nothing comes down yet.
@warning_ignore("unused_signal")
signal storm_ash_started()
@warning_ignore("unused_signal")
signal storm_started(severity: int)
## Per-tick bite while ash or storm is overhead, for the UI to react to.
## `phase` follows StormCycle.Phase.
@warning_ignore("unused_signal")
signal storm_tick(phase: int, seconds_left: float)
@warning_ignore("unused_signal")
signal storm_ended(severity: int)
## The Assessors arrive to collect. `taken` is resource_name -> amount.
@warning_ignore("unused_signal")
signal tithe_demanded(severity: int)
@warning_ignore("unused_signal")
signal tithe_resolved(paid: bool, taken: Dictionary)
## La Orden de la Regencia cambio: encargo nuevo, entregado, o una rebaja del
## Diezmo apuntada (StormManager.add_tithe_discount). `fresh` es true solo cuando
## sale una Orden nueva (al armarse el reloj y tras cada Diezmo): el HUD abre la
## tarjeta. Emitida solo por StormManager.
@warning_ignore("unused_signal")
signal storm_order_changed(fresh: bool)
## La guarnicion peleo sola: el Diezmo cayo con el tablero ocupado por una
## expedicion y la defensa se resolvio a ciegas (AutoResolver). `summary` es
## CombatManager.get_last_result(). Emitida solo por CombatManager, y es la UNICA
## senal de esa pelea: ninguna encounter_*/turn_started/unit_* la acompaña, porque
## el tablero abierto las tomaria como suyas.
@warning_ignore("unused_signal")
signal defense_auto_resolved(victory: bool, rounds: int, summary: Dictionary)
## El Impuesto de juguete de la tormenta de prueba (era 1) quedo resuelto:
## `repelled` si las tropas de casa echaron a los Cobradores; si no, `taken` es lo
## que se llevaron de la bolsa (recursos por nombre). Solo StormManager. No es
## `tithe_resolved`: el Mercado, las salidas y el sonido del Impuesto de verdad no
## tienen que reaccionar a un ensayo. Lo pinta WarReportScreen.
@warning_ignore("unused_signal")
signal trial_tithe_resolved(repelled: bool, taken: Dictionary)
## La Visita (feat/ritmo-colono): un Impuesto que se resuelve con parte
## automatico ofrece ¡PELEAR! unos segundos (`open` = true) y la oferta se cierra
## (false) al pulsarlo, al resolverse sola o al cargar. Solo StormManager; el
## boton vive en StormHUD.
@warning_ignore("unused_signal")
signal tithe_choice_changed(open: bool)
## Una sola llave (feat/ritmo-colono): el jefe de la campana `domain` entrego su
## pieza del Cuartel General nivel 3. Solo CombatManager, justo despues de
## `campaign_completed`.
@warning_ignore("unused_signal")
signal campaign_piece_won(domain: String)
## Capitulos de Colono (feat/ritmo-colono): el capitulo `chapter` (1-3) se acaba
## de cerrar. Solo ProgressionManager, una vez por capitulo y partida (nunca al
## cargar). La pantalla corta de cierre la pinta ChapterScreen.
@warning_ignore("unused_signal")
signal chapter_completed(chapter: int)

# ── The Final Audit ──
## Emitidas solo por ProgressionManager. El Cuartel General a nivel 3 ya no gana
## la partida: convoca la auditoria definitiva de la Regencia, y sobrevivirla es
## la victoria. Un asedio son 3-5 oleadas seguidas contra la misma guarnicion.
## La Regencia ha sido convocada. Todavia no hay nadie en el tablero.
@warning_ignore("unused_signal")
signal final_audit_summoned(waves: int, summons: int)
## Empieza el asedio: a partir de aqui no se reentrena nada.
@warning_ignore("unused_signal")
signal final_audit_started(waves: int)
## La oleada que toca poner en el tablero: quien baja y con cuanto peso. Esta es
## la costura del asedio — el modelo dice que oleada es, y quien conduce el
## tablero es quien llama a CombatManager.start_defense(). Nadie mas.
@warning_ignore("unused_signal")
signal final_audit_wave_ready(wave: int, roster: Dictionary, scale: float)
@warning_ignore("unused_signal")
signal final_audit_wave_cleared(wave: int, remaining: int)
## La guarnicion ha caido. No hay Game Over: se cobra el Diezmo maximo y la
## ciudad queda en ruinas, pero el asedio se puede volver a convocar cuando el
## ejercito este rehecho.
@warning_ignore("unused_signal")
signal final_audit_lost(wave: int)
## Se ha sobrevivido a la auditoria. La Tormenta para para siempre: StormManager
## escucha aqui cuando se cablee, y nada mas tiene permiso para detener el ciclo.
@warning_ignore("unused_signal")
signal storm_halted_forever()

# ── Random Events ──
@warning_ignore("unused_signal")
signal random_event_started(event_id: String, event_data: Dictionary)
@warning_ignore("unused_signal")
signal random_event_ended(event_id: String)

# ── Notifications ──
@warning_ignore("unused_signal")
signal notification_posted(message: String, category: String, color: Color)
@warning_ignore("unused_signal")
signal objective_panel_toggled()

# ── UI ──
@warning_ignore("unused_signal")
signal sidebar_toggled(visible: bool)
@warning_ignore("unused_signal")
signal grid_overlay_toggled(visible: bool)
## La calidad grafica del mapa cambio en Ajustes ("auto", "high", "low");
## WorldLook la aplica al entorno y al sol de la escena 3D.
@warning_ignore("unused_signal")
signal graphics_quality_changed(quality: String)
## La velocidad del juego cambio (1.0 o 2.0; GameConfig.set_game_speed). La
## simulacion la lee en GameConfig.sim_delta(); la vista de combate, para
## acortar sus animaciones con GameConfig.combat_pace().
@warning_ignore("unused_signal")
signal game_speed_changed(speed: float)

## Emitted when the window switches to/from fullscreen (F11 or Settings).
signal fullscreen_changed(enabled: bool)

## Emitted when the on-screen touch controls preference changes (Settings).
## Carries the RESOLVED state: "auto" already checked against the hardware.
@warning_ignore("unused_signal")
signal touch_controls_changed(enabled: bool)
## La opacidad de los controles en pantalla cambio (Ajustes → Controles).
@warning_ignore("unused_signal")
signal touch_controls_opacity_changed(opacity: float)
## Los nombres junto a los iconos del HUD se encendieron o apagaron (Ajustes >
## Interfaz, o el "auto" que se apaga pasada la primera hora). Lleva el estado
## ya resuelto (GameConfig.hud_words_enabled()).
@warning_ignore("unused_signal")
signal hud_words_changed(shown: bool)
## El tamano de los controles en pantalla cambio (Ajustes → Controles, o el
## perfil de dispositivo en "auto"). Lleva la escala RESUELTA (1.0 = 100 %).
@warning_ignore("unused_signal")
signal touch_controls_size_changed(scale: float)

## Los globos de ayuda se encendieron o apagaron (AYUDA del menu ☰ o Ajustes >
## Interfaz). GameConfig.ui_helper_visible ya tiene el valor nuevo.
@warning_ignore("unused_signal")
signal helper_visibility_changed(visible: bool)

## Los instructores (bustos junto a tutorial, consejos y partes) se encendieron
## o apagaron en Ajustes > Interfaz. GameConfig.ui_instructors_visible ya tiene
## el valor nuevo.
@warning_ignore("unused_signal")
signal instructors_visibility_changed(visible: bool)

## Emitted when music is switched on/off (Settings or the ☰ quick button).
@warning_ignore("unused_signal")
signal music_toggled(enabled: bool)
## El idioma cambio (GameConfig.set_locale). Ya esta aplicado en Tr y guardado en
## settings.cfg cuando llega. GameManager lo escucha y recarga la escena
## conservando la partida, para que todo panel vuelva a pintarse en el idioma
## nuevo; quien pinte textos de larga vida puede escucharlo tambien.
signal locale_changed(locale: String)

# ── Persistence ──
@warning_ignore("unused_signal")
signal game_new_started()
@warning_ignore("unused_signal")
signal game_load_completed()
## Mientras GameManager coloca la partida al arrancar: `done` de `total` piezas
## (los edificios del guardado; en una partida nueva, sus pasos). La escucha la
## pantalla de carga (LoadingScreen) para mover su barra.
@warning_ignore("unused_signal")
signal game_load_progress(done: int, total: int)

# ── Tutorial ──
## Emitidas solo por TutorialManager. El manager decide QUE se ensena y CUANDO
## (una intro por partida, un consejo por suceso); TutorialPanel solo pinta lo
## que le llega. Asi el manager no conoce a ningun panel y se puede probar sin
## escena.
## La intro paginada del lore y del "como se juega". Se pide al empezar partida
## nueva si aun no se ha visto, y desde show_intro() cuando el jugador la quiera.
@warning_ignore("unused_signal")
signal tutorial_intro_requested()
## Un consejo contextual: tarjeta pequena, no modal, con "Entendido". El texto
## ya viene traducido para que el panel no tenga que saber de que trata.
@warning_ignore("unused_signal")
signal tutorial_tip_requested(tip_id: String, title: String, body: String)
## El jugador cerro la intro, leida o saltada. Es lo que la marca como vista:
## saltar cuenta como leer, porque volver a insistir seria castigar el "Saltar".
@warning_ignore("unused_signal")
signal tutorial_intro_closed()

# ── modos-de-juego ──
## La partida termino sin vuelta atras (Supervivencia: Auditoria perdida). La
## emite ProgressionManager despues de `final_audit_lost`; GameManager escribe el
## guardado una ultima vez, marcado, y la pantalla de derrota ofrece empezar otra.
@warning_ignore("unused_signal")
signal run_ended(result: String)
## Sandbox: se invoco a mano una tormenta o la Auditoria. `what` es "storm" o
## "audit". Solo informativo (avisos, sonido); las reglas no cambian.
@warning_ignore("unused_signal")
signal sandbox_invoked(what: String)

# ── Rango del gobernador ──
## Emitidas solo por RankManager. La XP sale de las senales de arriba; el rango
## se deriva de ella (GameConfig.rank_xp_thresholds).
## La XP cambio. `gained` es lo que acaba de entrar (0 al cargar o empezar).
@warning_ignore("unused_signal")
signal governor_xp_changed(xp: int, rank: int, gained: int)
## Se subio de rango. `rewards` es la union de GameConfig.rank_rewards de cada
## rango alcanzado en este salto (un hito gordo puede saltar dos).
@warning_ignore("unused_signal")
signal governor_rank_up(rank: int, rewards: Dictionary)
## El pais cambio de nombre o de bandera (☰ MENU > COLONIA, el paso de Nueva
## partida o una carga). `flag_spec` es la receta de ColonyFlag:
## {"pattern", "emblem", "colors": [fondo 1, fondo 2, emblema]}. Los mastiles
## del Nucleo y del Cuartel General, la insignia y los partes se repintan al oirla.
@warning_ignore("unused_signal")
signal colony_identity_changed(colony_name: String, flag_spec: Dictionary)

# ── prologo-ayudas ──
## El tutorial guiado cambio de paso (TutorialManager.GUIDE_STEPS). "" = ninguno
## en pantalla (terminado, saltado o sin empezar).
@warning_ignore("unused_signal")
signal tutorial_step_changed(step_id: String)
## El tutorial guiado termino. `skipped`: el jugador pulso "Saltar tutorial".
## HelperPanel pone entonces en cola los globos basicos, de uno en uno.
@warning_ignore("unused_signal")
signal tutorial_guide_finished(skipped: bool)
## El jugador pidio volver a ver una ayuda concreta (indice de AYUDA). El id es
## de HelpCatalog. HelperPanel la ensena ya, senalando su control.
@warning_ignore("unused_signal")
signal help_reopen_requested(help_id: String)
## El combate guiado cambio de paso (TutorialManager.COMBAT_STEPS: "c_select",
## "c_move"...). "" = ninguna marca en el tablero. Lo pinta TutorialPanel.
@warning_ignore("unused_signal")
signal combat_lesson_step_changed(step_id: String)

# ── comida-granja-recoger (2026-10-04) ──
## Cambio lo acumulado en un edificio (produjo, se recogio, se echo a perder).
## `stock` es recurso -> cantidad. Lo escuchan el icono flotante y el badge.
@warning_ignore("unused_signal")
signal building_stock_changed(node: Node, stock: Dictionary)
## El jugador recogio lo de un edificio. `collected` es lo que entro en la bolsa;
## lo que no cupo se queda en el edificio.
@warning_ignore("unused_signal")
signal production_collected(node: Node, collected: Dictionary)
## Lo acumulado paso demasiado tiempo sin recoger y se perdio una parte
## (solo con GameMode.spoilage_enabled()).
@warning_ignore("unused_signal")
signal stock_spoiled(node: Node, lost: Dictionary)
## Se planto (o cambio) el cultivo de una Granja.
@warning_ignore("unused_signal")
signal crop_planted(node: Node, crop_id: String)

# ── Encargos (feat/encargos) ──
## ContractManager publica lo que devuelve el modelo puro ContractBoard. `source`
## es "regency", "neighbors" o "smuggler"; `contract` es el encargo entero
## ({id, source, template, ask, reward, seconds_total, seconds_left}).
## Llego un encargo nuevo al tablon.
@warning_ignore("unused_signal")
signal contract_offered(source: String, contract: Dictionary)
## Se entrego: lo pedido ya salio de la bolsa y `reward` ya se pago.
@warning_ignore("unused_signal")
signal contract_delivered(source: String, contract: Dictionary, reward: Dictionary)
## Se acabo el plazo sin entregarlo. En Colono no castiga; en Gobernador baja
## la reputacion con quien lo pidio (`reputation`, 0 a contract_reputation_min).
@warning_ignore("unused_signal")
signal contract_expired(source: String, contract: Dictionary, reputation: int)
## El jugador lo rechazo ("No, gracias").
@warning_ignore("unused_signal")
signal contract_discarded(source: String, contract: Dictionary)
## Algo cambio en el tablon (cualquiera de las de arriba, o una carga/reset).
## El panel se repinta con esta.
@warning_ignore("unused_signal")
signal contract_board_changed()

# ── Defensa y vida (feat/edificios-defensa-vida) ──
## Tras la Tormenta, las brigadas de la Chatarreria despejaron ruinas: `steel`
## de acero, `parts` repuestos y `lifted` edificios levantados.
@warning_ignore("unused_signal")
signal scrap_salvaged(steel: int, parts: int, lifted: int)
# ── Economia (feat/edificios-economia) ──
## EconomyManager publica el barco del contrabandista (Puerto comercial), el
## combustible de las Centrales diesel y el interes de la Casa de cambio.
## Atraco el barco del contrabandista junto al Puerto. `offers`: las ofertas
## (ver scripts/economy/SmugglerShip.gd); `port`: el nodo del Puerto.
@warning_ignore("unused_signal")
signal smuggler_ship_arrived(offers: Array, port: Node)
## El barco zarpo. `reason`: "time", "storm" (llego la Ceniza) o "no_port".
@warning_ignore("unused_signal")
signal smuggler_ship_departed(reason: String)
## Se cerro un trato con el barco (la oferta `index`, ya cobrada y pagada).
@warning_ignore("unused_signal")
signal smuggler_offer_taken(index: int, offer: Dictionary)
## Se compro un plano menor al barco: `building_id` ya se puede construir
## aunque el rango aun no llegue.
@warning_ignore("unused_signal")
signal building_plan_bought(building_id: String)
## Una Central diesel se quedo sin combustible (`running` false) o volvio a
## arrancar (true).
@warning_ignore("unused_signal")
signal diesel_plant_fuel_changed(node: Node, running: bool)
## La Casa de cambio pago interes (solo Gobernador).
@warning_ignore("unused_signal")
signal exchange_interest_paid(amount: int)
## Algo de lo de arriba cambio (el panel del Puerto y la ficha se repintan).
@warning_ignore("unused_signal")
signal economy_changed()
# ── Volverse el Imperio (feat/volverse-imperio, docs/06) ──
## Empieza la fase: se gano el Ataque Final (o se cargo una partida ya ganada) y
## el reloj del tributo se pone en marcha. Una vez por partida.
@warning_ignore("unused_signal")
signal empire_phase_started()
## Algo cambio en el archipielago (mision, isla, tributo, carga). Los paneles se
## repintan con esta.
@warning_ignore("unused_signal")
signal empire_changed()
## Se gano la mision `mission` (desde 0) de `island_id`. `conquered`: era la
## ultima y la isla ya es tuya.
@warning_ignore("unused_signal")
signal conquest_mission_won(island_id: String, mission: int, conquered: bool)
## Tu bandera ondea en `island_id`: empieza a pagar tributo y da su recompensa.
@warning_ignore("unused_signal")
signal island_conquered(island_id: String)
## Todas las islas del archipielago son tuyas.
@warning_ignore("unused_signal")
signal archipelago_conquered()
## Las islas conquistadas pagaron (recurso -> cantidad, ya en la bolsa).
@warning_ignore("unused_signal")
signal empire_tribute_paid(amounts: Dictionary)

# ── Final con eleccion (v1.2, decision de Bryan 2026-10-25) ──
## El jugador decidio que hacer con el libro del Impuesto tras ganar el Ataque
## Final: `choice` = "sign" (firma: la fase del archipielago) o "burn" (lo
## quema: la isla queda libre). Una vez por partida (EmpireManager.choose_ending).
@warning_ignore("unused_signal")
signal ending_chosen(choice: String)

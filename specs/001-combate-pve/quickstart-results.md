# Resultados del quickstart — combate PVE

Parte de la tarea T045: recorrer los escenarios E1 a E9 de
[quickstart.md](quickstart.md) y dejar por escrito cuál pasa, cómo se comprobó y
qué queda pendiente de mirar con los ojos.

**Fecha:** 16 de septiembre de 2026. **Rama:** `feat/hito-3-expedicion`.

## Cómo se comprobó cada cosa

Tres instrumentos, ninguno de ellos "lo he mirado y parecía bien":

| Instrumento | Qué es |
|---|---|
| **Sonda** | `tools/expedition_probe.gd`, registrada como autoload temporal. Juega campañas enteras sin tocar la interfaz y afirma 50 invariantes, una por una. |
| **Tests** | La suite gdUnit4: 726 casos, 0 fallos, ninguno saltado. En particular `tests/integration/test_full_campaign.gd` (juega la partida de colonia nueva a Victoria Imperial), `tests/combat/test_expedition_wiring.gd` y `tests/ui/test_expedition_ui.gd`. |
| **Barrido** | `tools/balance_probe.gd` y `tools/siege_probe.gd`: decenas de miles de encuentros para las afirmaciones de balance. Ver [16-balance-combate.md](../../docs/16-balance-combate.md) y [17-balance-asedio.md](../../docs/17-balance-asedio.md). |

## Los escenarios

| # | Escenario | Estado | Cómo |
|---|---|---|---|
| **E1** | Un encuentro completo (SC-001, SC-002, SC-003) | ✅ | Sonda: ningún encuentro pasa del límite de 20 rondas (el peor, 10) y **todos** se deciden por eliminación, ninguno por agotar el reloj. Tests de `test_encounter.gd` y `test_combat_rules.gd`. |
| **E2** | Expedición ramificada con draft y atrición (SC-008, SC-009) | ✅ | Sonda: cada nodo ganado ofrece 3 cartas aplicables (≥2 exigidas) y la elegida se aplica; 5 semillas dan 5 mapas distintos en rutas, riesgos y rosters. Atrición verificada: nadie se cura entre nodos salvo por la carta de curación. |
| **E3** | Derrota y permadeath (FR-010) | ✅ | Sonda: ningún caído vuelve a un tablero posterior. Test `test_expedition_wiring.gd`. |
| **E4** | La economía recibe el resultado (SC-004, SC-005) | ✅ | Sonda: los recursos no se mueven **durante** la campaña; al volver, el botín pagado coincide exactamente con lo acumulado nodo a nodo, el Cuartel queda con los supervivientes y el Poder Militar cuadra con el roster. También en el test de campaña completa. |
| **E5** | Inteligencia artificial que actúa (SC-007) | ✅ | `tests/combat/test_combat_ai.gd`: barrido que comprueba que nunca devuelve "sin acción" habiendo objetivo alcanzable, más los casos de prioridad de objetivo y del repliegue de artillería. |
| **E6** | Cerrar el juego a mitad de expedición (FR-020, SC-006) | ✅ | Sonda, pasada 3: guardar, resetear, cargar. Vuelven intactos el mapa, el nodo actual, los nodos limpiados, el HP de cada superviviente, el botín acumulado y las cartas ya elegidas; el tablero se redespliega con esas heridas. Un save anterior a esta función arranca sin campaña, y uno con campaña terminada no la reabre. |
| **E7** | Abandonar (FR-016) | ✅ | Sonda, pasada 2: se cobra el botín acumulado, no hay bajas extra por abandonar y los supervivientes vuelven al Cuartel. |
| **E8** | Sin unidades (FR-002) | ✅ | Sonda, pasada 0: lanzar sin tropas devuelve `MSG_NO_UNITS` y no crea campaña; pedir más de las que hay devuelve `MSG_UNITS_UNAVAILABLE`; pasarse del tope, `MSG_DEPLOY_CAP_EXCEEDED`. |
| **E9** | Legibilidad móvil | ⚠️ **Parcial** | Cubierto por test a 400×720 en `test_expedition_ui.gd` y `test_battle_board_icons.gd`: ningún control se sale del viewport y las celdas mantienen los 44 px mínimos. **Falta mirarlo en un teléfono de verdad**: ni el tacto ni las densidades de pantalla distintas de 1 se pueden comprobar sin dispositivo. |

## Lo que la sonda mide y no juzga

Dos cifras salen del parte como información, no como veredicto, porque una sonda
con pocas semillas y la inteligencia artificial conduciendo también al jugador es
un suelo muy pesimista: `CombatAI` está escrita para atacar, no para cuidar una
columna.

- **La campaña de la pasada 1 se cerró como perdida** en el nodo del jefe, con la
  columna reducida a dos unidades. Todas las invariantes de cableado pasaron.
- **La profundidad máxima alcanzada en 5 semillas fue 2.**

El balance real está medido aparte y con otra política de juego: una columna de
cuatro unidades de era 1 completa la expedición el 53 % de las veces
([16-balance-combate.md](../../docs/16-balance-combate.md)). Si alguna vez estas
dos cifras y el barrido se contradicen de verdad, **manda el barrido**.

## Pendiente de verificación manual

Lo que no se puede comprobar sin ojos y sin dispositivo:

1. **E9 en un teléfono real**: tacto, densidades de pantalla y la sensación del
   umbral de arrastre (12 píxeles) y del pellizco.
2. **Colocar un edificio con el dedo** ocurre ahora al levantarlo, no al apoyarlo,
   para que el ratón emulado no mueva el mapa dos veces. Es el cambio de tacto
   más notorio del hito y conviene confirmarlo en mano.
3. **El tablero en movimiento**: el número de daño flotando sobre un icono, la
   transición al mover una unidad, el halo del jefe entre celdas vecinas. Todo
   revisado en render estático, no jugando.
4. **El ritmo**: que un encuentro de 3,4 minutos medidos se *sienta* como 3,4
   minutos depende de cuánto tarde una persona en decidir cada turno, y eso solo
   se sabe jugando.

## Cómo repetirlo

```
# La sonda: registrar como autoload temporal y arrancar CON ventana
#   project.godot -> [autoload] -> ExpeditionProbe="*res://tools/expedition_probe.gd"
# (quitar la línea después: project.godot no debe cambiar en el commit)

# La suite entera
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests
```

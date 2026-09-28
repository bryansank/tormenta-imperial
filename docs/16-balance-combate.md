# Balance de combate

Qué valores de `GameConfig.combat_*` se movieron en **T046**, por qué, y qué
medición respalda cada uno. Ningún número de este documento sale de jugar a ojo:
todos salen de `tools/balance_probe.gd`, que resuelve encuentros y expediciones
enteras con `AutoResolver` y cuenta lo que pasa.

> Nota de numeración: `docs/15-combat.md` describe **cómo está construido** el
> pilar de combate. Este documento habla sólo de **los números**. El 16 es el
> siguiente libre.

---

## Contenido

1. [Los dos objetivos](#1-los-dos-objetivos)
2. [Cómo se mide](#2-cómo-se-mide)
3. [De rondas a minutos](#3-de-rondas-a-minutos)
4. [Antes](#4-antes)
5. [Qué se cambió y por qué](#5-qué-se-cambió-y-por-qué)
6. [Después](#6-después)
7. [¿Se cumplen los objetivos?](#7-se-cumplen-los-objetivos)
8. [Lo que no se arregla desde `combat_*`](#8-lo-que-no-se-arregla-desde-combat_)
9. [Lo que esto mueve fuera de la expedición](#9-lo-que-esto-mueve-fuera-de-la-expedición)
10. [Tests tocados](#10-tests-tocados)
11. [Cómo repetir la medición](#11-cómo-repetir-la-medición)

---

## 1. Los dos objetivos

T046 (`specs/001-combate-pve/tasks.md`) pide dos cosas concretas:

1. **Un encuentro dura 3-5 minutos** de reloj.
2. **La primera expedición es ganable con 3-4 unidades de era 1.**

Y una restricción: sólo se pueden mover claves `combat_*` de
`scripts/services/GameConfig.gd`. Nada de código.

---

## 2. Cómo se mide

### La sonda

`tools/balance_probe.gd` es un autoload temporal (hermano de `storm_probe.gd` y
`battle_probe.gd`). Usa `AutoResolver`, que juega un `Encounter` entero con
`CombatAI` a los **dos** lados, en memoria y al instante. Hace dos barridos:

| Barrido | Rejilla | Semillas | Qué saca |
|---|---|---|---|
| **Encuentros sueltos** | era 1-3 × profundidad 0-6 × riesgo bajo/medio/alto × plantilla de 3, 4 y 6 | 200 por celda (189 celdas) | tasa de victoria, rondas medias y desviación, % que llega al tope de turnos, bajas medias, minutos estimados |
| **Expediciones completas** | era 1-3 × plantilla de 3, 4 y 6 × dos modos de juego | 200 por celda | % de expediciones ganadas, nodos limpiados, profundidad a la que muere la columna, bajas, minutos por expedición |

La expedición se simula entera y de verdad: mapa generado desde la semilla,
atrición real entre nodos (nadie se cura salvo con la carta de curación),
muerte permanente y el jefe al final.

### Los dos modos de juego

El enunciado de T046 pide "draft elegido al azar entre las opciones". Eso es una
**cota inferior**: un jugador que no mira las cartas. La sonda mide también el
otro extremo razonable:

| Modo | Draft | Ruta |
|---|---|---|
| `azar` | carta al azar entre las tres | salida al azar |
| `jugado` | cura si la columna ha encajado algo, si no defensa, si no ataque | siempre la salida de menos riesgo |

"Ganable" se juzga con `jugado`. El `azar` sirve para ver cuánto margen deja el
balance a quien no se fija. Los dos van en las tablas.

### El combate no tira dados

`Encounter`, `CombatRules` y `CombatAI` son deterministas: el daño es
`atk - def` sin varianza y todo desempate acaba en el `uid` menor. Con la misma
plantilla y el mismo roster, el encuentro **sale idéntico siempre**. Consecuencias
que hay que tener delante al leer las tablas:

- En **era 1**, donde sólo hay infantería, cada celda del barrido de encuentros
  es una única partida repetida 200 veces: la desviación de rondas es 0 y la tasa
  de victoria es 0% o 100%, nunca algo intermedio. El balance es una **función
  escalón**, no una distribución.
- La variedad de las eras 2 y 3 viene sólo de lo que sortea
  `ExpeditionGenerator` (composición del roster) y de la plantilla que lleva el
  jugador.
- La sonda aprovecha esto: memoriza los encuentros ya jugados y sólo simula las
  combinaciones distintas. Sigue sacando sus 200 muestras por celda; lo que se
  ahorra es repetir la misma cuenta.

### Lo que la sonda no sabe

`AutoResolver` conduce al jugador con la misma IA que al enemigo. Esa IA cierra
distancia, remata al que puede matar y mantiene la artillería a tiro, pero no se
repliega, no ceba, no sacrifica una unidad para salvar tres. **Un jugador humano
juega mejor que el modelo `jugado`.** Todas las tasas de victoria de estas tablas
son, por tanto, conservadoras.

---

## 3. De rondas a minutos

Sin esta conversión "3-5 minutos" no se puede comprobar. La fórmula que usa la
sonda es:

```
segundos = pasos_enemigos      × combat_ai_step_delay
         + turnos_jugador      × PLAYER_SECONDS_PER_TURN
         + (turnos_jugador + turnos_enemigos) × TURN_OVERHEAD_SECONDS
```

**Lo que se mide de verdad:** los pasos enemigos se cuentan uno a uno sobre los
eventos del encuentro (`unit_moved`, `unit_attacked`, `unit_defended` de una
unidad del bando enemigo), porque `CombatManager._run_enemy_turn()` espera
`combat_ai_step_delay` **antes de cada paso del plan**. Los turnos de cada bando
salen de los eventos `turn_started`. Nada de esto es una estimación.

**Lo que se supone:** el lado del jugador. No hay reloj en el código que mida
cuánto tarda una persona en mirar el tablero, tocar una unidad, tocar la casilla
y tocar el objetivo.

| Constante | Valor | Qué supone |
|---|---|---|
| `PLAYER_SECONDS_PER_TURN` | **5,0 s** | Un jugador que ya conoce el tablero, en un móvil: ~1 s de lectura y tres toques con su animación |
| `TURN_OVERHEAD_SECONDS` | 0,3 s | Cámara y animación entre turno y turno, los dos bandos |
| `combat_ai_step_delay` | 0,45 s | Se lee de `GameConfig` (el valor real, no el de `dev_mode`, que lo divide por dos) |

Como esa constante manda sobre el resultado, **la sonda publica siempre tres
columnas de minutos**: con 3 s (jugador rápido), con 5 s (referencia) y con 8 s
(jugador que se lo piensa), y además el número de turnos de jugador, para que
cualquiera rehaga la cuenta con la suya. Si una conclusión cambiara de signo
entre la columna de 3 s y la de 8 s, esa conclusión sería de la constante y no
del balance; se dice en el sitio donde ocurre.

---

## 4. Antes

`git show HEAD~:scripts/services/GameConfig.gd`, medido con la sonda final.

### 4.1 Encuentros — medias sobre profundidad y riesgo

| Celda | Victoria | Rondas | Tope de turnos | Bajas | Minutos (3 s / 8 s) |
|---|---|---|---|---|---|
| era 1, plantilla 3 | 14 % | 3,6 | 0 % | 2,67 | **1,0** (0,7 / 1,5) |
| era 1, plantilla 4 | 14 % | 4,7 | 0 % | 3,48 | **1,5** (1,0 / 2,3) |
| era 1, plantilla 6 | 43 % | 5,4 | 0 % | 4,14 | **2,3** (1,5 / 3,5) |
| era 2, plantilla 3 | 0 % | 3,0 | 0 % | 3,00 | **0,7** (0,5 / 0,9) |
| era 2, plantilla 4 | 2 % | 3,4 | 0 % | 3,97 | **0,9** (0,7 / 1,3) |
| era 2, plantilla 6 | 24 % | 4,7 | 0 % | 5,43 | **1,7** (1,1 / 2,5) |
| era 3, plantilla 3 | 1 % | 2,4 | 0 % | 2,98 | **0,6** (0,4 / 0,8) |
| era 3, plantilla 4 | 7 % | 2,9 | 0 % | 3,83 | **0,9** (0,6 / 1,3) |
| era 3, plantilla 6 | 13 % | 4,1 | 0 % | 5,40 | **1,7** (1,1 / 2,5) |

**De las 189 celdas, 0 caían dentro de la ventana de 3-5 minutos. Las 189 eran
demasiado cortas.** El tope de 20 rondas no saltaba nunca: sobraban 15 rondas de
margen en todas partes.

### 4.2 Expediciones completas

| Era | Plantilla | Modo | Ganadas | Nodos limpiados | Muere en profundidad |
|---|---|---|---|---|---|
| 1 | 3 | azar | **0 %** | 1,31 | 1,31 |
| 1 | 3 | jugado | **0 %** | 1,77 | 1,77 |
| 1 | 4 | azar | **0 %** | 1,50 | 1,50 |
| 1 | 4 | jugado | **0 %** | 1,83 | 1,83 |
| 1 | 6 | azar | **0 %** | 2,27 | 2,27 |
| 1 | 6 | jugado | **0 %** | 3,05 | 3,05 |
| 2 | 6 | jugado | **0 %** | 0,90 | 0,90 |
| 3 | 6 | jugado | **0 %** | 1,51 | 1,51 |

Cero. **Ninguna expedición se ganaba nunca: ni con ninguna plantilla, ni en
ninguna era, ni jugándola bien.** 3.600 expediciones simuladas, cero victorias.
Una columna de cuatro unidades de era 1 moría en el segundo nodo de un mapa de
seis a ocho, y una de seis no pasaba del tercero.

El histograma de muertes de era 1, jugando bien, no deja lugar a dudas:

| Plantilla | Derrotas | Reparto por profundidad |
|---|---|---|
| 3 | 200/200 | d1:46 d2:154 |
| 4 | 200/200 | d1:46 d2:143 d3:11 |
| 6 | 200/200 | d2:25 d3:140 d4:35 |

### 4.3 Diagnóstico

Tres cosas, en este orden:

1. **Los encuentros eran demasiado cortos porque la vida era demasiado poca.**
   El daño es `atk - def` sin dados: las rondas de un encuentro son literalmente
   vida dividida entre golpe. Con 30 HP de infantería y 6-8 de daño por golpe,
   una unidad caía en cuatro o cinco impactos, y el encuentro entero en tres a
   cinco rondas — poco más de un minuto.
2. **La curva de dificultad subía al cubo mientras el jugador subía sumando.**
   `enemy_pressure` alimenta a la vez el **número de cuerpos**
   (`combat_enemy_base_slots × presión`) y el **multiplicador de HP y ataque**.
   Como el multiplicador sube las dos estadísticas, una escala `s` vale `s²` de
   poder de combate; con los cuerpos, la presión cuenta al cubo. A profundidad 6
   con riesgo alto, la presión original era 2,3: cinco enemigos a 2,3× contra un
   máximo de seis unidades del jugador a 1×. El jugador, en cambio, sólo crece
   con los drafts, que suman +2 a una estadística.
3. **La atrición no daba de sí.** Nadie se cura entre nodos salvo con la carta de
   curación, que sólo sale en 3 de 5 cartas y curaba el 30 %. Medido: una
   plantilla de cuatro salía del primer nodo con el **73 %** del depósito de vida,
   del segundo con el **56 %** y del tercero con el **1 %**. Siete nodos a ese
   ritmo no caben en un depósito.

---

## 5. Qué se cambió y por qué

Siete valores. Cada uno con la medición que lo obliga.

| Clave | Antes | Después | Qué medición lo justifica |
|---|---|---|---|
| `combat_unit_stats` → `hp` | 30 / 22 / 60 | **100 / 75 / 200** | Las 189 celdas del barrido quedaban por debajo de 3 min. Las rondas son vida entre golpe: ×3,3 lleva un encuentro de 3-5 rondas a 8-12, que es la ventana pedida. `atk` y `def` no se tocan (ver más abajo) |
| `combat_enemy_scale_per_depth` | 0,15 | **0,02** | Con 0,15, cero expediciones ganadas sobre 3.600 simuladas. Con 0,035 (probado) la columna de cuatro de era 1 seguía en 0 %; con 0,02 sube al 53 % sobre 200 semillas |
| `combat_enemy_scale_per_era` | 0,25 | **0,12** | Con 0,25, eras 2 y 3 al 0 % con cualquier plantilla. Con 0,12, la plantilla de seis pasa al 76 % (era 2) y al 30 % (era 3) |
| `combat_risk_enemy_scale` | 0,20 | **0,05** | Mismo motivo que la profundidad: el riesgo empujaba el roster de dos a tres cuerpos, y el tercer cuerpo es el acantilado (ver §8) |
| `combat_boss_multiplier` | 1,8 | **1,15** | A 1,8 el jefe llegaba a escala 4,4 con seis cuerpos: ni una sola victoria. A 1,15 la escala del jefe queda en ~1,4 con un cuerpo más que un nodo normal, que es lo que la columna superviviente puede morder |
| `combat_draft_values.heal_pct` | 0,3 | **0,5** | Ablación directa (100 semillas, todo lo demás igual): con 0,3 la plantilla de cuatro de era 1 gana el **29 %**; con 0,5, el **56 %**. Es la única sanación de toda la expedición |
| `combat_morale_attack_range` | (0,85 – 1,15) | **(0,60 – 1,40)** | Ablación directa (100 semillas): con el rango estrecho la misma plantilla de cuatro gana el **11 %**; con el ancho, el **56 %**. A moral 75 el estrecho daba ×1,075, que el redondeo se comía entero (8 × 1,075 = 8,6 → 9, el mismo 9 que sin moral) |

### Por qué HP y no `atk`

Subir la vida y bajar el ataque alargan igual el encuentro, pero no cuestan lo
mismo:

- `atk` y `def` son la relación que hace que la artillería pegue (14 contra 8) y
  que el vehículo aguante (def 5 contra 2). Moverlos cambia **qué unidad sirve
  para qué**, que no es lo que pedía T046.
- `tests/combat/test_combat_ai.gd` fija la prioridad de objetivos de la IA sobre
  esos números concretos (infantería atk 8, vehículo def 5 → recibe 3;
  infantería def 2 → recibe 6). Son tests de **regla**, no de balance: tocar
  `atk`/`def` los rompería sin que la regla que protegen hubiera cambiado.

Subir sólo la vida deja intactas las dos cosas y mueve exactamente el número que
había que mover.

### Por qué la moral es la palanca de la columna pequeña

`morale_attack_mod` es **el único modificador que sólo tiene el jugador**: los
enemigos se construyen siempre a 1,0 (`Expedition.build_enemy_units()`). Es, por
tanto, la única forma de que una columna pequeña gane un nodo sin dejarse a
nadie, sin tocar las estadísticas base que comparten los dos bandos.

El rango sigue siendo **simétrico alrededor de 1,0**: moral 50 no suma ni resta.
Esa es una regla, no un número de balance, y `tests/combat/test_combat_rules.gd`
la fija — un rango asimétrico rompe el test, y con razón. El precio de la mitad
de abajo es real y deliberado: salir con la moral por los suelos (×0,60) es salir
a perder, que es justo lo que la moral debería significar.

### Lo que no se tocó, y por qué

| Clave | Valor | Motivo |
|---|---|---|
| `combat_turn_limit` | 20 | **El objetivo ya se cumple sin moverlo.** El tope de turnos no salta: 0 % de los encuentros llega a él antes, y del 0 % al 1 % después. No hay nada que arreglar |
| `combat_ai_step_delay` | 0,45 s | Subirlo alargaría el reloj sin alargar la partida: haría el encuentro más lento, no más largo. No es lo mismo |
| `combat_enemy_base_slots` | 2 | Es el suelo útil: con presión 1,0 da dos enemigos, y uno solo no es un encuentro |
| `combat_risk_reward_bonus` | 0,35 | Se bajó el lado del enemigo del riesgo, no el del botín: el camino peligroso tiene que seguir pagando más de lo que cuesta |
| `combat_reward_base` | oro 60, madera 30 | La economía de la expedición no estaba en el encargo y la sonda no la mide. Ver §8 |
| `combat_draft_values` (resto) | atk 2, def 2, move 1, init 2 | Con la curación al 0,5 el objetivo ya se alcanza. No hacía falta tocarlos |
| `combat_map_depth`, `combat_map_branching`, `combat_board_size`, `combat_deploy_cap`, `combat_draft_options`, `combat_draft_focus_multiplier`, `combat_morale_initiative_bonus`, `combat_morale_on_victory`, `combat_morale_per_casualty` | sin cambios | Ninguna medición los señaló |

---

## 6. Después

Misma sonda, mismas semillas.

### 6.1 Encuentros — medias sobre profundidad y riesgo

| Celda | Victoria | Rondas | Tope de turnos | Bajas | Minutos (3 s / 8 s) |
|---|---|---|---|---|---|
| era 1, plantilla 3 | 100 % | 11,4 | 0 % | 0,00 | **3,1** (2,0 / 4,8) |
| era 1, plantilla 4 | 100 % | 9,9 | 0 % | 0,00 | **3,5** (2,3 / 5,4) |
| era 1, plantilla 6 | 100 % | 8,0 | 0 % | 0,10 | **4,3** (2,8 / 6,7) |
| era 2, plantilla 3 | 62 % | 9,3 | 0 % | 1,14 | **2,5** (1,6 / 3,7) |
| era 2, plantilla 4 | 88 % | 10,2 | 0 % | 1,19 | **3,1** (2,0 / 4,6) |
| era 2, plantilla 6 | 100 % | 6,7 | 0 % | 0,43 | **3,4** (2,2 / 5,2) |
| era 3, plantilla 3 | 52 % | 11,2 | 1 % | 1,65 | **2,9** (2,0 / 4,3) |
| era 3, plantilla 4 | 84 % | 11,4 | 1 % | 0,99 | **3,7** (2,5 / 5,6) |
| era 3, plantilla 6 | 100 % | 8,1 | 0 % | 0,16 | **4,3** (2,8 / 6,5) |

**107 de las 189 celdas caen dentro de 3-5 minutos (57 %), y ninguna se pasa de
5.** Las 82 cortas son casi todas plantillas de tres, que juegan menos turnos por
ronda: una columna pequeña pelea más rápido, y eso no es un defecto.

Un encuentro típico de era 1 (plantilla de 4, profundidad 0-2):

| Profundidad | Riesgo | Victoria | Rondas | Bajas | Turnos de jugador | Minutos |
|---|---|---|---|---|---|---|
| 0 | bajo | 100 % | 9,0 | 0,00 | 35,0 | **3,3** |
| 0 | medio | 100 % | 10,0 | 0,00 | 37,0 | **3,5** |
| 0 | alto | 100 % | 10,0 | 0,00 | 37,0 | **3,5** |
| 1 | bajo | 100 % | 9,0 | 0,00 | 35,0 | **3,3** |
| 2 | bajo | 100 % | 9,0 | 0,00 | 35,0 | **3,3** |

### 6.2 Expediciones completas

| Era | Plantilla | Modo | Ganadas | Nodos limpiados | Muere en profundidad | Bajas | Min/expedición |
|---|---|---|---|---|---|---|---|
| 1 | 3 | azar | 0 % | 2,47 | 2,47 | 2,95 | 8,5 |
| 1 | 3 | **jugado** | **2 %** | 4,47 | 4,42 | 2,79 | 15,1 |
| 1 | 4 | azar | 2 % | 4,38 | 4,33 | 3,88 | 15,0 |
| 1 | 4 | **jugado** | **53 %** | 6,55 | 5,91 | 2,43 | 23,2 |
| 1 | 6 | azar | 58 % | 6,59 | 6,07 | 4,21 | 25,3 |
| 1 | 6 | **jugado** | **100 %** | 7,04 | — | 1,32 | 28,6 |
| 2 | 4 | jugado | 0 % | 5,32 | 5,32 | 3,90 | 15,2 |
| 2 | 6 | jugado | **76 %** | 6,80 | 6,06 | 3,35 | 20,9 |
| 3 | 4 | jugado | 1 % | 3,85 | 3,84 | 3,88 | 14,6 |
| 3 | 6 | jugado | **30 %** | 6,04 | 5,62 | 4,60 | 26,5 |

### 6.3 El desgaste, que es donde se juega la expedición

Porcentaje del depósito de vida que le queda a la columna al salir de cada nodo
(era 1; el depósito es la suma de HP de toda la plantilla inicial, viva o
muerta, así que los muertos cuentan como cero):

| Plantilla | Modo | d0 | d1 | d2 | d3 | d4 | d5 | d6 | d7 |
|---|---|---|---|---|---|---|---|---|---|
| 4 | **antes**, jugado | 73 % | 56 % | 1 % | — | — | — | — | — |
| 6 | **antes**, jugado | 83 % | 62 % | 34 % | 17 % | — | — | — | — |
| 4 | después, azar | 81 % | 66 % | 47 % | 35 % | 28 % | 29 % | 27 % | — |
| 4 | **después, jugado** | 81 % | 75 % | 70 % | 64 % | 56 % | 47 % | 44 % | **36 %** |
| 6 | **después, jugado** | 89 % | 81 % | 73 % | 70 % | 68 % | 65 % | 64 % | **62 %** |

Ésta es la tabla que explica todo lo demás. Antes, la curva se desplomaba y la
columna no llegaba ni a la mitad del mapa. Ahora una plantilla de cuatro bien
jugada pisa el jefe con algo más de un tercio del depósito: apretado, que es lo
que debe ser el último nodo de una run roguelike, pero jugable.

### 6.4 Dónde muere la columna (era 1, 200 expediciones por fila)

| Plantilla | Modo | Derrotas | Reparto por profundidad |
|---|---|---|---|
| 3 | azar | 200/200 | d2:121 d3:69 d4:7 d5:2 d7:1 |
| 3 | jugado | 197/200 | d2:8 d3:40 d4:51 d5:65 d6:26 d7:7 |
| 4 | azar | 196/200 | d3:48 d4:68 d5:55 d6:18 d7:7 |
| 4 | **jugado** | **94/200** | d5:35 d6:32 d7:27 |
| 6 | azar | 84/200 | d5:22 d6:34 d7:28 |
| 6 | **jugado** | **0/200** | — |

Las derrotas de la plantilla de cuatro bien jugada se concentran en d5-d7, es
decir **en el jefe o en el nodo anterior**. Es exactamente donde una run debe
decidirse.

---

## 7. ¿Se cumplen los objetivos?

### Objetivo 1 — un encuentro dura 3-5 minutos: **sí, con matices**

- La media por era y plantilla va de **2,5 a 4,3 minutos**; siete de las nueve
  combinaciones caen dentro de la ventana y **ninguna se pasa de 5**.
- Contando celda a celda: 107 de 189 dentro (57 %), 82 por debajo, 0 por encima.
- El caso de referencia del encargo — plantilla de 4 de era 1 — mide **3,3-3,5
  minutos**, centrado en la ventana.
- **Margen frente a la constante del jugador:** con 3 s por turno el mismo
  encuentro mide 2,1-2,3 min y con 8 s, 5,0-5,4. O sea: la conclusión "está en
  la ventana" vale para un jugador de entre ~4 y ~7 segundos por turno. Por
  debajo de eso el encuentro se queda corto; por encima, se pasa. Es el rango más
  honesto que se puede dar sin un reloj real sobre una partida real.
- Lo que queda corto son las plantillas de tres (2,5-3,1 min). Alargarlas más
  exigiría subir la vida otra vez, y eso empujaría las plantillas de seis por
  encima de los 5 minutos. **Con un solo número de vida para todos, la duración
  no puede quedar centrada para 3 y para 6 a la vez**; se eligió no pasarse por
  arriba, porque un encuentro largo se abandona y uno corto no.

### Objetivo 2 — la primera expedición es ganable con 3-4 unidades de era 1: **sí con 4, a duras penas con 3**

| Plantilla | Antes | Después (azar) | Después (jugado) |
|---|---|---|---|
| 3 unidades | 0 % | 0 % | **2 %** |
| 4 unidades | 0 % | 2 % | **53 %** |
| 6 unidades | 0 % | 58 % | **100 %** |

- Con **cuatro** unidades de era 1 la expedición se gana algo más de la mitad de
  las veces jugando razonablemente bien, y eso con el modelo `jugado`, que es
  peor que una persona. El objetivo se cumple con margen.
- Con **tres** el 2 % dice que es posible y poco más. Es una consecuencia directa
  de la ley del cuadrado en un combate determinista: el enemigo mínimo de un nodo
  son dos cuerpos con las mismas estadísticas que el jugador, y tres unidades
  contra dos pierden ~0,76 unidades por combate mientras que cuatro contra dos
  pierden ~0,54. No hay ningún valor `combat_*` que rompa esa aritmética sin
  hacer trivial la plantilla de seis, que ya está al 100 %.
- El coste de esa afinación es que **una columna de seis de era 1 gana siempre**.
  Es el precio de que una de cuatro pueda ganar: mientras la única diferencia
  entre plantillas sea su tamaño, el balance no puede apretar a la pequeña sin
  volver invencible a la grande. Comprometer el ejército entero debería costar
  algo en la base (mantenimiento, el Diezmo que llega sin guarnición), y eso ya
  no es `combat_*`.

---

## 8. Lo que no se arregla desde `combat_*`

Con los números delante, y por orden de cuánto duele:

### 8.1 El tercer cuerpo es un acantilado, no una rampa

Medido: una plantilla de cuatro contra **dos** enemigos a escala 1 gana con
**0,00 bajas**; contra **tres**, pierde 2-3 unidades o el encuentro entero. No
hay término medio, porque el combate no tiene varianza y el fuego se concentra.
Eso obliga a que casi toda la primera expedición sean nodos de dos enemigos: la
dificultad sube por el multiplicador y por el cuerpo extra del jefe, no por
llenar el tablero.

Se nota en que `combat_enemy_scale_per_depth` acabó en 0,02, que es casi plano.
Probado: a 0,035 la plantilla de cuatro vuelve al 0 %.

**Lo que habría que tocar, y está fuera de `combat_*`:** que la presión no
alimente a la vez el número de cuerpos y el multiplicador de estadísticas
(`ExpeditionGenerator.enemy_roster()` / `enemy_scale()`), o que el daño tenga
algo de varianza para que perder un enfrentamiento no signifique perderlo todo.

### 8.2 La curación es lo único que sostiene una run, y es una carta al azar

La carta de curación sale en 3 de 5 cartas del catálogo y hay que gastar el draft
del nodo en ella. Subirla a 0,5 casi duplicó la tasa de victoria (29 % → 56 % sobre las mismas 100 semillas), lo que
dice lo que pesa. Pero sigue siendo azar: la diferencia entre el modo `azar`
(2 %) y el modo `jugado` (53 %) es, sobre todo, coger la curación cuando toca.

**Fuera de alcance:** una fuente de recuperación que no compita con las mejoras
(una carta de campamento aparte, o curación fija al limpiar un nodo). Es diseño,
no un número.

### 8.3 Perder un encuentro es perder la columna entera

En las tablas de antes, las bajas por derrota son siempre el tamaño exacto de la
plantilla. Con daño determinista y fuego concentrado, el perdedor se queda sin
nadie. No hay retirada: `Expedition.mark_defeated()` acaba la run. Eso convierte
cada nodo en todo o nada y es lo que hace que el balance sea tan sensible.

**Fuera de alcance:** una retirada con coste (perder el botín del nodo pero
salvar a los vivos), que es `Expedition` y `CombatManager`.

### 8.4 La duración no puede centrarse para 3 y para 6 unidades a la vez

Ya explicado en §7. Los minutos son proporcionales a los turnos de jugador, que
son proporcionales al tamaño de la plantilla. Un único juego de HP no puede
centrar las dos puntas.

**Fuera de alcance:** que el tope de turnos o el tamaño del tablero dependan del
tamaño de la columna, o que el tablero encoja con plantillas pequeñas.

### 8.5 El botín ya no crece con la profundidad

`ExpeditionGenerator.node_rewards()` reutiliza `combat_enemy_scale_per_depth` y
`combat_enemy_scale_per_era` **también** para el multiplicador del botín. Al
bajar 0,15 → 0,02 y 0,25 → 0,12, el pago por nodo deja de crecer casi nada con la
profundidad: un nodo de fondo paga ~14 % más que el de apertura, cuando antes
pagaba ~90 % más. El riesgo sí sigue pagando (`combat_risk_reward_bonus` 0,35,
sin tocar) y el jefe también.

No se compensó subiendo `combat_reward_base` porque esa clave la comparten las
escaramuzas y el Diezmo (`CombatRules.encounter_rewards()`), y la sonda no mide
la economía de la base: sería mover un número de la economía a ciegas, que es
exactamente lo que T046 pide no hacer. **Pendiente:** desacoplar el
multiplicador de botín del de dificultad, o una pasada de economía con su propia
medición.

---

## 9. Lo que esto mueve fuera de la expedición

Los mismos `combat_*` los usan la escaramuza suelta, la defensa del Diezmo y la
Auditoría Final. Lo que cambia allí, sin haberlo medido en este encargo:

- **Todos los combates duran ~3 veces más rondas.** Es simétrico (la vida sube en
  los dos bandos), así que no cambia quién gana, pero sí cuánto se tarda. Un
  asedio de 3-5 oleadas de la Auditoría Final pasa de unos minutos a bastantes
  más. Medirlo es `tools/audit_probe.gd`, y la palanca son las claves
  `final_audit_*`, que quedan fuera de T046.
- **La guarnición pega más con la moral alta y bastante menos con la baja.** El
  rango de moral se aplica también a la defensa y a la Auditoría
  (`CombatManager` línea 398, `FinalAudit.gd` línea 104). Con la base sana la
  defensa es más fácil que antes; con la base hundida, bastante peor. Es
  coherente con lo que la moral debería significar, pero es un cambio de
  dificultad en el endgame que nadie ha medido todavía.
- **`docs/15-combat.md` §8** lista los valores por defecto anteriores. Esa tabla
  quedó desactualizada con este cambio; actualizarla está pendiente.

---

## 10. Tests tocados

Dos tests de `tests/combat/` cayeron con el cambio. Uno era una regla y el otro
un número:

| Test | Qué pasó | Qué se hizo |
|---|---|---|
| `test_combat_rules.gd` → `test_morale_attack_modifier_spans_the_configured_range` | Fijaba que **moral 50 no suma ni resta** (`morale_attack_mod(50) == 1.0`). El primer intento de rango, (0,80 – 1,40), es asimétrico y daba 1,10 | **El cambio estaba mal, no el test.** El rango se rehízo simétrico: (0,60 – 1,40). El test no se tocó |
| `test_expedition_generator.gd` → `test_rosters_grow_with_depth` | Comprobaba la regla "el roster crece con la profundidad" tomando como muestra la profundidad 8. Con `combat_enemy_scale_per_depth` en 0,02 el tercer cuerpo entra más tarde | **La regla sigue en pie, cambió cuándo se nota.** La profundidad de muestra pasó de 8 a 16, con el porqué en el propio test. `test_the_roster_never_shrinks_as_the_run_goes_deeper` sigue comprobando la monotonía y el crecimiento estricto sin tocar |

Suite entera: **670 casos, 35 suites, 0 fallos.**

---

## 11. Cómo repetir la medición

La sonda es reutilizable. Todos los parámetros del barrido están arriba del
archivo como constantes (`SEEDS`, `EXPEDITION_SEEDS`, `ERAS`, `DEPTHS`, `RISKS`,
`PARTY_SIZES`, `MORALE`, `PLAYER_SECONDS_PER_TURN`).

```bash
# 1. Registrar la sonda como autoload, TEMPORALMENTE
#    project.godot -> [autoload] -> BalanceProbe="*res://tools/balance_probe.gd"

# 2. Correr el juego headless: la sonda imprime las tablas y cierra sola
godot --headless --path . > balance.txt

# 3. QUITAR la línea del autoload antes de commitear
git diff project.godot   # tiene que salir vacío
```

La sonda se aparta sola cuando Godot arranca con `-s` (la suite de gdUnit lo
hace): si no, una sonda que cierra el juego al acabar se llevaría por delante la
ejecución de los tests.

Para medir un cambio, lo único que hace falta es tocar el valor en
`GameConfig.gd` y volver a correrla. Un barrido completo de 200 semillas tarda
unos minutos.

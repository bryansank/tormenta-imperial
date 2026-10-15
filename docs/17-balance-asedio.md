# Balance de la Auditoría Final

La Auditoría Final es el final del juego: de 3 a 5 oleadas defensivas
encadenadas, sin relevos y sin curación entre ellas. Este documento recoge cómo
se midió y por qué los multiplicadores son tan pequeños.

Hermano de [16-balance-combate.md](16-balance-combate.md), que cubre los
encuentros y las expediciones. Sonda: `tools/siege_probe.gd`.

---

## El hallazgo: no se podía ganar

El test de campaña completa (`tests/integration/test_full_campaign.gd`) destapó
que el asedio era invencible. La sonda lo confirmó sobre 200 semillas por
configuración, con moral 100, era 3 y las dos torres en pie:

| Guarnición | Gana | Oleadas limpiadas | Supervivientes |
|---|---|---|---|
| 3 infantería (mínima) | 0,0 % | 1,00 de 3,98 | 0,00 |
| 3 vehículos | 0,0 % | 2,00 | 0,00 |
| 4 vehículos | 0,0 % | 2,00 | 0,00 |
| 5 vehículos | 0,0 % | 2,00 | 0,00 |
| 6 infantería | 0,0 % | 2,00 | 0,00 |
| Mixta 3+2+1 | 0,0 % | 2,00 | 0,00 |
| Mixta 2+2+2 | 0,0 % | 2,00 | 0,00 |
| **6 vehículos (máxima)** | **0,0 %** | 2,32 | 0,27 |

Cero victorias en 1.600 asedios. Con la guarnición más fuerte que el juego
permite: el tope de despliegue ocupado por la unidad de más poder, más las dos
dotaciones de torre, y con la inteligencia artificial jugando los dos bandos.

## Por qué

No era el número de oleadas ni su composición. Eran tres cosas sumándose:

1. **El multiplicador toca vida y ataque a la vez.** El poder efectivo sube al
   cuadrado, así que un `+0,22` por oleada no es un 22 % más de dificultad.
2. **No era la única cuesta.** Los cuerpos ya suben solos (3, 4, 5, 6), la
   formación ya mete cañones en la segunda oleada y blindados en la tercera, y
   la guarnición no se cura ni se reentrena. La atrición ya era el balance de
   verdad; la escalada solo decidía cuánto muerde.
3. **La era entraba dos veces.** El `+0,25` por era valía `+0,50` fijo en *toda*
   oleada, porque el Cuartel General es de era 3 y el asedio no se convoca
   antes. La oleada de apertura salía ya multiplicada por 1,5.

## Lo que se cambió

| Clave | Antes | Después |
|---|---|---|
| `final_audit_scale_per_wave` | 0,22 | **0,03** |
| `final_audit_scale_per_era` | 0,25 | **0,05** |
| `final_audit_last_wave_multiplier` | 1,50 | **1,05** |

Nada más. Ni el número de oleadas, ni los cuerpos por oleada, ni la formación,
ni una sola estadística de unidad.

## Después

Mismas 200 semillas por configuración:

| Guarnición | Gana | Oleadas | Supervivientes al ganar | Minutos |
|---|---|---|---|---|
| 3 infantería (mínima) | 0,0 % | 2,00 | — | 8,7 |
| 3 vehículos | 6,0 % | 2,73 | 1,00 | 14,3 |
| 4 vehículos | 33,5 % | 3,25 | 2,76 | 16,5 |
| 5 vehículos | 65,0 % | 3,63 | 2,92 | 19,8 |
| 6 infantería | 0,0 % | 2,00 | — | 16,0 |
| Mixta 3+2+1 | 29,0 % | 2,96 | 0,72 | 18,6 |
| Mixta 2+2+2 | 33,5 % | 3,06 | 3,24 | 19,9 |
| **6 vehículos (máxima)** | **82,0 %** | 3,81 de 3,98 | 3,89 de 6 | 21,1 |

Lo que dice esta tabla, que es lo que se buscaba:

- **Duro y ganable.** La guarnición máxima gana cuatro de cada cinco veces y
  llega al final con tres de seis unidades en pie. No es un trámite.
- **La mínima no basta.** Tres infantes no ganan nunca; tres vehículos, una de
  cada dieciséis. Perder el asedio sigue costando.
- **Hay gradiente.** 4 vehículos 33 %, 5 vehículos 65 %, 6 vehículos 82 %. Más
  ejército, más posibilidades, que es lo que hace que valga la pena criarlo.
- **La infantería sola no llega.** Seis infantes pierden siempre. Para el final
  hacen falta blindados, y eso es una afirmación de diseño, no un accidente.

## Gobernador

En el nivel Gobernador de la Campaña (docs/20 §1b) cada oleada lleva además
`audit_enemy_mult` (`GameConfig.game_tier_rules.governor`) sobre su escala.
Objetivo: con la guarnición máxima el asedio sigue siendo ganable **≥ 60 %**.
Medido el 2026-10-04 con 200 semillas, era 3, moral 100, 2 torres:

| Guarnición | Colono (×1,00) | **Gobernador ×1,06** | ×1,10 |
|---|---|---|---|
| 3 infantería (mínima) | 0,0 % | 0,0 % | 0,0 % |
| 3 vehículos | 6,0 % | 0,0 % | 0,0 % |
| 4 vehículos | 33,5 % | 33,5 % | 33,5 % |
| 5 vehículos | 65,0 % | **43,0 %** | 33,5 % |
| 6 infantería | 0,0 % | 0,0 % | 0,0 % |
| Mixta 3+2+1 | 29,0 % | 0,0 % | 0,0 % |
| Mixta 2+2+2 | 33,5 % | 29,0 % | 15,0 % |
| **6 vehículos (máxima)** | 82,0 % | **68,0 %** (2,46 vivos; 3,63 al ganar) | 68,0 % |

Se queda **×1,06**: la máxima gana 68 % (≥ 60 %), cinco vehículos bajan de 65 %
a 43 % (en Gobernador hay que llegar con el ejército entero) y las mixtas
siguen teniendo opciones. Con ×1,10 la máxima no se mueve (el combate es
determinista y salta a escalones), pero las mixtas y los cinco vehículos se
hunden: más castigo sin ganar nada. Duración igual (~21 min con la máxima).

```
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --tier=governor
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --tier=governor --audit_mult=1.10
```

(Con un `override.cfg` propio en la raíz, como toda sonda; bórralo al terminar.)

## Advertencias

- **La medición es un suelo pesimista.** La juega `AutoResolver` con
  `CombatAI` a los dos lados, y esa inteligencia está escrita para atacar, no
  para defender una posición. Una persona juega la defensa mejor.
- **Duración.** El asedio completo con guarnición máxima son unos 21 minutos y
  34 rondas repartidas en cuatro oleadas, es decir 8 o 9 rondas por oleada, que
  es justo la ventana de diseño de un encuentro. Largo para una sola sentada,
  pero es el final de la partida. Si alguna vez se quiere acortar, la palanca
  es el rango de oleadas (`final_audit_waves`), no la escalada.
- **El combate no tira dados.** Como se explica en
  [16-balance-combate.md](16-balance-combate.md), el daño es determinista: las
  tasas de victoria de esta tabla salen de que cambia la semilla del asedio
  (longitud y formación), no de que el mismo asedio se juegue distinto.

## Cómo volver a medirlo

```
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --spw=0.12 --last=1.25
```

Los argumentos `--spw`, `--spe` y `--last` pisan los tres multiplicadores sin
tocar `GameConfig`, que es como se hicieron las dos tablas de arriba. `--detail=1`
desglosa por longitud de asedio.

Los dos casos de guardia viven en `tests/integration/test_full_campaign.gd`:
`test_the_siege_is_hard_but_winnable_with_a_full_garrison` y
`test_the_smallest_garrison_that_can_resummon_does_not_win`.

---

## Ventaja por tipo (2026-10-13, rama `feat/combate-3d`)

La regla nueva del combate (docs/15 §3 "Segunda tanda"): artilleria > vehiculo >
infanteria > artilleria, x1,5 con ventaja y x0,75 con desventaja sobre el dano
neto (`GameConfig.combat_type_advantage`). Medido con `tools/siege_probe.gd`
(era 3, moral 100, 2 torres, nivel Colono), con los `final_audit_*` de esta rama
(oleada 0.03, era 0.05, ultima x1.05, 3+1 cuerpos, un canon cada 3, blindado
desde la oleada 2). `-- --adv=off` mide el antes; `-- --adv=A,D` pisa los
multiplicadores.

| Guarnicion | Antes (sin ventaja, 200 sem.) | Despues x1,5/x0,75 (200 sem.) |
|---|---|---|
| min 3 infanteria | 0 % | 0 % |
| min 3 vehiculos | 6,0 % | 6,0 % |
| 4 vehiculos | 33,5 % | 33,5 % |
| 5 vehiculos | 65,0 % | 48,5 % |
| 6 infanteria | 0 % | 0 % |
| mixta 3+2+1 | 29,0 % | 25,5 % |
| mixta 2+2+2 | 33,5 % | 33,5 % |
| **MAX 6 vehiculos** | **82,0 %** | **68,0 %** |

Por que baja: las oleadas llevan un canon por cada 3 cuerpos, y el canon pega al
blindado con ventaja; la guarnicion maxima es toda blindados. Variantes (100
semillas, MAX 6 vehiculos / mixta 2+2+2):

| Multiplicadores | Canones de la Regencia | MAX 6 vehiculos | mixta 2+2+2 |
|---|---|---|---|
| 1,25 / 0,8 | 1 de cada 3 | 71 % | 34 % |
| 1,35 / 0,85 | 1 de cada 3 | 76 % | 34 % |
| 1,5 / 0,9 | 1 de cada 3 | 71 % | 34 % |
| 1,25 / 0,9 | 1 de cada 3 | 76 % | 34 % |
| **1,5 / 0,75** | **1 de cada 4** (`--gun=4`) | **83 %** | 34 % |
| 1,5 / 0,75 | 1 de cada 5 (`--gun=5`) | 83 % | 34 % |
| 1,35 / 0,85 | 1 de cada 4 | 88 % | 34 % |

**Propuesta (sin aplicar, la decide la rama de balance):** mantener x1,5 / x0,75
y subir `final_audit_artillery_share` de 3 a 4. Devuelve la guarnicion maxima al
~82 % de antes (83 %) sin tocar la escala de las oleadas, y deja intacta la
mixta. 5 no da mas. Hay que medirlo junto a lo que endurezca el final la rama
`balance/campana-4-6h`: los dos cambios tocan el mismo asedio.

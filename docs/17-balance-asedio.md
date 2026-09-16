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

# Audio Manifest

> **Estado (2026-10-12):** todas las claves tienen su propio archivo. Ya no queda
> ningun alias: el combate, la Tormenta, el rango, la comida y la UI suenan con
> clips propios, y el ambiente tiene dos bucles (dia y Tormenta). Terceros: solo
> **CC0** (ver `assets/CREDITS.md` y `THIRD-PARTY-NOTICES.md`). Lo sintetizado es
> obra propia (`tools/gen_ambient_audio.gd`).

Drop audio files into the folders below using the **exact base filenames** listed.
`AudioManager` loads each one automatically at startup (tries `.ogg`, then `.wav`,
then `.mp3`). **Files are optional** — anything missing is skipped silently, so the
game runs fine with partial or zero audio installed. No code changes are needed to
replace a clip: just drop the file with the right name.

The manifest keys live in `scripts/services/AudioManager.gd` (`MUSIC_MANIFEST`,
`AMBIENT_MANIFEST`, `SFX_MANIFEST`). To add a new sound, add a key there and a
matching `EventBus` hook in `_connect_events()`. A signal that may not exist yet is
connected with `_connect_optional()` (guarded by `EventBus.has_signal`).

### Peso y equipos flojos

El juego tiene que ir en equipos y tablets muy flojos y cuidar el tamano del .exe y
del APK:

- **Bucles largos** (musica, ambiente) en **OGG** (Vorbis, se decodifica en
  streaming). El ambiente son **dos bucles de 40 s a 22 050 Hz** (~250-300 KB cada
  uno) y nunca suenan mas de dos a la vez (solo durante el fundido).
- **Efectos cortos** en OGG, de 0,1 a 5,5 s, 44,1 kHz o menos. Ninguno pasa de 30 KB.
- **Voces simultaneas:** los efectos salen de un pool de `GameConfig.audio_sfx_voices`
  reproductores; el limite de rafaga (`SFX_BURST_GAP_MSEC`, 60 ms) impide que la
  misma clave se apile.
- Nada de pistas de varios minutos: la mas larga (`combat`) dura 96 s.

### Volumen

Todo va bajo por defecto. Cada efecto tiene su ganancia fija en `SFX_GAIN_DB`
(por nombre de fichero; lo que no aparece baja `SFX_DEFAULT_GAIN_DB`, -6 dB), y cada
bucle de ambiente la suya en `AMBIENT_GAIN_DB`. La musica sigue siendo opcional
(`set_music_enabled()` / `toggle_music()`); el ambiente y los efectos no dependen de
ese interruptor.

---

## `music/` — cross-faded background tracks (looping)

| Filename (base) | When it plays | EventBus trigger | Source |
|-----------------|---------------|------------------|--------|
| `era_1_frontier`   | New game / Era 1        | `game_new_started`, `era_advanced(1)` | Dark Sci-Fi Audio Pack (SRG774, OGA, CC0) |
| `era_2_industrial` | On reaching Era 2       | `era_advanced(2)` | idem |
| `era_3_petroleum`  | On reaching Era 3       | `era_advanced(3)` | idem |
| `victory`          | Imperial Victory        | `victory_achieved` | idem |
| `combat`           | During a board          | `encounter_started` → back to the era on the last `encounter_ended` / `expedition_ended` | **Battle Theme A**, cynicmusic (https://opengameart.org/content/battle-theme-a, CC0), re-encoded to OGG at -4.5 dB to sit level with the era tracks. 96 s, 1.1 MB |

The combat theme is no longer a loan of `era_3_petroleum`. A chained encounter keeps
the theme; if victory music took the bus during the fight, it is left alone.

## `ambient/` — dos bucles con fundido (bus Ambient)

| Filename (base) | When it plays | EventBus trigger | Source |
|-----------------|---------------|------------------|--------|
| `day`   | Calma y Aviso: olas suaves + pajaros | `game_new_started`, `game_load_completed`; vuelve con `storm_phase_changed(CALM)` | Sintesis propia (`tools/gen_ambient_audio.gd`). 40 s, estereo, 22 050 Hz, 247 KB |
| `storm` | Ceniza, Tormenta y Diezmo: viento con rachas + truenos lejanos; los pajaros callan | `storm_phase_changed(ASH / STORM / TITHE)` | Sintesis propia. 40 s, estereo, 22 050 Hz, 289 KB |

The loop is chosen from the storm phase (`StormCycle.Phase`): ASH, STORM and TITHE →
`storm`; CALM and WARNING → `day`. Switching cross-fades in `AMBIENT_FADE_SECONDS`
(4 s). On `game_load_completed` the phase is read from `StormManager.get_phase()`, so
a save made mid-storm reloads with wind (and no phase sound). `storm_halted_forever`
puts the cycle back to CALM, and the birds come back. Both loops are flagged as
looping at load (`_make_ambient_loop()`), with the `finished` restart as a safety net.

## `sfx/` — one-shot effects (pooled, can overlap)

### Base

| Filename (base) | When it plays | EventBus trigger | Source |
|-----------------|---------------|------------------|--------|
| `build_place`       | Building dropped on grid      | `building_placed`            | Kenney Impact Sounds |
| `build_complete`    | Construction finishes         | `construction_completed`     | Kenney Interface Sounds |
| `upgrade_complete`  | Upgrade finishes              | `building_upgrade_completed` | Kenney Music Jingles (`STEEL03`) |
| `demolish`          | Building demolished           | `building_demolished`        | Kenney Impact Sounds |
| `trade_buy`         | Market purchase               | `market_trade_completed` (buy)  | Kenney RPG Audio (`handleCoins`) |
| `trade_sell`        | Market sale                   | `market_trade_completed` (sell) | Kenney RPG Audio |
| `unlock`            | New resource unlocked         | `resource_unlocked`          | Kenney Interface Sounds |
| `era_up`            | Era advances                  | `era_advanced`               | Kenney Music Jingles (`STEEL06`) |
| `milestone`         | Milestone achieved            | `milestone_completed`        | Kenney Music Jingles (`STEEL01`) |
| `event_danger`      | Danger event (storm, raid…)   | `random_event_started` (danger)  | Kenney Interface Sounds |
| `event_positive`    | Good event (festival, caravan)| `random_event_started` (positive)| Kenney Interface Sounds |
| `process_done`      | Manual process finishes       | `process_completed`          | Kenney Impact Sounds |
| `mining_done`       | Mining action finishes        | `mining_completed`           | Kenney Impact Sounds |
| `unit_ready`        | Unit finishes training        | `unit_trained`               | Kenney RPG Audio |
| `insufficient`      | Not enough resources          | `resources_insufficient`     | Kenney Interface Sounds |
| `rank_up`           | Governor rank up              | `governor_rank_up`           | Kenney Music Jingles (`STEEL10`), 16 KB — ya no es alias de `era_up` |

### UI (enganche automatico)

`AudioManager` escucha `get_tree().node_added` y engancha el `pressed` de cada
`BaseButton` que entra al arbol (y de los que ya estaban al arrancar), y el
`tab_clicked` de cada `TabBar` (tambien los internos de un `TabContainer`). Ningun
panel tiene que llamar a nada. Un boton con la meta `no_click_sfx` no suena.

| Filename (base) | When it plays | Source |
|-----------------|---------------|--------|
| `ui_click`  | Cualquier boton normal (-13 dB) | Kenney Interface Sounds (`click_001`), 5 KB |
| `ui_toggle` | Interruptores (`toggle_mode`), `CheckBox`, `CheckButton` y pestanas (-15 dB, mas suave) | Kenney UI Audio (`switch2`), 6 KB |

### Combate

| Key / file | EventBus trigger | Source | Size |
|-----------|------------------|--------|------|
| `combat_start`      | `encounter_started`             | Kenney Music Jingles (`HIT11`, golpe de tambor orquestal) | 18 KB |
| `combat_hit`        | `unit_attacked`                 | Kenney Impact Sounds (`impactMetal_heavy_000`) | 6 KB |
| `combat_unit_lost`  | `unit_died`                     | Kenney Sci-Fi Sounds (`explosionCrunch_000`) | 28 KB |
| `combat_victory`    | `encounter_ended(true)`         | Kenney Music Jingles (`SAX02`, sube) | 17 KB |
| `combat_defeat`     | `encounter_ended(false)`, `expedition_ended(1/2)` | Kenney Music Jingles (`SAX01`, baja) | 17 KB |
| `expedition_start`  | `expedition_started`            | Kenney Music Jingles (`HIT09`, redoble corto) | 15 KB |
| `expedition_return` | `expedition_ended(0)`           | Kenney Music Jingles (`SAX10`, sube) | 14 KB |
| `audit_summoned`    | `final_audit_summoned` (opcional) | Kenney Impact Sounds (`impactBell_heavy_001`, campana grave) | 16 KB |
| `storm_halted`      | `storm_halted_forever` (opcional) | Kenney Music Jingles (`STEEL15`, acorde claro) | 16 KB |

Burst guard: the same key is not re-triggered within `SFX_BURST_GAP_MSEC` (60 ms), so
an AI turn landing several hits at once does not stack the clip or drain the voice
pool (`GameConfig.audio_sfx_voices`).

### La Tormenta

| Key / file | When it plays | EventBus trigger | Source | Size |
|-----------|---------------|------------------|--------|------|
| `storm_warning`   | Se abre el Aviso | `storm_phase_changed(WARNING)` | Sintesis propia: sirena antiaerea lejana con eco | 17 KB |
| `storm_thunder`   | La Tormenta encima | `storm_phase_changed(STORM)` | Sintesis propia: chasquido + retumbo | 21 KB |
| `tithe_demanded`  | Bajan los Tasadores | `storm_phase_changed(TITHE)` | Kenney Impact Sounds (`impactBell_heavy_002`, campana) | 9 KB |
| `tithe_collected` | El Diezmo se cobro | `tithe_resolved(false, taken)` | Kenney RPG Audio (`handleCoins2`) | 13 KB |
| `tithe_repelled`  | No se llevaron nada | `tithe_resolved(true, {})` — se calla si `combat_victory` sono hace menos de 2,5 s (el tablero ganado ya tuvo su fanfarria) | Kenney Music Jingles (`STEEL11`) | 15 KB |

La Ceniza no tiene sonido propio: la anuncia el viento del bucle `storm`, que entra
con ella. Repetir la fase en la que ya se esta no suena (p. ej. el CALM que emite
`storm_halted_forever`). La tormenta de prueba de la era 1 emite las mismas senales
y suena igual.

### Comida (rama `feat/comida-granja-recoger`)

Conectadas con `_connect_optional`: hasta que esa rama entre, la senal no existe y
no pasa nada.

| Key / file | When it plays | EventBus trigger | Source | Size |
|-----------|---------------|------------------|--------|------|
| `collect` | Recoger la produccion de un edificio | `production_collected(node, collected)` sin comida | Kenney RPG Audio (`handleSmallLeather`, bolsa) | 10 KB |
| `harvest` | Cosecha de la Granja | `production_collected(node, collected)` con `"food"` | Kenney RPG Audio (`chop`, hoz) | 9 KB |

"Recoger todo" emite una vez por edificio en el mismo frame; el limite de rafaga deja
un solo sonido.

---

## Regenerar lo sintetizado

```bash
godot --headless --path . -s tools/gen_ambient_audio.gd -- --out=res://build/audio_gen/
```

Escribe `day.wav`, `storm.wav`, `storm_warning.wav` y `storm_thunder.wav` (PCM 16 bits,
22 050 Hz; semilla fija, asi que sale lo mismo cada vez). Los OGG del repo se
codificaron desde esos WAV con libsndfile (Vorbis, `compression_level` 0,6 para el
ambiente y 0,5 para los efectos); vale cualquier codificador Vorbis (p. ej.
`ffmpeg -i day.wav -c:a libvorbis -q:a 3 day.ogg`). Como es por un `-s`, conviene
correrlo con el `override.cfg` de un user dir propio (los autoloads arrancan).

## Where to get more (free, commercial-use safe)

- **Kenney** — https://kenney.nl/assets?q=audio (UI, impacts, jingles) — **CC0**
- **OpenGameArt** — solo con **CC0** marcado en el campo License(s) de la pagina
- **Incompetech (Kevin MacLeod)** — **CC-BY** (must credit)

**Per-file rule:** verify each clip's license individually. Use **CC0** (free) or
**CC-BY** (credit required in `CREDITS.md`). Avoid **CC-BY-NC** (no commercial use).
Nothing from any commercial game.

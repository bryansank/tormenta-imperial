# Asset Credits

All third-party assets here are free and redistributable.

## Fonts (`assets/fonts/`)

| Font | Use | License | Source |
|------|-----|---------|--------|
| Black Ops One | UI titles / headers | OFL 1.1 (`OFL-BlackOpsOne.txt`) | Google Fonts |
| Rajdhani (Medium/SemiBold/Bold) | UI body, buttons, labels | OFL 1.1 (`OFL-Rajdhani.txt`) | Google Fonts |
| Special Elite | Typewritten dossier text (prologue) | Apache 2.0 (`LICENSE-SpecialElite.txt`) | Google Fonts |
| Caveat | Handwritten margin notes (prologue) | OFL 1.1 (`OFL-Caveat.txt`) | Google Fonts |

Wired in `scripts/ui/UITheme.gd` (global theme default font + title/section overrides).

## Textures (`assets/textures/`)

| Texture | Use | License | Source |
|---------|-----|---------|--------|
| metal_plate (diff/rough/nor_gl, 1K) | Building material relief + reflections | CC0 | Poly Haven |
| ui/panel_metal, panel_inset_metal, button_metal (9-patch) | Riveted metal UI panels + buttons | CC0 (derived) | Generated from metal_plate (Poly Haven) |

The three `ui/*_metal` 9-patch sprites are composited from the CC0 metal_plate
diffuse above, with a drawn brass frame + corner rivets, by `tools/gen_ui_textures.gd`
(re-runnable). Wired as textured StyleBoxes in `scripts/ui/UITheme.gd`.

Building materials are wired in `scripts/buildings/DieselpunkBuildingFactory.gd`
(`_metal()` applies the normal + roughness maps to every metal surface while keeping
each material's color).

## Audio (`assets/audio/`)

Wired in `scripts/services/AudioManager.gd` (autoload, driven by `EventBus`). File
naming, triggers and the source of every clip are documented in
`assets/audio/MANIFEST.md`. The system loads only files that exist.

All third-party audio below is **CC0** (public domain — no attribution required).
Sources are credited anyway as good practice. Kenney's licence text for each pack is
in `licenses/CC0-KENNEY-*.txt`.

| Clip(s) | Use | License | Source |
|---------|-----|---------|--------|
| `music/era_1_frontier`, `era_2_industrial`, `era_3_petroleum`, `victory` | Era background tracks + victory theme | CC0 | Dark Sci-Fi Audio Pack by **SRG774** (OpenGameArt) |
| `music/combat` | Combat theme (orchestral, war drums) | CC0 | Battle Theme A by **cynicmusic** (OpenGameArt) |
| `music/audit` | Final Audit siege theme (boss loop, 33 s) | CC0 | Basilisk Boss Battle Loop by **beardalaxy** (OpenGameArt) |
| `sfx/build_place`, `demolish`, `process_done`, `mining_done` | Placement / demolish / process / mining impacts | CC0 | Kenney — Impact Sounds |
| `sfx/combat_hit`, `audit_summoned`, `tithe_demanded` | Metal hit, low bell, short bell | CC0 | Kenney — Impact Sounds (`impactMetal_heavy_000`, `impactBell_heavy_001`, `impactBell_heavy_002`) |
| `sfx/build_complete`, `unlock`, `event_positive`, `event_danger`, `insufficient`, `ui_click` | UI feedback / alerts | CC0 | Kenney — Interface Sounds |
| `sfx/upgrade_complete`, `era_up`, `milestone` | Progression stingers (steel jingles) | CC0 | Kenney — Music Jingles |
| `sfx/combat_start`, `expedition_start` | Drum hits | CC0 | Kenney — Music Jingles (`jingles_HIT11`, `jingles_HIT09`) |
| `sfx/combat_victory`, `combat_defeat`, `expedition_return` | Sax rise / fall | CC0 | Kenney — Music Jingles (`jingles_SAX02`, `jingles_SAX01`, `jingles_SAX10`) |
| `sfx/storm_halted`, `tithe_repelled`, `rank_up` | Steel stingers | CC0 | Kenney — Music Jingles (`jingles_STEEL15`, `jingles_STEEL11`, `jingles_STEEL10`) |
| `sfx/trade_buy`, `trade_sell`, `unit_ready` | Market coins / metal click | CC0 | Kenney — RPG Audio |
| `sfx/tithe_collected`, `collect`, `harvest` | Coins, purse, chop | CC0 | Kenney — RPG Audio (`handleCoins2`, `handleSmallLeather`, `chop`) |
| `sfx/combat_unit_lost` | Crunching blast | CC0 | Kenney — Sci-Fi Sounds (`explosionCrunch_000`) |
| `sfx/ui_toggle` | Soft switch for toggles and tabs | CC0 | Kenney — UI Audio (`switch2`) |
| `ambient/day`, `ambient/night`, `ambient/storm`, `ambient/coast`, `sfx/storm_warning`, `sfx/storm_thunder` | Ambience loops (day, night crickets, storm with rain, board coast with gulls), siren, thunder | Original (game) | Synthesised by `tools/gen_ambient_audio.gd` |
| `sfx/shot_rifle`, `shot_cannon`, `tank_fire`, `tank_engine`, `plane_prop`, `plane_strafe`, `bomb_drop`, `airship_drone`, `ship_horn`, `torpedo`, `splash`, `unit_sunk`, `unit_downed` | Combat by unit type: rifle, cannon, tank, engines, propeller planes, airship, ship horn, torpedo, water hits, sinking, crash | Original (game) | Synthesised by `tools/gen_combat_audio.gd` |

Source URLs: Kenney — https://kenney.nl/assets/impact-sounds,
https://kenney.nl/assets/interface-sounds, https://kenney.nl/assets/music-jingles,
https://kenney.nl/assets/rpg-audio, https://kenney.nl/assets/sci-fi-sounds,
https://kenney.nl/assets/ui-audio. Dark Sci-Fi Audio Pack —
https://opengameart.org/content/dark-sci-fi-audio-pack. Battle Theme A —
https://opengameart.org/content/battle-theme-a. Basilisk Boss Battle Loop —
https://opengameart.org/content/basilisk-boss-battle-loop

> When adding more audio, prefer **CC0** (no attribution) or **CC-BY** (credit the
> author in this table). Do **not** use CC-BY-NC (non-commercial) clips.

---

> OFL requires the license text to ship with the fonts (kept here) and the fonts
> not be sold on their own. CC0 has no conditions. Both are safe for commercial use.

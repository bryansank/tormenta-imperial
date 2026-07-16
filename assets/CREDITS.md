# Asset Credits

All third-party assets here are free and redistributable.

## Fonts (`assets/fonts/`)

| Font | Use | License | Source |
|------|-----|---------|--------|
| Black Ops One | UI titles / headers | OFL 1.1 (`OFL-BlackOpsOne.txt`) | Google Fonts |
| Rajdhani (Medium/SemiBold/Bold) | UI body, buttons, labels | OFL 1.1 (`OFL-Rajdhani.txt`) | Google Fonts |

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
naming, triggers and recommended sources are documented in `assets/audio/MANIFEST.md`.
The system loads only files that exist, so this table grows as clips are added.

All audio below is **CC0** (public domain — no attribution required). Sources are
credited anyway as good practice.

| Clip(s) | Use | License | Source |
|---------|-----|---------|--------|
| `music/era_1_frontier`, `era_2_industrial`, `era_3_petroleum`, `victory` | Era background tracks + victory theme | CC0 | Dark Sci-Fi Audio Pack by **SRG774** (OpenGameArt) |
| `sfx/build_place`, `demolish`, `process_done`, `mining_done` | Placement / demolish / process / mining impacts | CC0 | Kenney — Impact Sounds |
| `sfx/build_complete`, `unlock`, `event_positive`, `event_danger`, `insufficient`, `ui_click` | UI feedback / alerts | CC0 | Kenney — Interface Sounds |
| `sfx/upgrade_complete`, `era_up`, `milestone` | Progression stingers (steel jingles) | CC0 | Kenney — Music Jingles |
| `sfx/trade_buy`, `trade_sell`, `unit_ready` | Market coins / metal click | CC0 | Kenney — RPG Audio |

Source URLs: Kenney — https://kenney.nl/assets (Interface Sounds, Impact Sounds,
Music Jingles, RPG Audio). Dark Sci-Fi Audio Pack —
https://opengameart.org/content/dark-sci-fi-audio-pack

> **Not yet installed:** `ambient/base_ambient` (world atmosphere loop) is intentionally
> empty — a melodic track there would clash with the era music. Add a subtle
> wind/machinery *drone* when one is sourced (see `assets/audio/MANIFEST.md`).
>
> When adding more audio, prefer **CC0** (no attribution) or **CC-BY** (credit the
> author in this table). Do **not** use CC-BY-NC (non-commercial) clips.

---

> OFL requires the license text to ship with the fonts (kept here) and the fonts
> not be sold on their own. CC0 has no conditions. Both are safe for commercial use.

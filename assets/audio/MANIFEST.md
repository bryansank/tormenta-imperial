# Audio Manifest

> **Status:** All music + SFX are installed (CC0 — see `assets/CREDITS.md`). The only
> open slot is `ambient/base_ambient` — left empty on purpose so it doesn't clash with
> the era music; add a subtle wind/machinery drone if you want a world-atmosphere bed.

Drop audio files into the folders below using the **exact base filenames** listed.
`AudioManager` loads each one automatically at startup (tries `.ogg`, then `.wav`,
then `.mp3`). **Files are optional** — anything missing is skipped silently, so the
game runs fine with partial or zero audio installed. No code changes are needed to
enable a clip: just add the file with the right name.

> Prefer **`.ogg`** for music/ambience (small, looping) and **`.wav`** for short SFX
> (instant, no decode lag). Keep SFX mono, music/ambience stereo.

The manifest keys live in `scripts/services/AudioManager.gd`. To add a new sound,
add a key there and a matching `EventBus` hook in `_connect_events()`.

---

## `music/` — cross-faded background tracks (looping)

| Filename (base) | When it plays | EventBus trigger | Suggested tone |
|-----------------|---------------|------------------|----------------|
| `era_1_frontier`   | New game / Era 1        | `game_new_started`, `era_advanced(1)` | Calm acoustic / folk-industrial |
| `era_2_industrial` | On reaching Era 2       | `era_advanced(2)` | Metallic percussion, mid orchestral |
| `era_3_petroleum`  | On reaching Era 3       | `era_advanced(3)` | Dense epic dieselpunk orchestral |
| `victory`          | Imperial Victory        | `victory_achieved` | Triumphant fanfare |

## `ambient/` — positional-free background loop (world atmosphere)

| Filename (base) | When it plays | EventBus trigger | Suggested tone |
|-----------------|---------------|------------------|----------------|
| `base_ambient` | Whole session (loops) | `game_new_started`, `game_load_completed` | Wind + distant machinery hum |

## `sfx/` — one-shot effects (pooled, can overlap)

| Filename (base) | When it plays | EventBus trigger | Suggested sound |
|-----------------|---------------|------------------|-----------------|
| `build_place`       | Building dropped on grid      | `building_placed`            | Heavy "thunk" / stamp |
| `build_complete`    | Construction finishes         | `construction_completed`     | Rivet/steam "ready" |
| `upgrade_complete`  | Upgrade finishes              | `building_upgrade_completed` | Ascending mechanical chime |
| `demolish`          | Building demolished           | `building_demolished`        | Collapse / debris |
| `trade_buy`         | Market purchase               | `market_trade_completed` (buy)  | Coins out / cash register |
| `trade_sell`        | Market sale                   | `market_trade_completed` (sell) | Coins in / cha-ching |
| `unlock`            | New resource unlocked         | `resource_unlocked`          | Bright reveal shimmer |
| `era_up`            | Era advances                  | `era_advanced`               | Rising brass sting |
| `milestone`         | Milestone achieved            | `milestone_completed`        | Positive stamp/ding |
| `event_danger`      | Danger event (storm, raid…)   | `random_event_started` (danger)  | Alarm / low horn |
| `event_positive`    | Good event (festival, caravan)| `random_event_started` (positive)| Warm bell |
| `process_done`      | Manual process finishes       | `process_completed`          | Short mechanical clack |
| `mining_done`       | Mining action finishes        | `mining_completed`           | Pickaxe / ore drop |
| `unit_ready`        | Unit finishes training        | `unit_trained`               | Military whistle |
| `ui_click`          | (reserved for UI buttons)     | call `AudioManager.play_sfx("ui_click")` | Soft click |
| `insufficient`      | Not enough resources          | `resources_insufficient`     | Denied buzz |

---

## Where to get these (free, commercial-use safe)

See `assets/CREDITS.md` for the license policy. Recommended CC0 (no attribution)
starting points that cover most of the above:

- **Kenney** — https://kenney.nl/assets?q=audio (UI, impacts, jingles) — **CC0**
- **OpenGameArt** — https://opengameart.org/content/cc0-music-0 (era tracks) — **CC0**
- **Pixabay / BigSoundBank** — Foley: steam, gears, saws, coins — **CC0**
- **Incompetech (Kevin MacLeod)** — orchestral era tracks — **CC-BY** (must credit)

**Per-file rule:** verify each clip's license individually. Use **CC0** (free) or
**CC-BY** (credit required in `CREDITS.md`). Avoid **CC-BY-NC** (no commercial use).

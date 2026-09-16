# Combat

Everything that puts units on an 8x8 board: the pure models in `scripts/combat/`,
the `CombatManager` service that publishes them, and the screens that read them.

This document describes **the code as it stands**, not the specification. Where a
piece is specified but not wired, it says so.

> Number note: `docs/14-guia-de-juego.md` (Spanish, player-facing) already holds
> number 14, so the technical combat document is 15.

---

## Contents

1. [The three layers](#1-the-three-layers)
2. [The three roads to the same board](#2-the-three-roads-to-the-same-board)
3. [The board](#3-the-board)
4. [The expedition](#4-the-expedition)
5. [The auto-resolved defence](#5-the-auto-resolved-defence)
6. [The Final Audit](#6-the-final-audit)
7. [Signals](#7-signals)
8. [Balance](#8-balance)
9. [Testing](#9-testing)
10. [Known gaps](#10-known-gaps)

---

## 1. The three layers

The rule that holds the whole pillar together: **the models never emit**. Every
mutating method on a model returns an `Array` of plain event dictionaries. A
service drains that array and republishes it on the `EventBus`. The interface
only reads and calls.

```
scripts/combat/*.gd   → Array[Dictionary]   (pure, headless, deterministic)
        ↓
CombatManager / ProgressionManager  → EventBus.<signal>.emit(...)
        ↓
BattleScreen / SkirmishPanel / AudioManager / StormManager  (read-only)
```

### Layer 1 — pure models (`scripts/combat/`)

All `RefCounted`. No nodes, no timers, no `EventBus`, no global `randf()`.

| File | Class | What it owns |
|------|-------|--------------|
| `CombatUnit.gd` | `CombatUnit` | One unit: hp, position, side, draft bonuses, morale modifiers. Derived stats (`attack_power`, `defense`, `move_range`, `initiative`) read `GameConfig.combat_unit_stats` and apply bonuses on top — the stored stats are never mutated |
| `CombatRules.gd` | `CombatRules` | Static maths: damage, morale modifiers, Manhattan range, BFS reachability, turn order, timeout resolution, encounter rewards, morale delta |
| `Encounter.gd` | `Encounter` | One board: units, deploy zones, turn order, rounds, win/lose/timeout |
| `CombatAI.gd` | `CombatAI` | Plans one unit's turn. Pure: reads an `Encounter`, returns a list of steps, mutates nothing |
| `AutoResolver.gd` | `AutoResolver` | Plays a whole `Encounter` with `CombatAI` on **both** sides, returns the accumulated events |
| `Expedition.gd` | `Expedition` | One roguelike run: map, party, loot, current node, state |
| `ExpeditionGenerator.gd` | `ExpeditionGenerator` | Static and seeded: map graph, enemy rosters, rewards, draft options |
| `FinalAudit.gd` | `FinalAudit` | The closing siege: waves, garrison, summons counter |

Event dictionaries always carry an `"e"` key naming the event. The ones the models
produce:

| `e` | Payload | Produced by |
|-----|---------|-------------|
| `turn_started` | `side`, `uid` | `Encounter._advance()` |
| `unit_moved` | `uid`, `from`, `to` | `Encounter.move_unit()` |
| `unit_attacked` | `attacker`, `target`, `damage` | `Encounter.attack()` |
| `unit_died` | `uid`, `side` | `Encounter.attack()` |
| `unit_defended` | `uid` | `Encounter.defend()` |
| `encounter_ended` | `victory`, `rounds` | `Encounter._finish()` / `_resolve_timeout()` |
| `node_cleared` | `index`, `is_boss` | `Expedition.mark_cleared()` |
| `expedition_node_selected` | `index` | `Expedition.select_node()` |
| `draft_applied` | `option` | `Expedition.apply_draft()` |
| `expedition_ended` | `result` | `Expedition.mark_cleared/mark_defeated/abandon()` |
| `final_audit_summoned` | `waves`, `summons` | `ProgressionManager.summon_final_audit()` / `FinalAudit.resummon()` |
| `final_audit_started` | `waves`, `summons` | `FinalAudit.begin()` |
| `final_audit_wave_cleared` | `wave`, `remaining` | `FinalAudit.clear_wave()` |
| `final_audit_won` | `waves`, `summons` | `FinalAudit.clear_wave()` |
| `final_audit_lost` | `wave` | `FinalAudit.lose()` / `clear_wave()` |

### Layer 2 — the services

| Service | File | Owns |
|---------|------|------|
| `CombatManager` (autoload) | `scripts/services/CombatManager.gd` | The active `Encounter` and the active `Expedition`. The only thing that mutates combat state, drives the enemy turn, applies consequences to the base, and saves/loads the expedition |
| `ProgressionManager` (autoload) | `scripts/services/ProgressionManager.gd` | The `FinalAudit`. It publishes the siege's events; `FinalAudit` itself never emits |

`CombatManager._emit_events()` and `_publish_expedition_events()` are the two
translation tables from model events to `EventBus` signals.
`ProgressionManager._publish_audit()` is the third.

**Ordering that matters:** `encounter_ended` is emitted *after* `_apply_result()`
has already paid out, so any listener reading `CombatManager.get_last_result()`
sees it settled. The expedition follow-ups (draft offered, run ended) are held in
`_expedition_followups` and published *after* `encounter_ended`, so the UI always
sees the board close before it hears what comes next.

### Layer 3 — the interface

> **Note for whoever integrates this.** The interface layer was still landing when
> this document was written. `BattleScreen` and `SkirmishPanel` exist and work for
> the boards described below, but nothing in `scripts/ui/` calls
> `launch_expedition()`, `select_node()`, `apply_draft()` or `abandon_expedition()`
> yet, and no panel listens to `draft_offered`, `expedition_node_selected`,
> `expedition_resumed` or `defense_auto_resolved`. Re-check this section against
> the code before trusting it.

| Script | Role |
|--------|------|
| `scripts/ui/BattleScreen.gd` | The board. `CanvasLayer` at `layer = 18`, deliberately kept out of `UIManager`'s window stack so ESC cannot dismiss a fight. Opens on `encounter_started`, redraws on every combat signal, routes every click back through `CombatManager`. Its close button calls `CombatManager.end_encounter()` — which is what advances the Final Audit to the next wave |
| `scripts/ui/SkirmishPanel.gd` | Troop commitment before a board opens, plus the "QUE BAJEN" button that begins or re-summons the Final Audit. Its launch button calls `CombatManager.start_skirmish()` |
| `scripts/services/AudioManager.gd` | SFX on `encounter_started`, `unit_attacked`, `unit_died`, `encounter_ended`, `expedition_started`, `expedition_ended`, `storm_halted_forever` |
| `scripts/ui/HelperPanel.gd` | One callout pointing at the Escaramuzas button once a Barracks exists |
| `scripts/services/TutorialManager.gd` | A one-shot contextual tip on `encounter_started` |

---

## 2. The three roads to the same board

Three different situations build an `Encounter`. The board, the rules and the AI
are identical in all three; what differs is who composes the player's side, who
pays, and what losing costs.

| | Skirmish / expedition node | Tithe defence | Final Audit wave |
|---|---|---|---|
| Entry point | `CombatManager.start_skirmish()` · `enter_current_node()` | `CombatManager.start_defense()` | `EventBus.final_audit_wave_ready` → `CombatManager._on_final_audit_wave_ready()` |
| Who composes the player's side | The player, in `SkirmishPanel` (skirmish); `Expedition.party` (node) | `get_garrison()`: everything trained and **at home**, capped at `combat_deploy_cap` | `FinalAudit.living_garrison()`, carried wave to wave with its damage |
| Tower crews | No | Yes — `get_tower_crews()`, outside the deploy cap, back row | Yes, and crews lost in earlier waves are **not** replaced (`_audit_crew_losses`) |
| `Encounter.is_defense` | `false` | `true` | `true` |
| Deployment rows | Enemy on row 1 then 0 | Enemy on row 0 then 1 (one extra round of approach for the defender) | Same as the Tithe defence |
| Loot on a win | Yes, `CombatRules.encounter_rewards(era)` — banked immediately for a skirmish, accumulated in the model for an expedition node | **None.** The reward is that the Tithe goes uncollected | None |
| Casualties | Struck off `ArmyManager` (at once for a skirmish, at the end of the run for an expedition) | Struck off `ArmyManager`; tower crews never are | Struck off `ArmyManager`; tower crews never are |
| Morale swing | `CombatRules.morale_delta()` | `CombatRules.morale_delta()` | `CombatRules.morale_delta()` |
| What losing costs | The dead, and the run | The Tithe is collected (`StormManager._pay_tithe()`) | The siege is lost: maximum-severity Tithe and maximum storm damage (`StormManager._on_final_audit_lost()`), but no game over |

Tower crews are marked by uid in `CombatManager._tower_crew_uids` and filtered out
of the casualty and survivor counts by `_roster_only()`. They fight for the player
but never touch the `ArmyManager` ledger — otherwise a lost defence would delete
artillery the player never trained.

---

## 3. The board

`GameConfig.combat_board_size` is `Vector2i(8, 8)`; `combat_deploy_cap` is 6 per
side. Both are read by `Encounter.create()`.

### Deployment (`Encounter._deploy()`)

- The player always holds the bottom two rows; the enemy the top two.
- Each side fills its **front** row first and centres it, so a squad opens as a
  line facing the enemy rather than a zigzag.
- `back_row_uids` (today: tower crews) take the rear row **before** the line
  forms. They are artillery with `min_range` 2 — in front they go mute the moment
  anything reaches contact.

### Turn flow

1. `start()` → `_begin_round()`: every living unit gets `begin_turn()` (clears
   `has_acted`, `moved_this_turn`, `defending`), then `CombatRules.build_turn_order()`
   sorts by initiative descending. Ties go to the player, then to the lower uid —
   the order is stable and observable.
2. `_advance()` walks to the next unit that can still act, setting `state` to
   `PLAYER_TURN` or `ENEMY_TURN` and emitting `turn_started`.
3. When the order is spent the round number rises. Past `combat_turn_limit`
   (20 rounds) the encounter is force-resolved.

### Actions

| Method | Ends the turn? | Notes |
|--------|----------------|-------|
| `move_unit(uid, to)` | **No** | A unit may move then attack, never move twice. Occupied cells block the BFS, so units cannot walk through each other |
| `attack(uid, target)` | Yes | Damage is `maxi(1, attacker.attack_power() - target.defense())` — deterministic on purpose, and never zero so a fight cannot stall |
| `defend(uid)` | Yes | Doubles `defense()` until the unit's next `begin_turn()` |
| `wait_unit(uid)` | Yes | |
| `end_turn()` | Yes | Closes whoever is active |

`in_attack_range()` uses Manhattan distance and enforces both `min_range` and
`range`. Artillery (`min_range` 2) cannot fire at an adjacent target: that single
rule is what makes positioning matter.

### Resolution

- Enemy side wiped → `WON`. Player side wiped → `LOST`.
- Round limit passed → `TIMEOUT`, decided by `CombatRules.resolve_timeout()`:
  the side with more total HP takes it, **and a tie is a player loss**. Stalling is
  a losing strategy by design.

### Enemy turns

`CombatManager._run_enemy_turn()` asks `CombatAI.plan_turn()` for a list of steps
and executes them with `GameConfig.get_combat_ai_step_delay()` seconds between
each (halved in dev mode), so the player can follow what hit them. It closes the
unit's turn afterwards if the plan did not.

`CombatAI` is deliberately simple: score every reachable cell (a cell that lets
the unit shoot this turn is worth `SCORE_CAN_ATTACK` = 1000 more than any amount
of walking), move there, focus the lowest-HP target in range, break ties toward
the higher-`power` unit, and entrench (`defend`) when nothing is reachable. It
takes `rival_side(unit.side)`, so the same AI drives the enemy on the board and
either side under `AutoResolver`.

---

## 4. The expedition

One roguelike run: march out with a committed party, fight a chain of encounters
across a branching map, and settle up only when the column comes home.

> Everything in this section is implemented and tested at the service level
> (`tests/combat/test_expedition_wiring.gd`). **No screen drives it yet** — see the
> note in §1.

### The map is a seed

`ExpeditionGenerator.generate_map()` builds a layered graph from a single
`RandomNumberGenerator`:

- Depth 0 is always a single, low-risk opening node.
- `combat_map_depth` layers of `combat_map_branching` nodes each follow.
- The boss is the last layer, always alone, always risk 2.
- Edges only run from one layer to the next. Two passes — every parent gets exits,
  then every unadopted child gets a parent — guarantee the invariant that
  **every node reaches the boss**, with no repair pass. `every_node_reaches_boss()`
  exposes it for tests.
- Risk is rolled at 45% / 37% / 18% for low / medium / high, so high risk reads as
  a choice the player made, not the map's default mood.
- Rosters are assigned last, in index order, so the RNG stream stays stable if the
  linking code changes.

`Array.shuffle()` is banned here — it reaches for the global generator.
`_shuffled()` is a Fisher-Yates against the expedition's own RNG.

### Nodes and rosters

`enemy_pressure(depth, era, risk)` sums `combat_enemy_scale_per_depth`,
`combat_enemy_scale_per_era` and `combat_risk_enemy_scale`. It drives two things
at once: the number of bodies (`combat_enemy_base_slots * pressure`, clamped to
`combat_deploy_cap`) and the HP/ATK multiplier handed to `CombatUnit.create()`.
The boss multiplies both by `combat_boss_multiplier` and adds one unit of the
highest tier the era fields.

Composition is a line of infantry with guns behind it, plus armour once era 3
allows it and the slot count reaches 4 — enough shape that artillery's minimum
range matters from the first node.

### The draft

After a won non-boss node, `_offer_draft()` puts `combat_draft_options` (3) cards
on the table, rolled from `draft_rng(seed, node_index)` — an independent stream,
so drafts stay reproducible across a save/load even though the map generator is
not replayed alongside them.

Five catalogue entries: `+atk`, `+def`, `+move`, `+initiative`, and a heal. With
more than one unit type alive, a 40% roll narrows the card to one type and doubles
its value (`combat_draft_focus_multiplier`); healing never doubles. Only
*applicable* options are offered — a field station is not on the table for a party
at full health (`is_applicable()`).

Bonuses live in `CombatUnit.draft_bonuses` and die with the expedition. There is
no meta-progression.

While a draft is pending, `select_node()` and `enter_current_node()` both refuse:
first the card, then the route.

### Attrition, permadeath, lockout

- **Attrition.** `build_encounter_units()` hands the board the *same*
  `CombatUnit` instances that live in `Expedition.party`. The board damages them
  directly, so a survivor walks into the next node wounded. Nothing heals between
  nodes; HP only comes back at the base, and only because the party objects are
  discarded when the run resolves.
- **Permadeath.** A fallen unit stays in `party` as a casualty. `living_party()`
  and `_living()` skip it; a draft never brings anybody back.
- **Lockout.** `get_units_on_expedition()` counts the whole party, living and
  fallen. `get_garrison()` subtracts it, so units on campaign do not defend the
  base, and `get_deployable_units()` subtracts it too. `ArmyManager` is **not**
  debited at launch — Military Power never lies mid-run — the dead are struck off
  only at settlement.

### Settlement

`_resolve_expedition()` runs exactly once, when the model emits `expedition_ended`:

1. Accumulated `rewards` go into `ResourceManager` (the shared pool trims and fires
   `storage_overflow` on its own).
2. `ArmyManager.remove_units(casualties)`.
3. `PopulationManager.adjust_morale(CombatRules.morale_delta(won, dead))` — a
   costly victory can still leave the town worse than it started.
4. `EventBus.expedition_ended.emit(result, rewards, casualties)`.

`result` is `0` won, `1` lost, `2` abandoned. Abandoning (`abandon_expedition()`)
keeps the loot and the survivors: quitting while ahead has to be a real option.

### What is saved and what is regenerated

`CombatManager.get_save_data()` writes `Expedition.to_dict()` plus a
`draft_pending` flag into `data["expedition"]` (see `GameManager`).

| Saved | Regenerated on load |
|-------|---------------------|
| `id`, `seed`, `era`, `current_node`, `state`, `morale_snapshot` | The whole `map` — rebuilt from the seed, then repainted with the saved `cleared` indices |
| `party` (each unit's uid, type, hp, max_hp, draft bonuses, scale) | `morale_attack_mod` / `morale_initiative_bonus` — pure functions of `morale_snapshot` |
| `draft_picks`, `rewards`, `cleared` | The draft cards, from `draft_rng(seed, node)` — the same three cards come back |
| `draft_pending` (service state, not model state) | |

The **encounter in progress is never saved**. On load the party carries its current
HP and the node is still uncleared, so the board is redeployed from scratch.
`load_save_data()` emits `expedition_resumed`; the UI is expected to call
`enter_current_node()`. A save with no `expedition` key simply means no expedition
and is never an error.

`era` is stored on top of the documented schema because the rosters depend on it:
the player can reach a new era while a run is paused.

---

## 5. The auto-resolved defence

When the Tithe lands while the player is already on a board,
`StormManager._begin_tithe()` cannot open a second one. It calls
`CombatManager.auto_resolve_defense()` instead.

**Why it uses the same `Encounter` rather than a formula.** A separate resolution
formula would be a second set of combat rules to keep in sync with the first, and
it would drift: towers, minimum range, deployment rows, the timeout tiebreak and
the morale snapshot would all have to be re-expressed. Instead the defending side
is composed exactly as `start_defense()` composes it (garrison + tower crews, same
morale, same enemy scale), a private `Encounter` is built, and `AutoResolver` plays
it with `CombatAI` on both sides. Same model, same numbers, no second arithmetic.

`AutoResolver.resolve()` is pure and deterministic — neither `Encounter` nor
`CombatAI` rolls dice — so the same board always produces the same result. It has
a step budget (`(turn_limit + 1) * units * 4 + 4`) purely as a hang guard against a
future AI bug; a healthy board never reaches it. If the budget runs out, the
defence counts as lost.

The private encounter is **never** assigned to `_encounter`, so it emits no
`encounter_started` / `turn_started` / `unit_*` / `encounter_ended` — those would be
read by `BattleScreen` as belonging to the board the player is actually looking at.
The single signal for this fight is `defense_auto_resolved(victory, rounds, summary)`.
The result is applied through the same `_apply_result_for()` as a played defence.

Final Audit waves deliberately do **not** take this path: `can_launch()` blocks an
expedition while the Regency is summoned or active, so there is never a board to
dodge — and resolving the endgame blind would take away exactly what makes it the
endgame.

---

## 6. The Final Audit

HQ level 3 no longer wins the game. `ProgressionManager._complete_milestone()`
catches the `hq_max` milestone and calls `summon_final_audit()`.

| Stage | Call | State |
|-------|------|-------|
| Summoned | `summon_final_audit()` | `PENDING` — nobody on the board yet; `SkirmishPanel` offers the button |
| Begun | `begin_final_audit()` | `ACTIVE`; `_announce_wave()` emits `final_audit_wave_ready` |
| Wave on the board | `CombatManager._on_final_audit_wave_ready()` → `start_defense(roster, defenders, scale)` | A normal defensive `Encounter` |
| Wave reported | `CombatManager.end_encounter()` → `ProgressionManager.report_audit_wave(won)` | `clear_wave()` or `lose()` |
| Won | last `clear_wave()` | `WON` → `storm_halted_forever` **then** `victory_achieved` |
| Lost | `lose()` | `LOST` — not a game over |

**The seam.** `ProgressionManager` never calls `CombatManager.start_defense()`. It
emits `final_audit_wave_ready(wave, roster, scale)`; whoever drives the board
listens. Today that listener is `CombatManager._on_final_audit_wave_ready()`. The
report comes back the other way, and deliberately from `end_encounter()` rather
than from the end of the fight — reporting earlier would leave
`is_in_encounter()` still true when the next wave arrives, and the wave would be
lost.

- **Waves:** `final_audit_waves` (3–5), rolled from the siege seed. The seed comes
  from `randi()` and is **not** saved as a re-rollable choice — a lost siege that is
  summoned again is a different night, so reloading cannot shop for an easier one.
- **Attrition across waves.** `build_encounter_units()` hands over
  `living_garrison()` — the same objects, wound by wound. No retraining, no
  reinforcement. That, not the scaling, is the real difficulty curve.
- **Tower crews** are rebuilt each wave from the standing towers, minus every crew
  that has already fallen (`_audit_crew_losses`). A tower does not tire; a dead
  crew is not replaced.
- **Shape.** `wave_slots()` grows from `final_audit_base_slots` by
  `final_audit_slots_per_wave`, capped by `combat_deploy_cap`. Guns appear from
  wave 1, armour from `final_audit_armour_wave`, and the last wave gets an extra
  vehicle. Once bodies stop fitting, `wave_scale()` is the only thing still
  pushing.
- **Losing** costs a maximum-severity Tithe and maximum storm damage
  (`StormManager._on_final_audit_lost()`), but the siege can be re-summoned once
  `final_audit_resummon_min_units` (3) units stand again
  (`can_resummon()` / `resummon()`). `resummon()` rolls a new seed, a new garrison
  and new waves, and increments `summons` — the only record that it happened.
- **Persistence:** `to_dict()` saves seed, era, state, `current_wave`, `summons`,
  `morale_snapshot` and the garrison. The waves themselves are rebuilt from the
  seed and the era, exactly the way `Expedition` rebuilds its map.

Winning emits `storm_halted_forever` **before** `victory_achieved`: the world goes
quiet before the screen says so. `StormManager._on_halted_forever()` sets `_halted`,
disarms the cycle and resets the production multiplier; `StormSky` restores the
sky; `AudioManager` plays the unlock sting.

---

## 7. Signals

Same format as [`10-signals-reference.md`](10-signals-reference.md). These sections
are **not** in that file yet; when you add them there, copy these rows.

### Combat

Emitted only by `CombatManager`. `side`: 0 = player, 1 = enemy.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `expedition_started` | `expedition_id: int, node_count: int` | CombatManager | AudioManager |
| `expedition_node_selected` | `node_index: int` | CombatManager | — *(no listener yet)* |
| `expedition_resumed` | `expedition_id: int` | CombatManager | — *(no listener yet)* |
| `encounter_started` | `encounter_index: int, is_boss: bool` | CombatManager | BattleScreen, SkirmishPanel, AudioManager, TutorialManager |
| `turn_started` | `side: int, unit_uid: int` | CombatManager | BattleScreen |
| `unit_moved` | `unit_uid: int, from: Vector2i, to: Vector2i` | CombatManager | BattleScreen |
| `unit_attacked` | `attacker_uid: int, target_uid: int, damage: int` | CombatManager | BattleScreen, AudioManager |
| `unit_defended` | `unit_uid: int` | CombatManager | BattleScreen |
| `unit_died` | `unit_uid: int, side: int` | CombatManager | BattleScreen, AudioManager |
| `encounter_ended` | `victory: bool, turns_used: int` | CombatManager | BattleScreen, StormManager, AudioManager |
| `draft_offered` | `options: Array` | CombatManager | — *(no listener yet)* |
| `draft_applied` | `option: Dictionary` | CombatManager | — *(no listener yet)* |
| `expedition_ended` | `result: int, rewards: Dictionary, casualties: Dictionary` | CombatManager | AudioManager |
| `defense_auto_resolved` | `victory: bool, rounds: int, summary: Dictionary` | CombatManager | — *(no listener yet; `StormManager` reads the return value of `auto_resolve_defense()` directly)* |

`result` on `expedition_ended`: 0 = victory, 1 = defeat, 2 = abandoned.
`summary` on `defense_auto_resolved` is `CombatManager.get_last_result()`, and that
signal is the **only** one that fight emits — no `encounter_*` accompanies it,
because the open board would claim them.

### The Final Audit

Emitted only by `ProgressionManager`.

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `final_audit_summoned` | `waves: int, summons: int` | ProgressionManager | SkirmishPanel, AudioManager *(optional connect)* |
| `final_audit_started` | `waves: int` | ProgressionManager | SkirmishPanel |
| `final_audit_wave_ready` | `wave: int, roster: Dictionary, scale: float` | ProgressionManager | CombatManager |
| `final_audit_wave_cleared` | `wave: int, remaining: int` | ProgressionManager | — *(no listener yet)* |
| `final_audit_lost` | `wave: int` | ProgressionManager | StormManager, SkirmishPanel |
| `storm_halted_forever` | — | ProgressionManager | StormManager, StormSky, SkirmishPanel, AudioManager |

`victory_achieved(stats)` is still emitted by `ProgressionManager` and consumed by
`VictoryScreen`, but it is now reached **only** through a won Final Audit.

---

## 8. Balance

All of it in `scripts/services/GameConfig.gd`. No magic numbers anywhere in
`scripts/combat/`.

### `combat_*`

| Key | Default | What it does | Turn it up / down |
|-----|---------|--------------|-------------------|
| `combat_board_size` | `(8, 8)` | Board dimensions | Bigger boards mean longer approaches and more value in `move`; the deploy rows are hardcoded as two per side, so a very small board leaves no neutral ground |
| `combat_deploy_cap` | `6` | Max units per side (also caps garrisons and generated rosters) | Higher = longer, busier fights and more that can die at once. It is also the ceiling every roster generator clamps to, so raising it makes the whole game heavier at once |
| `combat_turn_limit` | `20` | Rounds before the HP tiebreak | Lower punishes slow, defensive play harder (a tie is a player loss); higher lets attrition decide instead of the clock |
| `combat_ai_step_delay` | `0.45` s | Pause between enemy actions | Lower is snappier and harder to read; 0 makes the enemy round vanish in a frame. Halved automatically in dev mode |
| `combat_unit_stats` | see below | `hp`/`atk`/`def`/`move`/`range`/`min_range`/`initiative` per unit type | The single most sensitive dial in the pillar. `min_range` is what makes positioning matter — set artillery's to 1 and the board flattens into a brawl |
| `combat_enemy_scale_per_depth` | `0.15` | Pressure added per map layer | Higher makes a deep run steepen fast; it drives both roster size and HP/ATK |
| `combat_enemy_scale_per_era` | `0.25` | Pressure added per era past 1 | Higher keeps late-era fights dangerous; it also scales encounter loot (`encounter_rewards`), so raising it is not purely a tax |
| `combat_boss_multiplier` | `1.8` | Boss stat and reward multiplier | Higher makes the boss a wall rather than a capstone |
| `combat_map_depth` | `(4, 6)` | Layers between start and boss | Longer maps mean more attrition before the boss, which matters more than any stat here |
| `combat_map_branching` | `(2, 3)` | Nodes per layer and exits per node | Wider maps give more route choice and more risk-dodging |
| `combat_draft_options` | `3` | Cards offered after a won node | More options is strictly more power for the player |
| `combat_risk_enemy_scale` | `0.20` | Extra pressure per risk level (0–2) | Raise with `combat_risk_reward_bonus`, or the dangerous road stops being worth taking |
| `combat_risk_reward_bonus` | `0.35` | Extra loot per risk level | The other half of the same bet |
| `combat_enemy_base_slots` | `2` | Roster size at depth 0, era 1, risk 0 | The opening fight's size. Higher makes the first node of every run harsh |
| `combat_draft_values` | `atk 2, def 2, move 1, initiative 2, heal_pct 0.3` | What one pick is worth | A run is 6–8 fights: a pick should tilt a fight, never decide the expedition |
| `combat_draft_focus_multiplier` | `2` | Multiplier when a card targets one unit type | Higher rewards mono-type parties |
| `combat_reward_base` | `{gold 60, wood 30}` | Loot per cleared encounter, before scaling | The whole economic case for going out at all |
| `combat_morale_initiative_bonus` | `2` | Initiative swing across the morale range | At ±2 a demoralised squad can lose the first move entirely; at 0 morale stops touching turn order |
| `combat_morale_attack_range` | `(0.85, 1.15)` | Attack multiplier at 0 and 100 morale | Widen it and the base's mood decides fights; narrow it and the two halves of the game stop talking |
| `combat_morale_on_victory` | `8.0` | Morale gained by a win | |
| `combat_morale_per_casualty` | `3.0` | Morale lost per unit that does not come back | With the default pair, three dead cancel a victory. That is the point: a costly win should be able to leave the town worse off |

Default `combat_unit_stats`:

| Unit | hp | atk | def | move | range | min_range | initiative |
|------|----|-----|-----|------|-------|-----------|------------|
| `infantry` | 30 | 8 | 2 | 3 | 1 | 1 | 5 |
| `artillery` | 22 | 14 | 1 | 1 | 3 | 2 | 3 |
| `vehicle` | 60 | 12 | 5 | 4 | 1 | 1 | 4 |

Morale is captured once, at launch (`_morale_snapshot`), and frozen for the whole
expedition or siege: the battle is fought with the spirit the town had when the
column marched out.

### `final_audit_*`

| Key | Default | What it does | Turn it up / down |
|-----|---------|--------------|-------------------|
| `final_audit_waves` | `(3, 5)` | Waves per siege, rolled from the seed | The single biggest lever on how much army the endgame demands |
| `final_audit_base_slots` | `3` | Bodies in wave 0 | |
| `final_audit_slots_per_wave` | `1` | Bodies added per wave (capped by `combat_deploy_cap`) | Once the cap is hit this does nothing; only `scale_per_wave` still bites |
| `final_audit_scale_per_wave` | `0.22` | HP/ATK multiplier added per wave | The real curve after the board fills |
| `final_audit_scale_per_era` | `0.25` | HP/ATK multiplier added per era past 1 | |
| `final_audit_last_wave_multiplier` | `1.5` | Extra multiplier on the closing wave | It is the end of the game, not one more step |
| `final_audit_artillery_share` | `3` | One gun per N bodies, from wave 1 | Lower = more guns = the garrison gets punished for bunching up |
| `final_audit_armour_wave` | `2` | First wave that can field a vehicle | |
| `final_audit_extra_gun_chance` | `0.35` | The siege's one coin flip | Set to 0 and every siege of the same era looks identical |
| `final_audit_resummon_min_units` | `3` | Living units needed to call the Regency back after a loss | The price of losing: rebuild this much before trying again |

Tower crews are configured on the storm side, not here:
`storm_tower_garrison_unit` (`artillery`), `storm_tower_garrison_per_tower` (1),
`storm_tower_garrison_max` (2), and `GameConfig.get_tower_garrison()`, which caps
the crews so the defender's row never overflows `combat_board_size.x`.

---

## 9. Testing

gdUnit4, headless. Whole suite:

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests
```

Just the combat models:

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/combat
```

| Suite | Covers |
|-------|--------|
| `tests/combat/test_combat_rules.gd` | Damage floor, morale modifiers, Manhattan/range checks, BFS reachability, turn order and its tiebreaks, timeout resolution, rewards, morale delta |
| `tests/combat/test_encounter.gd` | Deployment rows and centring, move-then-attack, blocked cells, defend, win/lose/timeout, `release_survivors()` |
| `tests/combat/test_combat_ai.gd` | The AI attacks when a target is in range, picks the killable one, keeps artillery at stand-off, never idles with a reachable target |
| `tests/combat/test_auto_resolver.gd` | A whole encounter resolved headless, determinism, the step budget, the returned event list |
| `tests/combat/test_expedition_generator.gd` | Map connectivity (every node reaches the boss), seed reproducibility, risk weighting, roster and reward scaling, draft applicability |
| `tests/combat/test_expedition.gd` | Party construction, node selection legality, attrition, permadeath, drafts, abandon, `to_dict`/`from_dict` round-trip |
| `tests/combat/test_expedition_wiring.gd` | `CombatManager`'s side: `can_launch` refusals, launch, chained nodes, draft gating, settlement, save/resume |
| `tests/combat/test_army_casualties.gd` | Casualties reaching `ArmyManager`, and tower crews staying out of it |
| `tests/combat/test_final_audit.gd` | Wave rolling, shape per wave, attrition across waves, loss without game over, resummon floor, persistence |
| `tests/storm/test_defense.gd` | The Tithe defence path through `start_defense()` |
| `tests/storm/test_defense_auto_resolve.gd` | `auto_resolve_defense()` when the board is busy |
| `tests/storm/test_tower_garrison.gd` | Crew count, back-row deployment, crews outside the deploy cap and outside the ledger |
| `tests/storm/test_final_audit_wiring.gd` | `ProgressionManager` ↔ `CombatManager` seam, `storm_halted_forever`, victory ordering |
| `tests/storm/test_storm_toasts_over_board.gd` | Notification toasts draw above `BattleScreen` and below `VictoryScreen` |
| `tests/audio/test_audio_combat.gd` | `AudioManager` connects the combat and audit signals it claims to |
| `tests/ui/test_helper_skirmish_callout.gd` | The Escaramuzas callout appears with the Barracks and only once |

### Probes (`tools/`)

Probes are dev-only `Node` scripts. Each is registered **temporarily** as an
autoload in `project.godot`, the game is run **with a window** (not headless), and
the line is removed afterwards. They all no-op unless `GameConfig.dev_mode` is on.

| Probe | What it does |
|-------|--------------|
| `tools/battle_probe.gd` | Seeds an army, opens the skirmish panel and the board, and screenshots them into `res://docs/media/dev/`. For reviewing the battle screen without playing up to a Barracks |
| `tools/audit_probe.gd` | Summons the Final Audit, plays the whole siege without touching the UI, and logs what happened. `FORCE_SHORT_SIEGE = true` forces a one-wave siege so the victory path (the Storm stopping for good) can be seen without luck. It is the proof that **the game can be finished** |

There is no `expedition_probe.gd` in this tree. The expedition is exercised by
`tests/combat/test_expedition_wiring.gd` instead.

---

## 10. Known gaps

Verified against the code, not the spec. Update this list as things land.

- **No expedition UI.** `launch_expedition()`, `select_node()`, `apply_draft()`,
  `abandon_expedition()` and `enter_current_node()` are implemented, saved, loaded
  and tested, but only tests call them. `SkirmishPanel`'s launch button calls
  `start_skirmish()`, which is the standalone one-off fight. There is no map view
  and no draft modal.
- **Four combat signals have no listener** in `scripts/`: `draft_offered`,
  `draft_applied`, `expedition_node_selected`, `expedition_resumed`. Add the
  consumers along with the UI above. `final_audit_wave_cleared` has none either.
- **`defense_auto_resolved` has no listener.** `StormManager` reads the return value
  of `auto_resolve_defense()` directly and posts its own notification
  (`MSG_DEFENSE_AUTO_WON` / `MSG_DEFENSE_AUTO_LOST`). The signal is there for a
  proper after-action report.
- **`CombatManager.build_enemy_roster()` is provisional.** It is the unseeded
  roster used by `start_skirmish()`; its own docstring says
  `ExpeditionGenerator.enemy_roster()` replaces it. Both exist today.
- **`ArmyPanel` does not show units on campaign.** `CombatManager`'s comment says
  it paints them "en campaña"; `scripts/ui/ArmyPanel.gd` does not reference
  `CombatManager` at all.
- **Unit glyphs on the board are the first letter** of the translated unit name
  (`BattleScreen._unit_glyph()`). Real icons are an art task.
- **Towers have no behaviour of their own** beyond mitigating storm damage and
  fielding a crew on a defensive board. There is no tower attack on the base map.

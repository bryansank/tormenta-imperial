# Random Events System

## Overview

Random events fire at intervals to keep gameplay dynamic. They can be positive, negative, or have timed effects. Managed by `RandomEventManager` (autoload singleton).

## Timing

- Events fire every **2-5 minutes** (random interval)
- In dev mode: every **15-30 seconds**
- Only one timed event can be active at once
- Instant events fire and resolve immediately

## Event Pool (8 events)

### Positive Events

| ID | Name | Weight | Effect |
|----|------|--------|--------|
| `resource_find` | Resource Find | 20 | Gain 30-80 of a random unlocked resource |
| `trade_caravan` | Trade Caravan | 15 | Gain 50-120 gold |
| `morale_boost` | Festival | 15 | +20 morale |
| `good_harvest` | Good Harvest | 18 | Gain 40-80 wood |

### Negative Events

| ID | Name | Weight | Duration | Effect |
|----|------|--------|----------|--------|
| `storm` | Storm | 15 | instant | Lose 20-50 wood |
| `mining_accident` | Mining Accident | 10 | instant | Lose 1 pop, -15 morale |
| `plague` | Plague | 8 | 60s | -25 morale, production x0.5 while active (timed) |
| `bandit_raid` | Bandit Raid | 12 | instant | Lose 30-80 gold, -10 morale |

### Probability

Events use weighted random selection. Total weight = 113.

| Event | Weight | Probability |
|-------|--------|------------|
| Resource Find | 20 | 17.7% |
| Good Harvest | 18 | 15.9% |
| Storm | 15 | 13.3% |
| Trade Caravan | 15 | 13.3% |
| Festival | 15 | 13.3% |
| Bandit Raid | 12 | 10.6% |
| Mining Accident | 10 | 8.8% |
| Plague | 8 | 7.1% |

**Positive events: ~60%** | **Negative events: ~40%**

## Timed Events

Only the Plague is currently timed (60 seconds). During a timed event:
- `_active_event` stores the event data
- `_active_timer` counts down
- When timer hits 0: `_end_active_event()` runs, notification posted
- The Plague's production penalty lives in `GameConfig.random_event_production_multiplier`
  (`plague_production_multiplier = 0.5`). It is a separate variable from the storm's
  `event_production_multiplier`; `GameConfig.get_event_production_multiplier()` multiplies
  the two, so neither can erase the other when it ends.
- The active event (id only), its remaining time and the clock to the next event are
  saved. Loading re-applies the sustained effect (the halved production) but not the
  entry hit (the -25 morale).

## Integration Points

- All events post notifications via `EventBus.notification_posted`
- `EventBus.random_event_started` / `random_event_ended` for external tracking
- Mining accident directly modifies `PopulationManager._population` and calls `_adjust_morale()`
- Resource events use `ResourceManager.add()` / `.spend()`

## Adding New Events

1. Add entry to `_get_event_pool()` array with: id, name, desc, category, color, weight, duration, effect
2. Create `_effect_xxx()` function with the effect logic
3. Add translation keys in `Tr.gd` (both ES and EN)

## Key File

`scripts/services/RandomEventManager.gd`

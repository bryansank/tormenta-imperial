# Tormenta Imperial

**Tormenta Imperial** is a dieselpunk base management + turn-based strategy game built in **Godot 4.6 .NET**. Build an industrial empire on a procedural island, manage population and resources through 3 economic eras, and achieve Imperial Victory.

> "On the mud of history, we shall build monuments of steel."

---

## Game Overview

### Core Loop
1. **Build** production buildings (sawmill, mine, foundry, refinery)
2. **Manage** population (houses provide workers, workers operate buildings)
3. **Trade** resources on the Imperial Market (buy/sell with floating prices)
4. **Progress** through 3 eras by unlocking steel and oil
5. **Survive** random events (storms, plagues, bandit raids)
6. **Win** by building and upgrading Headquarters to Level 3

### What This Game Is NOT
- NOT real-time strategy (RTS). It's a **management/city builder** first
- Combat is **turn-based** (PVE + PVP), planned but not yet implemented
- No real-money transactions — all economy is internal

---

## How to Play

### Controls
| Action | PC | Mobile |
|--------|-----|--------|
| Pan camera | WASD / Arrow keys | Single finger drag |
| Pan (alt) | Middle mouse drag | — |
| Zoom | Scroll wheel | Two-finger pinch |

### Getting Started
1. You start with a **Nucleo** (core building) + 300 gold + 200 wood
2. Build **Houses** to grow your population (workers!)
3. Build a **Sawmill** for wood production, **Gold Mine** for gold
4. Build **Warehouses** when storage gets tight (cap = 800 base)
5. Save up for a **Foundry** (200 gold + 120 wood) to unlock **Era 2: Industrial**
6. Steel unlocks! Now build barracks, towers, and save for a **Refinery**
7. Refinery unlocks **Era 3: Petroleum**
8. Build and upgrade **Headquarters** to Level 3 for **Imperial Victory**

### Tips
- Keep morale high (build decorations!) — it affects production speed
- Don't over-expand without houses. No workers = no production
- Population consumes 1 wood + 1 gold per person every 30 seconds
- Use the market to convert surplus resources into what you need
- Watch for random events — storms can destroy wood, bandits steal gold

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Engine | Godot 4.6 .NET Edition | Game engine (Forward+ renderer) |
| Logic | GDScript | All current systems (services, UI, gameplay) |
| Logic (planned) | C# | Unit AI, combat math, pathfinding |
| Backend (planned) | Supabase | Cloud saves, auth |
| Multiplayer (planned) | Nakama (Docker) | PvP and Co-op turn-based combat |

---

## Architecture

See [CLAUDE.md](CLAUDE.md) for complete technical documentation including:
- All 13 autoload services and their responsibilities
- Scene tree structure
- Complete building/economy tables
- Code conventions and patterns
- How to add buildings, signals, and tune economy

---

## Development

### Prerequisites
- **Godot 4.6 .NET Edition**
- **.NET SDK 8.0+**

### Running
```bash
# Open project in Godot and press F5
# Or from command line:
godot --path . --editor
```

### Dev Mode
`GameConfig.dev_mode = true` (default) makes all timers 1-2 seconds for fast testing.

### Deleting Save
Delete `user://save_game.json` (on Windows: `%APPDATA%/Godot/app_userdata/Tormenta Imperial/save_game.json`)

---

## License

This project is licensed under the **MIT License**.

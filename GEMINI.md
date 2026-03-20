# GEMINI.md - Tormenta Imperial Project Context

This file provides instructional context for Gemini CLI when working on the **Tormenta Imperial** project.

## Project Overview

**Tormenta Imperial** is a hybrid strategy game that combines real-time strategy (RTS) combat with a persistent, monumental base-management system. The game features a "Dieselpunk" and "Heroic Realism" aesthetic, where players manage resources, research technologies, and engage in tactical combat.

### Key Features:
- **Heroic Realism / Dieselpunk Aesthetic:** Massively neoclassical architecture ("Monumentalism") contrasted with the "Barro" (mud) of the battlefield.
- **Persistent Base Management (Meta-Game):** Base grows and persists outside of matches. Improvements unlock new frontline units.
- **RTS Combat:** Micro and macro management of units on 2D maps with tactical AI (cover, flanking).
- **Backend Persistence:** Integration with Supabase for user authentication and game state saving.

## Tech Stack (100% Open Source / Free)

- **Game Engine:** [Godot Engine 4.3 .NET Edition](https://godotengine.org/)
- **Programming Languages:**
    - **C#:** Used for performance-critical systems (Unit AI, combat logic, pathfinding).
    - **GDScript:** Used for UI, scene management, and light gameplay glue.
- **Backend:** [Supabase](https://supabase.com/) (PostgreSQL Database, Auth, Edge Functions).
- **Networking (Future):** [Nakama](https://heroiclabs.com/) (Local Docker setup for competitive multiplayer).
- **IDE:** Visual Studio Code with Godot extensions.
- **Art:** Aseprite (Pixel Art), Inkscape (Vector icons).

## Building and Running

1.  **Engine:** Requires **Godot 4.3 .NET Edition**.
2.  **Environment:** Open the root folder in VS Code with the Godot extension.
3.  **Run:** Open the project in Godot and press **F5** (or the Play button).
4.  **Backend Config:** (TODO) Configure Supabase API keys in the project configuration (file to be determined).

## Development Conventions

- **Performance:** Always prioritize **C#** for heavy computations and complex systems (e.g., unit selection logic, navigation agents).
- **UI/Glue:** Use **GDScript** for simple UI scripts and connecting scene components.
- **Organization:**
    - Use `NavigationAgent2D` for unit movement.
    - Implement a grid-based system for building placement.
- **Naming & Style:** Adhere to standard Godot (GDScript) and C# (.NET) naming conventions where applicable.

## Initial Roadmap (Phase 1: Foundations)

- [ ] **Infrastructure:** Setup camera system (Zoom, Pan, Map limits).
- [ ] **Backend:** Initial Supabase integration (Login system).
- [ ] **Combat Basics:** Drag selection box and `NavigationAgent2D` movement.
- [ ] **Assets:** Create "Eagle Imperial" icon and "Light Tank" unit.
- [ ] **Base Building:** Grid-based placement and "Vintage Military" UI.
- [ ] **Persistence:** Cloud-save logic for base state.

## Key Files (Current)

- `readme.md`: Main project documentation and roadmap.
- `CLAUDE.md`: Context for Claude Code.
- `GEMINI.md`: This file.
- `project.godot`: (TODO: Create once the Godot project is initialized).

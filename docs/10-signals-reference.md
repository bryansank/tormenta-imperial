# EventBus Signals Reference

All inter-system communication flows through `EventBus` (`scripts/services/EventBus.gd`). Systems emit signals; others subscribe. No direct references between services.

## Camera

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `camera_pan_requested` | `direction: Vector2` | InputService | MonumentalCamera |
| `camera_zoom_requested` | `amount: float` | InputService | MonumentalCamera |
| `camera_drag_moved` | `delta: Vector2` | InputService | MonumentalCamera |
| `camera_drag_world_requested` | `delta: Vector2` (world XZ) | BuildingPlacer (left-drag grab-pan) | MonumentalCamera |
| `camera_rotate_requested` | `amount: float` | InputService | MonumentalCamera |
| `camera_rotate_step_requested` | `degrees: float` | OnScreenControls | MonumentalCamera |

## Resources

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `resource_changed` | `resource_type: String, new_amount: int, delta: int` | ResourceManager | ResourceHUD, PopulationManager |
| `resources_insufficient` | `resource_type: String, required: int, available: int` | ResourceManager, MarketManager | ResourceHUD |

## Buildings

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_selected_for_placement` | `building_data: Resource` | ConstructionMenu | BuildingPlacer, BuildingInfoPanel |
| `building_placement_cancelled` | — | (reserved) | BuildingPlacer |
| `building_placed` | `building_data: Resource, cell: Vector2i` | BuildingPlacer | ProductionManager, GameManager, ProgressionManager, PopulationManager |
| `building_moved` | `from_cell: Vector2i, to_cell: Vector2i` | BuildingPlacer | GameManager |
| `building_removed` | `cell: Vector2i` | (reserved) | — |

## Selection

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_clicked` | `building_node: Node3D, building_data: Resource` | BuildingPlacer | BuildingInfoPanel |
| `building_deselected` | — | BuildingPlacer | BuildingInfoPanel |
| `deposit_clicked` | `deposit_node: Node3D, deposit_id: String, cell: Vector2i` | BuildingPlacer | BuildingInfoPanel |
| `request_move_building` | `building_node: Node3D` | BuildingInfoPanel | BuildingPlacer |
| `building_renamed` | `building_node: Node3D, new_name: String` | BuildingInfoPanel | GameManager |

## Processes & Mining

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `process_started` | `building_node: Node3D, process_id: String` | ProcessManager | BuildingInfoPanel |
| `process_completed` | `building_node: Node3D, process_id: String` | ProcessManager | BuildingInfoPanel |
| `mining_started` | `deposit_node: Node3D, deposit_id: String` | ProcessManager | — |
| `mining_completed` | `deposit_node: Node3D, deposit_id: String` | ProcessManager | MapGenerator, BuildingInfoPanel |

## Construction

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `construction_started` | `building_node: Node3D` | ProductionManager | — |
| `construction_completed` | `building_node: Node3D` | ProductionManager | BuildingInfoPanel, ProgressionManager, PopulationManager |

## Production

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `production_tick` | `building_node: Node3D` | ProductionManager | — |

## Upgrades

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `building_upgrade_started` | `building_node: Node3D, new_level: int` | ProductionManager | — |
| `building_upgrade_completed` | `building_node: Node3D, new_level: int` | ProductionManager | BuildingInfoPanel, ProgressionManager, PopulationManager |

## Demolish

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `request_demolish_building` | `building_node: Node3D` | BuildingInfoPanel | BuildingPlacer |
| `building_demolished` | `building_node: Node3D, cell: Vector2i` | BuildingPlacer | GameManager, PopulationManager |

## Deposits

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `deposit_depleted` | `deposit_node: Node3D, deposit_id: String` | MapGenerator | BuildingInfoPanel, GameManager |

## Ground Interaction (reserved for future terrain interaction)

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `ground_clicked` | `world_pos: Vector3, cell: Vector2i` | (reserved) | — |
| `ground_hover` | `world_pos: Vector3, cell: Vector2i` | (reserved) | — |

## Market

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `market_prices_updated` | `prices: Dictionary` | MarketManager | MarketPanel |
| `market_trade_completed` | `resource: String, amount: int, is_buy: bool, total_price: int` | MarketManager | ProgressionManager, MarketPanel |

## Progression

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `resource_unlocked` | `resource_name: String` | ResourceManager | ResourceHUD, ConstructionMenu, MarketPanel |
| `era_advanced` | `new_era: int` | ProgressionManager | ProgressPanel |
| `milestone_completed` | `milestone_id: String` | ProgressionManager | ProgressPanel |
| `victory_achieved` | `stats: Dictionary` | ProgressionManager | VictoryScreen |

## Population & Morale

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `population_changed` | `current: int, max_pop: int` | PopulationManager | NotificationPanel |
| `workers_changed` | `used: int, total: int` | PopulationManager | NotificationPanel |
| `morale_changed` | `new_morale: int` | PopulationManager | NotificationPanel |
| `consumption_failed` | `resource: String` | PopulationManager | — |

## Random Events

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `random_event_started` | `event_id: String, event_data: Dictionary` | RandomEventManager | — |
| `random_event_ended` | `event_id: String` | RandomEventManager | — |

## Notifications

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `notification_posted` | `message: String, category: String, color: Color` | PopulationManager, RandomEventManager, any system | NotificationPanel |

## Persistence

| Signal | Params | Emitted By | Consumed By |
|--------|--------|------------|-------------|
| `game_new_started` | — | GameManager | — |
| `game_load_completed` | — | GameManager | — |

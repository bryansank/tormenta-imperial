# Imperial Market

## Overview

The market allows buying and selling wood, steel, and oil using gold as currency. Prices float based on supply/demand with mean reversion.

## How It Works

- **Gold is the currency** — you can only buy/sell the other 3 resources
- **Buy price > Sell price** (30% spread prevents instant arbitrage)
- **Buying raises the price**, selling lowers it
- **Prices drift back toward base** over time (mean reversion)
- Only unlocked resources appear in the market UI

## Price Mechanics

### Base Prices (gold per unit)

| Resource | Base Price |
|----------|-----------|
| Wood | 3 |
| Steel | 8 |
| Oil | 12 |

### Price Calculation

```
buy_price = ceil(base * price_modifier * (1 + spread/2))
sell_price = floor(base * price_modifier * (1 - spread/2))
```

Where:
- `price_modifier` starts at 1.0, ranges from 0.5 to 2.5
- `spread` = 0.3 (30%)

### Example (Wood, modifier=1.0)

- Buy: ceil(3 * 1.0 * 1.15) = 4 gold/unit
- Sell: floor(3 * 1.0 * 0.85) = 2 gold/unit

### Price Movement

When player **buys** N units: `modifier += N * sensitivity` (price goes up)
When player **sells** N units: `modifier -= N * sensitivity` (price goes down)

`sensitivity` = 0.02 (2% per unit)

### Mean Reversion

Every market tick (60s, or 10s in dev mode):
1. Add random volatility: `modifier += random(-0.015, +0.015)`
2. Revert toward 1.0: `modifier = lerp(modifier, 1.0, 0.05)`

## Configuration (GameConfig.gd)

| Variable | Default | Purpose |
|----------|---------|---------|
| `market_base_prices` | {wood:3, steel:8, oil:12} | Base gold-per-unit |
| `market_spread` | 0.3 | Buy/sell gap (30%) |
| `market_volatility` | 0.15 | Max random swing per tick |
| `market_tick_interval` | 60.0 | Seconds between price updates |
| `market_price_sensitivity` | 0.02 | Price shift per traded unit |
| `market_min_price_mult` | 0.5 | Minimum price modifier |
| `market_max_price_mult` | 2.5 | Maximum price modifier |
| `market_mean_reversion` | 0.05 | Reversion speed toward 1.0 |

## UI (MarketPanel)

- Button "MERCADO" in top-right corner
- Shows: resource name, buy price, sell price, amount selector (+/- 5), buy/sell buttons
- Gold display at bottom
- Only shows unlocked resources
- Rebuilds when a resource is unlocked

## Milestone Integration

Completing 10 trades triggers the "Merchant" milestone.

## Key Files

- `scripts/services/MarketManager.gd` — price calculation, trading logic
- `scripts/ui/MarketPanel.gd` — market UI
- `scripts/services/GameConfig.gd` — market configuration values

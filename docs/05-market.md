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

## Mercado dinámico (solo Gobernador)

En el nivel **Gobernador** de la Campaña (`GameMode.market_dynamic()`, docs/20) la
"media" a la que vuelven los precios deja de ser 1.0: la marca un **calendario
fijo de la Tormenta** (`GameConfig.market_calendar`). El patrón es siempre el mismo,
para que se pueda aprender y jugar con él (comprar madera en la calma, vender acero
antes de la Tormenta...). En **Colono** el mercado es exactamente el de arriba.

| Estación (`MarketManager.season()`) | Cuándo | Objetivo del precio |
|---|---|---|
| `warning` | Aviso y Ceniza | madera **+30 %** |
| `storm` | Tormenta | acero **−25 %** |
| `after_tithe` | Diezmo y los **120 s** siguientes (`market_after_tithe_seconds`) | el oro vale menos: madera, acero y petróleo **+15 %** |
| `calm` | el resto | vuelta a la media (1.0) |

- Cada tick (cada **15 s** en Gobernador, `market_dynamic_tick_interval`; 3 s en
  dev_mode) el modificador se acerca a su objetivo un **35 %**
  (`market_calendar_pull`), además de la volatilidad de siempre. Un Aviso de 45 s
  ya lleva la madera a ~+22 %; la Tormenta (60 s) deja el acero en ~−20 %.
- Comprar y vender siguen moviendo el precio igual (`market_price_sensitivity`).
- "Tras el Diezmo" lleva su propio reloj (`_after_tithe_left`), que **se guarda**
  (`market.after_tithe_left`; un guardado viejo sin la clave = 0) y `reset()` tira.
- La tendencia (`get_price_trend`) en Gobernador dice **hacia dónde va** el precio
  (objetivo frente a ahora, con zona muerta `market_trend_deadband` = 0.02); en
  Colono sigue diciendo si está caro o barato.

**Panel (solo Gobernador):** una línea con la estación ("Aviso de Tormenta: la
madera sube."), y por recurso, además de compra y venta, el **margen** (spread =
compra − venta, `MarketManager.get_spread()`) y una **flecha de tendencia**
dibujada (triángulo rojo arriba = sube, verde abajo = baja, barra = estable; no es
un carácter porque las fuentes no garantizan ▲▼ en Android). Se refresca con el
tick del mercado, con cada cambio de fase de la Tormenta y con el Diezmo.

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
| `market_calendar` | ver arriba | Gobernador: desplazamiento del precio por estación de la Tormenta |
| `market_calendar_pull` | 0.35 | Gobernador: cuánto se acerca al objetivo por tick |
| `market_dynamic_tick_interval` | 15.0 | Gobernador: segundos entre ticks |
| `market_after_tithe_seconds` | 120.0 | Gobernador: duración de "tras el Diezmo" |
| `market_trend_deadband` | 0.02 | Gobernador: por debajo, la flecha dice "estable" |

## UI (MarketPanel)

- Opened by tapping a **Market** building → ABRIR MERCADO (`BuildingInfoPanel.SCREENS`,
  2026-09-28; disabled while the Market has no road). It used to be an entry of
  ☰ MENÚ → COLONIA; that entry is gone. The Market (2x2, 100 gold + 60 wood, 1
  worker, max 1) needs a Gold Mine, and prices only tick from the ECONOMY phase
  (first Gold Mine)
- ¿QUÉ HACER? does not suggest buying or selling while there is no Market
- Shows: resource name, buy price, sell price, amount selector (+/- 5), buy/sell buttons
- Gold display at bottom
- Only shows unlocked resources
- Rebuilds when a resource is unlocked

## Milestone Integration

Completing 10 trades triggers the "Merchant" milestone — which now needs a Market
building first.

## Key Files

- `scripts/services/MarketManager.gd` — price calculation, trading logic
- `scripts/ui/MarketPanel.gd` — market UI
- `scripts/services/GameConfig.gd` — market configuration values

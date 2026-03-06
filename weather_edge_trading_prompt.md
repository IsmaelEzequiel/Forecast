# Weather Forecast Trading System — Prompt Arquitetural

## Contexto para o agente de código

You are a senior quantitative engineer and Elixir architect. Build a **weather forecast trading system** for Polymarket temperature markets using Elixir/Phoenix LiveView.

---

## 1. Product Overview

### What is this?

A system that **automatically detects and buys underpriced temperature forecast positions** on Polymarket the moment they are created, then helps the user decide whether to hold or sell for profit.

### How the opportunity works

Every day at **6:01 AM ET**, Polymarket creates a new temperature event for **3 days ahead** (e.g., on March 6 it creates the March 9 event). Each event has multiple markets — one per temperature degree (26°C, 27°C, 28°C, etc.), each with YES/NO shares.

**The edge:** When the event first opens, prices are low and inefficient (YES shares at $0.10–$0.20). A trader who immediately checks the weather forecast, identifies the most likely temperature, and buys YES at <$0.20 can profit in two ways:

1. **Price appreciation:** As more traders discover the event and forecasts converge, the YES price for the likely temperature rises from ~$0.15–$0.20 to $0.35–$0.60+ over the next 1–2 days. The user can **sell before resolution** and lock in profit regardless of the actual outcome.

2. **Resolution win:** If the user holds until the event resolves and the temperature matches, the YES share pays out $1.00 (bought at $0.15 = +566% return).

### What the system does

1. **Monitors Polymarket** every minute around 6:01 AM ET for new temperature events
2. **Fetches weather forecasts** from multiple models for the event's station/date
3. **Auto-buys** the most likely temperature outcome at YES price ≤ configured threshold (e.g., $0.20)
4. **Tracks positions** and shows real-time P&L on a LiveView dashboard
5. **Detects mispricing** throughout the day by comparing forecast probabilities vs market prices
6. **Alerts the user** to sell/hold decisions with data-driven recommendations

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Phoenix LiveView                      │
│              (Dashboard + Position Manager)               │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ Stations │  │ Positions│  │  Signals │              │
│  │ Context  │  │ Context  │  │  Context │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │              │              │                    │
├───────┼──────────────┼──────────────┼────────────────────┤
│                    Oban Workers                           │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────┐    │
│  │ EventScanner│ │ForecastFetch │ │MispricingDetect│    │
│  │ (every 1min │ │(every 15min) │ │ (every 5min)   │    │
│  │  6:00-6:15) │ │              │ │                │    │
│  └──────┬──────┘ └──────┬───────┘ └───────┬────────┘    │
│         │               │                 │              │
│  ┌──────┴──────┐ ┌──────┴───────┐ ┌──────┴────────┐    │
│  │  AutoBuyer  │ │ Probability  │ │  Signal Gen   │    │
│  │  Worker     │ │ Engine       │ │               │    │
│  └─────────────┘ └──────────────┘ └───────────────┘    │
│                                                          │
├─────────────────────────────────────────────────────────┤
│                  External APIs                           │
│  ┌────────────┐ ┌─────────────┐ ┌──────────────────┐   │
│  │ Polymarket │ │  Open-Meteo  │ │ Aviation Weather │   │
│  │ Gamma+CLOB │ │ Multi-model  │ │   METAR data     │   │
│  └────────────┘ └─────────────┘ └──────────────────┘   │
│                                                          │
├─────────────────────────────────────────────────────────┤
│            PostgreSQL + TimescaleDB                      │
└─────────────────────────────────────────────────────────┘
```

### Tech Stack

- **Backend:** Elixir/Phoenix 1.7+
- **Frontend:** Phoenix LiveView (no separate frontend framework)
- **Database:** PostgreSQL with TimescaleDB extension
- **Job Scheduler:** Oban
- **HTTP Client:** Req
- **Trading:** Polymarket py-clob-client equivalent in Elixir (or wrap via Port/NIF)

---

## 3. Data Sources

### 3.1 Polymarket APIs

**Gamma API** (public, no auth) — `https://gamma-api.polymarket.com`

Used for market discovery. Temperature events follow a predictable pattern:

```
GET /events?active=true&closed=false
```

Each temperature event contains:
- `id`, `slug` (e.g., `highest-temperature-in-sao-paulo-on-march-9-2026`)
- `title` (e.g., "Highest temperature in São Paulo on March 9?")
- `markets[]` — array of temperature outcome markets, each with:
  - `question`: "Will the highest temperature in São Paulo be 27°C on March 9?"
  - `outcomes`: `["Yes", "No"]`
  - `outcomePrices`: `["0.15", "0.86"]`
  - `clobTokenIds`: `["TOKEN_YES_ID", "TOKEN_NO_ID"]`
  - Volume, liquidity data

**CLOB API** (public for reads, auth for orders) — `https://clob.polymarket.com`

```
GET /price?token_id=TOKEN_ID&side=buy          # Current price
GET /book?token_id=TOKEN_ID                     # Orderbook depth
POST /order                                      # Place order (requires L2 auth)
```

**Authentication for trading:**
- L1: EIP-712 signature with private key (Polygon wallet)
- L2: HMAC-SHA256 with derived API credentials (apiKey, secret, passphrase)
- The system needs the user's **private key** stored securely (encrypted at rest, environment variable)

**Data API** (public with wallet address) — `https://data-api.polymarket.com`

```
GET /positions?user=WALLET_ADDRESS              # Open positions with current value
GET /activity?user=WALLET_ADDRESS               # Trade history
```

### 3.2 Weather Forecasts

**Primary: Open-Meteo API** (free, no API key, global coverage)

```
GET https://api.open-meteo.com/v1/forecast?latitude=-23.43&longitude=-46.47
    &hourly=temperature_2m&models=gfs,ecmwf_ifs,icon_global,jma,gem_global
    &forecast_days=5
```

Returns hourly temperature forecasts from multiple models. Extract daily maximum temperature from each model's hourly data.

Models to fetch:
- GFS (NOAA, USA)
- ECMWF IFS (European)
- ICON (DWD, Germany)
- JMA (Japan)
- GEM (Canada, CMC)

**Secondary: Aviation Weather METAR** (verification + current conditions)

```
GET https://aviationweather.gov/api/data/metar?ids=SBGR
GET https://aviationweather.gov/api/data/metar?ids=KATL
```

METAR provides current observed conditions at the exact station Polymarket uses for resolution. Useful for:
- Verifying forecasts against current observations on event day
- Confirming resolution temperature matches expectation

### 3.3 Resolution Source

Polymarket resolves temperature markets using **Weather Underground** historical data for a specific ICAO station:

```
https://www.wunderground.com/history/daily/br/guarulhos/SBGR
```

The ICAO code (METAR code) is extracted from the event's resolution rules. This same code is what the user enters to register a station.

---

## 4. Station Management

### 4.1 Station Registry

The user manually adds stations through the dashboard by entering a **METAR/ICAO code** (e.g., `SBGR`, `KATL`, `KMIA`).

For each station, the system stores:

```elixir
%Station{
  code: "SBGR",                    # ICAO code (user input)
  city: "São Paulo",               # Auto-resolved or user input
  latitude: -23.4356,              # Auto-resolved from ICAO database
  longitude: -46.4731,             # Auto-resolved from ICAO database
  country: "BR",
  wunderground_url: "https://www.wunderground.com/history/daily/br/guarulhos/SBGR",
  monitoring_enabled: true,         # Toggle on/off
  auto_buy_enabled: true,           # Toggle on/off (separate from monitoring)
  max_buy_price: 0.20,             # Maximum YES price to auto-buy (user configurable)
  buy_amount_usdc: 5.00,           # Amount in USDC per auto-buy (user configurable)
  slug_pattern: "highest-temperature-in-sao-paulo-on-*",  # Pattern to match Polymarket events
  inserted_at: ~U[2026-03-05 12:00:00Z]
}
```

### 4.2 Station Dashboard Controls

Each station card in the dashboard has:

```
┌──────────────────────────────────────────────────┐
│ 🌡️  SBGR — São Paulo                             │
│                                                    │
│  [● Monitoring ON]  [● Auto-Buy ON]              │
│                                                    │
│  Max Buy Price:  [$0.20 ▼]                        │
│  Buy Amount:     [$5.00  ▼]                       │
│  Balance:        $47.23 USDC                      │
│                                                    │
│  Next event opens: ~6:01 AM ET tomorrow           │
│  Events tracked: Mar 7, Mar 8, Mar 9              │
└──────────────────────────────────────────────────┘
```

### 4.3 Add Station Flow

1. User types ICAO code (e.g., `SBGR`)
2. System validates via Aviation Weather API: `GET /api/data/metar?ids=SBGR`
3. If valid: resolves coordinates, city name, country
4. Creates station record with defaults (monitoring ON, auto-buy OFF until user enables)
5. System searches Polymarket for matching temperature events
6. Renders station card with current events (if any)

---

## 5. Core Workflow: Event Scanner + Auto-Buyer

### 5.1 Event Scanner

**Schedule:** Runs every **1 minute** from **5:55 AM to 6:20 AM ET** daily (Oban cron)

**Logic:**

```
For each station where monitoring_enabled = true:

  1. Query Gamma API for new temperature events matching the station
     GET /events?active=true&closed=false
     Filter by slug pattern or title containing station's city name

  2. Check if event already exists in our database
     If new event found:
       a. Parse event → extract markets, prices, target_date, station_code
       b. Store as MarketCluster in database
       c. Broadcast via PubSub: {:new_event, station_code, event}
       d. If auto_buy_enabled for this station → trigger AutoBuyerWorker
```

### 5.2 Auto-Buyer

**Triggered by:** EventScanner when a new event is detected for a station with `auto_buy_enabled = true`

**Logic:**

```
1. Fetch multi-model weather forecasts for station + target_date
   (Open-Meteo: GFS, ECMWF, ICON, JMA, GEM)

2. Extract daily max temperature from each model

3. Determine the most likely temperature:
   - Build empirical distribution from models
   - Apply Gaussian smoothing (σ based on days out)
   - Pick the outcome with highest probability

4. Find the corresponding market in the event's markets array

5. Check the current YES price for that market:
   GET https://clob.polymarket.com/price?token_id=YES_TOKEN_ID&side=buy

6. If YES price ≤ station.max_buy_price (e.g., ≤ $0.20):
   a. Fetch user's USDC balance
   b. Calculate token amount: station.buy_amount_usdc / yes_price
   c. Place limit order via CLOB API:
      POST /order
      {
        token_id: YES_TOKEN_ID,
        side: "BUY",
        price: current_yes_price,
        size: calculated_tokens,
        type: "GTC"  # Good Till Cancelled
      }
   d. Record the order in database
   e. Broadcast: {:auto_buy_executed, station_code, details}

7. If YES price > max_buy_price:
   - Log: "Price too high ($X.XX > $0.20), skipping auto-buy"
   - Broadcast: {:auto_buy_skipped, station_code, reason}

8. ALSO check if secondary opportunities exist:
   - Any other temperature in the cluster with YES < max_buy_price
     AND model probability > 20%?
   - If yes, flag as opportunity (don't auto-buy, just alert)
```

### 5.3 Safety Guards

```
- Never buy if USDC balance < buy_amount + $2 (keep minimum reserve)
- Never buy if an order for the same event + station already exists
- Maximum 1 auto-buy per event per station
- If CLOB API returns error, retry once after 30 seconds, then alert user
- All orders are logged with timestamps for audit
- Rate limit: max 1 order per 10 seconds per station
```

---

## 6. Mispricing Detection

### 6.1 Continuous Monitoring

**Schedule:** Runs every **5 minutes** for all active events (Oban recurring)

**Logic:**

```
For each active (unresolved) market cluster:

  1. Fetch latest multi-model forecasts from Open-Meteo
  2. Build probability distribution (same engine as auto-buyer)
  3. Fetch current market prices from CLOB API
  4. For each temperature outcome in the cluster:

     model_prob = probability_engine.probability_for(temp)
     market_yes_price = current YES price
     market_no_price = current NO price

     edge_yes = model_prob - market_yes_price
     edge_no = (1 - model_prob) - market_no_price

     Best side = whichever has positive edge

  5. Generate signals:

     | Edge     | Min Liquidity | Alert Level        |
     |----------|---------------|--------------------|
     | ≥ 0.08   | > $20         | OPPORTUNITY (🟡)   |
     | ≥ 0.15   | > $20         | STRONG SIGNAL (🟠) |
     | ≥ 0.25   | any           | EXTREME (🔴)       |

  6. Special case — "Safe NO" detection:
     If model_prob < 0.05 AND market_no_price ≤ 0.92:
       → Signal: "Safe NO at $X.XX — 95%+ probability of profit"
       This is the low-risk strategy: buy NO for temperatures that
       are very unlikely, collect small but near-certain gains.

  7. Structural check:
     Sum all YES prices across the cluster.
     If |sum - 1.0| > 0.05 → flag "STRUCTURAL MISPRICING"

  8. Store all signals in TimescaleDB
  9. Broadcast via PubSub to update dashboard in real-time
```

### 6.2 Position Monitoring (Sell/Hold Recommendations)

For positions the user already holds:

```
For each open position:

  current_price = fetch YES price from CLOB
  buy_price = original purchase price (from database)
  unrealized_pnl = (current_price - buy_price) * tokens
  unrealized_pnl_pct = (current_price - buy_price) / buy_price

  model_prob = current forecast probability for this temperature
  days_until_resolution = target_date - today

  Recommendation logic:

  IF unrealized_pnl_pct ≥ 100% AND model_prob < 0.40:
    → "SELL NOW — Take profit, forecast shifting away" 🔴

  IF unrealized_pnl_pct ≥ 75% AND days_until_resolution ≤ 1:
    → "CONSIDER SELLING — Good profit, resolution tomorrow" 🟠

  IF unrealized_pnl_pct ≥ 50% AND model_prob > 0.50:
    → "HOLD — Forecast still favorable, could win at resolution" 🟢

  IF unrealized_pnl_pct < 20% AND model_prob < 0.20:
    → "CUT LOSS — Sell before it drops further" 🔴

  IF model_prob > 0.60 AND days_until_resolution == 0:
    → "HOLD TO RESOLUTION — Strong chance of $1.00 payout" 🟢

  DEFAULT:
    → "MONITORING — No action needed" ⚪
```

---

## 7. Probability Engine

### 7.1 Multi-Model Ensemble

```elixir
defmodule WeatherEdge.Probability.Engine do
  @doc """
  Given a station and target date, returns a probability distribution
  across all temperature outcomes.
  """

  def compute_distribution(station, target_date) do
    # 1. Fetch forecasts from all models
    forecasts = OpenMeteo.fetch_all_models(station.latitude, station.longitude, target_date)
    # Returns: %{"GFS" => 28.3, "ECMWF" => 27.8, "ICON" => 28.1, "JMA" => 27.5, "GEM" => 28.0}

    # 2. Round to integers (Polymarket uses whole degrees)
    rounded = Enum.map(forecasts, fn {model, temp} -> {model, round(temp)} end)

    # 3. Build empirical distribution
    total = length(rounded)
    counts = Enum.frequencies_by(rounded, fn {_model, temp} -> temp end)
    raw_probs = Map.new(counts, fn {temp, count} -> {temp, count / total} end)

    # 4. Apply Gaussian smoothing
    days_out = Date.diff(target_date, Date.utc_today())
    sigma = gaussian_sigma(days_out)
    smoothed = apply_gaussian_kernel(raw_probs, sigma)

    # 5. Handle edge buckets ("26°C or below", "34°C or higher")
    smoothed_with_tails = collapse_tails(smoothed, lower_bound: 26, upper_bound: 34)

    # 6. Normalize to sum = 1.0
    normalize(smoothed_with_tails)
  end

  defp gaussian_sigma(days_out) do
    case days_out do
      d when d <= 1 -> 0.8
      2 -> 1.2
      _ -> 1.8
    end
  end
end
```

### 7.2 Calibration

After each event resolves:

1. Fetch actual temperature from Weather Underground (resolution source)
2. Compare model predictions vs actual
3. Track per-station, per-model accuracy
4. Adjust Gaussian sigma over time based on historical accuracy
5. Store in `forecast_accuracy` table

---

## 8. LiveView Dashboard

### 8.1 Main Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  WEATHER EDGE                            Balance: $47.23 USDC   │
│  [+ Add Station]  [⚙ Settings]           Wallet: 0x1a2b...3c4d │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─ STATIONS ──────────────────────────────────────────────┐    │
│  │                                                          │    │
│  │  ┌─ SBGR São Paulo ──────────────────────────────────┐  │    │
│  │  │  [● Monitor ON] [● Auto-Buy ON]                   │  │    │
│  │  │  Max: $0.20  |  Amount: $5.00  |  Bal: $47.23     │  │    │
│  │  │                                                     │  │    │
│  │  │  ┌─ Mar 8 (resolves tomorrow) ──────────────────┐  │  │    │
│  │  │  │  My Position: 28°C YES × 33.3 tokens         │  │    │
│  │  │  │  Bought: $0.15  |  Now: $0.42  |  +180% 🟢   │  │    │
│  │  │  │  Forecast: 28°C (72% prob)                    │  │    │
│  │  │  │  → HOLD TO RESOLUTION — strong chance of $1   │  │    │
│  │  │  │  [SELL] [HOLD]                                │  │    │
│  │  │  └──────────────────────────────────────────────┘  │  │    │
│  │  │                                                     │  │    │
│  │  │  ┌─ Mar 9 (in 2 days) ─────────────────────────┐  │  │    │
│  │  │  │  My Position: 27°C YES × 25.0 tokens         │  │    │
│  │  │  │  Bought: $0.20  |  Now: $0.31  |  +55% 🟢    │  │    │
│  │  │  │  Forecast: 27°C (45%), 28°C (35%)             │  │    │
│  │  │  │  → MONITORING — forecast still favorable       │  │    │
│  │  │  │  [SELL] [HOLD]                                │  │    │
│  │  │  └──────────────────────────────────────────────┘  │  │    │
│  │  │                                                     │  │    │
│  │  │  ┌─ Mar 10 (just opened!) ─────────────────────┐  │  │    │
│  │  │  │  ⚡ Auto-bought: 28°C YES × 33.3 @ $0.15    │  │    │
│  │  │  │  Forecast: GFS 28°C, ECMWF 28°C, ICON 27°C  │  │    │
│  │  │  │  Model prob: 28°C = 52%                       │  │    │
│  │  │  └──────────────────────────────────────────────┘  │  │    │
│  │  └────────────────────────────────────────────────────┘  │    │
│  │                                                          │    │
│  │  ┌─ KATL Atlanta ────────────────────────────────────┐  │    │
│  │  │  [● Monitor ON] [○ Auto-Buy OFF]                  │  │    │
│  │  │  ...                                               │  │    │
│  │  └────────────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─ SIGNALS & OPPORTUNITIES ─────────────────────────────────┐  │
│  │  🔴 12:05 SBGR — 30°C NO @ $0.94 — edge +22% — EXTREME  │  │
│  │  🟡 12:05 SBGR — 27°C YES @ $0.24 — edge +9% — OPPORT.  │  │
│  │  🟢 11:50 KATL — 72°F NO @ $0.96 — safe NO — 97% prob   │  │
│  │  ⚡ 06:02 SBGR — Auto-bought 28°C YES × 33.3 @ $0.15    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌─ PORTFOLIO SUMMARY ───────────────────────────────────────┐  │
│  │  Open Positions: 4  |  Total Invested: $23.50              │  │
│  │  Current Value: $38.20  |  Unrealized P&L: +$14.70 (+62%) │  │
│  │  Today's Resolved: +$4.50  |  Total Realized: +$31.20     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Station Card Detail View (expandable)

When user clicks a station card or specific event:

```
┌─ SBGR — São Paulo — March 9, 2026 ──────────────────────────┐
│                                                                │
│  TEMPERATURE DISTRIBUTION                                      │
│  ┌────────────────────────────────────────────────────┐       │
│  │  Bar chart: Model probability (blue) vs Market     │       │
│  │  price (orange) for each temperature degree         │       │
│  │  Highlighted: your position + mispricing edges      │       │
│  └────────────────────────────────────────────────────┘       │
│                                                                │
│  MODEL BREAKDOWN                                               │
│  GFS:   28°C (max: 28.3°C)                                   │
│  ECMWF: 28°C (max: 27.8°C)                                   │
│  ICON:  27°C (max: 27.2°C)                                   │
│  JMA:   28°C (max: 28.1°C)                                   │
│  GEM:   27°C (max: 27.4°C)                                   │
│  → Consensus: 28°C (52%) / 27°C (35%)                        │
│                                                                │
│  MARKET CLUSTER HEALTH                                         │
│  Σ YES prices = 1.03 (⚠️ slight overpricing)                  │
│                                                                │
│  ORDERBOOK (28°C YES)                                          │
│  Best bid: $0.41 × 150 tokens                                │
│  Best ask: $0.43 × 200 tokens                                │
│  Spread: $0.02 (4.7%)                                         │
│                                                                │
│  FORECAST EVOLUTION (last 48h)                                 │
│  ┌────────────────────────────────────────────────────┐       │
│  │  Line chart: how model consensus shifted over time  │       │
│  └────────────────────────────────────────────────────┘       │
│                                                                │
│  METAR CURRENT (SBGR)                                          │
│  Observed: 26°C, Wind 8kt NE, Humidity 72%                   │
│  Last update: 12:00 UTC                                        │
│                                                                │
│  [SELL POSITION]  [BUY MORE]  [← Back]                        │
└────────────────────────────────────────────────────────────────┘
```

### 8.3 LiveView Components

```
dashboard_live.ex
├── header_component.ex          # Balance, wallet, add station
├── station_card_component.ex    # One per station (monitoring controls)
│   └── event_card_component.ex  # One per event (position + forecast)
├── signal_feed_component.ex     # Global alert feed
├── portfolio_summary_component.ex  # Totals bar
├── station_detail_live.ex       # Expanded view with charts
└── add_station_modal_component.ex  # ICAO input + validation
```

Each component subscribes to PubSub topics and updates in real-time:

```elixir
# PubSub topics
"station:#{station_code}:new_event"
"station:#{station_code}:forecast_update"
"station:#{station_code}:price_update"
"station:#{station_code}:auto_buy"
"station:#{station_code}:signal"
"portfolio:balance_update"
"portfolio:position_update"
```

---

## 9. Background Jobs (Oban)

### 9.1 Job Schedule

```elixir
config :weather_edge, Oban,
  queues: [
    scanner: 5,
    forecasts: 3,
    trading: 2,
    signals: 3,
    cleanup: 1
  ],
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      # Event scanner: every minute from 5:55 to 6:20 AM ET
      {"55-59 5 * * *", WeatherEdge.Workers.EventScannerWorker, queue: :scanner},
      {"0-20 6 * * *", WeatherEdge.Workers.EventScannerWorker, queue: :scanner},

      # Forecast refresh: every 15 minutes
      {"*/15 * * * *", WeatherEdge.Workers.ForecastRefreshWorker, queue: :forecasts},

      # Mispricing detection: every 5 minutes
      {"*/5 * * * *", WeatherEdge.Workers.MispricingWorker, queue: :signals},

      # Price snapshot: every 5 minutes (for position tracking)
      {"*/5 * * * *", WeatherEdge.Workers.PriceSnapshotWorker, queue: :signals},

      # Position monitor (sell/hold recommendations): every 10 minutes
      {"*/10 * * * *", WeatherEdge.Workers.PositionMonitorWorker, queue: :signals},

      # Cleanup + resolution: daily at 11 PM ET
      {"0 23 * * *", WeatherEdge.Workers.ResolutionWorker, queue: :cleanup},

      # Balance refresh: every 5 minutes
      {"*/5 * * * *", WeatherEdge.Workers.BalanceWorker, queue: :trading},
    ]}
  ]
```

### 9.2 Worker Descriptions

**EventScannerWorker**
- For each station with `monitoring_enabled = true`
- Queries Gamma API for new temperature events
- If new event found → stores in DB, broadcasts PubSub
- If `auto_buy_enabled` → enqueues AutoBuyerWorker

**AutoBuyerWorker**
- Receives `{station_code, event_id}`
- Fetches forecasts, determines best outcome
- Checks price ≤ max_buy_price
- Checks balance ≥ buy_amount + reserve
- Places order via CLOB API
- Records order + broadcasts

**ForecastRefreshWorker**
- For each station with active (unresolved) events
- Fetches multi-model forecasts from Open-Meteo
- Stores snapshot in TimescaleDB
- Broadcasts forecast updates

**MispricingWorker**
- For each active market cluster
- Runs probability engine vs current prices
- Generates signals with edge calculations
- Broadcasts signals to dashboard

**PriceSnapshotWorker**
- For each tracked market (positions + monitored)
- Fetches current YES/NO prices from CLOB
- Stores in TimescaleDB for historical charts

**PositionMonitorWorker**
- For each open position
- Calculates unrealized P&L
- Generates sell/hold recommendation
- Broadcasts position updates

**BalanceWorker**
- Fetches USDC balance from Data API
- Broadcasts to update dashboard header

**ResolutionWorker**
- Checks which events have resolved
- Fetches actual temperature from Weather Underground
- Updates market clusters as resolved
- Calculates forecast accuracy
- Moves positions to realized P&L

---

## 10. Database Schema

```sql
-- ═══════════════════════════════════════════════════
-- STATION MANAGEMENT
-- ═══════════════════════════════════════════════════

CREATE TABLE stations (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(4) UNIQUE NOT NULL,          -- ICAO/METAR code
  city VARCHAR(100) NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  country VARCHAR(2) NOT NULL,
  wunderground_url TEXT,
  monitoring_enabled BOOLEAN DEFAULT true,
  auto_buy_enabled BOOLEAN DEFAULT false,
  max_buy_price DOUBLE PRECISION DEFAULT 0.20,
  buy_amount_usdc DOUBLE PRECISION DEFAULT 5.00,
  slug_pattern VARCHAR(200),                -- Polymarket slug pattern
  inserted_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════
-- MARKET DATA
-- ═══════════════════════════════════════════════════

CREATE TABLE market_clusters (
  id BIGSERIAL PRIMARY KEY,
  event_id VARCHAR(100) UNIQUE NOT NULL,    -- Polymarket event ID
  event_slug VARCHAR(200) NOT NULL,
  station_code VARCHAR(4) REFERENCES stations(code),
  target_date DATE NOT NULL,
  title VARCHAR(300),
  outcomes JSONB NOT NULL,                  -- Full market cluster data
  resolved BOOLEAN DEFAULT false,
  resolution_temp INTEGER,                  -- Actual temperature after resolution
  inserted_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE market_snapshots (
  id BIGSERIAL,
  market_cluster_id BIGINT NOT NULL REFERENCES market_clusters(id),
  snapshot_at TIMESTAMPTZ NOT NULL,
  outcome_label VARCHAR(30) NOT NULL,       -- '27°C', '28°C', etc.
  yes_price DOUBLE PRECISION,
  no_price DOUBLE PRECISION,
  volume DOUBLE PRECISION,
  PRIMARY KEY (id, snapshot_at)
);
SELECT create_hypertable('market_snapshots', 'snapshot_at');

-- ═══════════════════════════════════════════════════
-- FORECASTS
-- ═══════════════════════════════════════════════════

CREATE TABLE forecast_snapshots (
  id BIGSERIAL,
  station_code VARCHAR(4) NOT NULL REFERENCES stations(code),
  fetched_at TIMESTAMPTZ NOT NULL,
  target_date DATE NOT NULL,
  model VARCHAR(20) NOT NULL,               -- 'GFS', 'ECMWF', etc.
  max_temp_c DOUBLE PRECISION NOT NULL,
  hourly_temps JSONB,
  PRIMARY KEY (id, fetched_at)
);
SELECT create_hypertable('forecast_snapshots', 'fetched_at');

-- ═══════════════════════════════════════════════════
-- TRADING
-- ═══════════════════════════════════════════════════

CREATE TABLE positions (
  id BIGSERIAL PRIMARY KEY,
  station_code VARCHAR(4) NOT NULL REFERENCES stations(code),
  market_cluster_id BIGINT NOT NULL REFERENCES market_clusters(id),
  outcome_label VARCHAR(30) NOT NULL,       -- '28°C'
  side VARCHAR(3) NOT NULL,                 -- 'YES' or 'NO'
  token_id TEXT NOT NULL,                   -- CLOB token ID
  tokens DOUBLE PRECISION NOT NULL,         -- Number of tokens held
  avg_buy_price DOUBLE PRECISION NOT NULL,  -- Average entry price
  total_cost_usdc DOUBLE PRECISION NOT NULL,-- Total USDC spent
  current_price DOUBLE PRECISION,           -- Latest price
  unrealized_pnl DOUBLE PRECISION,          -- Current P&L
  status VARCHAR(20) DEFAULT 'open',        -- 'open', 'sold', 'resolved_win', 'resolved_loss'
  recommendation VARCHAR(50),               -- Latest sell/hold recommendation
  auto_bought BOOLEAN DEFAULT false,        -- Was this an auto-buy?
  opened_at TIMESTAMPTZ DEFAULT NOW(),
  closed_at TIMESTAMPTZ,
  close_price DOUBLE PRECISION,
  realized_pnl DOUBLE PRECISION
);

CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY,
  position_id BIGINT REFERENCES positions(id),
  station_code VARCHAR(4) NOT NULL,
  order_id VARCHAR(100),                    -- Polymarket order ID
  token_id TEXT NOT NULL,
  side VARCHAR(4) NOT NULL,                 -- 'BUY' or 'SELL'
  price DOUBLE PRECISION NOT NULL,
  size DOUBLE PRECISION NOT NULL,           -- Token amount
  usdc_amount DOUBLE PRECISION NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',     -- 'pending', 'filled', 'cancelled', 'failed'
  auto_order BOOLEAN DEFAULT false,
  error_message TEXT,
  placed_at TIMESTAMPTZ DEFAULT NOW(),
  filled_at TIMESTAMPTZ
);

-- ═══════════════════════════════════════════════════
-- SIGNALS
-- ═══════════════════════════════════════════════════

CREATE TABLE signals (
  id BIGSERIAL,
  station_code VARCHAR(4) NOT NULL,
  market_cluster_id BIGINT NOT NULL,
  computed_at TIMESTAMPTZ NOT NULL,
  outcome_label VARCHAR(30) NOT NULL,
  model_probability DOUBLE PRECISION NOT NULL,
  market_price DOUBLE PRECISION NOT NULL,
  edge DOUBLE PRECISION NOT NULL,
  recommended_side VARCHAR(3) NOT NULL,     -- 'YES' or 'NO'
  alert_level VARCHAR(20),                  -- 'opportunity', 'strong', 'extreme', 'safe_no'
  PRIMARY KEY (id, computed_at)
);
SELECT create_hypertable('signals', 'computed_at');

-- ═══════════════════════════════════════════════════
-- CALIBRATION
-- ═══════════════════════════════════════════════════

CREATE TABLE forecast_accuracy (
  id BIGSERIAL PRIMARY KEY,
  station_code VARCHAR(4) NOT NULL REFERENCES stations(code),
  target_date DATE NOT NULL,
  predicted_distribution JSONB NOT NULL,    -- Model probabilities
  actual_temp INTEGER NOT NULL,
  model_errors JSONB NOT NULL,              -- Per-model errors
  best_edge DOUBLE PRECISION,               -- Best signal edge
  auto_buy_outcome VARCHAR(20),             -- 'win', 'loss', 'sold_early'
  auto_buy_pnl DOUBLE PRECISION,
  resolution_correct BOOLEAN NOT NULL,
  inserted_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (station_code, target_date)
);

-- ═══════════════════════════════════════════════════
-- INDEXES
-- ═══════════════════════════════════════════════════

CREATE INDEX idx_positions_open ON positions(status) WHERE status = 'open';
CREATE INDEX idx_positions_station ON positions(station_code);
CREATE INDEX idx_market_clusters_active ON market_clusters(resolved) WHERE resolved = false;
CREATE INDEX idx_market_clusters_station_date ON market_clusters(station_code, target_date);
CREATE INDEX idx_orders_pending ON orders(status) WHERE status = 'pending';
```

---

## 11. Polymarket Trading Client (Elixir)

The CLOB API requires authenticated requests for placing orders. Build an Elixir client that handles:

### 11.1 Authentication

```elixir
defmodule WeatherEdge.Trading.Auth do
  @doc """
  L1 Authentication: EIP-712 signature
  L2 Authentication: HMAC-SHA256 with API credentials

  The user's private key is stored encrypted and loaded from environment:
    POLYMARKET_PRIVATE_KEY=0x...
    POLYMARKET_API_KEY=...
    POLYMARKET_API_SECRET=...
    POLYMARKET_API_PASSPHRASE=...
    POLYMARKET_WALLET_ADDRESS=0x...
  """
end
```

### 11.2 Client Module

```elixir
defmodule WeatherEdge.Trading.ClobClient do
  @base_url "https://clob.polymarket.com"

  # Public (no auth)
  def get_price(token_id, side)
  def get_orderbook(token_id)
  def get_market(condition_id)

  # Authenticated (L2)
  def place_order(token_id, side, price, size, type \\ "GTC")
  def cancel_order(order_id)
  def get_open_orders()
end

defmodule WeatherEdge.Trading.GammaClient do
  @base_url "https://gamma-api.polymarket.com"

  # Public (no auth)
  def get_events(params \\ %{})
  def get_event_by_slug(slug)
  def search_events(query)
end

defmodule WeatherEdge.Trading.DataClient do
  @base_url "https://data-api.polymarket.com"

  # Public with wallet address
  def get_positions(wallet_address)
  def get_activity(wallet_address)
  def get_balance(wallet_address)
end
```

### 11.3 Order Execution

**Important considerations for Polymarket CLOB orders:**

- Polymarket uses CTF (Conditional Token Framework) on Polygon
- Orders require EIP-712 signatures
- The system should handle: order placement, status tracking, fill detection
- Use WebSocket for real-time order status: `wss://ws-subscriptions-clob.polymarket.com/ws/`
- Token allowances must be set before first trade (one-time setup)

**Recommendation:** Since Polymarket provides official Python (`py-clob-client`) and TypeScript clients but not Elixir, consider:

1. **Option A:** Port the signing logic to Elixir using `ex_secp256k1` + `ex_abi` for EIP-712
2. **Option B:** Wrap `py-clob-client` via a Python microservice called from Elixir
3. **Option C:** Use the TypeScript client via a Node.js sidecar

Option A is preferred for a pure Elixir solution. The critical parts to implement:
- EIP-712 struct hashing for CLOB auth
- HMAC-SHA256 request signing for L2 endpoints
- Order struct building compatible with Polymarket's exchange contract

---

## 12. Project Structure

```
weather_edge/
├── lib/
│   ├── weather_edge/
│   │   ├── stations/                    # Station management
│   │   │   ├── station.ex               # Ecto schema
│   │   │   └── stations.ex              # Context (CRUD, validation)
│   │   │
│   │   ├── markets/                     # Polymarket market data
│   │   │   ├── gamma_client.ex          # Gamma API HTTP client
│   │   │   ├── event_parser.ex          # Parse events → MarketCluster
│   │   │   ├── market_cluster.ex        # Ecto schema
│   │   │   └── market_snapshot.ex       # Ecto schema
│   │   │
│   │   ├── forecasts/                   # Weather forecast system
│   │   │   ├── open_meteo_client.ex     # Open-Meteo multi-model client
│   │   │   ├── metar_client.ex          # Aviation Weather METAR client
│   │   │   ├── multi_model.ex           # Aggregate all models
│   │   │   └── forecast_snapshot.ex     # Ecto schema
│   │   │
│   │   ├── probability/                 # Probability engine
│   │   │   ├── engine.ex               # Main distribution calculator
│   │   │   ├── gaussian.ex             # Gaussian smoothing kernel
│   │   │   └── distribution.ex         # Distribution struct
│   │   │
│   │   ├── signals/                     # Mispricing detection
│   │   │   ├── detector.ex             # Edge calculator
│   │   │   ├── signal.ex               # Ecto schema
│   │   │   └── alerter.ex              # PubSub broadcaster
│   │   │
│   │   ├── trading/                     # Order execution
│   │   │   ├── auth.ex                 # EIP-712 + HMAC signing
│   │   │   ├── clob_client.ex          # CLOB API client
│   │   │   ├── data_client.ex          # Data API client
│   │   │   ├── order_manager.ex        # Place, track, cancel orders
│   │   │   ├── position.ex             # Ecto schema
│   │   │   ├── order.ex                # Ecto schema
│   │   │   └── position_tracker.ex     # P&L calculation + recommendations
│   │   │
│   │   ├── calibration/                 # Post-resolution learning
│   │   │   ├── resolver.ex             # Fetch actual temp, compare
│   │   │   ├── accuracy.ex             # Ecto schema
│   │   │   └── bias_tracker.ex         # Per-station/model stats
│   │   │
│   │   └── workers/                     # Oban workers
│   │       ├── event_scanner_worker.ex
│   │       ├── auto_buyer_worker.ex
│   │       ├── forecast_refresh_worker.ex
│   │       ├── mispricing_worker.ex
│   │       ├── price_snapshot_worker.ex
│   │       ├── position_monitor_worker.ex
│   │       ├── balance_worker.ex
│   │       └── resolution_worker.ex
│   │
│   ├── weather_edge_web/
│   │   ├── live/
│   │   │   ├── dashboard_live.ex
│   │   │   ├── station_detail_live.ex
│   │   │   └── components/
│   │   │       ├── header_component.ex
│   │   │       ├── station_card_component.ex
│   │   │       ├── event_card_component.ex
│   │   │       ├── signal_feed_component.ex
│   │   │       ├── portfolio_summary_component.ex
│   │   │       └── add_station_modal_component.ex
│   │   ├── router.ex
│   │   └── endpoint.ex
│   │
│   └── weather_edge/
│       └── application.ex
│
├── priv/
│   └── repo/migrations/
│       ├── 001_create_stations.exs
│       ├── 002_create_market_clusters.exs
│       ├── 003_create_market_snapshots.exs
│       ├── 004_create_forecast_snapshots.exs
│       ├── 005_create_positions.exs
│       ├── 006_create_orders.exs
│       ├── 007_create_signals.exs
│       └── 008_create_forecast_accuracy.exs
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs                     # Reads POLYMARKET_PRIVATE_KEY etc.
│
├── test/
│   ├── weather_edge/
│   │   ├── markets/gamma_client_test.exs
│   │   ├── forecasts/open_meteo_client_test.exs
│   │   ├── probability/engine_test.exs
│   │   ├── signals/detector_test.exs
│   │   └── trading/order_manager_test.exs
│   └── weather_edge_web/
│       └── live/dashboard_live_test.exs
│
└── mix.exs
```

---

## 13. Configuration

```elixir
# config/runtime.exs

config :weather_edge, WeatherEdge.Trading,
  private_key: System.get_env("POLYMARKET_PRIVATE_KEY"),
  api_key: System.get_env("POLYMARKET_API_KEY"),
  api_secret: System.get_env("POLYMARKET_API_SECRET"),
  api_passphrase: System.get_env("POLYMARKET_API_PASSPHRASE"),
  wallet_address: System.get_env("POLYMARKET_WALLET_ADDRESS"),
  chain_id: 137  # Polygon mainnet

config :weather_edge, WeatherEdge.Trading.Safety,
  min_reserve_usdc: 2.0,          # Never trade below this balance
  max_orders_per_minute: 6,        # Rate limit
  max_position_per_event: 1,       # Only 1 auto-buy per event
  order_retry_delay_ms: 30_000     # 30s retry on failure

config :weather_edge, WeatherEdge.Forecasts,
  models: ["gfs", "ecmwf_ifs", "icon_global", "jma", "gem_global"],
  open_meteo_base_url: "https://api.open-meteo.com/v1/forecast",
  metar_base_url: "https://aviationweather.gov/api/data/metar"
```

---

## 14. Deliverables

Return the full working code for:

1. All Ecto schemas and TimescaleDB migrations
2. Gamma API + CLOB API + Data API clients (Req-based HTTP)
3. Open-Meteo multi-model forecast client
4. Aviation Weather METAR client
5. Probability engine with Gaussian smoothing
6. Mispricing detector with edge calculation and alert levels
7. Auto-buyer with safety guards
8. Position tracker with sell/hold recommendation engine
9. All 8 Oban workers with proper scheduling and cron
10. EIP-712 / HMAC-SHA256 auth module for CLOB trading
11. LiveView dashboard with all components:
    - Station cards with monitoring/auto-buy toggles
    - Event cards with positions, forecasts, recommendations
    - Signal feed (real-time)
    - Portfolio summary
    - Station detail view with charts
    - Add station modal
12. PubSub integration for real-time updates
13. Calibration system (post-resolution accuracy tracking)
14. Tests for core modules

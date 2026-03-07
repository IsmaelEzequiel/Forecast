# Signals Intelligence Page — Prompt de Desenvolvimento

## Contexto

This is a new dedicated page for the Weather Edge trading system (Elixir/Phoenix LiveView). The system already has a working dashboard with station cards, auto-buying, forecast engine, and a basic signal feed showing mispricing alerts.

The current signal feed is a simple chronological list embedded in the dashboard — functional but passive. This new page replaces it with a **full trading operations desk** where the user can analyze, filter, compare, group, and act on signals with full context.

**This page is the primary place where the user decides what to buy.**

The existing system already has:
- `signals` table (TimescaleDB hypertable) with: station_code, market_cluster_id, computed_at, outcome_label, model_probability, market_price, edge, recommended_side, alert_level
- `market_clusters` table with full event data (outcomes JSONB, target_date, station_code)
- `market_snapshots` hypertable with historical price data
- `forecast_snapshots` hypertable with per-model temperature predictions
- `positions` table tracking open/closed positions
- `orders` table tracking all executed orders
- `forecast_accuracy` table with post-resolution calibration data
- `stations` table with METAR codes and config
- PubSub broadcasting on signal/price/forecast updates
- Gamma API, CLOB API, Data API clients
- Probability engine with multi-model Gaussian smoothing

**Do not rebuild existing modules.** Reuse all existing contexts, schemas, and clients. This prompt covers only the new LiveView page and any new queries/functions needed to power it.

---

## 1. Page Layout Overview

Route: `/signals`

```
┌─────────────────────────────────────────────────────────────────────┐
│  SIGNALS INTELLIGENCE          Balance: $47.23    [← Dashboard]     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─ FILTER BAR (sticky top) ──────────────────────────────────────┐ │
│  │  [Stations ▼] [Edge ≥ 8% ─●────── 50%] [Date ▼] [Side ▼]     │ │
│  │  [Max Price ▼] [Alert Level ▼] [Sort: Edge% ▼] [✓ Actionable] │ │
│  │  Active: 3 filters  |  Showing 24 of 87 signals  [Clear All]  │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─ VIEW TOGGLE ─┐                                                  │
│  │ [📋 Table] [📦 Grouped] [🗺️ Heatmap]                           │ │
│  └───────────────┘                                                   │
│                                                                      │
│  ┌─ MAIN CONTENT AREA ───────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  (Table View / Grouped View / Heatmap — based on toggle)      │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─ SIGNAL DETAIL PANEL (slide-in from right, on row click) ─────┐  │
│  │  Full cluster distribution, model breakdown, edge history,     │  │
│  │  orderbook, buy button                                         │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─ PERFORMANCE TRACKER (collapsible section at bottom) ──────────┐ │
│  │  Signal accuracy stats, P&L of followed signals, calibration   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─ QUICK ACTIONS BAR (sticky bottom) ────────────────────────────┐ │
│  │  Balance: $47.23  |  Selected: 3 signals  |  Cost: $15.40     │ │
│  │  [BUY SELECTED]                                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Filter Bar

Sticky at the top of the page. All filters apply in real-time (LiveView patch, no page reload). Filters are AND-combined.

### 2.1 Filter Controls

```elixir
# Filter state in LiveView assigns
%{
  stations: [],                # [] = all, ["SBGR", "EDDM"] = specific
  min_edge: 8,                 # Percentage, range slider 0-60
  resolution_date: "all",      # "all", "today", "tomorrow", "+2d", "+3d"
  side: "all",                 # "all", "yes", "no"
  max_price: nil,              # nil = no limit, 0.25 = only ≤ $0.25
  alert_level: "all",          # "all", "extreme", "strong", "opportunity", "safe_no", "auto_buy", "confirmed"
  sort_by: "edge_desc",        # "edge_desc", "edge_asc", "model_prob_desc", "time_to_resolution", "price_asc", "newest"
  actionable_only: false,      # true = hide signals where price > user's max_buy_price for that station
  has_position: "all"          # "all", "with_position", "without_position"
}
```

### 2.2 Filter UI Components

**Station multi-select dropdown:**
- Shows all active stations with count of signals each
- Example: "SBGR (12) · EDDM (8) · KJFK (5)"
- Checkbox per station

**Edge slider:**
- Range: 0% to 60%
- Shows current value as tooltip
- Default: 8% (minimum alert threshold)

**Resolution date dropdown:**
- "All dates"
- "Today" (resolves today)
- "Tomorrow"
- "+2 days (Mar 08)"
- "+3 days (Mar 09)"
- Dynamic — computed from actual active event dates

**Sort dropdown:**
- "Highest Edge" (default)
- "Lowest Price"
- "Highest Model Probability"
- "Soonest Resolution"
- "Newest First"

**Actionable Only toggle:**
- When ON: filters to signals where entry price ≤ the station's configured `max_buy_price`
- Visual: filled checkbox or toggle switch

**Active filter count + Clear All:**
- "Active: 3 filters | Showing 24 of 87 signals [Clear All]"
- Clear All resets to defaults

### 2.3 Query Strategy

Filters translate to an Ecto query against the `signals` table joined with `market_clusters`, `stations`, and `positions`:

```elixir
defmodule WeatherEdge.Signals.Queries do
  def list_filtered_signals(filters, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(s in Signal,
      join: mc in MarketCluster, on: s.market_cluster_id == mc.id,
      join: st in Station, on: s.station_code == st.code,
      left_join: p in Position, on: p.market_cluster_id == mc.id
        and p.outcome_label == s.outcome_label
        and p.status == "open",
      where: mc.resolved == false,
      # Apply filters dynamically
      select: %{
        signal: s,
        cluster: mc,
        station: st,
        position: p,
        hours_to_resolution: fragment("EXTRACT(EPOCH FROM (? - NOW())) / 3600", mc.target_date),
      }
    )
    |> apply_filters(filters)
    |> apply_sort(filters.sort_by)
    |> limit(^limit)
    |> offset(^offset)
  end

  # Also need: count query for "Showing X of Y"
  def count_filtered_signals(filters)
end
```

---

## 3. Table View (default)

The primary view. Enhanced version of the current signal feed with additional context columns.

### 3.1 Columns

```
┌──────┬────────┬───────┬────────┬──────────┬───────────┬────────────┬─────────┬──────────┬───────────┬──────────┬──────────┬─────────┬──────┐
│  ☐   │ Time   │ Stn   │ Temp   │ Resolves │ Action    │ Alert      │ Confid. │ Mkt ($)  │ Model (%) │ Edge (%) │ Volume   │ Trend   │ Pos? │
├──────┼────────┼───────┼────────┼──────────┼───────────┼────────────┼─────────┼──────────┼───────────┼──────────┼──────────┼─────────┼──────┤
│  ☐   │ 15:55  │ EDDM  │ 16°C   │ 18h      │ BUY YES   │ 🔴Extreme │ ✓Conf   │ $0.38    │ 100.0%    │ +62.5%   │ $1,240   │ ↗ +$0.08│  —   │
│  ☐   │ 15:55  │ EDDM  │ 14°C   │ 18h      │ BUY NO    │ 🟡Safe NO │ ✓Conf   │ $0.37    │ 0.0%      │ +37.0%   │ $890     │ → $0.00 │  —   │
│  ☐   │ 15:52  │ SBGR  │ 28°C   │ 42h      │ BUY YES   │ 🟠Strong  │ ~High   │ $0.24    │ 48.5%     │ +24.5%   │ $521     │ ↗ +$0.04│ 33tk │
└──────┴────────┴───────┴────────┴──────────┴───────────┴────────────┴─────────┴──────────┴───────────┴──────────┴──────────┴─────────┴──────┘
```

### 3.2 Column Definitions

| Column | Source | Description |
|--------|--------|-------------|
| ☐ | UI state | Checkbox for batch selection. Feeds Quick Actions Bar. |
| Time | `signals.computed_at` | HH:MM UTC. Tooltip shows full timestamp. |
| Stn | `signals.station_code` | ICAO code. Color-coded dot per station for visual scanning. |
| Temp | `signals.outcome_label` | Temperature outcome. Bold if matches top model prediction. |
| Resolves | Computed: `market_clusters.target_date - now()` | Hours until resolution. Shows "18h", "42h", etc. Red if < 6h. "Today" badge if resolves today. |
| Action | `signals.recommended_side` | "BUY YES" (green) / "BUY NO" (blue) / "BOUGHT" (purple, if position exists). |
| Alert | `signals.alert_level` | Color badge: 🔴 Extreme, 🟠 Strong, 🟡 Opportunity, 🔵 Safe NO, ⚡ Auto-Buy. |
| Confid. | Computed from station peak status | "✓Confirmed" (post-peak, highest confidence), "~High", "?Forecast" (early, lower confidence). |
| Mkt ($) | `signals.market_price` | Current YES price on Polymarket. |
| Model (%) | `signals.model_probability` | Ensemble model probability. |
| Edge (%) | `signals.edge` | Model prob minus market price. Bold + larger font. Green if > 15%, yellow if > 8%. |
| Volume | From market_clusters outcomes JSONB | Market volume in USD. Gray if < $50 (low liquidity warning). |
| Trend | Computed from `market_snapshots` | Price direction over last 3-6 hours. Sparkline or arrow + delta. "↗ +$0.08" means price rose $0.08. |
| Pos? | From `positions` join | "—" if no position, "33tk" if you hold 33 tokens, clickable to view position detail. |

### 3.3 Row Interactions

- **Click row** → opens Signal Detail Panel (slide-in from right)
- **Click checkbox** → adds to batch selection (updates Quick Actions Bar)
- **Click station code** → filters table to that station only
- **Click "BOUGHT" badge** → navigates to position detail
- **Hover edge** → tooltip with "Potential payout: buy 25tk @ $0.38 → $25.00 if wins, cost $9.50"

### 3.4 Data Loading

- Initial load: 20 signals, sorted by filter
- "Show more" button loads next 20 (infinite scroll or button)
- Real-time updates via PubSub: new signals prepend to list with highlight animation
- Stale signals (price changed significantly) show ⚠️ icon with "Price may have changed"

---

## 4. Grouped View

Groups signals by **event** (station + date) instead of flat list. Each group is a collapsible card.

### 4.1 Group Card Structure

```
┌─ EDDM — Munich — March 7 (resolves in 18h) ─────────────────────┐
│                                                                    │
│  Cluster Health: Σ YES = 1.06 (⚠️ +6% overpriced)                │
│  Forecast Consensus: 16°C (5/5 models agree)                      │
│                                                                    │
│  BEST PLAY                                                         │
│  ┌────────────────────────────────────────────────────────┐       │
│  │  🔴 16°C YES @ $0.38 — edge +62.5% — 100% model prob  │       │
│  │  If resolved correctly: $1.00 payout (163% return)      │       │
│  │  [BUY $5.00]                                            │       │
│  └────────────────────────────────────────────────────────┘       │
│                                                                    │
│  HEDGE OPTIONS                                                     │
│  🔵 15°C NO @ $0.80 — edge +20.0% — Safe NO                      │
│  🔵 14°C NO @ $0.63 — edge +37.0% — Safe NO                      │
│  🔵 13°C NO @ $0.89 — edge +10.5% — Safe NO                      │
│                                                                    │
│  OTHER                                                             │
│  12°C YES @ $0.11 — edge +20.9% — Strong                          │
│                                                                    │
│  [VIEW FULL CLUSTER]  [BUY BEST]  [BUY BEST + HEDGE]              │
└────────────────────────────────────────────────────────────────────┘

┌─ SBGR — São Paulo — March 8 (resolves in 42h) ──────────────────┐
│  ...                                                               │
└────────────────────────────────────────────────────────────────────┘
```

### 4.2 Group Card Logic

For each active market cluster with signals:

```elixir
defmodule WeatherEdge.Signals.GroupedView do
  def group_signals_by_event(signals) do
    signals
    |> Enum.group_by(fn s -> {s.station_code, s.market_cluster_id} end)
    |> Enum.map(fn {{station, cluster_id}, sigs} ->
      sorted = Enum.sort_by(sigs, & &1.edge, :desc)

      best_yes = sorted |> Enum.find(& &1.recommended_side == "YES" and &1.edge > 0)
      safe_nos = sorted |> Enum.filter(& &1.alert_level == "safe_no")
      others = sorted -- [best_yes | safe_nos] |> Enum.filter(& &1 != nil)

      cluster = get_cluster(cluster_id)
      yes_sum = compute_yes_price_sum(cluster)

      %{
        station_code: station,
        cluster: cluster,
        best_play: best_yes,
        hedge_options: safe_nos,
        other_signals: others,
        cluster_health: yes_sum,
        forecast_consensus: get_consensus(station, cluster.target_date),
        hours_to_resolution: hours_until(cluster.target_date),
        signal_count: length(sigs)
      }
    end)
    |> Enum.sort_by(& &1.hours_to_resolution, :asc)  # Soonest first
  end
end
```

### 4.3 Group Actions

- **"BUY BEST"** — buys the highest-edge YES signal at configured amount
- **"BUY BEST + HEDGE"** — buys best YES + best Safe NO (two orders)
- **"VIEW FULL CLUSTER"** — opens Signal Detail Panel with full cluster view

---

## 5. Heatmap View

A grid visualization for instant overview of where opportunities exist.

### 5.1 Grid Structure

```
              │  Today   │ Tomorrow │  +2d     │  +3d     │
─────────────┼──────────┼──────────┼──────────┼──────────┤
  SBGR (SP)  │  ██ +42% │  ██ +18% │  ░░  +5% │  ░░  new │
  EDDM (MUC) │  ██ +62% │  ██ +31% │  ░░  +9% │          │
  KJFK (NYC) │  ░░ +11% │  ██ +24% │          │          │
  KMIA (MIA) │  ░░  +8% │  ░░ +12% │  ░░  +7% │          │
```

### 5.2 Cell Content

Each cell represents the **best available edge** for that station + date combination:

- **Color intensity**: based on max edge (darker = higher edge)
  - Edge < 8%: gray (no signal)
  - Edge 8-15%: light green
  - Edge 15-25%: medium green
  - Edge 25%+: dark green / red (extreme)
  - No event: empty cell
- **Text**: "+42%" showing best edge
- **Click**: navigates to grouped view filtered to that station + date

### 5.3 Implementation

```elixir
defmodule WeatherEdge.Signals.HeatmapData do
  def build_heatmap() do
    stations = Stations.list_active()
    dates = compute_relevant_dates()  # today through +3d

    for station <- stations, date <- dates do
      best_signal = Signals.best_signal_for(station.code, date)

      %{
        station_code: station.code,
        city: station.city,
        date: date,
        date_label: date_label(date),  # "Today", "Tomorrow", "+2d", "+3d"
        best_edge: best_signal && best_signal.edge,
        signal_count: Signals.count_for(station.code, date),
        has_position: Positions.has_open_for?(station.code, date),
        has_event: MarketClusters.exists_for?(station.code, date)
      }
    end
  end
end
```

---

## 6. Signal Detail Panel

Slides in from the right when a signal row is clicked. Covers ~40% of the screen width. Closeable with X or clicking outside.

### 6.1 Panel Content

```
┌─ SIGNAL DETAIL ──────────────────────────── [X] ┐
│                                                   │
│  EDDM — 16°C YES — March 7                       │
│  Edge: +62.5%  |  Alert: Extreme  |  Confirmed   │
│                                                   │
│  ┌─ CLUSTER DISTRIBUTION ──────────────────────┐ │
│  │                                              │ │
│  │  Horizontal bar chart:                       │ │
│  │  Each temperature shows two bars:            │ │
│  │  - Blue: Model probability                   │ │
│  │  - Orange: Market YES price                  │ │
│  │  Gap between = edge                          │ │
│  │  Your position highlighted with purple dot   │ │
│  │                                              │ │
│  │  12°C  ██░░ 31% vs $0.11                     │ │
│  │  13°C  ░░░░  0% vs $0.11                     │ │
│  │  14°C  ░░░░  0% vs $0.37  ← mispriced       │ │
│  │  15°C  ░░░░  0% vs $0.20  ← mispriced       │ │
│  │  16°C  ████████████ 100% vs $0.38 ★ BEST    │ │
│  │  17°C  ░░░░  0% vs $0.05                     │ │
│  │                                              │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  MODEL BREAKDOWN                                  │
│  ┌──────────────────────────────────────────────┐ │
│  │  GFS     → 16°C (max: 16.2°C)    ✓          │ │
│  │  ECMWF   → 16°C (max: 15.8°C)    ✓          │ │
│  │  ICON    → 16°C (max: 16.1°C)    ✓          │ │
│  │  JMA     → 16°C (max: 16.0°C)    ✓          │ │
│  │  GEM     → 16°C (max: 15.9°C)    ✓          │ │
│  │                                              │ │
│  │  Consensus: 5/5 models → 16°C               │ │
│  │  Confidence: VERY HIGH                       │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  EDGE HISTORY (last 24h)                          │
│  ┌──────────────────────────────────────────────┐ │
│  │  Line chart: edge % over time                │ │
│  │  Shows if edge is growing, stable, or closing│ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  PRICE HISTORY (since event opened)               │
│  ┌──────────────────────────────────────────────┐ │
│  │  Line chart: YES price since market opened   │ │
│  │  Mark: your buy price (if position exists)   │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  ORDERBOOK                                        │
│  Best Bid: $0.37 × 200 tokens                    │
│  Best Ask: $0.39 × 150 tokens                    │
│  Spread: $0.02 (5.1%)                            │
│  Depth (±$0.05): $1,240 bids / $980 asks         │
│                                                   │
│  METAR CURRENT (if resolves today)                │
│  Station: EDDM | Obs: 14°C at 15:00 UTC          │
│  Max recorded today: 15°C at 13:00 UTC            │
│                                                   │
│  YOUR POSITION (if exists)                        │
│  28°C YES × 33.3 tokens @ $0.15                  │
│  Current: $0.42  |  P&L: +$8.99 (+180%)          │
│                                                   │
│  ┌──────────────────────────────────────────────┐ │
│  │  Amount: [$5.00        ]  Tokens: ~13.2      │ │
│  │  Payout if wins: $13.20  |  Return: +164%    │ │
│  │                                              │ │
│  │  [BUY YES $5.00]    [BUY NO $5.00]           │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  [Open on Polymarket ↗]                           │
└───────────────────────────────────────────────────┘
```

### 6.2 Data Requirements

The panel needs data from multiple sources. Fetch on open, not pre-loaded:

```elixir
defmodule WeatherEdge.Signals.DetailData do
  def fetch_signal_detail(signal_id) do
    signal = Signals.get_signal!(signal_id)
    cluster = MarketClusters.get_with_outcomes!(signal.market_cluster_id)

    %{
      signal: signal,
      cluster: cluster,

      # Full cluster distribution (model prob vs market price for ALL temps)
      distribution: Probability.Engine.compute_distribution(
        cluster.station_code, cluster.target_date
      ),

      # Per-model breakdown
      model_breakdown: ForecastSnapshots.latest_by_model(
        cluster.station_code, cluster.target_date
      ),

      # Edge history: how this signal's edge changed over time
      edge_history: Signals.edge_history(
        signal.station_code, signal.market_cluster_id,
        signal.outcome_label, hours: 24
      ),

      # Price history: YES price over time for this outcome
      price_history: MarketSnapshots.price_history(
        signal.market_cluster_id, signal.outcome_label, hours: 48
      ),

      # Orderbook snapshot
      orderbook: ClobClient.get_orderbook(signal.token_id),

      # METAR current conditions (if resolves today/tomorrow)
      metar: MetarClient.fetch(cluster.station_code),

      # User's position in this market (if any)
      position: Positions.get_open_for(
        cluster.station_code, signal.market_cluster_id, signal.outcome_label
      ),

      # User balance
      balance: Trading.get_cached_balance()
    }
  end
end
```

### 6.3 Charts

Use **VegaLite** (server-side rendering for LiveView) or a lightweight JS charting library pushed via hooks.

Required charts:
1. **Cluster distribution bar chart** — horizontal bars, dual series (model prob blue, market price orange)
2. **Edge history line chart** — single line, time on X axis, edge % on Y
3. **Price history line chart** — single line, time on X, price on Y, with buy price marker if position exists

---

## 7. Performance Tracker Section

Collapsible section at the bottom of the page. Shows historical signal accuracy and P&L.

### 7.1 Summary Stats Row

```
┌─ SIGNAL PERFORMANCE ──────────────────────────────────────────────┐
│                                                                    │
│  Overall      │  By Alert Level                                    │
│  ───────────  │  ─────────────────────────────────────────         │
│  Accuracy:    │  🔴 Extreme:     82% accuracy (14/17)              │
│    71%        │  🟠 Strong:      68% accuracy (28/41)              │
│  Avg Edge:    │  🟡 Opportunity: 61% accuracy (19/31)              │
│    +18.3%     │  🔵 Safe NO:     94% accuracy (47/50)              │
│  Total P&L:   │                                                    │
│    +$142.50   │  By Station                                        │
│  Signals      │  ─────────────────────────────────────────         │
│  followed:    │  SBGR: 78% accuracy | +$62.30 P&L                 │
│    89          │  EDDM: 65% accuracy | +$41.20 P&L                 │
│               │  KJFK: 72% accuracy | +$39.00 P&L                 │
└───────────────┴────────────────────────────────────────────────────┘
```

### 7.2 Signal History Table

Below the summary, a table of past signals with outcomes:

```
┌────────┬───────┬────────┬──────────┬────────┬────────┬──────────┬────────┐
│ Date   │ Stn   │ Temp   │ Action   │ Edge   │ Result │ P&L      │ Status │
├────────┼───────┼────────┼──────────┼────────┼────────┼──────────┼────────┤
│ Mar 5  │ EDDM  │ 16°C   │ BUY YES  │ +62.5% │ ✅ Won  │ +$3.10   │ Held   │
│ Mar 5  │ SBGR  │ 28°C   │ BUY YES  │ +24.5% │ ❌ Lost │ -$5.00   │ Held   │
│ Mar 4  │ SBGR  │ 27°C   │ BUY NO   │ +18.2% │ ✅ Won  │ +$0.85   │ Held   │
│ Mar 4  │ EDDM  │ 14°C   │ BUY YES  │ +31.0% │ 💰 Sold │ +$2.30   │ Sold   │
└────────┴───────┴────────┴──────────┴────────┴────────┴──────────┴────────┘
```

### 7.3 Data Source

Query from `forecast_accuracy` + `positions` (closed) + `signals` (resolved clusters):

```elixir
defmodule WeatherEdge.Signals.Performance do
  def compute_stats(opts \\ []) do
    timeframe = Keyword.get(opts, :days, 30)
    since = Date.utc_today() |> Date.add(-timeframe)

    resolved = from(fa in ForecastAccuracy,
      where: fa.target_date >= ^since,
      join: mc in MarketCluster, on: mc.station_code == fa.station_code
        and mc.target_date == fa.target_date,
      preload: []
    ) |> Repo.all()

    %{
      total_signals: length(resolved),
      accuracy: compute_accuracy(resolved),
      accuracy_by_level: group_accuracy_by(:alert_level, resolved),
      accuracy_by_station: group_accuracy_by(:station_code, resolved),
      total_pnl: sum_pnl(resolved),
      avg_edge: avg_field(resolved, :best_edge),
      history: build_history_table(resolved)
    }
  end
end
```

---

## 8. Quick Actions Bar

Sticky bar at the bottom of the page. Always visible.

### 8.1 Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  💰 $47.23 USDC  │  ☑ 3 selected  │  Cost: $15.40  │ [BUY ALL 3] │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.2 Behavior

- **Balance**: refreshed every 5 minutes via BalanceWorker, updated via PubSub
- **Selected count**: tracks checked rows from Table View
- **Cost**: sum of `station.buy_amount_usdc` for each selected signal (or configurable per-signal in detail panel)
- **BUY ALL**: executes orders for all selected signals sequentially
  - Shows progress: "Buying 1/3... 2/3... Done ✓"
  - Each order creates a Position record
  - Failed orders show error inline
  - After completion, selected signals update to show "BOUGHT" badge

### 8.3 Safety Checks Before Batch Buy

```elixir
def validate_batch_buy(selected_signals, balance) do
  total_cost = Enum.sum(Enum.map(selected_signals, & &1.buy_amount))

  cond do
    total_cost > balance - min_reserve() ->
      {:error, "Insufficient balance. Need $#{total_cost}, have $#{balance} (reserve: $#{min_reserve()})"}

    Enum.any?(selected_signals, & has_existing_position?(&1)) ->
      {:error, "Some signals already have open positions"}

    length(selected_signals) > 10 ->
      {:error, "Maximum 10 orders per batch"}

    true ->
      {:ok, total_cost}
  end
end
```

---

## 9. LiveView Implementation

### 9.1 Main LiveView Module

```elixir
defmodule WeatherEdgeWeb.SignalsLive do
  use WeatherEdgeWeb, :live_view

  # State
  # - filters: current filter state
  # - signals: loaded signals (paginated)
  # - total_count: total matching signals
  # - selected: MapSet of selected signal IDs
  # - view_mode: :table | :grouped | :heatmap
  # - detail_signal_id: nil | signal_id (open detail panel)
  # - balance: current USDC balance
  # - performance_expanded: boolean

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "signals:new")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "portfolio:balance_update")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "portfolio:position_update")
    end

    filters = default_filters()
    {signals, total} = load_signals(filters, limit: 20, offset: 0)

    {:ok, assign(socket,
      filters: filters,
      signals: signals,
      total_count: total,
      selected: MapSet.new(),
      view_mode: :table,
      detail_signal_id: nil,
      detail_data: nil,
      balance: Trading.get_cached_balance(),
      performance_expanded: false,
      performance_data: nil,
      buying_state: nil  # nil | {:buying, progress} | {:done, results}
    )}
  end

  # Handle real-time signal updates
  def handle_info({:new_signal, signal}, socket) do
    if matches_filters?(signal, socket.assigns.filters) do
      {:noreply, update(socket, :signals, fn sigs -> [signal | sigs] end)
       |> update(:total_count, & &1 + 1)}
    else
      {:noreply, socket}
    end
  end

  # Handle filter changes
  def handle_event("filter_changed", %{"filter" => filter_params}, socket) do
    new_filters = merge_filters(socket.assigns.filters, filter_params)
    {signals, total} = load_signals(new_filters, limit: 20, offset: 0)

    {:noreply, assign(socket,
      filters: new_filters,
      signals: signals,
      total_count: total,
      selected: MapSet.new()  # Clear selection on filter change
    )}
  end

  # Handle view mode toggle
  def handle_event("set_view", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, view_mode: String.to_atom(mode))}
  end

  # Handle signal row click → open detail panel
  def handle_event("open_detail", %{"signal_id" => id}, socket) do
    detail = Signals.DetailData.fetch_signal_detail(id)
    {:noreply, assign(socket, detail_signal_id: id, detail_data: detail)}
  end

  # Handle close detail panel
  def handle_event("close_detail", _, socket) do
    {:noreply, assign(socket, detail_signal_id: nil, detail_data: nil)}
  end

  # Handle row selection (checkbox)
  def handle_event("toggle_select", %{"signal_id" => id}, socket) do
    selected = if MapSet.member?(socket.assigns.selected, id) do
      MapSet.delete(socket.assigns.selected, id)
    else
      MapSet.put(socket.assigns.selected, id)
    end
    {:noreply, assign(socket, selected: selected)}
  end

  # Handle batch buy
  def handle_event("buy_selected", _, socket) do
    signals = get_selected_signals(socket.assigns.signals, socket.assigns.selected)

    case validate_batch_buy(signals, socket.assigns.balance) do
      {:ok, _cost} ->
        # Execute orders asynchronously, update progress via send()
        Task.start(fn -> execute_batch_buy(signals, self()) end)
        {:noreply, assign(socket, buying_state: {:buying, 0, length(signals)})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  # Handle buy from detail panel
  def handle_event("buy_from_detail", %{"signal_id" => id, "amount" => amount}, socket) do
    signal = Enum.find(socket.assigns.signals, & &1.id == id)
    # Execute single buy
    case Trading.OrderManager.place_signal_order(signal, amount) do
      {:ok, order} ->
        {:noreply, socket |> put_flash(:info, "Order placed: #{order.id}")}
      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Order failed: #{reason}")}
    end
  end

  # Handle load more
  def handle_event("load_more", _, socket) do
    offset = length(socket.assigns.signals)
    {more, _total} = load_signals(socket.assigns.filters, limit: 20, offset: offset)
    {:noreply, update(socket, :signals, fn sigs -> sigs ++ more end)}
  end

  # Handle performance section toggle
  def handle_event("toggle_performance", _, socket) do
    expanded = !socket.assigns.performance_expanded
    data = if expanded and is_nil(socket.assigns.performance_data) do
      Signals.Performance.compute_stats(days: 30)
    else
      socket.assigns.performance_data
    end
    {:noreply, assign(socket, performance_expanded: expanded, performance_data: data)}
  end
end
```

### 9.2 Component Tree

```
signals_live.ex
├── render/1
│   ├── header (balance, back link)
│   ├── filter_bar_component (sticky top)
│   ├── view_toggle_component
│   ├── case @view_mode do
│   │   ├── :table → signal_table_component
│   │   ├── :grouped → grouped_view_component
│   │   │   └── event_group_card_component (×N)
│   │   └── :heatmap → heatmap_component
│   ├── if @detail_signal_id → signal_detail_panel_component (slide-in)
│   ├── if @performance_expanded → performance_tracker_component
│   └── quick_actions_bar_component (sticky bottom)
```

---

## 10. New Database Queries Needed

Add these functions to existing context modules:

```elixir
# In Signals context
def edge_history(station_code, cluster_id, outcome_label, opts) do
  hours = Keyword.get(opts, :hours, 24)
  since = DateTime.utc_now() |> DateTime.add(-hours * 3600)

  from(s in Signal,
    where: s.station_code == ^station_code
      and s.market_cluster_id == ^cluster_id
      and s.outcome_label == ^outcome_label
      and s.computed_at >= ^since,
    order_by: [asc: s.computed_at],
    select: %{time: s.computed_at, edge: s.edge, model_prob: s.model_probability, market_price: s.market_price}
  ) |> Repo.all()
end

def best_signal_for(station_code, date) do
  from(s in Signal,
    join: mc in MarketCluster, on: s.market_cluster_id == mc.id,
    where: s.station_code == ^station_code
      and mc.target_date == ^date
      and mc.resolved == false,
    order_by: [desc: s.edge],
    limit: 1
  ) |> Repo.one()
end

# In MarketSnapshots context
def price_history(cluster_id, outcome_label, opts) do
  hours = Keyword.get(opts, :hours, 48)
  since = DateTime.utc_now() |> DateTime.add(-hours * 3600)

  from(ms in MarketSnapshot,
    where: ms.market_cluster_id == ^cluster_id
      and ms.outcome_label == ^outcome_label
      and ms.snapshot_at >= ^since,
    order_by: [asc: ms.snapshot_at],
    select: %{time: ms.snapshot_at, yes_price: ms.yes_price, volume: ms.volume}
  ) |> Repo.all()
end

# In Positions context
def has_open_for?(station_code, date) do
  from(p in Position,
    join: mc in MarketCluster, on: p.market_cluster_id == mc.id,
    where: p.station_code == ^station_code
      and mc.target_date == ^date
      and p.status == "open"
  ) |> Repo.exists?()
end
```

---

## 11. Navigation Integration

Add to the existing app layout/router:

```elixir
# router.ex
live "/signals", SignalsLive, :index

# In the main dashboard header, add link:
# [Dashboard] [Signals] [Settings]
```

The existing dashboard's signal feed can be simplified to show only the latest 5 signals with a "View All →" link to `/signals`.

---

## 12. Deliverables

Build the complete Signals Intelligence page:

1. `SignalsLive` LiveView module with full filter/view/selection state management
2. All LiveComponents:
   - `FilterBarComponent` with all filter controls
   - `SignalTableComponent` with enhanced columns
   - `GroupedViewComponent` with event group cards
   - `HeatmapComponent` with clickable grid
   - `SignalDetailPanelComponent` with charts, model breakdown, buy button
   - `PerformanceTrackerComponent` with accuracy stats and history table
   - `QuickActionsBarComponent` with batch buy
3. New query functions in existing contexts (Signals, MarketSnapshots, Positions)
4. `Signals.GroupedView` module for event grouping logic
5. `Signals.HeatmapData` module for heatmap grid data
6. `Signals.Performance` module for accuracy/P&L computation
7. `Signals.DetailData` module for detail panel data assembly
8. Chart rendering (VegaLite or JS hooks) for: cluster distribution, edge history, price history
9. Batch buy execution with progress tracking
10. PubSub integration for real-time updates on the page
11. Tests for: filter queries, grouping logic, performance calculations, batch buy validation
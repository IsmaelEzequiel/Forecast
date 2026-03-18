# Dutching Strategy + Position Manager — Weather Edge

## Context

Weather Edge is an existing Elixir/Phoenix LiveView app that monitors Polymarket temperature markets. It already has:

- `EventScannerWorker` — detects new events at 6:01 AM ET via Gamma API
- `AutoBuyerWorker` — buys single most likely outcome (to be replaced by dutching)
- `Probability.Engine` — multi-model ensemble (GFS, ECMWF, ICON, JMA, GEM) with Gaussian smoothing
- `ClobClient` — Polymarket CLOB API client (read + write)
- `GammaClient` — event/market discovery
- `DataClient` — wallet balance, positions
- Stations context with METAR codes, monitoring toggles
- `market_clusters`, `market_snapshots`, `forecast_snapshots`, `signals` tables (TimescaleDB)
- LiveView dashboard with station cards, signal feed
- Oban for background jobs

**Do NOT rebuild existing modules.** Extend what exists.

**Critical constraint:** The server is hosted in the US. Polymarket geo-blocks trading (`POST /order`) from US IPs. All trading requests must route through a configurable non-US proxy. Read endpoints (GET prices, events, orderbook) work without proxy.

---

## 1. What to Build

Two things:

**A) Dutching Engine + Auto-Buyer** — replaces single-outcome buying with multi-outcome dutching that guarantees profit when sum of YES prices < $1.00

**B) Position Manager UI** — a LiveView page where the user sees all open dutch positions with real-time P&L, current value vs guaranteed payout, forecast status, and one-click SELL ALL or HOLD buttons with clear profit comparison

---

## 2. Dutching Strategy

### 2.1 How It Works

Every day at 6:01 AM ET, Polymarket creates a temperature event for 3 days ahead with 9 outcomes (e.g., 14°C or below, 15°C, 16°C, ..., 22°C or higher). At market open, prices are low and inefficient — the sum of all YES prices is typically $0.50–$0.70, well below the theoretical $1.00.

**Dutching** means buying YES on multiple outcomes. If the sum of their prices < $1.00, profit is guaranteed when ANY of them wins:

```
Budget: $50
Selected outcomes: 19°C ($0.08), 20°C ($0.10), 21°C ($0.12), 22°C+ ($0.18)
Sum: $0.48
Tokens per outcome: $50 / $0.48 = 104.17
Invest per outcome: price × 104.17 tokens

Payout regardless of which wins: 104.17 × $1.00 = $104.17
Profit: $54.17 (+108.3%) GUARANTEED
```

The key: **only works in first 30-60 minutes after market opens.** After that, prices correct and sum rises above $1.00.

Additionally, the user can **sell before resolution** at any time. As the market matures over 2-3 days, the winning outcome's price rises significantly (e.g., 22°C+ goes from $0.18 → $0.74), making the total position value often exceed the guaranteed payout. Selling early can yield MORE than waiting for resolution, with zero risk since you exit immediately.

### 2.2 Outcome Selection Algorithm

```
1. Fetch multi-model forecasts for station + target_date
2. Compute probability distribution via Engine (Gaussian smoothed)
3. Fetch LIVE YES prices from CLOB API (prices change fast at open)
4. Sort outcomes by model probability (highest first)
5. Greedily add outcomes while:
   - sum_prices < station.dutch_max_sum (default: $0.85)
   - coverage >= station.dutch_min_coverage (default: 90%)
   - count <= station.dutch_max_outcomes (default: 5)
   - each outcome has model_prob >= 2%
6. Compute allocation: equal payout per outcome (proportional to price)
7. Validate: is_profitable (sum < 1.0), profit% >= min_profit, balance sufficient
8. Execute orders sequentially with 2s delay between each
```

### 2.3 Allocation Formula

```
tokens_per_outcome = total_budget / sum_of_selected_prices

For each selected outcome:
  investment = outcome_price × tokens_per_outcome
  tokens_bought = tokens_per_outcome
  payout_if_wins = tokens_per_outcome × $1.00

guaranteed_profit = tokens_per_outcome - total_budget
guaranteed_profit_pct = (1 / sum_of_selected_prices) - 1
```

---

## 3. Database Changes

### 3.1 New Tables

```sql
CREATE TABLE dutch_groups (
  id BIGSERIAL PRIMARY KEY,
  station_code VARCHAR(4) NOT NULL REFERENCES stations(code),
  market_cluster_id BIGINT NOT NULL REFERENCES market_clusters(id),
  target_date DATE NOT NULL,
  total_invested DOUBLE PRECISION NOT NULL,
  guaranteed_payout DOUBLE PRECISION NOT NULL,
  guaranteed_profit_pct DOUBLE PRECISION NOT NULL,
  coverage DOUBLE PRECISION NOT NULL,
  num_outcomes INTEGER NOT NULL,
  status VARCHAR(20) DEFAULT 'open',
    -- 'open': waiting for resolution or sell
    -- 'won': result fell in covered range, position paid out $1/token
    -- 'lost': result fell outside covered range, all tokens worthless
    -- 'sold': user sold all positions before resolution
  winning_outcome VARCHAR(30),
  actual_pnl DOUBLE PRECISION,
  current_value DOUBLE PRECISION,
  sell_recommendation VARCHAR(20),
    -- 'sell_now', 'hold', 'sell_urgent'
  sell_reason TEXT,
  inserted_at TIMESTAMPTZ DEFAULT NOW(),
  closed_at TIMESTAMPTZ
);

CREATE TABLE dutch_orders (
  id BIGSERIAL PRIMARY KEY,
  dutch_group_id BIGINT NOT NULL REFERENCES dutch_groups(id),
  outcome_label VARCHAR(30) NOT NULL,
  token_id_yes TEXT NOT NULL,
  buy_price DOUBLE PRECISION NOT NULL,
  current_price DOUBLE PRECISION,
  tokens DOUBLE PRECISION NOT NULL,
  invested DOUBLE PRECISION NOT NULL,
  current_value DOUBLE PRECISION,
  polymarket_order_id VARCHAR(100),
  status VARCHAR(20) DEFAULT 'filled'
);

CREATE INDEX idx_dutch_groups_open ON dutch_groups(status) WHERE status = 'open';
CREATE INDEX idx_dutch_groups_station ON dutch_groups(station_code);
```

### 3.2 Station Schema Extension

```sql
ALTER TABLE stations ADD COLUMN strategy VARCHAR(10) DEFAULT 'dutch';
  -- 'dutch': auto-buy multiple outcomes (default)
  -- 'single': auto-buy single best outcome (legacy behavior)
  -- 'manual': monitor only, no auto-buy

ALTER TABLE stations ADD COLUMN dutch_max_sum DOUBLE PRECISION DEFAULT 0.85;
ALTER TABLE stations ADD COLUMN dutch_min_coverage DOUBLE PRECISION DEFAULT 0.90;
ALTER TABLE stations ADD COLUMN dutch_max_outcomes INTEGER DEFAULT 5;
ALTER TABLE stations ADD COLUMN dutch_min_profit_pct DOUBLE PRECISION DEFAULT 0.10;
```

---

## 4. Backend Modules

### 4.1 DutchEngine

```elixir
defmodule WeatherEdge.Trading.DutchEngine do
  @moduledoc """
  Core dutching math. Pure functions, no side effects.
  """

  defstruct [:outcomes, :sum_prices, :profit_pct, :coverage, :is_profitable]

  @doc "Select which outcomes to include in the dutch"
  def select_outcomes(cluster_outcomes, model_distribution, live_prices, config)
  # Returns %DutchEngine{} with selected outcomes and profitability analysis

  @doc "Compute dollar allocation per outcome for equal payout"
  def compute_allocation(%DutchEngine{} = selection, budget)
  # Returns %{orders: [...], total_invested, guaranteed_payout, profit_pct, profit_usd}

  @doc "Compute current total value of a dutch group at current market prices"
  def compute_current_value(dutch_orders, current_prices)
  # Returns float (total USDC value if sold now)

  @doc "Compare selling now vs holding to resolution"
  def compare_exit_strategies(dutch_group, dutch_orders, current_prices, forecast)
  # Returns %{
  #   sell_now: %{value: x, profit: y, profit_pct: z, risk: "none"},
  #   hold_to_resolution: %{value: x, profit: y, profit_pct: z, risk: "3% chance of total loss"},
  #   recommendation: :sell | :hold,
  #   reason: "..."
  # }
end
```

### 4.2 DutchBuyerWorker

```elixir
defmodule WeatherEdge.Workers.DutchBuyerWorker do
  use Oban.Worker, queue: :trading, max_attempts: 2, priority: 0

  @doc """
  Triggered by EventScannerWorker when new event detected.
  Fetches forecasts, selects outcomes, validates, executes orders.
  All trading requests routed through non-US proxy.
  """

  def perform(%{args: %{"station_code" => code, "event_id" => event_id}})

  # Steps:
  # 1. Load station config + market cluster
  # 2. Fetch multi-model forecasts (Open-Meteo)
  # 3. Compute probability distribution
  # 4. Fetch LIVE prices from CLOB (critical: prices move fast at open)
  # 5. DutchEngine.select_outcomes/4
  # 6. Validate: profitable? coverage? balance? no duplicate?
  # 7. DutchEngine.compute_allocation/2
  # 8. Execute orders sequentially (2s between each, via proxy)
  # 9. Create dutch_group + dutch_orders records
  # 10. Broadcast via PubSub for dashboard update

  # Safety guards:
  # - Never buy if balance < budget + $2 reserve
  # - Never buy if dutch_group already exists for this event + station
  # - Max 1 dutch per event per station
  # - If 2+ orders fail, cancel the successful ones (rollback)
  # - Retry once with refreshed prices if price_moved error
end
```

### 4.3 DutchMonitorWorker

```elixir
defmodule WeatherEdge.Workers.DutchMonitorWorker do
  use Oban.Worker, queue: :signals

  @doc """
  Runs every 5 minutes. For each open dutch group:
  1. Fetch current prices for all outcomes
  2. Compute current total value
  3. Update dutch_orders.current_price and dutch_orders.current_value
  4. Update dutch_group.current_value
  5. Run sell/hold recommendation engine
  6. Update dutch_group.sell_recommendation and sell_reason
  7. Broadcast position update via PubSub
  """
end
```

### 4.4 DutchResolverWorker

```elixir
defmodule WeatherEdge.Workers.DutchResolverWorker do
  use Oban.Worker, queue: :cleanup

  @doc """
  Runs daily at 11 PM ET. For each dutch group where target_date <= today:
  1. Check if market_cluster is resolved
  2. If resolved: determine winning outcome
  3. If winning_outcome is in covered outcomes → status = 'won', pnl = payout - invested
  4. If winning_outcome is NOT covered → status = 'lost', pnl = -invested
  5. Update forecast_accuracy record
  6. Broadcast resolution via PubSub
  """
end
```

### 4.5 DutchSeller

```elixir
defmodule WeatherEdge.Trading.DutchSeller do
  @moduledoc """
  Executes sell orders for dutch groups. All sells go through proxy.
  """

  @doc "Sell all positions in a dutch group at market price"
  def sell_all(dutch_group_id)
  # For each dutch_order:
  #   1. Get current sell price from CLOB
  #   2. Place SELL order via proxy
  #   3. Track result
  # Update dutch_group: status='sold', sold_value, actual_pnl, closed_at
  # Broadcast update

  @doc "Sell a single outcome within a dutch group"
  def sell_one(dutch_order_id)
  # Sells just one outcome (e.g., sell the high-value one, keep the rest)
end
```

### 4.6 Sell/Hold Recommendation Engine

```elixir
defmodule WeatherEdge.Trading.DutchAdvisor do
  @moduledoc """
  Generates sell/hold recommendations for open dutch positions.
  """

  def recommend(dutch_group, dutch_orders, current_prices, latest_forecast) do
    current_value = DutchEngine.compute_current_value(dutch_orders, current_prices)
    sell_profit = current_value - dutch_group.total_invested
    sell_profit_pct = sell_profit / dutch_group.total_invested
    hold_profit = dutch_group.guaranteed_payout - dutch_group.total_invested
    hold_profit_pct = dutch_group.guaranteed_profit_pct
    days_left = Date.diff(dutch_group.target_date, Date.utc_today())
    forecast_in_range = forecast_covered?(latest_forecast, dutch_group)

    cond do
      # Forecast shifted OUTSIDE covered range → SELL IMMEDIATELY
      not forecast_in_range and days_left <= 1 ->
        %{
          action: :sell_urgent,
          reason: "Forecast shifted outside your covered temperatures. Sell NOW to keep #{format_pct(sell_profit_pct)} profit before potential loss.",
          sell_value: current_value,
          sell_profit: sell_profit,
          sell_profit_pct: sell_profit_pct,
          hold_value: dutch_group.guaranteed_payout,
          hold_profit: hold_profit,
          hold_risk: "HIGH — forecast no longer supports your position"
        }

      # Current value exceeds guaranteed payout → sell and take the extra
      current_value > dutch_group.guaranteed_payout * 1.05 ->
        %{
          action: :sell_now,
          reason: "Selling now gives #{format_money(sell_profit)} (#{format_pct(sell_profit_pct)}) — MORE than holding to resolution (#{format_money(hold_profit)}). Zero risk.",
          sell_value: current_value,
          sell_profit: sell_profit,
          sell_profit_pct: sell_profit_pct,
          hold_value: dutch_group.guaranteed_payout,
          hold_profit: hold_profit,
          hold_risk: "#{Float.round((1 - dutch_group.coverage) * 100, 1)}% chance of total loss"
        }

      # Resolution today, forecast in range → hold for guaranteed payout
      days_left == 0 and forecast_in_range ->
        %{
          action: :hold,
          reason: "Resolves today. Forecast still in your covered range. Hold for guaranteed #{format_money(hold_profit)} (#{format_pct(hold_profit_pct)}).",
          sell_value: current_value,
          sell_profit: sell_profit,
          sell_profit_pct: sell_profit_pct,
          hold_value: dutch_group.guaranteed_payout,
          hold_profit: hold_profit,
          hold_risk: "#{Float.round((1 - dutch_group.coverage) * 100, 1)}% chance of loss"
        }

      # Resolution tomorrow, good profit already → show comparison
      days_left == 1 and sell_profit_pct > 0.3 ->
        %{
          action: :consider_sell,
          reason: "You have #{format_pct(sell_profit_pct)} profit now. Resolution tomorrow — you can lock in or wait for guaranteed #{format_pct(hold_profit_pct)}.",
          sell_value: current_value,
          sell_profit: sell_profit,
          sell_profit_pct: sell_profit_pct,
          hold_value: dutch_group.guaranteed_payout,
          hold_profit: hold_profit,
          hold_risk: "#{Float.round((1 - dutch_group.coverage) * 100, 1)}% chance of loss"
        }

      # Early days, position healthy → hold
      true ->
        %{
          action: :hold,
          reason: "Position healthy. #{days_left} days to resolution. Current value: #{format_money(current_value)}.",
          sell_value: current_value,
          sell_profit: sell_profit,
          sell_profit_pct: sell_profit_pct,
          hold_value: dutch_group.guaranteed_payout,
          hold_profit: hold_profit,
          hold_risk: "#{Float.round((1 - dutch_group.coverage) * 100, 1)}% chance of loss"
        }
    end
  end
end
```

---

## 5. ClobClient Proxy Support

```elixir
defmodule WeatherEdge.Trading.ClobClient do
  @base_url "https://clob.polymarket.com"

  # ══════════════════════════════════════════════
  # PUBLIC ENDPOINTS (no proxy, no auth)
  # ══════════════════════════════════════════════

  def get_price(token_id, side) do
    Req.get!("#{@base_url}/price",
      params: %{token_id: token_id, side: side}
    ).body
  end

  def get_orderbook(token_id) do
    Req.get!("#{@base_url}/book",
      params: %{token_id: token_id}
    ).body
  end

  # ══════════════════════════════════════════════
  # TRADING ENDPOINTS (proxy + L2 auth required)
  # ══════════════════════════════════════════════

  def place_order(token_id, side, price, size, type \\ "GTC") do
    signed_order = Auth.build_signed_order(token_id, side, price, size, type)

    Req.post!("#{@base_url}/order",
      json: signed_order,
      headers: Auth.l2_headers("POST", "/order", signed_order),
      connect_options: proxy_opts()
    ).body
  end

  def cancel_order(order_id) do
    Req.delete!("#{@base_url}/order/#{order_id}",
      headers: Auth.l2_headers("DELETE", "/order/#{order_id}"),
      connect_options: proxy_opts()
    ).body
  end

  # ══════════════════════════════════════════════
  # PROXY CONFIG
  # ══════════════════════════════════════════════

  defp proxy_opts do
    case trading_config()[:trading_proxy] do
      nil -> []
      "" -> []
      proxy_url -> [proxy: parse_proxy(proxy_url)]
    end
  end

  defp parse_proxy("socks5://" <> _ = url) do
    uri = URI.parse(url)
    {:socks5, String.to_charlist(uri.host), uri.port}
  end

  defp parse_proxy("http://" <> _ = url) do
    uri = URI.parse(url)
    {:http, String.to_charlist(uri.host), uri.port}
  end

  defp trading_config do
    Application.get_env(:weather_edge, WeatherEdge.Trading, [])
  end
end
```

**Configuration:**

```elixir
# config/runtime.exs
config :weather_edge, WeatherEdge.Trading,
  # Set to proxy URL if server is in the US
  # Set to nil if server is outside the US
  # Examples:
  #   "socks5://user:pass@your-eu-vps:1080"
  #   "http://user:pass@your-br-vps:8080"
  trading_proxy: System.get_env("TRADING_PROXY_URL"),
  private_key: System.get_env("POLYMARKET_PRIVATE_KEY"),
  api_key: System.get_env("POLYMARKET_API_KEY"),
  api_secret: System.get_env("POLYMARKET_API_SECRET"),
  api_passphrase: System.get_env("POLYMARKET_API_PASSPHRASE"),
  wallet_address: System.get_env("POLYMARKET_WALLET_ADDRESS"),
  chain_id: 137
```

---

## 6. Oban Job Schedule

Add/modify these cron entries:

```elixir
# In config
{Oban.Plugins.Cron, crontab: [
  # Existing: Event scanner (every minute 5:55-6:20 AM ET)
  {"55-59 9 * * *", WeatherEdge.Workers.EventScannerWorker, queue: :scanner},
  {"0-20 10 * * *", WeatherEdge.Workers.EventScannerWorker, queue: :scanner},
  # Note: 6:00 AM ET = 10:00 UTC (ET is UTC-4 in summer, UTC-5 in winter)
  # Adjust for current DST offset

  # NEW: Dutch position monitor (every 5 min)
  {"*/5 * * * *", WeatherEdge.Workers.DutchMonitorWorker, queue: :signals},

  # NEW: Dutch resolution checker (daily 11 PM ET = 3 AM UTC next day)
  {"0 3 * * *", WeatherEdge.Workers.DutchResolverWorker, queue: :cleanup},

  # Existing: keep other workers as-is
  {"*/15 * * * *", WeatherEdge.Workers.ForecastRefreshWorker, queue: :forecasts},
  {"*/5 * * * *", WeatherEdge.Workers.MispricingWorker, queue: :signals},
  {"*/5 * * * *", WeatherEdge.Workers.BalanceWorker, queue: :trading},
]}
```

---

## 7. Position Manager UI

### 7.1 Route

```elixir
# router.ex
live "/positions", PositionsLive, :index
```

Add to main navigation: `[Dashboard] [Signals] [Positions] [Settings]`

### 7.2 Page Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│  POSITIONS                                    Balance: $147.23 USDC     │
│                                                                          │
│  Open: 3 positions | Invested: $150 | Current Value: $287 | P&L: +$137  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─ SBGR — São Paulo — March 14 ─── Resolves in 2 days ──────────────┐ │
│  │                                                                     │ │
│  │  Strategy: DUTCHING (4 outcomes) | Coverage: 97%                    │ │
│  │                                                                     │ │
│  │  ┌─────────────────────────────────────────────────────────────┐   │ │
│  │  │  ██████████████████████████████████░░░░░  $159 / $50       │   │ │
│  │  │  ◄── invested ──►◄────── profit ──────►                    │   │ │
│  │  └─────────────────────────────────────────────────────────────┘   │ │
│  │                                                                     │ │
│  │  ┌──────────┬──────────┬──────────┬──────────┬───────────────┐    │ │
│  │  │ Outcome  │ Bought @ │ Now @    │ Tokens   │ Value Now     │    │ │
│  │  ├──────────┼──────────┼──────────┼──────────┼───────────────┤    │ │
│  │  │ 19°C YES │ $0.08    │ $0.02 ↓  │ 104.2    │ $2.08         │    │ │
│  │  │ 20°C YES │ $0.10    │ $0.14 ↑  │ 104.2    │ $14.58        │    │ │
│  │  │ 21°C YES │ $0.12    │ $0.22 ↑  │ 104.2    │ $22.92        │    │ │
│  │  │ 22°C+ YES│ $0.18    │ $1.15 ↑↑ │ 104.2    │ $119.83       │    │ │
│  │  ├──────────┼──────────┼──────────┼──────────┼───────────────┤    │ │
│  │  │ TOTAL    │ $50.00   │          │          │ $159.42       │    │ │
│  │  └──────────┴──────────┴──────────┴──────────┴───────────────┘    │ │
│  │                                                                     │ │
│  │  ┌─ SELL vs HOLD COMPARISON ──────────────────────────────────┐   │ │
│  │  │                                                             │   │ │
│  │  │  💰 SELL NOW                    📊 HOLD TO RESOLUTION      │   │ │
│  │  │  ───────────                    ──────────────────          │   │ │
│  │  │  Receive:  $159.42              Receive:  $104.17           │   │ │
│  │  │  Profit:   +$109.42             Profit:   +$54.17           │   │ │
│  │  │  Return:   +218.8%              Return:   +108.3%           │   │ │
│  │  │  Risk:     NONE (exit now)      Risk:     3% total loss     │   │ │
│  │  │                                                             │   │ │
│  │  │  [████ SELL ALL — LOCK IN $109 ████]                       │   │ │
│  │  │                                                             │   │ │
│  │  │  [  Hold to resolution  ]                                   │   │ │
│  │  │                                                             │   │ │
│  │  └─────────────────────────────────────────────────────────────┘   │ │
│  │                                                                     │ │
│  │  Forecast: GFS 23°C | ECMWF 23°C | ICON 22°C | JMA 23°C | GEM 23°C│ │
│  │  → Consensus: 23°C (in your covered range ✓)                       │ │
│  │                                                                     │ │
│  │  💡 Recommendation: SELL NOW — you get $109 profit by selling      │ │
│  │     vs $54 by holding. Selling gives MORE profit with ZERO risk.    │ │
│  │                                                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌─ EDDM — Munich — March 13 ─── Resolves tomorrow ──────────────────┐ │
│  │  ... (same card structure)                                          │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌─ HISTORY ─────────────────────────────────────────────────────────┐  │
│  │  [Expand ▼]                                                        │  │
│  │                                                                    │  │
│  │  ┌────────┬────────┬──────────┬───────────┬────────┬────────────┐ │  │
│  │  │ Date   │ Station│ Invested │ Result    │ P&L    │ Exit       │ │  │
│  │  ├────────┼────────┼──────────┼───────────┼────────┼────────────┤ │  │
│  │  │ Mar 11 │ SBGR   │ $50.00   │ 22°C+ ✅  │ +$54.17│ Resolution │ │  │
│  │  │ Mar 10 │ EDDM   │ $50.00   │ Sold 💰   │ +$72.30│ Sold early │ │  │
│  │  │ Mar 9  │ SBGR   │ $50.00   │ 18°C ❌   │ -$50.00│ Lost       │ │  │
│  │  │ Mar 8  │ KJFK   │ $50.00   │ 52°F ✅   │ +$48.90│ Resolution │ │  │
│  │  ├────────┼────────┼──────────┼───────────┼────────┼────────────┤ │  │
│  │  │ TOTAL  │        │ $200.00  │ Win: 75%  │+$125.37│            │ │  │
│  │  └────────┴────────┴──────────┴───────────┴────────┴────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌─ PERFORMANCE STATS ──────────────────────────────────────────────┐   │
│  │  Total P&L: +$125.37 | Win Rate: 75% | Avg Profit: +$62.69      │   │
│  │  Avg Hold: 2.3 days | Best: +$72.30 (EDDM sold early)           │   │
│  │  Sold Early: 40% of exits | Avg Extra Profit from Early Sell: +38%│  │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Position Card Component

Each open dutch group renders as a card with these sections:

**Header bar:**
- Station code + city + target date
- "Resolves in X days/hours" badge (red if < 6h)
- Strategy label + coverage percentage

**Progress bar:**
- Visual bar showing invested → current value
- Green fill for profit portion
- Numbers: "$159 / $50 invested"

**Outcome table:**
- One row per outcome in the dutch
- Columns: Outcome, Buy Price, Current Price (with ↑↓ arrows), Tokens, Current Value
- Total row at bottom
- Rows sorted by current value descending
- Price updates in real-time via PubSub (flash green/red on change)

**Sell vs Hold comparison:**
- Two columns side by side with clear numbers:
  - SELL NOW: receive amount, profit $, profit %, risk level
  - HOLD TO RESOLUTION: guaranteed payout, profit $, profit %, risk level
- The better option is highlighted with a larger, more prominent button
- If sell > hold: SELL button is large and green, HOLD is small and gray
- If hold > sell: HOLD button is large, SELL is small
- If urgent (forecast shifted): SELL button is RED and pulsing

**SELL ALL button:**
- Single click opens confirmation modal:
  ```
  ┌─ Confirm Sell ────────────────────────────┐
  │                                             │
  │  Selling all positions for SBGR March 14    │
  │                                             │
  │  You will receive: ~$159.42                 │
  │  Your profit: +$109.42 (+218.8%)            │
  │                                             │
  │  ⚠️ Final amounts may vary slightly due     │
  │  to orderbook depth and execution price.    │
  │                                             │
  │  [Cancel]  [████ CONFIRM SELL ████]         │
  └─────────────────────────────────────────────┘
  ```
- After confirmation: shows progress "Selling 1/4... 2/4... 3/4... Done ✓"
- On completion: card transitions to "SOLD" state with final P&L

**Forecast row:**
- Current forecast from each model
- Whether consensus is inside or outside covered range (✓ or ⚠️)

**Recommendation:**
- One-line text with emoji from DutchAdvisor
- Color-coded: green (hold), yellow (consider sell), red (sell urgent)

### 7.4 LiveView Implementation

```elixir
defmodule WeatherEdgeWeb.PositionsLive do
  use WeatherEdgeWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:price_update")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:new_position")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:sold")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:resolved")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "portfolio:balance_update")
    end

    open_positions = DutchGroups.list_open_with_orders()
    history = DutchGroups.list_closed(limit: 20)
    stats = DutchGroups.compute_performance_stats()
    balance = Trading.get_cached_balance()

    {:ok, assign(socket,
      open_positions: open_positions,
      history: history,
      stats: stats,
      balance: balance,
      selling: nil,           # nil | dutch_group_id being sold
      sell_progress: nil,     # nil | {completed, total}
      confirm_sell: nil,      # nil | dutch_group_id awaiting confirmation
      history_expanded: false
    )}
  end

  # ── Real-time price updates ──
  def handle_info({:dutch_price_update, group_id, updated_orders, recommendation}, socket) do
    # Update the specific position card with new prices and recommendation
    positions = update_position(socket.assigns.open_positions, group_id, updated_orders, recommendation)
    {:noreply, assign(socket, open_positions: positions)}
  end

  # ── New position from auto-buyer ──
  def handle_info({:dutch_new_position, position}, socket) do
    {:noreply, update(socket, :open_positions, fn pos -> [position | pos] end)}
  end

  # ── Position resolved ──
  def handle_info({:dutch_resolved, group_id, result}, socket) do
    # Move from open to history
    {:noreply, socket
      |> update(:open_positions, fn pos -> Enum.reject(pos, & &1.id == group_id) end)
      |> update(:history, fn hist -> [result | hist] end)
      |> assign(:stats, DutchGroups.compute_performance_stats())
    }
  end

  # ── User clicks SELL ──
  def handle_event("request_sell", %{"group_id" => id}, socket) do
    group = Enum.find(socket.assigns.open_positions, & &1.id == String.to_integer(id))
    {:noreply, assign(socket, confirm_sell: group)}
  end

  # ── User confirms sell ──
  def handle_event("confirm_sell", %{"group_id" => id}, socket) do
    group_id = String.to_integer(id)

    # Start async sell process
    Task.start(fn ->
      DutchSeller.sell_all_with_progress(group_id, fn progress ->
        send(self(), {:sell_progress, group_id, progress})
      end)
    end)

    {:noreply, assign(socket,
      confirm_sell: nil,
      selling: group_id,
      sell_progress: {0, count_orders(socket, group_id)}
    )}
  end

  # ── Sell progress updates ──
  def handle_info({:sell_progress, group_id, {:completed, n, total}}, socket) do
    {:noreply, assign(socket, sell_progress: {n, total})}
  end

  def handle_info({:sell_progress, group_id, {:done, result}}, socket) do
    {:noreply, socket
      |> assign(selling: nil, sell_progress: nil)
      |> update(:open_positions, fn pos -> Enum.reject(pos, & &1.id == group_id) end)
      |> update(:history, fn hist -> [result | hist] end)
      |> assign(:stats, DutchGroups.compute_performance_stats())
      |> put_flash(:info, "Sold! Profit: $#{result.actual_pnl}")
    }
  end

  def handle_event("cancel_sell", _, socket) do
    {:noreply, assign(socket, confirm_sell: nil)}
  end

  def handle_event("toggle_history", _, socket) do
    {:noreply, update(socket, :history_expanded, &not/1)}
  end
end
```

### 7.5 Component Tree

```
positions_live.ex
├── render/1
│   ├── header (balance, totals bar)
│   │
│   ├── for position <- @open_positions
│   │   └── dutch_position_card_component
│   │       ├── progress_bar
│   │       ├── outcome_table
│   │       ├── sell_hold_comparison
│   │       ├── forecast_row
│   │       └── recommendation_text
│   │
│   ├── if @confirm_sell → sell_confirmation_modal
│   │
│   ├── if @selling → sell_progress_indicator
│   │
│   ├── history_section (collapsible)
│   │   └── history_table
│   │
│   └── performance_stats_bar
```

---

## 8. PubSub Topics

```elixir
# Published by DutchMonitorWorker (every 5 min)
"dutch:price_update"  →  {group_id, updated_orders_with_prices, recommendation}

# Published by DutchBuyerWorker (on auto-buy)
"dutch:new_position"  →  {dutch_group_with_orders}

# Published by DutchSeller (on manual sell)
"dutch:sold"  →  {group_id, sell_result}

# Published by DutchResolverWorker (on resolution)
"dutch:resolved"  →  {group_id, resolution_result}

# Published by BalanceWorker (every 5 min)
"portfolio:balance_update"  →  {new_balance}
```

---

## 9. Deliverables

Build all of the following:

1. **Database migration** — `dutch_groups` table, `dutch_orders` table, station schema extensions
2. **DutchEngine** — outcome selection, allocation math, current value computation, exit strategy comparison
3. **DutchAdvisor** — sell/hold recommendation engine with all cases (sell_urgent, sell_now, consider_sell, hold)
4. **DutchBuyerWorker** — Oban worker triggered at event open, executes dutching orders via proxy
5. **DutchMonitorWorker** — Oban worker every 5 min, updates prices + recommendations for open positions
6. **DutchResolverWorker** — Oban worker daily, handles market resolution + P&L recording
7. **DutchSeller** — sell execution module with progress tracking, proxy routing
8. **ClobClient proxy support** — route only trading endpoints through configurable SOCKS5/HTTP proxy
9. **PositionsLive** — LiveView page with full position cards, sell/hold UI, history, stats
10. **DutchPositionCardComponent** — LiveComponent with progress bar, outcome table, sell/hold comparison, forecast, recommendation
11. **SellConfirmationModal** — modal with estimated proceeds, confirm/cancel
12. **Updated EventScannerWorker** — routes to DutchBuyerWorker when station.strategy == "dutch"
13. **Updated station card on dashboard** — show strategy selector (dutch/single/manual) and dutching config fields
14. **PubSub integration** — all workers broadcast updates, PositionsLive subscribes
15. **DutchGroups context** — Ecto queries for list_open, list_closed, compute_performance_stats

# PRD: Weather Edge Trading System

## Introduction

Weather Edge is an automated weather forecast trading system for Polymarket temperature markets, built with Elixir/Phoenix LiveView. It exploits a daily pricing inefficiency: when Polymarket creates new temperature events at 6:01 AM ET (for 3 days ahead), YES shares are underpriced at $0.10-$0.20. The system automatically identifies the most likely temperature outcome using multi-model weather forecasts, buys underpriced shares immediately, then tracks positions and recommends sell/hold decisions as prices converge toward fair value.

The system is designed for a solo trader running a self-hosted Docker Compose deployment, using TimescaleDB for time-series data and a pure Elixir implementation of the Polymarket CLOB trading client (EIP-712 + HMAC-SHA256 signing).

## Goals

- Automatically detect new Polymarket temperature events within 1 minute of creation (5:55-6:20 AM ET window)
- Fetch and ensemble 5 weather forecast models (GFS, ECMWF, ICON, JMA, GEM) to compute probability distributions
- Auto-buy the most likely temperature outcome when YES price is below a configurable threshold (default $0.20)
- Continuously detect mispricing between forecast probabilities and market prices, generating actionable signals
- Track all positions with real-time P&L and data-driven sell/hold recommendations
- Provide a real-time LiveView dashboard showing stations, events, positions, signals, and portfolio summary
- Calibrate forecast accuracy post-resolution to improve predictions over time
- Run as a self-contained Docker Compose stack (Elixir app + PostgreSQL/TimescaleDB)

## User Stories

### US-001: Project Bootstrap & Infrastructure
**Description:** As a developer, I need the Phoenix project scaffolded with all dependencies, database setup, and Docker Compose configuration so I can begin building features.

**Acceptance Criteria:**
- [ ] Phoenix 1.7+ project created with `weather_edge` name
- [ ] `mix.exs` includes dependencies: phoenix, phoenix_live_view, ecto_sql, postgrex, oban, req, ex_secp256k1, ex_abi, jason, timex
- [ ] `docker-compose.yml` with services: `app` (Elixir), `db` (TimescaleDB image)
- [ ] `Dockerfile` for the Elixir application (multi-stage build)
- [ ] Database config points to Docker TimescaleDB instance
- [ ] Oban configured with queues: scanner(5), forecasts(3), trading(2), signals(3), cleanup(1)
- [ ] `config/runtime.exs` reads all Polymarket env vars (POLYMARKET_PRIVATE_KEY, API_KEY, API_SECRET, API_PASSPHRASE, WALLET_ADDRESS)
- [ ] `.env.example` with all required environment variables documented
- [ ] `mix ecto.create && mix ecto.migrate` runs successfully against TimescaleDB
- [ ] `mix phx.server` boots without errors

### US-002: Database Schema & Migrations
**Description:** As a developer, I need the full database schema with TimescaleDB hypertables so all system data can be persisted.

**Acceptance Criteria:**
- [ ] Migration 001: `stations` table with all fields (code, city, lat/lng, country, wunderground_url, monitoring_enabled, auto_buy_enabled, max_buy_price, buy_amount_usdc, slug_pattern)
- [ ] Migration 002: `market_clusters` table with event_id (unique), event_slug, station_code FK, target_date, title, outcomes (JSONB), resolved, resolution_temp
- [ ] Migration 003: `market_snapshots` as TimescaleDB hypertable (partitioned by snapshot_at) with outcome_label, yes_price, no_price, volume
- [ ] Migration 004: `forecast_snapshots` as TimescaleDB hypertable (partitioned by fetched_at) with station_code, target_date, model, max_temp_c, hourly_temps (JSONB)
- [ ] Migration 005: `positions` table with all trading fields (station_code, market_cluster_id, outcome_label, side, token_id, tokens, avg_buy_price, total_cost_usdc, current_price, unrealized_pnl, status, recommendation, auto_bought, close_price, realized_pnl)
- [ ] Migration 006: `orders` table with position_id FK, order_id, token_id, side, price, size, usdc_amount, status, auto_order, error_message
- [ ] Migration 007: `signals` as TimescaleDB hypertable (partitioned by computed_at) with edge, model_probability, market_price, alert_level
- [ ] Migration 008: `forecast_accuracy` table with predicted_distribution (JSONB), actual_temp, model_errors (JSONB), resolution_correct
- [ ] All indexes created (idx_positions_open, idx_positions_station, idx_market_clusters_active, idx_market_clusters_station_date, idx_orders_pending)
- [ ] Corresponding Ecto schemas for all tables with proper types and associations
- [ ] Hypertable creation calls (`SELECT create_hypertable(...)`) execute in migrations

### US-003: Station Management (Context + METAR Validation)
**Description:** As a trader, I want to add weather stations by ICAO code so the system knows which locations to monitor for temperature events.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Stations` context with create, update, delete, list, get_by_code functions
- [ ] `WeatherEdge.Forecasts.MetarClient` validates ICAO codes via Aviation Weather API (`GET /api/data/metar?ids=CODE`)
- [ ] On valid ICAO: auto-resolves latitude, longitude, city, country from METAR response
- [ ] On invalid ICAO: returns `{:error, :invalid_station}` with user-friendly message
- [ ] New stations created with defaults: monitoring_enabled=true, auto_buy_enabled=false, max_buy_price=0.20, buy_amount_usdc=5.00
- [ ] slug_pattern auto-generated from city name (e.g., `"highest-temperature-in-sao-paulo-on-*"`)
- [ ] Station code stored uppercase and unique-constrained
- [ ] CRUD operations broadcast PubSub events for LiveView updates

### US-004: Gamma API Client (Market Discovery)
**Description:** As a developer, I need an HTTP client to discover and parse Polymarket temperature events from the Gamma API.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Markets.GammaClient` module using Req
- [ ] `get_events/1` fetches `GET /events?active=true&closed=false` with optional filters
- [ ] `search_events/1` searches by query string
- [ ] `get_event_by_slug/1` fetches a specific event
- [ ] `WeatherEdge.Markets.EventParser` extracts from raw event JSON: event_id, slug, title, target_date, station_code, and array of market outcomes (question, outcome_label, yes_price, no_price, clob_token_ids, volume)
- [ ] Parser correctly identifies temperature degree from market question (e.g., "27 degrees C" -> "27C")
- [ ] Parser handles edge bucket outcomes ("26C or below", "34C or higher")
- [ ] Handles API errors and timeouts gracefully (returns `{:error, reason}`)
- [ ] Results stored as `MarketCluster` records via `WeatherEdge.Markets` context

### US-005: Open-Meteo Multi-Model Forecast Client
**Description:** As a developer, I need to fetch temperature forecasts from 5 weather models via Open-Meteo to compute probability distributions.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Forecasts.OpenMeteoClient` module using Req
- [ ] Fetches hourly temperature_2m data for models: gfs, ecmwf_ifs, icon_global, jma, gem_global
- [ ] Accepts latitude, longitude, and forecast_days parameters
- [ ] Extracts daily maximum temperature from each model's hourly data for a given target_date
- [ ] Returns `%{model_name => max_temp}` map (e.g., `%{"gfs" => 28.3, "ecmwf_ifs" => 27.8}`)
- [ ] Stores results as `ForecastSnapshot` records in TimescaleDB
- [ ] Handles partial model failures (some models unavailable) — returns available data
- [ ] Handles API errors and timeouts gracefully

### US-006: Probability Engine with Gaussian Smoothing
**Description:** As a developer, I need a probability engine that takes multi-model forecasts and produces a probability distribution across temperature outcomes.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Probability.Engine` module with `compute_distribution/2` accepting station and target_date
- [ ] Rounds each model's max temp to integer (Polymarket uses whole degrees)
- [ ] Builds empirical distribution from model frequency counts
- [ ] `WeatherEdge.Probability.Gaussian` applies Gaussian kernel smoothing with sigma varying by days-out (<=1 day: 0.8, 2 days: 1.2, 3+ days: 1.8)
- [ ] Handles edge buckets: collapses tails below lower_bound and above upper_bound into "X or below" / "X or higher" buckets
- [ ] Normalizes final distribution to sum = 1.0
- [ ] `WeatherEdge.Probability.Distribution` struct holds `%{outcome_label => probability}` with helper functions (top_outcome, top_n, probability_for)
- [ ] Returns correct distribution for test cases (e.g., 5 models predicting [28, 28, 27, 28, 27] should give ~60% for 28, ~40% for 27 before smoothing)

### US-007: CLOB API Client (Prices + Orderbook)
**Description:** As a developer, I need an HTTP client to read prices and orderbook data from Polymarket's CLOB API.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Trading.ClobClient` module using Req
- [ ] `get_price/2` fetches `GET /price?token_id=TOKEN&side=buy` — returns float price
- [ ] `get_orderbook/1` fetches `GET /book?token_id=TOKEN` — returns bids/asks with price and size
- [ ] `get_market/1` fetches market info by condition_id
- [ ] All public endpoints work without authentication
- [ ] Handles API errors and timeouts gracefully

### US-008: EIP-712 + HMAC Authentication for Trading
**Description:** As a developer, I need the Polymarket authentication system implemented in pure Elixir so the system can place and cancel orders.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Trading.Auth` module handles both L1 and L2 authentication
- [ ] L1: EIP-712 struct hashing and signing using `ex_secp256k1` and `ex_abi`
- [ ] L2: HMAC-SHA256 request signing using API credentials (api_key, api_secret, api_passphrase)
- [ ] Signs order structs compatible with Polymarket's CTF exchange contract on Polygon (chain_id: 137)
- [ ] `sign_order/1` produces valid EIP-712 signature for order placement
- [ ] `sign_request/3` produces HMAC headers for authenticated L2 API calls
- [ ] Credentials loaded from environment variables (never hardcoded)
- [ ] Private key stored only in memory after loading from env

### US-009: Order Execution & Management
**Description:** As a developer, I need the ability to place, track, and cancel orders on Polymarket so the system can trade.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Trading.ClobClient` extended with authenticated endpoints:
  - `place_order/5` (token_id, side, price, size, type \\ "GTC") via `POST /order`
  - `cancel_order/1` via `DELETE /order`
  - `get_open_orders/0` via `GET /orders`
- [ ] `WeatherEdge.Trading.OrderManager` orchestrates order lifecycle:
  - Validates balance >= order amount + $2 reserve
  - Checks no duplicate order for same event+station
  - Places order, stores in `orders` table with status "pending"
  - Tracks fill status and updates to "filled", "cancelled", or "failed"
- [ ] On fill: creates/updates corresponding `Position` record
- [ ] Rate limiting: max 1 order per 10 seconds per station
- [ ] Failed orders retry once after 30 seconds, then alert user
- [ ] All orders logged with timestamps for audit trail
- [ ] PubSub broadcasts on order placed, filled, failed

### US-010: Data API Client (Positions + Balance)
**Description:** As a developer, I need to read wallet positions and USDC balance from Polymarket's Data API.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Trading.DataClient` module using Req
- [ ] `get_positions/1` fetches open positions for wallet address
- [ ] `get_activity/1` fetches trade history
- [ ] `get_balance/1` fetches USDC balance
- [ ] Wallet address loaded from config/env
- [ ] Results used to reconcile local position records with on-chain state

### US-011: Event Scanner Worker
**Description:** As a trader, I want the system to automatically detect new temperature events on Polymarket every minute around 6:01 AM ET so I never miss an opportunity.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.EventScannerWorker` implements `Oban.Worker`
- [ ] Oban cron: runs every minute from 5:55-6:20 AM ET (`"55-59 5 * * *"` and `"0-20 6 * * *"`)
- [ ] For each station with `monitoring_enabled = true`: queries Gamma API, filters by slug_pattern or city name
- [ ] Detects new events not already in `market_clusters` table
- [ ] Parses and stores new events as `MarketCluster` records
- [ ] Broadcasts `{:new_event, station_code, event}` via PubSub
- [ ] If station has `auto_buy_enabled = true`: enqueues `AutoBuyerWorker`
- [ ] Handles API failures without crashing (logs error, retries next minute)

### US-012: Auto-Buyer Worker
**Description:** As a trader, I want the system to automatically buy the most likely temperature outcome when a new event opens at a low price.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.AutoBuyerWorker` implements `Oban.Worker` (queue: :trading)
- [ ] Triggered by EventScanner with `{station_code, event_id}` args
- [ ] Fetches multi-model forecasts for station + target_date
- [ ] Runs probability engine to determine most likely outcome
- [ ] Checks current YES price via CLOB API
- [ ] If YES price <= station.max_buy_price: places buy order via OrderManager
- [ ] If YES price > max_buy_price: logs skip reason, broadcasts `:auto_buy_skipped`
- [ ] Safety guards enforced:
  - Never buy if USDC balance < buy_amount + $2
  - Never buy if order for same event+station already exists
  - Maximum 1 auto-buy per event per station
- [ ] Also checks for secondary opportunities (other temperatures with YES < max_buy_price AND model_prob > 20%) and flags as alerts (no auto-buy)
- [ ] Broadcasts `:auto_buy_executed` with details on success

### US-013: Forecast Refresh Worker
**Description:** As a trader, I want forecasts refreshed every 15 minutes so the probability engine always uses current data.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.ForecastRefreshWorker` implements `Oban.Worker` (queue: :forecasts)
- [ ] Oban cron: `"*/15 * * * *"`
- [ ] For each station with active (unresolved) market clusters: fetches fresh multi-model forecasts
- [ ] Stores snapshots in `forecast_snapshots` hypertable
- [ ] Broadcasts forecast updates via PubSub for LiveView refresh

### US-014: Mispricing Detection Worker
**Description:** As a trader, I want the system to continuously compare forecast probabilities against market prices and alert me to profitable opportunities.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.MispricingWorker` implements `Oban.Worker` (queue: :signals)
- [ ] Oban cron: `"*/5 * * * *"`
- [ ] For each active market cluster: runs probability engine, fetches current market prices
- [ ] `WeatherEdge.Signals.Detector` calculates edge for each outcome: `edge = model_prob - market_yes_price`
- [ ] Generates signals with alert levels:
  - edge >= 0.08 AND liquidity > $20: OPPORTUNITY
  - edge >= 0.15 AND liquidity > $20: STRONG SIGNAL
  - edge >= 0.25: EXTREME
- [ ] "Safe NO" detection: model_prob < 0.05 AND market_no_price <= 0.92 -> flags as safe NO opportunity
- [ ] Structural check: if sum of all YES prices across cluster differs from 1.0 by > 0.05, flags STRUCTURAL MISPRICING
- [ ] Stores signals in `signals` hypertable
- [ ] Broadcasts signals via PubSub (`WeatherEdge.Signals.Alerter`)

### US-015: Price Snapshot Worker
**Description:** As a developer, I need periodic price snapshots stored in TimescaleDB to power historical charts and P&L tracking.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.PriceSnapshotWorker` implements `Oban.Worker` (queue: :signals)
- [ ] Oban cron: `"*/5 * * * *"`
- [ ] For each tracked market (positions + monitored clusters): fetches YES/NO prices from CLOB
- [ ] Stores in `market_snapshots` hypertable with timestamp
- [ ] Used by dashboard for forecast evolution and price history charts

### US-016: Position Monitor Worker (Sell/Hold Recommendations)
**Description:** As a trader, I want data-driven recommendations on whether to sell or hold my positions based on current forecasts, price movement, and time to resolution.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.PositionMonitorWorker` implements `Oban.Worker` (queue: :signals)
- [ ] Oban cron: `"*/10 * * * *"`
- [ ] `WeatherEdge.Trading.PositionTracker` calculates for each open position:
  - current_price from CLOB
  - unrealized_pnl and unrealized_pnl_pct
  - model_prob from latest forecast
  - days_until_resolution
- [ ] Recommendation logic implemented:
  - pnl >= 100% AND prob < 0.40: "SELL NOW" (take profit, forecast shifting)
  - pnl >= 75% AND days <= 1: "CONSIDER SELLING" (good profit, resolution soon)
  - pnl >= 50% AND prob > 0.50: "HOLD" (forecast favorable)
  - pnl < 20% AND prob < 0.20: "CUT LOSS" (sell before drop)
  - prob > 0.60 AND days == 0: "HOLD TO RESOLUTION" (strong chance of $1 payout)
  - DEFAULT: "MONITORING"
- [ ] Updates position.recommendation and position.current_price in database
- [ ] Broadcasts position updates via PubSub

### US-017: Balance Worker
**Description:** As a trader, I want my USDC balance displayed and refreshed automatically on the dashboard.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.BalanceWorker` implements `Oban.Worker` (queue: :trading)
- [ ] Oban cron: `"*/5 * * * *"`
- [ ] Fetches USDC balance from Data API for configured wallet
- [ ] Broadcasts via PubSub for dashboard header update

### US-018: Resolution Worker (Post-Event Processing)
**Description:** As a trader, I want resolved events processed automatically so my P&L is accurate and forecast accuracy is tracked.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Workers.ResolutionWorker` implements `Oban.Worker` (queue: :cleanup)
- [ ] Oban cron: `"0 23 * * *"` (daily at 11 PM ET)
- [ ] Checks which market_clusters have resolved (target_date has passed)
- [ ] Fetches actual temperature from Weather Underground resolution page
- [ ] Updates market_cluster: resolved=true, resolution_temp=actual
- [ ] Updates positions: status to resolved_win or resolved_loss, calculates realized_pnl
- [ ] `WeatherEdge.Calibration.Resolver` compares predicted_distribution vs actual_temp
- [ ] Stores per-model errors in `forecast_accuracy` table
- [ ] `WeatherEdge.Calibration.BiasTracker` tracks per-station, per-model accuracy stats

### US-019: LiveView Dashboard — Main Layout
**Description:** As a trader, I want a real-time dashboard showing all my stations, events, positions, and signals at a glance.

**Acceptance Criteria:**
- [ ] `WeatherEdgeWeb.DashboardLive` mounted at `/` route
- [ ] `HeaderComponent` shows USDC balance, truncated wallet address, "Add Station" button, "Settings" link
- [ ] Layout renders list of station cards, signal feed, and portfolio summary
- [ ] All components subscribe to relevant PubSub topics and update in real-time (no page refresh needed)
- [ ] Responsive layout works on desktop screens
- [ ] Verify in browser using dev-browser skill

### US-020: LiveView — Station Card Component
**Description:** As a trader, I want each station displayed as a card with monitoring controls and its associated events.

**Acceptance Criteria:**
- [ ] `StationCardComponent` shows: station code, city name, monitoring toggle, auto-buy toggle
- [ ] Displays max_buy_price and buy_amount_usdc (editable inline)
- [ ] Shows current USDC balance
- [ ] Lists next expected event opening time
- [ ] Contains nested `EventCardComponent` for each active event
- [ ] Toggle clicks update station via PubSub (no page reload)
- [ ] Verify in browser using dev-browser skill

### US-021: LiveView — Event Card Component
**Description:** As a trader, I want each event displayed with my position, current forecast, and sell/hold recommendation.

**Acceptance Criteria:**
- [ ] `EventCardComponent` shows: target date, days until resolution, position details (outcome, tokens, buy price, current price, P&L %)
- [ ] Color-coded P&L: green for profit, red for loss
- [ ] Shows current forecast consensus (top 2 outcomes with probabilities)
- [ ] Displays recommendation text from PositionTracker
- [ ] SELL and HOLD action buttons (SELL triggers order placement confirmation)
- [ ] For newly auto-bought events: shows flash indicator with purchase details
- [ ] Verify in browser using dev-browser skill

### US-022: LiveView — Signal Feed Component
**Description:** As a trader, I want a real-time feed of mispricing signals so I can act on opportunities.

**Acceptance Criteria:**
- [ ] `SignalFeedComponent` shows chronological list of signals
- [ ] Each signal shows: timestamp, station code, outcome, price, edge %, alert level
- [ ] Color-coded by alert level (yellow=opportunity, orange=strong, red=extreme, green=safe NO)
- [ ] Auto-buy execution events shown with flash icon
- [ ] New signals appear at top without page refresh (PubSub subscription)
- [ ] Scrollable with max ~50 visible signals
- [ ] Verify in browser using dev-browser skill

### US-023: LiveView — Portfolio Summary Component
**Description:** As a trader, I want a summary bar showing my overall portfolio performance.

**Acceptance Criteria:**
- [ ] `PortfolioSummaryComponent` shows: open position count, total invested, current value, unrealized P&L (amount + %), today's resolved P&L, total realized P&L
- [ ] Updates in real-time via PubSub
- [ ] Verify in browser using dev-browser skill

### US-024: LiveView — Add Station Modal
**Description:** As a trader, I want to add new stations via a modal dialog by entering an ICAO code.

**Acceptance Criteria:**
- [ ] `AddStationModalComponent` triggered by "Add Station" button in header
- [ ] Text input for ICAO code (auto-uppercase, max 4 chars)
- [ ] On submit: validates via METAR API, shows loading state
- [ ] On valid: shows resolved station info (city, country, coordinates), confirm button
- [ ] On invalid: shows error message
- [ ] On confirm: creates station, closes modal, new station card appears in dashboard
- [ ] Verify in browser using dev-browser skill

### US-025: LiveView — Station Detail View
**Description:** As a trader, I want an expanded view for each station/event showing detailed forecast data, orderbook, and price history.

**Acceptance Criteria:**
- [ ] `WeatherEdgeWeb.StationDetailLive` mounted at `/stations/:code/events/:event_id`
- [ ] Temperature distribution bar chart: model probability (blue) vs market price (orange) per degree
- [ ] Model breakdown table: each model's predicted max temp
- [ ] Market cluster health: sum of all YES prices with warning if far from 1.0
- [ ] Orderbook display: best bid/ask with sizes and spread
- [ ] Forecast evolution line chart (from TimescaleDB snapshots) showing how consensus shifted over time
- [ ] Current METAR observation for the station
- [ ] SELL POSITION and BUY MORE action buttons
- [ ] Back navigation to dashboard
- [ ] Verify in browser using dev-browser skill

### US-026: PubSub Integration
**Description:** As a developer, I need a PubSub topic structure that connects all workers to LiveView components for real-time updates.

**Acceptance Criteria:**
- [ ] Topics defined and used consistently:
  - `"station:#{code}:new_event"` — new event detected
  - `"station:#{code}:forecast_update"` — fresh forecast data
  - `"station:#{code}:price_update"` — price snapshot taken
  - `"station:#{code}:auto_buy"` — auto-buy executed or skipped
  - `"station:#{code}:signal"` — mispricing signal generated
  - `"portfolio:balance_update"` — USDC balance changed
  - `"portfolio:position_update"` — position P&L updated
- [ ] All workers broadcast to appropriate topics
- [ ] All LiveView components subscribe on mount and handle messages

### US-027: Calibration System
**Description:** As a trader, I want the system to track forecast accuracy over time so predictions improve and I can see which models perform best per station.

**Acceptance Criteria:**
- [ ] `WeatherEdge.Calibration.Resolver` runs post-resolution: compares predicted distribution vs actual temperature
- [ ] Stores per-model absolute error in `forecast_accuracy.model_errors` JSONB
- [ ] `WeatherEdge.Calibration.BiasTracker` computes running stats per station per model (mean error, MAE, hit rate)
- [ ] `resolution_correct` flag set based on whether top prediction matched actual
- [ ] Auto-buy outcome tracked (win/loss/sold_early) with realized P&L
- [ ] Gaussian sigma can be adjusted over time based on historical accuracy (future improvement, not required for v1)

### US-028: Core Module Tests
**Description:** As a developer, I need tests for critical business logic to ensure correctness and prevent regressions.

**Acceptance Criteria:**
- [ ] `test/weather_edge/markets/gamma_client_test.exs` — tests event parsing with mock responses
- [ ] `test/weather_edge/forecasts/open_meteo_client_test.exs` — tests multi-model data extraction with mock responses
- [ ] `test/weather_edge/probability/engine_test.exs` — tests distribution computation, Gaussian smoothing, tail collapsing, normalization
- [ ] `test/weather_edge/signals/detector_test.exs` — tests edge calculation, alert level classification, safe NO detection, structural mispricing
- [ ] `test/weather_edge/trading/order_manager_test.exs` — tests safety guards (balance check, duplicate prevention, rate limiting)
- [ ] `test/weather_edge_web/live/dashboard_live_test.exs` — tests LiveView renders stations, handles PubSub updates
- [ ] All tests pass with `mix test`

## Functional Requirements

- FR-1: The system must allow the user to add stations by ICAO code, validating via Aviation Weather METAR API
- FR-2: The system must auto-resolve station coordinates, city, and country from the ICAO code
- FR-3: The system must scan Polymarket Gamma API every minute from 5:55-6:20 AM ET for new temperature events matching registered stations
- FR-4: The system must parse temperature events into structured market clusters with individual temperature outcome markets
- FR-5: The system must fetch hourly forecasts from 5 weather models (GFS, ECMWF, ICON, JMA, GEM) via Open-Meteo API
- FR-6: The system must extract daily maximum temperature from each model's hourly data
- FR-7: The system must compute a probability distribution across temperature outcomes using empirical model frequencies with Gaussian kernel smoothing
- FR-8: The system must adjust Gaussian sigma based on days until resolution (0.8 for <=1 day, 1.2 for 2 days, 1.8 for 3+ days)
- FR-9: The system must handle edge bucket outcomes ("X or below", "X or higher") by collapsing distribution tails
- FR-10: The system must auto-buy YES shares for the most likely temperature when price <= configured max_buy_price
- FR-11: The system must enforce safety guards: minimum $2 USDC reserve, no duplicate orders per event, max 1 auto-buy per event per station, rate limit of 1 order per 10 seconds
- FR-12: The system must authenticate with Polymarket CLOB API using EIP-712 signatures (L1) and HMAC-SHA256 (L2)
- FR-13: The system must calculate mispricing edge as the difference between model probability and market YES price
- FR-14: The system must generate signals at three alert levels: OPPORTUNITY (edge >= 0.08), STRONG (edge >= 0.15), EXTREME (edge >= 0.25)
- FR-15: The system must detect "Safe NO" opportunities where model_prob < 0.05 and NO price <= 0.92
- FR-16: The system must detect structural mispricing when sum of YES prices across a cluster deviates from 1.0 by > 0.05
- FR-17: The system must calculate unrealized P&L for all open positions and generate sell/hold recommendations based on P&L %, model probability, and days to resolution
- FR-18: The system must display a real-time LiveView dashboard with station cards, event cards, signal feed, and portfolio summary
- FR-19: The system must allow toggling monitoring and auto-buy per station from the dashboard
- FR-20: The system must allow selling positions from the dashboard (with confirmation)
- FR-21: The system must store price and forecast snapshots in TimescaleDB hypertables for historical analysis
- FR-22: The system must resolve events daily at 11 PM ET, fetching actual temperature and updating positions/accuracy
- FR-23: The system must track per-station, per-model forecast accuracy for calibration

## Non-Goals

- No multi-user or authentication system (single trader, single wallet)
- No mobile-optimized or native mobile UI
- No automated selling (only recommendations; user must click SELL)
- No support for non-temperature Polymarket markets
- No historical backfilling of past events
- No Fahrenheit support in the probability engine (Polymarket uses Celsius for non-US stations; US station handling deferred)
- No WebSocket connection to CLOB for real-time order status (polling is sufficient for v1)
- No automated Gaussian sigma tuning from calibration data (manual adjustment only in v1)
- No email/SMS/push notification alerts (dashboard-only signals)
- No profit withdrawal or wallet management features
- No strategy backtesting engine

## Technical Considerations

- **Elixir/Phoenix 1.7+** with LiveView for real-time dashboard updates via WebSocket
- **PostgreSQL with TimescaleDB extension** for time-series data (market snapshots, forecast snapshots, signals)
- **Oban** for reliable job scheduling with cron-based workers and queue management
- **Req** as HTTP client for all external API calls (Gamma, CLOB, Data, Open-Meteo, METAR)
- **ex_secp256k1 + ex_abi** for pure Elixir EIP-712 signing (Polymarket CLOB authentication)
- **Docker Compose** deployment with two services: Elixir app + TimescaleDB
- **PubSub** (Phoenix.PubSub) for decoupling workers from LiveView components
- All Polymarket credentials stored as environment variables, loaded in `runtime.exs`
- Private key held only in memory after boot (never logged or persisted to disk)
- TimescaleDB hypertables used for `market_snapshots`, `forecast_snapshots`, and `signals` tables
- Timezone handling: Oban cron schedules in ET (America/New_York); use Timex for timezone conversions
- Rate limiting must be enforced in OrderManager to avoid Polymarket API bans
- Open-Meteo API is free with no API key; respect their fair-use rate limits

## Success Metrics

- New temperature events detected within 2 minutes of creation on Polymarket
- Auto-buy orders placed within 3 minutes of event detection (when enabled)
- Forecast probability distribution computed and available within 1 minute of forecast fetch
- Mispricing signals generated within 5 minutes of price or forecast changes
- Dashboard updates in real-time (< 1 second latency from PubSub broadcast to UI update)
- System runs continuously without manual intervention via Docker Compose
- Positive realized P&L over 30-day rolling window (measured post-resolution)
- Forecast accuracy: top predicted temperature matches actual >= 40% of the time

## Open Questions

1. How should the system handle Polymarket events that use Fahrenheit (US stations)? Should the probability engine support both units?
2. What is the exact format of Polymarket's EIP-712 order struct? Need to verify against py-clob-client source code.
3. Should the auto-buyer support buying multiple temperature outcomes per event (e.g., top 2 most likely) or strictly one?
4. How should the system handle Weather Underground scraping for resolution data — is there a structured API, or is HTML parsing required?
5. What happens if the CLOB API is down during the 6:01 AM auto-buy window? Should the system queue and retry, or alert the user to manually trade?
6. Should the calibration system eventually feed back into the probability engine (e.g., weighting models by historical accuracy)?
7. What is the minimum USDC balance to start using the system effectively?

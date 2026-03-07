# PRD: Signals Intelligence Page

## Introduction

A dedicated trading operations page at `/signals` for the WeatherEdge system. This is the primary place where the user analyzes, filters, compares, and acts on mispricing signals detected by the forecast engine. It replaces the passive signal feed with a full-featured trading desk featuring three view modes (Table, Grouped, Heatmap), a slide-in detail panel with charts, real-time PubSub updates, and batch buy execution via the existing CLOB/Gamma trading clients.

The existing `/analytics` page remains unchanged. This is a new separate page.

## Goals

- Provide a single page where the user can see all active signals across all stations and dates
- Enable filtering and sorting signals by station, edge, date, side, alert level, price, and position status
- Offer three complementary views: flat Table (default), Grouped by event, and Heatmap overview
- Show full signal context in a detail panel: cluster distribution, model breakdown, edge/price history charts, orderbook, METAR, and position data
- Allow batch selection and execution of real buy orders from the page
- Display real-time signal and price updates via PubSub
- Track signal performance with historical accuracy and P&L stats

## User Stories

### US-001: Create SignalsLive route and page skeleton
**Description:** As a user, I want to navigate to `/signals` from the header so I can access the signals intelligence page.

**Acceptance Criteria:**
- [ ] Route `/signals` added to router, renders `SignalsLive`
- [ ] Header navigation includes "Signals" link between Dashboard and Analytics
- [ ] Page renders with header (balance, wallet address), empty filter bar, and empty content area
- [ ] PubSub subscriptions established on mount: `signals:new`, `portfolio:balance_update`, `portfolio:position_update`
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-002: Build Signals.Queries module for filtered signal loading
**Description:** As a developer, I need a query module that loads signals with joins to market_clusters, stations, and positions, applying dynamic filters.

**Acceptance Criteria:**
- [ ] `Signals.Queries.list_filtered_signals(filters, opts)` returns signal rows with cluster, station, and position data
- [ ] `Signals.Queries.count_filtered_signals(filters)` returns total count for "Showing X of Y"
- [ ] Filters supported: stations (list), min_edge (float), resolution_date (string), side (string), max_price (float), alert_level (string), actionable_only (boolean), has_position (string)
- [ ] Sort options: edge_desc, edge_asc, model_prob_desc, time_to_resolution, price_asc, newest
- [ ] Only returns signals for unresolved clusters (`mc.resolved == false`)
- [ ] Deduplicates signals (latest per station_code + outcome_label + market_cluster_id)
- [ ] Pagination via limit/offset
- [ ] Compiles without warnings

### US-003: Build Filter Bar component
**Description:** As a user, I want to filter signals by station, edge, date, side, price, and alert level so I can find the best opportunities quickly.

**Acceptance Criteria:**
- [ ] Station multi-select dropdown showing active stations with signal count each
- [ ] Edge range slider (0-60%, default 8%) with current value display
- [ ] Resolution date dropdown: "All dates", "Today", "Tomorrow", "+2d", "+3d" (dynamic from active events)
- [ ] Side dropdown: All / YES / NO
- [ ] Max price input (optional, e.g., 0.25)
- [ ] Alert level dropdown: All / Extreme / Strong / Opportunity / Safe NO
- [ ] Sort dropdown: Highest Edge / Lowest Price / Highest Model Prob / Soonest Resolution / Newest
- [ ] Actionable Only toggle (filters to price <= station's max_buy_price)
- [ ] Has Position filter: All / With Position / Without Position
- [ ] "Active: N filters | Showing X of Y signals | [Clear All]" status line
- [ ] Filter changes trigger `phx-change` event, re-query signals, reset pagination
- [ ] Filter bar is sticky at top of page
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-004: Build Table View (default view)
**Description:** As a user, I want to see signals in a sortable table with columns for time, station, outcome, resolution, action, alert level, confidence, market price, model probability, edge, volume, trend, and position status.

**Acceptance Criteria:**
- [ ] Columns: checkbox, Time (HH:MM), Station (ICAO), Temp (outcome_label), Resolves (hours), Action (BUY YES/NO/BOUGHT), Alert (color badge), Confidence, Market ($), Model (%), Edge (%), Volume ($), Trend (arrow + delta), Position (token count or dash)
- [ ] Rows are clickable (opens detail panel)
- [ ] Checkbox per row for batch selection
- [ ] Station code clickable (filters to that station)
- [ ] Edge column bold + colored: green if >15%, yellow if >8%
- [ ] "Resolves" shows hours remaining, red if <6h, "Today" badge if resolves today
- [ ] "BOUGHT" purple badge if open position exists for that outcome
- [ ] "Show more" button loads next 20 signals (paginated)
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-005: Build Trend column data from market_snapshots
**Description:** As a user, I want to see price direction over the last 3-6 hours so I can tell if an opportunity is growing or closing.

**Acceptance Criteria:**
- [ ] `MarketSnapshots.price_trend(cluster_id, outcome_label, hours: 6)` returns `{direction, delta}` where direction is :up, :down, or :flat
- [ ] Direction computed from oldest vs newest snapshot in the window
- [ ] Displayed as arrow + delta: "up +$0.08", "down -$0.03", "flat $0.00"
- [ ] Gracefully handles missing snapshots (shows "-")
- [ ] Compiles without warnings

### US-006: Build Grouped View
**Description:** As a user, I want to see signals grouped by event (station + date) with best play, hedge options, and cluster health so I can evaluate entire events at once.

**Acceptance Criteria:**
- [ ] `Signals.GroupedView.group_signals_by_event(signals)` groups by {station_code, market_cluster_id}
- [ ] Each group card shows: station, city, target date, hours to resolution
- [ ] Cluster Health: sum of YES prices with warning if deviation > 5%
- [ ] Forecast Consensus: how many models agree on the predicted temperature
- [ ] "BEST PLAY" section: highest-edge YES signal with payout calculation
- [ ] "HEDGE OPTIONS" section: Safe NO signals sorted by edge
- [ ] "OTHER" section: remaining signals
- [ ] Group actions: "BUY BEST", "BUY BEST + HEDGE", "VIEW FULL CLUSTER"
- [ ] Groups sorted by soonest resolution first
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-007: Build Heatmap View
**Description:** As a user, I want a grid overview showing best edge per station per date so I can instantly spot where opportunities exist.

**Acceptance Criteria:**
- [ ] `Signals.HeatmapData.build_heatmap()` returns grid data: station rows x date columns (today through +3d)
- [ ] Each cell shows best available edge for that station+date
- [ ] Color intensity based on edge: gray (<8%), light green (8-15%), medium green (15-25%), dark green/red (25%+)
- [ ] Empty cell if no event exists for that station+date
- [ ] Position indicator (dot) if user has open position for that cell
- [ ] Click cell filters table view to that station+date
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-008: Build Signal Detail Panel (slide-in)
**Description:** As a user, I want to click a signal row and see full context in a slide-in panel: cluster distribution, model breakdown, orderbook, METAR, position, and buy controls.

**Acceptance Criteria:**
- [ ] Panel slides in from right, covers ~40% screen width
- [ ] Closeable with X button or clicking outside
- [ ] Header: station, outcome, date, edge, alert level, confidence
- [ ] Cluster distribution: horizontal bar chart showing model prob (blue) vs market price (orange) for ALL temperature outcomes in the cluster
- [ ] Model breakdown: per-model max temperature with consensus count
- [ ] Orderbook: best bid, best ask, spread, depth
- [ ] METAR section (if resolves today): current temp, max recorded today
- [ ] Position section (if exists): tokens, avg price, current price, P&L
- [ ] "Open on Polymarket" link
- [ ] Data fetched on panel open (not pre-loaded)
- [ ] `Signals.DetailData.fetch_signal_detail(signal_id)` assembles all data
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-009: Add charts to Detail Panel via JS hooks
**Description:** As a user, I want to see edge history and price history charts in the detail panel so I can understand signal momentum.

**Acceptance Criteria:**
- [ ] Chart.js (or lightweight alternative) loaded via JS hook
- [ ] Edge History chart: line chart of edge % over last 24h, time on X, edge on Y
- [ ] Price History chart: line chart of YES price since event opened, buy price marker if position exists
- [ ] Cluster Distribution chart: horizontal bar chart with dual series (model blue, market orange)
- [ ] `Signals.edge_history(station_code, cluster_id, outcome_label, hours: 24)` query implemented
- [ ] `MarketSnapshots.price_history(cluster_id, outcome_label, hours: 48)` query implemented
- [ ] Charts update when detail panel data changes
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-010: Build Quick Actions Bar with batch buy
**Description:** As a user, I want to select multiple signals and execute buy orders for all of them at once.

**Acceptance Criteria:**
- [ ] Sticky bar at bottom of page, always visible
- [ ] Shows: balance, selected count, total cost, "BUY ALL N" button
- [ ] Cost calculated as sum of each selected signal's station `buy_amount_usdc`
- [ ] Validation before buy: sufficient balance (minus reserve), no duplicate positions, max 10 per batch
- [ ] Buy executes real orders via existing `Trading.OrderManager` / CLOB client
- [ ] Progress indicator: "Buying 1/3... 2/3... Done"
- [ ] Failed orders show error inline
- [ ] After completion, selected signals show "BOUGHT" badge
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-011: Build buy controls in Detail Panel
**Description:** As a user, I want to buy directly from the detail panel with a configurable amount.

**Acceptance Criteria:**
- [ ] Amount input field (defaults to station's `buy_amount_usdc`)
- [ ] Shows: estimated tokens, payout if wins, return percentage
- [ ] "BUY YES $X" and "BUY NO $X" buttons
- [ ] Executes real order via existing trading clients
- [ ] Success/error flash message after execution
- [ ] Position section updates after successful buy
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-012: Build Performance Tracker section
**Description:** As a user, I want to see historical signal accuracy and P&L at the bottom of the page so I can evaluate my system's performance.

**Acceptance Criteria:**
- [ ] Collapsible section at bottom of page (collapsed by default)
- [ ] `Signals.Performance.compute_stats(days: 30)` returns accuracy, P&L, breakdowns
- [ ] Summary stats: overall accuracy %, avg edge, total P&L, signals followed count
- [ ] Breakdown by alert level: accuracy and count per level (Extreme, Strong, Opportunity, Safe NO)
- [ ] Breakdown by station: accuracy and P&L per station
- [ ] Signal history table: date, station, temp, action, edge, result (Won/Lost/Sold), P&L, status
- [ ] Data loaded only when section is expanded (lazy load)
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

### US-013: Real-time PubSub updates
**Description:** As a user, I want new signals to appear live and prices to update in real-time without refreshing.

**Acceptance Criteria:**
- [ ] New signals from `signals:new` PubSub topic prepend to list with highlight animation
- [ ] New signals respect active filters (only shown if they match)
- [ ] Balance updates from `portfolio:balance_update` reflected in header and Quick Actions Bar
- [ ] Position updates from `portfolio:position_update` reflected in table "Pos?" column and detail panel
- [ ] Stale signal detection: if price changed >10% since signal was computed, show warning icon
- [ ] Total count updates when new signals arrive
- [ ] Compiles without warnings

### US-014: View mode toggle component
**Description:** As a user, I want to switch between Table, Grouped, and Heatmap views.

**Acceptance Criteria:**
- [ ] Three toggle buttons: Table (default), Grouped, Heatmap
- [ ] Active view highlighted
- [ ] View state persists during filter changes
- [ ] Filters apply across all view modes
- [ ] Compiles without warnings
- [ ] Verify in browser using dev-browser skill

## Functional Requirements

- FR-1: Add route `/signals` rendering `WeatherEdgeWeb.SignalsLive`
- FR-2: Add "Signals" link to header navigation
- FR-3: Load signals via `Signals.Queries.list_filtered_signals/2` with dynamic Ecto filters
- FR-4: Deduplicate signals: latest per (station_code, outcome_label, market_cluster_id)
- FR-5: Filter bar sticky at top with all filter controls described in US-003
- FR-6: Table view as default with columns described in US-004
- FR-7: Grouped view groups signals by {station_code, market_cluster_id} with best play / hedge / other sections
- FR-8: Heatmap view shows station x date grid with best edge per cell
- FR-9: Signal detail panel slides in from right on row click with full context
- FR-10: Charts rendered via Chart.js JS hooks: cluster distribution, edge history, price history
- FR-11: Quick Actions Bar sticky at bottom with batch selection and real order execution
- FR-12: Detail panel includes buy controls with amount input and real order execution
- FR-13: Performance tracker section at bottom with accuracy stats and signal history
- FR-14: Real-time updates via PubSub for new signals, balance changes, and position updates
- FR-15: Pagination via "Show more" button (20 signals per page)
- FR-16: Only show signals for unresolved market clusters

## Non-Goals

- No mobile-optimized layout (desktop-first, responsive but not mobile-native)
- No WebSocket-based orderbook streaming (fetch on detail panel open only)
- No automated strategy execution (user must click buy)
- No modifications to the existing `/analytics` page
- No modifications to existing signal detection logic or probability engine
- No new database migrations (reuse existing tables)
- No VegaLite — using Chart.js via JS hooks instead

## Design Considerations

- Follow existing WeatherEdge Tailwind styling: zinc backgrounds, rounded-lg borders, dark mode support
- Reuse `HeaderComponent` with balance display
- Slide-in panel similar to a drawer component (absolute positioned, z-50)
- Chart.js minimal config — line charts and horizontal bar charts only
- Filter bar uses existing Tailwind form controls (select, input, toggle)
- Color coding consistent with existing alert_class, side_class, confidence_class helpers

## Technical Considerations

- All queries go through existing Ecto schemas: Signal, MarketCluster, Station, Position, MarketSnapshot, ForecastSnapshot
- Batch buy uses existing `Trading.OrderManager.place_signal_order/2` or `Trading.ClobClient`
- Chart.js loaded via CDN in app layout or assets pipeline, rendered via LiveView JS hooks (`phx-hook`)
- Detail panel data fetched asynchronously (send pattern) to avoid blocking mount
- Heatmap data can be expensive — compute once on view switch, cache in assigns
- Performance stats query can be slow — lazy load on expand only
- PubSub topics already exist: reuse `PubSubHelper` broadcast/subscribe patterns

## Success Metrics

- User can find and act on the best signal in under 30 seconds
- Batch buy of 3+ signals executable in under 10 seconds
- Page loads initial 20 signals in under 2 seconds
- All three views render without layout issues
- Real-time signal updates appear within 5 seconds of detection

## Open Questions

- Should filter state persist in URL params for shareability/bookmarking?
- Should the heatmap include resolved events (grayed out) for historical context?
- Should batch buy support configurable per-signal amounts or use station defaults only?
- Should the performance tracker include a "signal of the day" or "best call this week" highlight?

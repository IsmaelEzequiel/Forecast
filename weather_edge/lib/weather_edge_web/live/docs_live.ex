defmodule WeatherEdgeWeb.DocsLive do
  use WeatherEdgeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-8 pb-16">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-zinc-900">WeatherEdge Documentation</h1>
        <.link navigate="/" class="text-sm text-blue-600 hover:underline">&larr; Back to Dashboard</.link>
      </div>

      <p class="text-sm text-zinc-500">
        Reference guide for all labels, metrics, and information displayed across the application.
      </p>

      <%!-- TABLE OF CONTENTS --%>
      <nav class="rounded-lg border border-zinc-200 bg-zinc-50 p-4">
        <h2 class="text-sm font-semibold text-zinc-700 mb-2">Contents</h2>
        <ol class="list-decimal list-inside text-sm space-y-1 text-blue-600">
          <li><a href="#header" class="hover:underline">Header &amp; Navigation</a></li>
          <li><a href="#portfolio" class="hover:underline">Portfolio Summary</a></li>
          <li><a href="#station-card" class="hover:underline">Station Cards</a></li>
          <li><a href="#event-card" class="hover:underline">Event Cards</a></li>
          <li><a href="#station-detail" class="hover:underline">Station Detail Page</a></li>
          <li><a href="#signal-feed" class="hover:underline">Signal Feed</a></li>
          <li><a href="#alert-levels" class="hover:underline">Alert Levels</a></li>
          <li><a href="#workers" class="hover:underline">Background Workers</a></li>
          <li><a href="#architecture" class="hover:underline">Architecture Overview</a></li>
        </ol>
      </nav>

      <%!-- 1. HEADER --%>
      <section id="header" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">1. Header &amp; Navigation</h2>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Balance</dt>
            <dd class="text-zinc-500 ml-4">
              Your Polymarket wallet USDC balance. Updated in real-time via the Node.js sidecar.
              Shows "$--" when unavailable.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Wallet Address</dt>
            <dd class="text-zinc-500 ml-4">
              The Polymarket wallet address configured in <code class="text-xs bg-zinc-100 px-1 rounded">POLYMARKET_WALLET_ADDRESS</code>.
              Truncated to first 6 and last 4 characters.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">+ Add Station</dt>
            <dd class="text-zinc-500 ml-4">
              Opens a modal to add a new weather station by ICAO code (e.g., KJFK, EGLL, SBSP).
              You choose the temperature unit (Celsius or Fahrenheit) during setup.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 2. PORTFOLIO SUMMARY --%>
      <section id="portfolio" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">2. Portfolio Summary</h2>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Open Positions</dt>
            <dd class="text-zinc-500 ml-4">Number of currently open positions across all markets.</dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Total Invested</dt>
            <dd class="text-zinc-500 ml-4">
              Sum of <code class="text-xs bg-zinc-100 px-1 rounded">amount * avg_price</code> for all open positions.
              This is how much USDC you spent buying tokens.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Current Value</dt>
            <dd class="text-zinc-500 ml-4">
              Sum of <code class="text-xs bg-zinc-100 px-1 rounded">amount * current_price</code> for all open positions.
              Uses the latest market price from Polymarket.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Unrealized P&amp;L</dt>
            <dd class="text-zinc-500 ml-4">
              Current Value minus Total Invested. Green if positive, red if negative.
              This is your paper profit/loss on open positions.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Today's Realized</dt>
            <dd class="text-zinc-500 ml-4">
              Sum of <code class="text-xs bg-zinc-100 px-1 rounded">realized_pnl</code> for positions closed today.
              This is actual profit/loss from settled or sold positions.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Total Realized</dt>
            <dd class="text-zinc-500 ml-4">
              Sum of <code class="text-xs bg-zinc-100 px-1 rounded">realized_pnl</code> across all closed positions (lifetime).
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 3. STATION CARDS --%>
      <section id="station-card" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">3. Station Cards</h2>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Station Code</dt>
            <dd class="text-zinc-500 ml-4">
              ICAO airport/weather station code (e.g., KJFK = New York JFK, SBSP = Sao Paulo Congonhas).
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">City Name</dt>
            <dd class="text-zinc-500 ml-4">Resolved city name from the METAR validation API.</dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Monitoring (toggle)</dt>
            <dd class="text-zinc-500 ml-4">
              Enables/disables the mispricing detection pipeline for this station.
              When ON, the system scans for edge opportunities every 5 minutes.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Auto-Buy (toggle)</dt>
            <dd class="text-zinc-500 ml-4">
              When ON, the system automatically places buy orders on Polymarket when
              strong enough mispricings are detected. Requires monitoring to also be enabled.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Max Buy Price</dt>
            <dd class="text-zinc-500 ml-4">
              Maximum price (in cents, 0-99) at which auto-buy will execute.
              Prevents buying into outcomes that are already expensive.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Buy Amount (USDC)</dt>
            <dd class="text-zinc-500 ml-4">
              The USDC amount to spend per auto-buy order.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Active Events</dt>
            <dd class="text-zinc-500 ml-4">
              Lists active Polymarket temperature events for this station.
              Each event corresponds to a specific target date (e.g., "High temp in NYC on March 7").
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Scan Events</dt>
            <dd class="text-zinc-500 ml-4">
              Manually triggers the EventScannerWorker to discover new Polymarket events for this station.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 4. EVENT CARDS --%>
      <section id="event-card" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">4. Event Cards (within Station)</h2>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Target Date</dt>
            <dd class="text-zinc-500 ml-4">
              The date for which the temperature forecast applies. Shows relative labels:
              <span class="font-mono text-xs">Today</span>,
              <span class="font-mono text-xs">Tomorrow</span>, or
              <span class="font-mono text-xs">+Nd (Mar DD)</span> for further dates.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Resolution</dt>
            <dd class="text-zinc-500 ml-4">
              The event title/question from Polymarket (e.g., "Will the high temperature in NYC be 28°C or higher on March 7?").
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Position (if held)</dt>
            <dd class="text-zinc-500 ml-4">
              Shows your open position: outcome (YES/NO), token amount, buy price, current price, and unrealized P&amp;L %.
              Green background for profit, red for loss.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Top Outcomes</dt>
            <dd class="text-zinc-500 ml-4">
              Shows the top 3 outcomes by YES price from the Polymarket event.
              Includes the temperature label and current YES price.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Recommendation Badge</dt>
            <dd class="text-zinc-500 ml-4">
              If the system detects a mispricing, shows a colored badge with the recommended action
              (e.g., "BUY YES 28C @ $0.45").
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 5. STATION DETAIL --%>
      <section id="station-detail" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">5. Station Detail Page</h2>
        <p class="text-sm text-zinc-500">
          Accessed by clicking an event card. Shows detailed analysis for a specific station + event.
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Observed High</dt>
            <dd class="text-zinc-500 ml-4">
              The actual observed high temperature from the METAR weather report.
              Only available for today's date. Shows in the station's configured unit (C or F).
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Temperature Distribution Table</dt>
            <dd class="text-zinc-500 ml-4">
              A table showing every temperature outcome with columns:
              <ul class="list-disc ml-4 mt-1 space-y-1">
                <li><strong>Outcome</strong> &mdash; Temperature label (e.g., "28C or higher", "25-26C")</li>
                <li><strong>Model</strong> &mdash; Probability from the multi-model forecast ensemble (0-100%)</li>
                <li><strong>Market</strong> &mdash; Current YES price on Polymarket (0-100%)</li>
                <li><strong>Bar</strong> &mdash; Visual bar comparing model (blue) vs market (red outline)</li>
                <li><strong>Edge</strong> &mdash; Model minus Market. Positive = model thinks more likely than market prices.
                  Green for positive edge, red for negative.</li>
              </ul>
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Model Breakdown</dt>
            <dd class="text-zinc-500 ml-4">
              Shows individual forecast model predictions. Each model (GFS, ECMWF, ICON, GEM, etc.)
              contributes to the ensemble. Displays the forecasted high temperature from each model.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Market Cluster Health</dt>
            <dd class="text-zinc-500 ml-4">
              <ul class="list-disc ml-4 space-y-1">
                <li><strong>Sum YES</strong> &mdash; Sum of all YES prices in the event. Should be close to 1.00.
                  Values far from 1.00 indicate arbitrage or illiquidity.</li>
                <li><strong>Healthy / Unhealthy</strong> &mdash; "Healthy" if Sum YES is between 0.95 and 1.05,
                  "Unhealthy" otherwise.</li>
              </ul>
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 6. SIGNAL FEED --%>
      <section id="signal-feed" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">6. Signal Feed</h2>
        <p class="text-sm text-zinc-500">
          The real-time feed of mispricing signals on the dashboard. Each signal row shows:
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Timestamp</dt>
            <dd class="text-zinc-500 ml-4">
              Time the signal was computed (HH:MM:SS UTC).
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Station Code</dt>
            <dd class="text-zinc-500 ml-4">
              The ICAO station code this signal relates to (e.g., KJFK, SBSP).
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Temperature</dt>
            <dd class="text-zinc-500 ml-4">
              The specific temperature outcome, extracted from the Polymarket question.
              Examples: "28°C or higher", "25-26°C", "72°F or below".
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Target Date</dt>
            <dd class="text-zinc-500 ml-4">
              When this temperature outcome resolves. Shows "Today", "Tomorrow", "+2d (Mar 08)", etc.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">BUY YES / BUY NO</dt>
            <dd class="text-zinc-500 ml-4">
              The recommended action:
              <ul class="list-disc ml-4 mt-1 space-y-1">
                <li><strong class="text-green-700">BUY YES</strong> &mdash; Model probability is higher than market price.
                  The model thinks this outcome is underpriced.</li>
                <li><strong class="text-red-700">BUY NO</strong> &mdash; Model probability is lower than market price.
                  The model thinks this outcome is overpriced, so buying NO is profitable.</li>
                <li><strong class="text-indigo-700">BOUGHT</strong> &mdash; An auto-buy order was executed for this signal.</li>
              </ul>
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Market Price</dt>
            <dd class="text-zinc-500 ml-4">
              Current YES price on Polymarket (e.g., $0.45 = 45% implied probability).
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Model Probability</dt>
            <dd class="text-zinc-500 ml-4">
              The ensemble model's estimated probability for this outcome (e.g., 62.3%).
              Derived from multi-model weather forecasts with Gaussian smoothing.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Edge</dt>
            <dd class="text-zinc-500 ml-4">
              <code class="text-xs bg-zinc-100 px-1 rounded">Model Probability - Market Price</code>.
              Example: Model = 62%, Market = 45%, Edge = +17.0%.
              Higher edge = larger mispricing = better opportunity.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Open (link)</dt>
            <dd class="text-zinc-500 ml-4">
              Direct link to the Polymarket event page where you can manually place a trade.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 7. ALERT LEVELS --%>
      <section id="alert-levels" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">7. Alert Levels</h2>
        <p class="text-sm text-zinc-500">
          Each signal is classified into an alert level based on the edge magnitude and direction:
        </p>
        <div class="space-y-2 text-sm">
          <div class="flex items-center gap-3 rounded-md border border-green-300 bg-green-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-green-500"></span>
            <div>
              <span class="font-bold text-green-800">Safe NO</span>
              <span class="text-zinc-500 ml-2">
                Market price is very high but model probability is very low.
                Buying NO is likely safe. Edge is strongly negative (model &lt;&lt; market).
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-yellow-300 bg-yellow-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-yellow-500"></span>
            <div>
              <span class="font-bold text-yellow-800">Opportunity</span>
              <span class="text-zinc-500 ml-2">
                Moderate positive edge. Model sees value the market hasn't priced in yet.
                Worth monitoring but not a strong conviction trade.
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-orange-300 bg-orange-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-orange-500"></span>
            <div>
              <span class="font-bold text-orange-800">Strong</span>
              <span class="text-zinc-500 ml-2">
                Large positive edge. The model's probability significantly exceeds the market price.
                High-conviction signal.
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-red-300 bg-red-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-red-500"></span>
            <div>
              <span class="font-bold text-red-800">Extreme</span>
              <span class="text-zinc-500 ml-2">
                Very large positive edge. The market is heavily mispriced according to the model.
                Strongest signal &mdash; auto-buy will trigger if enabled.
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-indigo-300 bg-indigo-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-indigo-500"></span>
            <div>
              <span class="font-bold text-indigo-800">Auto-Buy</span>
              <span class="text-zinc-500 ml-2">
                An automatic buy order was placed and executed by the system.
                Only happens when both monitoring and auto-buy are enabled for the station.
              </span>
            </div>
          </div>
        </div>
      </section>

      <%!-- 8. WORKERS --%>
      <section id="workers" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">8. Background Workers</h2>
        <p class="text-sm text-zinc-500">
          Oban-powered jobs that run automatically:
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">ForecastRefreshWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Fetches multi-model weather forecasts from Open-Meteo every 15 minutes.
              Sources: GFS, ECMWF, ICON, GEM, JMA, and others.
              Stores snapshots in <code class="text-xs bg-zinc-100 px-1 rounded">forecast_snapshots</code>.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">MispricingWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Runs every 5 minutes. Compares forecast probability distributions to Polymarket prices.
              Generates signals when edge exceeds thresholds. Stores in DB and broadcasts via PubSub.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">EventScannerWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Discovers new Polymarket temperature events via the Gamma API using station tag slugs.
              Creates <code class="text-xs bg-zinc-100 px-1 rounded">market_clusters</code> for new events.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">AutoBuyerWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Executes buy orders through the Node.js sidecar when strong signals are detected
              and the station has auto-buy enabled. Respects max buy price and amount limits.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">PriceSnapshotWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Periodically snapshots current Polymarket prices for active markets.
              Updates position current prices for P&amp;L tracking.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 9. ARCHITECTURE --%>
      <section id="architecture" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 border-b pb-1">9. Architecture Overview</h2>
        <div class="text-sm text-zinc-500 space-y-3">
          <p>
            <strong class="text-zinc-700">Phoenix LiveView App</strong> &mdash;
            Main application. Handles the dashboard UI, real-time updates via PubSub,
            and all background job scheduling via Oban.
          </p>
          <p>
            <strong class="text-zinc-700">Node.js Sidecar</strong> &mdash;
            A small Express server that wraps the Polymarket SDK.
            Handles EIP-712 cryptographic signing for authenticated operations
            (placing orders, checking balances, syncing positions).
            The Elixir app calls the sidecar via HTTP for all trading operations.
          </p>
          <p>
            <strong class="text-zinc-700">Data Flow</strong>:
          </p>
          <ol class="list-decimal list-inside ml-4 space-y-1">
            <li>EventScannerWorker discovers new Polymarket temperature events</li>
            <li>ForecastRefreshWorker fetches multi-model weather forecasts</li>
            <li>MispricingWorker computes probability distributions and compares to market prices</li>
            <li>Signals are stored, broadcast via PubSub, and shown in the Signal Feed</li>
            <li>AutoBuyerWorker (if enabled) executes trades through the sidecar</li>
            <li>PriceSnapshotWorker tracks position performance over time</li>
          </ol>
          <p>
            <strong class="text-zinc-700">Probability Engine</strong> &mdash;
            Aggregates forecasts from multiple weather models, applies Gaussian smoothing,
            and produces a probability distribution over temperature outcomes.
            Supports both Celsius and Fahrenheit with configurable tail collapsing
            ("or below" / "or higher" buckets).
          </p>
        </div>
      </section>
    </div>
    """
  end
end

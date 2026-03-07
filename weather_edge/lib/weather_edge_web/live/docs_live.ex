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
        <h1 class="text-2xl font-bold text-zinc-900 dark:text-zinc-100">WeatherEdge Documentation</h1>
        <.link navigate="/" class="text-sm text-blue-600 hover:underline">&larr; Back to Dashboard</.link>
      </div>

      <p class="text-sm text-zinc-500">
        Reference guide for all labels, metrics, and information displayed across the application.
      </p>

      <%!-- TABLE OF CONTENTS --%>
      <nav class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-4">
        <h2 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-2">Contents</h2>
        <ol class="list-decimal list-inside text-sm space-y-1 text-blue-600">
          <li><a href="#header" class="hover:underline">Header &amp; Navigation</a></li>
          <li><a href="#portfolio" class="hover:underline">Portfolio Summary</a></li>
          <li><a href="#station-card" class="hover:underline">Station Cards</a></li>
          <li><a href="#event-card" class="hover:underline">Event Cards</a></li>
          <li><a href="#station-detail" class="hover:underline">Station Detail Page</a></li>
          <li><a href="#signal-feed" class="hover:underline">Signal Feed</a></li>
          <li><a href="#alert-levels" class="hover:underline">Alert Levels</a></li>
          <li><a href="#confidence" class="hover:underline">Confidence Levels</a></li>
          <li><a href="#peak-status" class="hover:underline">Peak Status &amp; Timezone Strategy</a></li>
          <li><a href="#observed-temp" class="hover:underline">Observed Temperature Override</a></li>
          <li><a href="#math-ensemble" class="hover:underline">Ensemble Model Weighting (Math)</a></li>
          <li><a href="#math-gaussian" class="hover:underline">Gaussian Kernel Smoothing (Math)</a></li>
          <li><a href="#math-probability" class="hover:underline">Probability Distribution Pipeline</a></li>
          <li><a href="#math-kelly" class="hover:underline">Kelly Criterion Position Sizing</a></li>
          <li><a href="#math-signals" class="hover:underline">Signal Detection Thresholds</a></li>
          <li><a href="#forecast-models" class="hover:underline">Forecast Models</a></li>
          <li><a href="#workers" class="hover:underline">Background Workers</a></li>
          <li><a href="#architecture" class="hover:underline">Architecture Overview</a></li>
        </ol>
      </nav>

      <%!-- 1. HEADER --%>
      <section id="header" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">1. Header &amp; Navigation</h2>
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
          <div>
            <dt class="font-semibold text-zinc-700">Docs</dt>
            <dd class="text-zinc-500 ml-4">Opens this documentation page.</dd>
          </div>
        </dl>
      </section>

      <%!-- 2. PORTFOLIO SUMMARY --%>
      <section id="portfolio" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">2. Portfolio Summary</h2>
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
              Positions are auto-reconciled: when a position disappears from Polymarket
              (sold or resolved), it is automatically marked closed with realized P&amp;L.
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
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">3. Station Cards</h2>
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
            <dt class="font-semibold text-zinc-700">Peak Status Badge</dt>
            <dd class="text-zinc-500 ml-4">
              Shows the current solar peak status for this station based on its longitude:
              <ul class="list-disc ml-4 mt-1 space-y-1">
                <li><strong>Pre-Peak</strong> (sky blue) &mdash; Before noon local solar time. Temperature still rising.</li>
                <li><strong>Near Peak</strong> (amber) &mdash; 12:00-16:00 local. Peak sun hours, temp may still climb.</li>
                <li><strong>Post-Peak</strong> (green) &mdash; After 16:00 local. Daily high is locked in. Best time to trade.</li>
                <li><strong>Night</strong> (gray) &mdash; Nighttime. Observed high is final.</li>
              </ul>
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Monitoring (toggle)</dt>
            <dd class="text-zinc-500 ml-4">
              Enables/disables the mispricing detection pipeline for this station.
              Scan frequency adapts to peak status: every run for post-peak, every other for pre-peak.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Auto-Buy (toggle)</dt>
            <dd class="text-zinc-500 ml-4">
              When ON, the system automatically places buy orders on Polymarket when
              strong enough mispricings are detected. For today's markets, auto-buy only
              triggers on confirmed/high confidence signals (post-peak or near-peak).
              Pre-peak forecast-only signals are skipped.
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
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">4. Event Cards (within Station)</h2>
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
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">5. Station Detail Page</h2>
        <p class="text-sm text-zinc-500">
          Accessed by clicking an event card. Shows detailed analysis for a specific station + event.
          Includes an "Open on Polymarket" button to view the market directly.
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Open on Polymarket</dt>
            <dd class="text-zinc-500 ml-4">
              Blue button that opens the Polymarket event page in a new tab for manual trading.
            </dd>
          </div>
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
                <li><strong>Bar</strong> &mdash; Visual bar comparing model (blue) vs market (amber)</li>
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
          <div>
            <dt class="font-semibold text-zinc-700">Orderbook</dt>
            <dd class="text-zinc-500 ml-4">
              Shows best bid/ask prices and spread for the top outcome or your held position.
              Loads automatically even without a position using the cluster's most active outcome.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Positions</dt>
            <dd class="text-zinc-500 ml-4">
              Shows all open positions for this event from the DB. Displays outcome, tokens, avg price,
              current price, and unrealized P&amp;L.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Polymarket Positions</dt>
            <dd class="text-zinc-500 ml-4">
              Positions fetched directly from Polymarket via the sidecar. Shows positions that may not
              be in the DB (e.g., bought directly on Polymarket). Displays size, avg price, current price, and P&amp;L.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 6. SIGNAL FEED --%>
      <section id="signal-feed" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">6. Signal Feed</h2>
        <p class="text-sm text-zinc-500">
          The real-time feed of mispricing signals on the dashboard. Shows 20 signals at a time
          with a "Show more" button to load additional results. Each signal row shows:
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Filter Buttons</dt>
            <dd class="text-zinc-500 ml-4">
              Filter signals by type. Available filters:
              <span class="font-mono text-xs">All</span>,
              <span class="font-mono text-xs">Confirmed</span> (post-peak observations),
              <span class="font-mono text-xs">Extreme</span>,
              <span class="font-mono text-xs">Strong</span>,
              <span class="font-mono text-xs">Opportunity</span>,
              <span class="font-mono text-xs">Safe NO</span>,
              <span class="font-mono text-xs">Auto-Buy</span>.
              Active filter is highlighted with its color.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Signal Count</dt>
            <dd class="text-zinc-500 ml-4">
              Shows how many signals are visible and total available (e.g., "20 of 87").
            </dd>
          </div>
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
            <dt class="font-semibold text-zinc-700">Alert Level Badge</dt>
            <dd class="text-zinc-500 ml-4">
              Color-coded badge showing signal strength: Safe NO, Opportunity, Strong, Extreme, or Auto-Buy.
              See <a href="#alert-levels" class="text-blue-600 hover:underline">Alert Levels</a> below.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Confidence Badge</dt>
            <dd class="text-zinc-500 ml-4">
              Shows how reliable the signal is based on the station's peak status:
              <span class="font-semibold text-emerald-700">Confirmed</span>,
              <span class="font-semibold text-sky-700">High</span>, or
              <span class="text-zinc-500">Forecast</span>.
              See <a href="#confidence" class="text-blue-600 hover:underline">Confidence Levels</a> below.
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
          <div>
            <dt class="font-semibold text-zinc-700">Show more</dt>
            <dd class="text-zinc-500 ml-4">
              Loads 20 more signals. Shows remaining count (e.g., "67 remaining").
              Fetches from DB when needed. Disappears when all signals are shown.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 7. ALERT LEVELS --%>
      <section id="alert-levels" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">7. Alert Levels</h2>
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
                Moderate positive edge (&ge; 8%). Model sees value the market hasn't priced in yet.
                Worth monitoring but not a strong conviction trade.
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-orange-300 bg-orange-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-orange-500"></span>
            <div>
              <span class="font-bold text-orange-800">Strong</span>
              <span class="text-zinc-500 ml-2">
                Large positive edge (&ge; 15%). The model's probability significantly exceeds the market price.
                High-conviction signal.
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-red-300 bg-red-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-red-500"></span>
            <div>
              <span class="font-bold text-red-800">Extreme</span>
              <span class="text-zinc-500 ml-2">
                Very large positive edge (&ge; 25%). The market is heavily mispriced according to the model.
                Strongest signal &mdash; auto-buy will trigger if enabled and confidence is sufficient.
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-indigo-300 bg-indigo-50 px-3 py-2">
            <span class="inline-block w-2 h-2 rounded-full bg-indigo-500"></span>
            <div>
              <span class="font-bold text-indigo-800">Auto-Buy</span>
              <span class="text-zinc-500 ml-2">
                An automatic buy order was placed and executed by the system.
                Only happens when monitoring + auto-buy are enabled and confidence is confirmed or high.
              </span>
            </div>
          </div>
        </div>
      </section>

      <%!-- 8. CONFIDENCE LEVELS --%>
      <section id="confidence" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">8. Confidence Levels</h2>
        <p class="text-sm text-zinc-500">
          Each signal has a confidence level based on the station's solar peak status.
          This indicates how reliable the signal data is:
        </p>
        <div class="space-y-2 text-sm">
          <div class="flex items-center gap-3 rounded-md border border-emerald-300 bg-emerald-50 px-3 py-2">
            <span class="inline-block px-2 py-0.5 rounded bg-emerald-100 text-emerald-700 font-semibold text-xs">Confirmed</span>
            <span class="text-zinc-500">
              Post-peak or night. The observed high temperature is final. Signals are backed by
              actual METAR observations, not just forecasts. <strong>Safest to trade on.</strong>
              Auto-buy will execute on these signals.
            </span>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-sky-300 bg-sky-50 px-3 py-2">
            <span class="inline-block px-2 py-0.5 rounded bg-sky-100 text-sky-700 text-xs font-medium">High</span>
            <span class="text-zinc-500">
              Near peak (12:00-16:00 local). Temperature may still rise slightly but is close to
              the daily maximum. Observations are near-final. Auto-buy will execute on these signals.
            </span>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2">
            <span class="inline-block px-2 py-0.5 rounded bg-zinc-100 text-zinc-500 text-xs">Forecast</span>
            <span class="text-zinc-500">
              Pre-peak (before noon local). Based on weather model forecasts only &mdash; no observed
              data yet. Higher uncertainty. Auto-buy is <strong>disabled</strong> for today's markets
              at this confidence level.
            </span>
          </div>
        </div>
      </section>

      <%!-- 9. PEAK STATUS --%>
      <section id="peak-status" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">9. Peak Status &amp; Timezone Strategy</h2>
        <p class="text-sm text-zinc-500">
          Temperature markets resolve based on the daily high, which typically occurs between
          12:00-15:00 local solar time. WeatherEdge uses each station's longitude to calculate
          solar time and determine peak status.
        </p>
        <div class="space-y-2 text-sm">
          <div class="flex items-center gap-3 rounded-md border border-sky-200 bg-sky-50 px-3 py-2">
            <span class="text-lg">🌤</span>
            <div>
              <span class="font-bold text-sky-800">Pre-Peak</span>
              <span class="text-zinc-500 ml-2">
                06:00-12:00 local. Temperature is still rising. Only forecast models available.
                Scanned less frequently (every 10 minutes).
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-amber-200 bg-amber-50 px-3 py-2">
            <span class="text-lg">⛅</span>
            <div>
              <span class="font-bold text-amber-800">Near Peak</span>
              <span class="text-zinc-500 ml-2">
                12:00-16:00 local. Peak sun hours. Temperature approaching daily maximum.
                Scanned every run (every 5 minutes).
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2">
            <span class="text-lg">☀</span>
            <div>
              <span class="font-bold text-emerald-800">Post-Peak</span>
              <span class="text-zinc-500 ml-2">
                16:00-06:00 local. Daily high is locked in. Observed temperature is the final answer.
                Scanned every run. <strong>Best time to trade &mdash; highest confidence signals.</strong>
              </span>
            </div>
          </div>
          <div class="flex items-center gap-3 rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2">
            <span class="text-lg">🌙</span>
            <div>
              <span class="font-bold text-zinc-700">Night</span>
              <span class="text-zinc-500 ml-2">
                Same as post-peak for trading purposes. The high is final.
                Scanned less frequently (every 15 minutes).
              </span>
            </div>
          </div>
        </div>
        <div class="rounded-md border border-blue-200 bg-blue-50 p-3 text-sm text-blue-800">
          <strong>Timezone advantage:</strong> From Maceió (UTC-3), your morning is post-peak
          for Asia/Oceania. Your midday is post-peak for Europe. Your afternoon is near-peak for US East.
          The system automatically prioritizes scanning cities where the outcome is already determined.
        </div>
      </section>

      <%!-- 10. OBSERVED TEMP --%>
      <section id="observed-temp" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">10. Observed Temperature Override</h2>
        <p class="text-sm text-zinc-500">
          For today's markets, the system fetches the actual observed high temperature from METAR
          and uses it to override weather model probabilities. This prevents bad signals like
          recommending "BUY NO" on a temperature that has already been reached.
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">Market-confirmed filter</dt>
            <dd class="text-zinc-500 ml-4">
              If an outcome's YES price is &ge; 95% and observed data exists, the outcome is
              considered settled. No signals are generated against it.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Observed overrides</dt>
            <dd class="text-zinc-500 ml-4">
              <ul class="list-disc ml-4 space-y-1">
                <li><strong>"27C or higher"</strong> + observed 27°C &rarr; resolved YES (100%)</li>
                <li><strong>"25C or below"</strong> + observed 27°C &rarr; resolved NO (0%)</li>
                <li><strong>"84-85F"</strong> + observed 84°F &rarr; resolved YES (in range)</li>
                <li><strong>"84-85F"</strong> + observed 86°F &rarr; resolved NO (above range)</li>
                <li><strong>"27C"</strong> + observed 27°C &rarr; resolved YES (exact match)</li>
                <li><strong>"26C"</strong> + observed 28°C &rarr; resolved NO (exceeded)</li>
              </ul>
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 11. ENSEMBLE MODEL WEIGHTING --%>
      <section id="math-ensemble" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">11. Ensemble Model Weighting (Math)</h2>
        <p class="text-sm text-zinc-500">
          When enough historical accuracy data exists (&ge; 3 resolved events for a station), models are
          weighted by inverse Mean Absolute Error (MAE). Models with lower historical error get more influence.
        </p>
        <div class="rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-4 text-sm font-mono space-y-2">
          <p class="text-zinc-700 dark:text-zinc-300">For each model <em>m</em>:</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">inverse_mae(m) = 1 / max(MAE(m), 0.5)</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">weight(m) = inverse_mae(m) / &sum; inverse_mae(all models)</p>
          <p class="text-zinc-500 dark:text-zinc-400 text-xs mt-2">
            The floor of 0.5 prevents a model with near-zero MAE from dominating.
            When &lt; 3 events exist, all models get equal weight (1/N).
          </p>
        </div>
        <p class="text-sm text-zinc-500">
          <strong>Example:</strong> If GFS has MAE=1.2 and ECMWF has MAE=0.8, then
          inverse_mae(GFS) = 1/1.2 = 0.833, inverse_mae(ECMWF) = 1/0.8 = 1.25.
          Total = 2.083. Weight(GFS) = 40%, Weight(ECMWF) = 60%.
        </p>
      </section>

      <%!-- 12. GAUSSIAN KERNEL SMOOTHING --%>
      <section id="math-gaussian" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">12. Gaussian Kernel Smoothing (Math)</h2>
        <p class="text-sm text-zinc-500">
          Raw model forecasts produce a sparse distribution (e.g., 5 models = 5 point estimates).
          Gaussian kernel smoothing spreads probability mass to neighboring temperatures,
          producing a realistic bell-curve-like distribution.
        </p>
        <div class="rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-4 text-sm font-mono space-y-2">
          <p class="text-zinc-700 dark:text-zinc-300">Kernel weight:</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">K(x, &mu;, &sigma;) = exp(-(x - &mu;)&sup2; / (2&sigma;&sup2;))</p>
          <p class="text-zinc-700 dark:text-zinc-300 mt-2">Smoothed probability at temperature t:</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">P'(t) = &sum;<sub>s</sub> K(s, t, &sigma;) &middot; P(s) / Z</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4 text-xs">where Z = normalization constant so &sum; P' = 1.0</p>
        </div>
        <div class="rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-4 text-sm space-y-1">
          <p class="text-zinc-700 dark:text-zinc-300 font-semibold">Sigma by forecast horizon:</p>
          <ul class="list-disc ml-4 text-zinc-500 dark:text-zinc-400 space-y-1">
            <li>&le; 1 day out: &sigma; = 0.8 (tight, high confidence)</li>
            <li>2 days out: &sigma; = 1.2 (moderate spread)</li>
            <li>3+ days out: &sigma; = 1.8 (wide, lower confidence)</li>
          </ul>
          <p class="text-zinc-500 dark:text-zinc-400 text-xs mt-2">
            Lower &sigma; = probability stays concentrated near forecast temps.
            Higher &sigma; = probability spreads to adjacent temps, reflecting forecast uncertainty.
          </p>
        </div>
      </section>

      <%!-- 13. PROBABILITY DISTRIBUTION PIPELINE --%>
      <section id="math-probability" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">13. Probability Distribution Pipeline</h2>
        <p class="text-sm text-zinc-500">
          The full pipeline from raw forecasts to final probabilities:
        </p>
        <ol class="list-decimal list-inside text-sm text-zinc-500 dark:text-zinc-400 space-y-2 ml-2">
          <li><strong class="text-zinc-700 dark:text-zinc-300">Fetch snapshots</strong> &mdash; Latest forecast per model for station + target date</li>
          <li><strong class="text-zinc-700 dark:text-zinc-300">Compute model weights</strong> &mdash; Inverse MAE weighting (or equal if &lt; 3 events)</li>
          <li><strong class="text-zinc-700 dark:text-zinc-300">Build weighted empirical</strong> &mdash; Each model's temp gets its weight as probability mass</li>
          <li><strong class="text-zinc-700 dark:text-zinc-300">Gaussian smoothing</strong> &mdash; Apply kernel with horizon-based &sigma;</li>
          <li><strong class="text-zinc-700 dark:text-zinc-300">Tail collapse</strong> &mdash; Aggregate extremes into "X or below" and "Y or higher" buckets matching Polymarket outcomes</li>
          <li><strong class="text-zinc-700 dark:text-zinc-300">Normalize</strong> &mdash; Ensure all probabilities sum to 1.0</li>
          <li><strong class="text-zinc-700 dark:text-zinc-300">Observed override</strong> &mdash; For today's markets, if METAR observed high exists, deterministically resolve applicable outcomes to 0% or 100%</li>
        </ol>
      </section>

      <%!-- 14. KELLY CRITERION --%>
      <section id="math-kelly" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">14. Kelly Criterion Position Sizing</h2>
        <p class="text-sm text-zinc-500">
          Position size is dynamically adjusted based on edge strength using the Kelly criterion.
          We use <strong>half-Kelly</strong> to reduce variance at the cost of slightly lower expected growth.
        </p>
        <div class="rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-4 text-sm font-mono space-y-2">
          <p class="text-zinc-700 dark:text-zinc-300">Given:</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">p = model probability of winning</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">q = 1 - p (probability of losing)</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">b = (1 - price) / price (net odds)</p>
          <p class="text-zinc-700 dark:text-zinc-300 mt-2">Full Kelly fraction:</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">f* = (p &middot; b - q) / b</p>
          <p class="text-zinc-700 dark:text-zinc-300 mt-2">Half-Kelly (what we use):</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">f = f* &times; 0.5</p>
          <p class="text-zinc-700 dark:text-zinc-300 mt-2">Final multiplier (clamped):</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">multiplier = clamp(f, 0.25, 1.50)</p>
          <p class="text-zinc-700 dark:text-zinc-300 ml-4">buy_amount = base_amount &times; multiplier</p>
        </div>
        <p class="text-sm text-zinc-500">
          <strong>Example:</strong> Model prob = 70%, market price = $0.45.
          b = 0.55/0.45 = 1.222. f* = (0.70 &times; 1.222 - 0.30) / 1.222 = 0.455.
          Half-Kelly = 0.228. Clamped to 0.25 (minimum). Buy amount = base &times; 0.25.
        </p>
        <p class="text-sm text-zinc-500">
          <strong>Why half-Kelly?</strong> Full Kelly maximizes long-run growth but has extreme variance.
          Half-Kelly achieves ~75% of the growth rate with ~50% of the drawdowns.
          The 0.25-1.50 clamps ensure we never bet too little (skip edge) or too much (blow up).
        </p>
      </section>

      <%!-- 15. SIGNAL DETECTION THRESHOLDS --%>
      <section id="math-signals" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">15. Signal Detection Thresholds</h2>
        <p class="text-sm text-zinc-500">
          The mispricing detector compares model probability to market price and classifies the edge:
        </p>
        <div class="rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-4 text-sm font-mono space-y-2">
          <p class="text-zinc-700 dark:text-zinc-300">edge = model_probability - market_price</p>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse mt-2">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-zinc-700">
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Alert Level</th>
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Edge Threshold</th>
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Direction</th>
              </tr>
            </thead>
            <tbody class="text-zinc-500 dark:text-zinc-400">
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold text-green-700">Safe NO</td><td class="py-1 px-2">edge &le; -15%</td><td class="py-1 px-2">Model &lt;&lt; Market (overpriced)</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold text-yellow-700">Opportunity</td><td class="py-1 px-2">edge &ge; 8%</td><td class="py-1 px-2">Model &gt; Market</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold text-orange-700">Strong</td><td class="py-1 px-2">edge &ge; 15%</td><td class="py-1 px-2">Model &gt;&gt; Market</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold text-red-700">Extreme</td><td class="py-1 px-2">edge &ge; 25%</td><td class="py-1 px-2">Model &gt;&gt;&gt; Market</td></tr>
            </tbody>
          </table>
        </div>
        <p class="text-sm text-zinc-500 mt-2">
          <strong>Signal deduplication:</strong> To prevent spam, signals are deduplicated per market cluster.
          If a signal with the same outcome + side (BUY YES/NO) was generated in the last 1 hour,
          it is skipped.
        </p>
        <p class="text-sm text-zinc-500">
          <strong>Auto-buy gating:</strong> Auto-buy only executes when: (1) station has auto-buy enabled,
          (2) signal confidence is Confirmed or High (post-peak/near-peak for today's markets),
          (3) market price &le; station's max buy price, (4) edge meets the threshold.
        </p>
      </section>

      <%!-- 16. FORECAST MODELS --%>
      <section id="forecast-models" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">16. Forecast Models</h2>
        <p class="text-sm text-zinc-500">
          The ensemble combines forecasts from 8 independent weather models:
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse mt-2">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-zinc-700">
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Model</th>
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Source</th>
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Provider</th>
                <th class="text-left py-1 px-2 text-zinc-700 dark:text-zinc-300">Strength</th>
              </tr>
            </thead>
            <tbody class="text-zinc-500 dark:text-zinc-400">
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">GFS</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">NOAA (US)</td><td class="py-1 px-2">Best for North America</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">ECMWF IFS</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">ECMWF (EU)</td><td class="py-1 px-2">Best overall global model</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">ICON</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">DWD (Germany)</td><td class="py-1 px-2">Strong for Europe</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">JMA</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">JMA (Japan)</td><td class="py-1 px-2">Strong for Asia-Pacific</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">GEM</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">ECCC (Canada)</td><td class="py-1 px-2">Strong for North America</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">UKMO</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">Met Office (UK)</td><td class="py-1 px-2">Strong for UK/Europe</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">ARPEGE</td><td class="py-1 px-2">Open-Meteo</td><td class="py-1 px-2">M&eacute;t&eacute;o-France</td><td class="py-1 px-2">Strong for Europe/Africa</td></tr>
              <tr class="border-b border-zinc-100 dark:border-zinc-800"><td class="py-1 px-2 font-semibold">Wunderground</td><td class="py-1 px-2">Web scrape</td><td class="py-1 px-2">Weather Underground</td><td class="py-1 px-2">Blended model, good for US cities</td></tr>
            </tbody>
          </table>
        </div>
        <p class="text-sm text-zinc-500 mt-2">
          All Open-Meteo models provide hourly <code class="text-xs bg-zinc-100 dark:bg-zinc-800 px-1 rounded">temperature_2m</code> data. The daily max is extracted
          by filtering hours matching the target date and taking the maximum value.
          Weather Underground forecast is scraped from their forecast page and converted from &deg;F to &deg;C.
        </p>
      </section>

      <%!-- 17. WORKERS --%>
      <section id="workers" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">17. Background Workers</h2>
        <p class="text-sm text-zinc-500">
          Oban-powered jobs that run automatically:
        </p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="font-semibold text-zinc-700">ForecastRefreshWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Fetches multi-model weather forecasts every 15 minutes.
              Sources: GFS, ECMWF IFS, ICON, GEM, JMA, UKMO, ARPEGE (via Open-Meteo) + Weather Underground (web scrape).
              Stores snapshots in <code class="text-xs bg-zinc-100 px-1 rounded">forecast_snapshots</code>.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">MispricingWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Cron runs every 5 minutes. Uses timezone-aware adaptive scanning:
              post-peak and near-peak stations are scanned every run, pre-peak every other run,
              night stations every third run. Compares forecast distributions to market prices,
              applies observed temperature overrides for today's markets, and tags each signal
              with a confidence level.
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
              and the station has auto-buy enabled. For today's markets, only executes on
              confirmed or high confidence signals (post-peak/near-peak). Pre-peak forecast-only
              signals are skipped to avoid risky trades.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">PriceSnapshotWorker</dt>
            <dd class="text-zinc-500 ml-4">
              Periodically snapshots current Polymarket prices for active markets.
              Updates position current prices for P&amp;L tracking.
            </dd>
          </div>
          <div>
            <dt class="font-semibold text-zinc-700">Position Reconciliation</dt>
            <dd class="text-zinc-500 ml-4">
              Runs on every sidecar sync (~30s). Compares Polymarket open positions with DB positions.
              When a DB "open" position is no longer on Polymarket (sold or resolved), it is
              automatically marked as closed with calculated realized P&amp;L. This powers the
              Today's Realized and Total Realized metrics.
            </dd>
          </div>
        </dl>
      </section>

      <%!-- 18. ARCHITECTURE --%>
      <section id="architecture" class="space-y-3">
        <h2 class="text-lg font-bold text-zinc-800 dark:text-zinc-200 border-b pb-1">18. Architecture Overview</h2>
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
            Syncs balance and positions every 30 seconds, triggering position reconciliation.
          </p>
          <p>
            <strong class="text-zinc-700">PeakCalculator</strong> &mdash;
            Uses station longitude to calculate local solar time and determine peak status.
            Every 15° of longitude = 1 hour UTC offset. Drives adaptive scan intervals,
            signal confidence levels, and auto-buy gating.
          </p>
          <p>
            <strong class="text-zinc-700">Data Flow</strong>:
          </p>
          <ol class="list-decimal list-inside ml-4 space-y-1">
            <li>EventScannerWorker discovers new Polymarket temperature events</li>
            <li>ForecastRefreshWorker fetches multi-model weather forecasts</li>
            <li>MispricingWorker calculates peak status per station, fetches observed highs for today</li>
            <li>Detector compares distributions to market prices, applies observed overrides, assigns confidence</li>
            <li>Signals are stored with confidence, broadcast via PubSub, shown in the Signal Feed</li>
            <li>AutoBuyerWorker (if enabled) executes trades only on confirmed/high confidence signals</li>
            <li>PriceSnapshotWorker tracks position performance over time</li>
            <li>Sidecar sync reconciles positions, updating realized P&amp;L when positions close</li>
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

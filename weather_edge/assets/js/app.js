// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

Hooks.UppercaseInput = {
  mounted() {
    this.el.addEventListener("input", (e) => {
      e.target.value = e.target.value.toUpperCase()
    })
  }
}

Hooks.DarkMode = {
  mounted() {
    this.el.addEventListener("click", () => {
      document.documentElement.classList.toggle("dark")
      const isDark = document.documentElement.classList.contains("dark")
      localStorage.setItem("theme", isDark ? "dark" : "light")
    })
  }
}

Hooks.ChartHook = {
  mounted() {
    this.chart = this.createChart()
  },
  updated() {
    if (this.chart) {
      const config = this.getConfig()
      this.chart.data = config.data
      if (config.options) {
        this.chart.options = config.options
      }
      this.chart.update()
    }
  },
  destroyed() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  },
  createChart() {
    const config = this.getConfig()
    const ctx = this.el.getContext("2d")
    return new Chart(ctx, config)
  },
  getConfig() {
    const chartType = this.el.dataset.chartType || "line"
    const rawData = JSON.parse(this.el.dataset.chartData || "{}")

    if (chartType === "distribution") {
      return this.distributionConfig(rawData)
    } else if (chartType === "edge_history") {
      return this.edgeHistoryConfig(rawData)
    } else if (chartType === "price_history") {
      return this.priceHistoryConfig(rawData)
    } else if (chartType === "pnl") {
      return this.pnlConfig(rawData)
    }
    return { type: "line", data: { labels: [], datasets: [] } }
  },
  distributionConfig(data) {
    return {
      type: "bar",
      data: {
        labels: data.labels || [],
        datasets: [
          {
            label: "Model Prob",
            data: data.model_probs || [],
            backgroundColor: "rgba(59, 130, 246, 0.7)",
            borderColor: "rgb(59, 130, 246)",
            borderWidth: 1
          },
          {
            label: "Market Price",
            data: data.market_prices || [],
            backgroundColor: "rgba(249, 115, 22, 0.7)",
            borderColor: "rgb(249, 115, 22)",
            borderWidth: 1
          }
        ]
      },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { min: 0, max: 1, ticks: { callback: v => (v * 100) + "%" } }
        },
        plugins: { legend: { position: "bottom" } }
      }
    }
  },
  edgeHistoryConfig(data) {
    return {
      type: "line",
      data: {
        labels: data.times || [],
        datasets: [
          {
            label: "Edge %",
            data: data.edges || [],
            borderColor: "rgb(34, 197, 94)",
            backgroundColor: "rgba(34, 197, 94, 0.1)",
            fill: true,
            tension: 0.3,
            pointRadius: 2
          },
          {
            label: "Model Prob %",
            data: data.model_probs || [],
            borderColor: "rgb(59, 130, 246)",
            borderDash: [5, 5],
            tension: 0.3,
            pointRadius: 2
          },
          {
            label: "Market Price",
            data: data.market_prices || [],
            borderColor: "rgb(249, 115, 22)",
            borderDash: [3, 3],
            tension: 0.3,
            pointRadius: 2
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { ticks: { callback: v => v + "%" } }
        },
        plugins: { legend: { position: "bottom" } }
      }
    }
  },
  pnlConfig(data) {
    const lastVal = data.values && data.values.length > 0 ? data.values[data.values.length - 1] : 0
    const color = lastVal >= 0 ? "rgb(22, 163, 74)" : "rgb(220, 38, 38)"
    const bgColor = lastVal >= 0 ? "rgba(22, 163, 74, 0.1)" : "rgba(220, 38, 38, 0.1)"

    return {
      type: "line",
      data: {
        labels: data.labels || [],
        datasets: [
          {
            label: "Cumulative P&L",
            data: data.values || [],
            borderColor: color,
            backgroundColor: bgColor,
            fill: true,
            tension: 0.3,
            pointRadius: 3,
            pointHoverRadius: 5
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            ticks: {
              callback: v => (v >= 0 ? "+$" : "-$") + Math.abs(v).toFixed(2)
            },
            grid: { color: "rgba(161, 161, 170, 0.2)" }
          },
          x: {
            grid: { display: false },
            ticks: { maxTicksLimit: 8 }
          }
        },
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: ctx => {
                const v = ctx.parsed.y
                return "P&L: " + (v >= 0 ? "+$" : "-$") + Math.abs(v).toFixed(2)
              }
            }
          }
        }
      }
    }
  },
  priceHistoryConfig(data) {
    const datasets = [
      {
        label: "YES Price",
        data: data.prices || [],
        borderColor: "rgb(59, 130, 246)",
        backgroundColor: "rgba(59, 130, 246, 0.1)",
        fill: true,
        tension: 0.3,
        pointRadius: 2
      }
    ]
    if (data.buy_price != null) {
      datasets.push({
        label: "Buy Price",
        data: (data.prices || []).map(() => data.buy_price),
        borderColor: "rgb(239, 68, 68)",
        borderDash: [8, 4],
        pointRadius: 0,
        fill: false
      })
    }
    return {
      type: "line",
      data: {
        labels: data.times || [],
        datasets: datasets
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            min: 0,
            max: 1,
            ticks: { callback: v => "$" + v.toFixed(2) }
          }
        },
        plugins: { legend: { position: "bottom" } }
      }
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket


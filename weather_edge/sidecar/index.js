/**
 * WeatherEdge Sidecar
 *
 * Uses @polymarket/clob-client to:
 * - Fetch user data (balance, positions) and push to Phoenix
 * - Listen for order requests from Phoenix and execute via SDK
 */

const http = require("http");
const { ClobClient } = require("@polymarket/clob-client");
const { Wallet } = require("ethers");

// Config from env (shared .env with Phoenix)
const PRIVATE_KEY = process.env.POLYMARKET_PRIVATE_KEY;
const API_KEY = process.env.POLYMARKET_API_KEY;
const API_SECRET = process.env.POLYMARKET_API_SECRET;
const API_PASSPHRASE = process.env.POLYMARKET_API_PASSPHRASE;
const WALLET_ADDRESS = process.env.POLYMARKET_WALLET_ADDRESS;
const CLOB_URL = process.env.POLYMARKET_CLOB_URL || "https://clob.polymarket.com";
const PHOENIX_URL = process.env.PHOENIX_URL || "http://localhost:4000";
const SIDECAR_SECRET = process.env.SIDECAR_SECRET || "sidecar-dev-secret";
const SIDECAR_PORT = parseInt(process.env.SIDECAR_PORT || "4001", 10);
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || "30000", 10);

if (!PRIVATE_KEY || !API_KEY || !API_SECRET || !API_PASSPHRASE || !WALLET_ADDRESS) {
  console.error("Missing Polymarket credentials in env. Check .env file.");
  process.exit(1);
}

const signer = new Wallet(PRIVATE_KEY);
const creds = { key: API_KEY, secret: API_SECRET, passphrase: API_PASSPHRASE };
const client = new ClobClient(CLOB_URL, 137, signer, creds, 1, WALLET_ADDRESS);

// --- Data sync (push to Phoenix) ---

async function fetchAndPush() {
  try {
    const [balanceResult, positions] = await Promise.allSettled([
      client.getBalanceAllowance({ asset_type: "COLLATERAL" }),
      fetchPositions(),
    ]);

    const rawBalance =
      balanceResult.status === "fulfilled" ? parseFloat(balanceResult.value?.balance || "0") : null;
    // USDC has 6 decimals — convert from smallest unit to dollars
    const balance = rawBalance != null ? rawBalance / 1e6 : null;

    const positionsData = positions.status === "fulfilled" ? positions.value : [];

    const payload = {
      balance,
      wallet_address: WALLET_ADDRESS,
      positions: positionsData,
      fetched_at: new Date().toISOString(),
    };

    await pushWithRetry(payload, 3);
  } catch (err) {
    console.error(`[${ts()}] Sync error:`, err.message);
  }
}

async function pushWithRetry(payload, retries) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const res = await fetch(`${PHOENIX_URL}/api/sidecar/sync`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${SIDECAR_SECRET}`,
        },
        body: JSON.stringify(payload),
      });

      if (res.ok) {
        console.log(`[${ts()}] Synced — balance: $${payload.balance ?? "?"}`);
        return;
      }
      console.error(`[${ts()}] Push failed: ${res.status} ${res.statusText}`);
    } catch (err) {
      console.error(`[${ts()}] Push error (attempt ${attempt}/${retries}):`, err.message);
    }

    if (attempt < retries) {
      const delay = attempt * 2000;
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

async function fetchPositions() {
  try {
    const url = `https://data-api.polymarket.com/positions?user=${WALLET_ADDRESS}`;
    const res = await fetch(url);
    return await res.json();
  } catch {
    return [];
  }
}

// --- Order placement (called by Phoenix) ---

async function placeOrder(tokenId, side, price, size) {
  // SDK expects string values for price/size and uppercase side
  const result = await client.createAndPostOrder({
    tokenID: tokenId.toString(),
    price: parseFloat(price),
    size: parseFloat(size),
    side: side.toUpperCase(),
    orderType: "FOK",
  });
  return result;
}

async function cancelOrder(orderId) {
  const result = await client.cancelOrder(orderId);
  return result;
}

// --- HTTP server for Phoenix requests ---

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => {
      try { resolve(JSON.parse(data)); }
      catch (e) { reject(e); }
    });
    req.on("error", reject);
  });
}

function authOk(req) {
  return req.headers.authorization === `Bearer ${SIDECAR_SECRET}`;
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");

  if (!authOk(req)) {
    res.writeHead(401);
    return res.end(JSON.stringify({ error: "unauthorized" }));
  }

  try {
    if (req.method === "POST" && req.url === "/order") {
      const body = await parseBody(req);
      const { token_id, side, price, size } = body;

      if (!token_id || !side || price == null || size == null) {
        res.writeHead(400);
        return res.end(JSON.stringify({ error: "missing fields: token_id, side, price, size" }));
      }

      console.log(`[${ts()}] Order: ${side} ${size}@${price} token=${token_id}`);
      const result = await placeOrder(token_id, side, price, size);
      console.log(`[${ts()}] Order result:`, JSON.stringify(result));

      res.writeHead(200);
      return res.end(JSON.stringify({ ok: true, result }));

    } else if (req.method === "POST" && req.url === "/cancel") {
      const body = await parseBody(req);
      const { order_id } = body;

      if (!order_id) {
        res.writeHead(400);
        return res.end(JSON.stringify({ error: "missing field: order_id" }));
      }

      console.log(`[${ts()}] Cancel: ${order_id}`);
      const result = await cancelOrder(order_id);

      res.writeHead(200);
      return res.end(JSON.stringify({ ok: true, result }));

    } else if (req.method === "GET" && req.url === "/open-orders") {
      const orders = await client.getOpenOrders();
      res.writeHead(200);
      return res.end(JSON.stringify({ ok: true, result: orders }));

    } else if (req.method === "GET" && req.url === "/health") {
      res.writeHead(200);
      return res.end(JSON.stringify({ ok: true, wallet: WALLET_ADDRESS }));

    } else {
      res.writeHead(404);
      return res.end(JSON.stringify({ error: "not found" }));
    }
  } catch (err) {
    console.error(`[${ts()}] Request error:`, err.message);
    res.writeHead(500);
    return res.end(JSON.stringify({ error: err.message }));
  }
});

function ts() {
  return new Date().toISOString();
}

// --- Start ---

server.listen(SIDECAR_PORT, () => {
  console.log(`WeatherEdge Sidecar listening on :${SIDECAR_PORT}`);
  console.log(`Polling every ${POLL_INTERVAL_MS / 1000}s | Wallet: ${WALLET_ADDRESS}`);
});

fetchAndPush();
setInterval(fetchAndPush, POLL_INTERVAL_MS);

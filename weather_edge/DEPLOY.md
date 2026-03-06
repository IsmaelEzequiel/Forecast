# WeatherEdge Deployment Guide

WeatherEdge consists of three services:

| Service | Description | Port |
|---------|-------------|------|
| **app** | Phoenix LiveView server (Elixir) | 4000 |
| **sidecar** | Polymarket SDK bridge (Node.js) | 4001 |
| **db** | TimescaleDB (PostgreSQL) | 5432 |

The **app** handles all UI, forecasting, signal detection, and trading logic.
The **sidecar** handles Polymarket wallet operations (balance, positions, order signing via EIP-712).
They communicate over HTTP — the sidecar pushes data to Phoenix and Phoenix sends order requests to the sidecar.

---

## Quick Start (Docker Compose)

```bash
# 1. Copy and fill in your environment variables
cp .env.example .env

# 2. Generate a secret key base
mix phx.gen.secret
# Paste the output into SECRET_KEY_BASE in .env

# 3. Set a strong sidecar secret
# Replace SIDECAR_SECRET in .env with a random string

# 4. Fill in your Polymarket credentials in .env
#    POLYMARKET_PRIVATE_KEY, POLYMARKET_API_KEY, etc.

# 5. Build and start all services
docker compose up --build -d

# 6. Check logs
docker compose logs -f app
docker compose logs -f sidecar
```

The app auto-runs migrations on startup via `entrypoint.sh`.

Open http://localhost:4000 and log in with the AUTH_USERNAME/AUTH_PASSWORD from your `.env`.

---

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix cookie signing key (use `mix phx.gen.secret`) |
| `POLYMARKET_PRIVATE_KEY` | Ethereum private key (hex, no 0x prefix) |
| `POLYMARKET_API_KEY` | Polymarket CLOB API key |
| `POLYMARKET_API_SECRET` | Polymarket CLOB API secret |
| `POLYMARKET_API_PASSPHRASE` | Polymarket CLOB API passphrase |
| `POLYMARKET_WALLET_ADDRESS` | Your Polymarket wallet address |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `PHX_HOST` | `localhost` | Public hostname for Phoenix |
| `PORT` | `4000` | Phoenix HTTP port |
| `PHX_SERVER` | `true` | Enable HTTP server in release |
| `AUTH_USERNAME` | `admin` | Login username |
| `AUTH_PASSWORD` | `changeme` | Login password |
| `SIDECAR_SECRET` | `sidecar-dev-secret` | Shared secret between app and sidecar |
| `SIDECAR_URL` | `http://localhost:4001` | How Phoenix reaches the sidecar |
| `PHOENIX_URL` | `http://localhost:4000` | How sidecar reaches Phoenix |
| `SIDECAR_PORT` | `4001` | Sidecar HTTP listen port |
| `POLL_INTERVAL_MS` | `30000` | Sidecar sync interval (ms) |
| `POOL_SIZE` | `10` | Database connection pool size |

---

## Deploying to a VPS (Manual)

### Prerequisites
- Docker and Docker Compose installed
- Domain name pointed to your server (optional, for HTTPS)

### Steps

```bash
# SSH into your server
ssh user@your-server

# Clone the repo
git clone <your-repo-url> weather_edge
cd weather_edge

# Create .env
cp .env.example .env
# Edit .env with your credentials
# Set PHX_HOST to your domain

# Build and start
docker compose up --build -d

# Verify
docker compose ps
curl http://localhost:4000/login
```

### HTTPS with Caddy (recommended)

Install Caddy as a reverse proxy in front of the app:

```bash
# Install Caddy
sudo apt install -y caddy

# /etc/caddy/Caddyfile
your-domain.com {
    reverse_proxy localhost:4000
}

# Reload
sudo systemctl reload caddy
```

Caddy auto-provisions TLS certificates via Let's Encrypt.

Update your `.env`:
```
PHX_HOST=your-domain.com
```

Then restart the app:
```bash
docker compose restart app
```

---

## Deploying to Fly.io

### Phoenix App

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Launch (creates fly.toml)
fly launch --no-deploy

# Set secrets
fly secrets set \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  DATABASE_URL="postgres://..." \
  POLYMARKET_PRIVATE_KEY="..." \
  POLYMARKET_API_KEY="..." \
  POLYMARKET_API_SECRET="..." \
  POLYMARKET_API_PASSPHRASE="..." \
  POLYMARKET_WALLET_ADDRESS="..." \
  AUTH_USERNAME="admin" \
  AUTH_PASSWORD="your-strong-password" \
  SIDECAR_SECRET="your-random-secret" \
  SIDECAR_URL="http://weather-edge-sidecar.internal:4001"

# Deploy
fly deploy
```

### Sidecar

```bash
cd sidecar

# Launch sidecar as a separate Fly app
fly launch --no-deploy --name weather-edge-sidecar

# Set secrets (same Polymarket creds)
fly secrets set \
  POLYMARKET_PRIVATE_KEY="..." \
  POLYMARKET_API_KEY="..." \
  POLYMARKET_API_SECRET="..." \
  POLYMARKET_API_PASSPHRASE="..." \
  POLYMARKET_WALLET_ADDRESS="..." \
  SIDECAR_SECRET="your-random-secret" \
  PHOENIX_URL="http://weather-edge.internal:4000" \
  SIDECAR_PORT="4001"

# Deploy
fly deploy
```

Both apps communicate over Fly's internal private network (`.internal` DNS).

---

## Deploying to Railway / Render

Both support multi-service from a single repo.

1. Create a **PostgreSQL** service (use TimescaleDB if available, otherwise standard Postgres)
2. Create a **web service** pointing to the repo root (Dockerfile at `./Dockerfile`)
3. Create a **worker service** pointing to `./sidecar` (Dockerfile at `./sidecar/Dockerfile`)
4. Set environment variables on each service as listed above
5. Make sure `SIDECAR_URL` on the app points to the sidecar's internal URL, and `PHOENIX_URL` on the sidecar points to the app's internal URL

---

## Architecture

```
                  +------------------+
                  |    Browser       |
                  |  (LiveView WS)   |
                  +--------+---------+
                           |
                           v
                  +------------------+
                  |   Phoenix App    |
                  |   :4000          |
                  |                  |
                  | - Dashboard UI   |
                  | - Forecast Engine|
                  | - Signal Detect  |
                  | - Oban Workers   |
                  +---+---------+----+
                      |         |
              DB queries    HTTP requests
                      |         |
                      v         v
              +-------+--+ +---+----------+
              |TimescaleDB| | Node Sidecar |
              |  :5432    | |   :4001      |
              |           | |              |
              | stations  | | @polymarket/ |
              | clusters  | | clob-client  |
              | snapshots | |              |
              | positions | | - Balance    |
              | signals   | | - Positions  |
              +-----------+ | - Orders     |
                            +--------------+
```

---

## Local Development (without Docker)

```bash
# Terminal 1: Database
docker compose up db

# Terminal 2: Phoenix
mix setup
mix phx.server

# Terminal 3: Sidecar
cd sidecar
npm install
export $(grep -v '^#' ../.env | xargs)
node index.js
```

---

## Troubleshooting

**Sidecar can't reach Phoenix**: Check `PHOENIX_URL`. In Docker Compose it should be `http://app:4000`, not `localhost`.

**App can't reach sidecar**: Check `SIDECAR_URL`. In Docker Compose it should be `http://sidecar:4001`.

**Balance shows $0**: Make sure the sidecar is running and `SIDECAR_SECRET` matches between both services.

**Orders fail**: The sidecar handles all signing. Make sure `POLYMARKET_PRIVATE_KEY` and API credentials are correct.

**Migrations fail**: Check `DATABASE_URL` is correct and the database is reachable. The entrypoint runs migrations automatically.

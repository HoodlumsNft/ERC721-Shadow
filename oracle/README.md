# Shadow Oracle Service

Oracle service for mirroring NFT ownership from Monad to ApeChain.

## Setup

1. Install dependencies:
```bash
pnpm install
```

2. Copy `.env.example` to `.env` and configure:
```bash
cp .env.example .env
```

3. Update the `.env` file with your values.

## Local Usage

### Start Live Listener
Listens for Transfer events on Monad and mirrors to ApeChain in real-time:
```bash
pnpm start
```

### Sync Existing Ownership
Syncs all existing token ownership from Monad to ApeChain:
```bash
pnpm run sync
```

### Development Mode (auto-restart)
```bash
pnpm run dev
```

## Docker Usage

### Build and Run
```bash
# Build the image
docker compose build

# Start the live listener (runs in background)
docker compose up -d

# View logs
docker compose logs -f oracle

# Stop
docker compose down
```

### Initial Sync (One-time)
```bash
# Run the sync service
docker compose --profile sync run --rm sync
```

### Check Status
```bash
docker compose ps
docker compose logs oracle
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           MONAD (Primary)                           │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Primary NFT Contract                                        │   │
│  │  0x4810C89F79fC1968e53b37958b3b59E216CF91Fa                 │   │
│  │                                                               │   │
│  │  Events: Transfer(from, to, tokenId)                         │   │
│  └─────────────────────────────────────┬───────────────────────┘   │
│                                         │                           │
└─────────────────────────────────────────┼───────────────────────────┘
                                          │
                            Oracle Listens│
                                          ▼
                      ┌───────────────────────────────────┐
                      │        ORACLE SERVICE (Node.js)   │
                      │                                   │
                      │  • Listens for Transfer events    │
                      │  • Batches updates (configurable) │
                      │  • Handles retries & errors       │
                      │  • Tracks processed blocks        │
                      └───────────────────┬───────────────┘
                                          │
                             Relays Updates│
                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          APECHAIN (Shadow)                          │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ShadowOracle Contract                                       │   │
│  │  0xa49633cF1d60BAf268caB1a44D1A0207B352991B                 │   │
│  │                                                               │   │
│  │  Functions: relayOwnershipBulk(), relayOwnershipPacked()     │   │
│  └─────────────────────────────────────┬───────────────────────┘   │
│                                         │                           │
│                                         ▼                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ERC721Shadow Contract                                       │   │
│  │  0x7Fbd7B2d493312727Bd03db9A82B886451ED5b49                 │   │
│  │                                                               │   │
│  │  Read-only ownership mirror                                   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Configuration

| Variable | Description |
|----------|-------------|
| `PRIVATE_KEY` | Private key of the relayer wallet |
| `MONAD_RPC_URL` | RPC endpoint for Monad |
| `APECHAIN_RPC_URL` | RPC endpoint for ApeChain |
| `PRIMARY_CONTRACT` | NFT contract address on Monad |
| `SHADOW_CONTRACT` | Shadow contract address on ApeChain |
| `ORACLE_CONTRACT` | ShadowOracle contract address on ApeChain |
| `BATCH_SIZE` | Number of transfers to batch before relaying (default: 10) |
| `BATCH_INTERVAL_MS` | Max time to wait before relaying a batch (default: 30000) |

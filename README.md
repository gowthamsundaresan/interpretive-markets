# interpretive-markets

Contracts + framework content + framework publishing tools for **interpretive prediction markets** — markets resolved by AI judges against registered evaluation frameworks. Built on EigenCloud (EigenAI for the inference, EigenCompute for the judge container, EigenDA + IPFS for re-execution bundles).

This repo is one of two:

- `interpretive-markets` (this repo) — Foundry contracts, framework content, `manager/` TS tools, and (later) the `judge/` EigenCompute app.
- `interpretive-markets-backend` — TS monorepo with the public API, chain indexer, and watcher (re-execution bot).

## Layout

```
src/                  Solidity sources (interfaces, core, libraries, utils)
test/                 Foundry tests
script/
  deploy/             Deployment scripts
  tasks/              Task scripts (register, create, resolve)
  configs/            Per-network config JSON
  outputs/            Deployment output JSON (written by deploy scripts)
frameworks/           Framework content (one directory per framework)
manager/              Nested TS package: pack + pin + register frameworks
```

## Contracts

- `FrameworkRegistry` — append-only registry. `id = sha256(framework tarball)`.
- `JudgeRegistry` — owner-gated binding from EigenCompute image digest → TEE-derived signer.
- `Market` — singleton (v0 stub). Stores per-market params and accepts judge-signed verdicts. Trading mechanics deferred to v1.

## Build & test

```bash
forge build
forge test
```

## Deploy to Sepolia

You need a `.env` (copy `.env.example`):

```
SEPOLIA_RPC_URL=https://...
DEPLOYER_PRIVATE_KEY=0x...
PINATA_JWT=...                  # only needed for the manager flow
```

Edit `script/configs/sepolia.json` to set the desired `owner` for `JudgeRegistry` (leave empty to default to the deployer).

```bash
source .env
forge script script/deploy/DeployRegistries.s.sol:DeployRegistries \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string)" -- "sepolia"
```

This writes `script/outputs/sepolia/deployment.json` with the deployed addresses.

## Publish a framework

The `manager/` package packs a framework directory, pins it to IPFS via Pinata, and registers the resulting hash + URI on-chain.

```bash
cd manager
cp .env.example .env   # fill in NETWORK, *_RPC_URL, DEPLOYER_PRIVATE_KEY, PINATA_JWT
npm install
npm run publish-framework football-player-value-v1
```

To publish every directory under `frameworks/` (skipping `_template`):

```bash
npm run publish-all
```

Individual stages can also be run separately for debugging:

```bash
npm run pack-framework football-player-value-v1
npm run pin-framework football-player-value-v1
npm run register-framework <id> <ipfs://cid>
```

## Run the judge (EigenCompute app)

The `judge/` nested package is a Fastify + worker app. It accepts `POST /resolve/:marketId` (auth-gated), runs the full pipeline (load framework → fetch data → call EigenAI → upload bundle → post verdict on-chain), and exposes `GET /resolve/:marketId` for status.

The judge depends on `@interpretive/shared` from the sibling `interpretive-markets-backend` repo via a plain symlink (no `npm link` / `bun link`).

```bash
cd judge
cp .env.example .env   # fill in MNEMONIC, JUDGE_API_KEY, EIGENAI_API_KEY, SEPOLIA_RPC_URL, PINATA_JWT, DEPLOYMENT_FILE
npm install
npm run link-shared    # creates node_modules/@interpretive/shared → ../../../../interpretive-markets-backend/packages/shared
npm run dev            # local: tsx watch
# or
npm run build && npm start
```

To deploy as an EigenCompute app, `judge/Dockerfile` is set up for `linux/amd64`. The `judge/ecloud.yaml` declares the runtime + secrets. Build context must include both this repo and `interpretive-markets-backend/` so the symlink resolves inside the image:

```bash
cd /Users/gowtham/Projects   # parent of both repos
docker build -f interpretive-markets/judge/Dockerfile -t interpretive-judge:v0 .
# then: ecloud compute app deploy   (per EigenCloud CLI)
```

After deploying, record the image digest and register it in `JudgeRegistry`:

```bash
forge script script/tasks/RegisterJudge.s.sol:RegisterJudge \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string,bytes32,address)" -- "sepolia" <imageDigest> <signerAddress>
```

The judge's signer address is logged at startup (`"judge running with signer 0x…"`). It's derived from `MNEMONIC` via viem's `mnemonicToAccount` — in EigenCompute production, that mnemonic comes from `process.env.MNEMONIC` injected into the TEE by KMS.

## End-to-end publish runbook (v0)

Assumes both `interpretive-markets` and `interpretive-markets-backend` are cloned as siblings.

```bash
# 0. install ecloud cli + foundry deps
npm i -g @layr-labs/ecloud-cli
ecloud auth login
ecloud billing subscribe

# 1. deploy contracts to sepolia
cd interpretive-markets
cp .env.example .env   # fill SEPOLIA_RPC_URL + DEPLOYER_PRIVATE_KEY (+ETHERSCAN_API_KEY optional)
source .env
forge script script/deploy/DeployRegistries.s.sol:DeployRegistries \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string)" -- "sepolia"
# → script/outputs/sepolia/deployment.json now has frameworkRegistry / judgeRegistry / market addresses

# 2. publish the Pedri framework (pack + pin + register)
cd manager
cp .env.example .env   # NETWORK=sepolia + same SEPOLIA_RPC_URL/DEPLOYER_PRIVATE_KEY + PINATA_JWT
npm install
npm run publish-framework football-player-value-v1
# → frameworkId logged + on-chain registration confirmed

# 3. bring up backend (postgres + api + seeder + watcher)
cd ../../interpretive-markets-backend
docker-compose up -d
cp .env.example .env   # DATABASE_URL is fine as-is for local
nvm exec 22 npm install
nvm exec 22 npm run prisma:migrate -w @interpretive/prisma
# fill each package's .env (DEPLOYMENT_FILE = absolute path to ../interpretive-markets/script/outputs/sepolia/deployment.json)
# in separate terminals:
nvm exec 22 npm run dev -w @interpretive/api      # 3000
nvm exec 22 npm run dev -w @interpretive/seeder
nvm exec 22 npm run dev -w @interpretive/watcher

# 4. build + deploy judge to EigenCompute
cd ../interpretive-markets/judge
cp .env.example .env   # MNEMONIC (local only), JUDGE_API_KEY, EIGENAI_API_KEY, SEPOLIA_RPC_URL, PINATA_JWT, DEPLOYMENT_FILE
npm install && npm run link-shared
cd /Users/gowtham/Projects   # build context must include both repos
docker build --platform linux/amd64 \
  -f interpretive-markets/judge/Dockerfile \
  -t interpretive-judge:v0 .
ecloud compute app create --name interpretive-judge --language typescript
ecloud compute app deploy   # records the image digest

# 5. fund the judge's TEE-derived signer address with ~0.01 Sepolia ETH
#    (the judge logs it at startup; resolve() costs gas)

# 6. register the judge image digest → signer mapping on-chain
cd ../interpretive-markets
forge script script/tasks/RegisterJudge.s.sol:RegisterJudge \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string,bytes32,address)" -- "sepolia" <imageDigest> <judgeSignerAddress>

# 7. create the Pedri market (resolutionTime in the past so it's immediately resolvable)
cd manager
npm run create-market \
  "Is Erling Haaland more valuable to Manchester City than Kylian Mbappe is to Real Madrid?" \
  "football-player-value-v1" \
  "https://<your-api-host>/api/v1/evidence/haaland-mbappe-2024" \
  "$(($(date +%s) - 60))" \
  "<imageDigest>"
# → marketId logged

# 8. trigger resolution
curl -X POST https://<judge-host>/resolve/<marketId> -H "x-api-key: $JUDGE_API_KEY"
# → 202 Accepted, judge runs the pipeline

# 9. observe
curl http://localhost:3000/api/v1/markets/<marketId>             # seeder picks it up within 30s
curl http://localhost:3000/api/v1/markets/<marketId>/verdict     # outcome + confidence + bundleRef
# watcher polls every 60s — should flip reExecStatus from `pending` → `verified`
```

If step 9 shows `reExecStatus: verified` then the determinism story works end-to-end and v0 is live.

## What's next

- `interpretive-markets-backend` — Postgres-backed API, chain indexer (seeder), and re-execution watcher (now live).
- Step 4 (deferred): swap the judge's direct-HTTPS data fetcher (`judge/src/services/data.ts`) for Opacity zkTLS — same `evidenceUrl` indirection means no changes to market creation.
- Step 7 (deferred): MarketFactory + YES/NO pool mechanics + settlement.

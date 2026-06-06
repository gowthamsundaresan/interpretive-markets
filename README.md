# interpretive-markets

Prediction markets resolved by AI judges against registered evaluation frameworks. Built on **Ritual L1** — `0x080C` Sovereign Agent investigator + `0x0802` LLM precompile judge, glued by an async-callback `Market.sol` that runs both stages atomically in one transaction.

## Why this exists

Truth comes in three flavours:

1. **Objective** — _"Roses are red."_ A fact of nature, deterministically observable.
2. **Subjective** — _"Violets are perfection."_ The observer's own experience is the only backing. Can be described, chosen to be believed, but not transmitted.
3. **Intersubjective** — _"Donald Trump won the election."_ Not directly observable, but reasonable humans who share a construct (here: the institutional rules of representative democracy) will agree on it.

Most human coordination systems (money, judiciary, markets) verify some combination of objective and intersubjective claims. Crypto stacks each of these:

- **L1 blockchains** verify on-chain state. Whatever is on-chain is true by virtue of being on-chain.
- **Oracles** verify off-chain facts (price feeds, sports results, weather) and import them on-chain.
- **Restaking / EigenLayer** verifies off-chain computation — "did this Docker image run with these inputs and produce that output?"

What none of them verify is **interpretive truth**: intersubjective claims that can be resolved differently depending on which _evaluation framework_ you apply. Given the same evidence, two valid frameworks can produce two different resolutions — each interpretively true within its own framework.

> _"Is Pedri Barcelona's most valuable player?"_ is an interpretive problem. Frameworks could weight on-field stats, transfer value, public sentiment, longevity, big-game starts, captaincy — each weighting produces a defensible verdict. An observer who rejects the framework will not recognise the verdict as truth.

> _"Did Arsenal win?"_ is **not** an interpretive problem. The rules of football are universally accepted.

LLMs are remarkably good at interpretation. Given a question, an evaluation framework, and unstructured evidence, they can reason out a defensible resolution. As verifiable AI matures, an arc of interpretive adjudication moving to AI becomes plausible.

**Near-term**, that looks like _interpretive prediction markets_ — markets predicated on reasoning, where multiple competing frameworks can be registered for the same question, and order flow votes on which framework people trust.

**Medium-term**, the same primitive scales to **cloud courts**: sovereign AI agents with property rights need arbitration on the internet, and internet societies can track, vote for, and propose changes to the frameworks they want their disputes resolved against.

## How it works

A market is a tuple `(question, frameworkId, sourceAllowlist, dossierPathPrefix, dossierSubjects, resolutionTime, cliType, model, ...)` committed on-chain at creation. All immutable. At resolution time:

1. The **operator** (a thin watch-and-kick service in `operator/`) deposits to `RitualWallet`, checks `AsyncJobTracker.hasPendingJobForSender`, and calls `Market.startInvestigation(marketId)`.
2. `Market.sol` invokes `RitualSystem.investigate(...)` against the `0x080C` Sovereign Agent precompile with the framework's `investigator.md` as `systemPrompt`, the `dossierV1.json` schema + `judge.md` as `skills[]`, `tools=["fetch_http"]`, `cliType=0` (Claude Code in TEE).
3. The Sovereign Agent (headless one-shot job inside Ritual's TEE) crawls the `sourceAllowlist`, structures the dossier into Tier 1/2/3 evidence, pins it to IPFS, **also pre-assembles the canonical judge `messagesJson`**. Returns via two-phase `AsyncDelivery` callback.
4. `Market.onSovereignAgentResult(jobId, result)` runs in one atomic transaction: `msg.sender == ASYNC_DELIVERY` check → decode `(dossierCid, messagesJson)` → emit `InvestigationDelivered` → call `0x0802` LLM precompile SPC inline (GLM-4.7-FP8, `temperature=0`, `seed=marketId`, `reasoningEffort=medium`) → emit `JudgmentDelivered` → parse verdict via `solady-json` → apply `HarnessRules` → emit `VerdictFinalized` (or `MalformedVerdict` on parse / range / citation / subject failure).
5. An off-chain watcher (companion backend repo) runs a consistency audit — recomputes `keccak256(abi.encode(marketId, frameworkId, question, sourceAllowlist))` and the canonical prompt hash from `judge.md + dossier + question`, cross-checks against the emitted values, and files `Market.disputeAttestation` on mismatch. **No re-execution; hash comparison only.**

### Why a single callback

`0x0802` is **SPC (Short Async)**, not two-phase async — result returns inline in the calling tx's receipt. The first design called for two `AsyncDelivery` callbacks (one for investigation, one for judgment); collapsing them eliminates a sender-lock window and gives the watcher one atomic transaction to audit.

### Why correctness is not byte-equality

`0x0802` runs GLM-4.7-FP8 — FP8 precision + GPU non-associativity → two honest executors produce different bytes. The original EigenCloud-style "watcher re-runs and SHA-256 matches" design **does not port**. Correctness instead means "executor was attested, request binding was honest, canonical prompt was the prompt, harness rules applied as written."

## Frameworks (two-role)

A framework is a content-addressed tarball with four required files:

- `investigator.md` — evidence-gathering spec: tier-by-tier collection rules, source-allowlist discipline, balance rules, fetch_http tool surface, **final-output assembly contract** (the investigator pre-assembles the judge `messagesJson` from `judge.md` + dossier + question).
- `judge.md` — adjudication spec: tier weighting, abstention rule, strict output schema (`outcome` 0|1|2, `confidence_bps` 0–10000, `driving_tier` 1|2|3, `subject_ref`, `dossier://` citations, `rationale_hash` 32-byte).
- `schemas/dossierV1.json` — JSON Schema for the dossier envelope.
- `manifest.json` — `model.id` (default `zai-org/GLM-4.7-FP8`), `sampling` (incl. `reasoningEffort: medium`), `outputSchema` (the verdict shape), `roles { investigator, judge }`.

The tarball is SHA-256'd to produce `frameworkId`. The registry stores `id → (uri, author, metadata)` — append-only, never updated. Once a framework is registered, no actor — not the market creator, not the operator, not the agent — can alter what the rules say.

The repo ships with [`frameworks/football-player-value-v1/`](./frameworks/football-player-value-v1) as a reference (v2.1.0). It resolves binary questions about a football player's value to their club (e.g. _"Is Erling Haaland more valuable to Manchester City than Kylian Mbappé is to Real Madrid?"_) using the tier framing.

See [`frameworks/_template/`](./frameworks/_template) to author your own.

## Build and test

```bash
forge build
forge test                  # 59 tests across 6 suites
```

## Deploy your own instance

```bash
cp .env.example .env       # fill RITUAL_RPC_URL, DEPLOYER_PRIVATE_KEY, PINATA_JWT
source .env

# 1. Deploy registries + market + system wrapper to Ritual L1
forge script script/deploy/DeployRegistries.s.sol:DeployRegistries \
  --rpc-url $RITUAL_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string)" -- "ritual"

# 2. Publish the framework (pack → pin to IPFS → register on-chain)
cd manager && npm install
npm run pin-framework football-player-value-v1
npm run register-framework -- <id> <uri> 0x

# 3. Create a market (edit market.example.json with your params first)
cp ../script/tasks/market.example.json my-market.json
$EDITOR my-market.json
npx tsx src/workflows/createMarket.ts my-market.json

# 4. Run the operator (watch-and-kick service)
cd ../operator && npm install
npm run start              # polls Market.get(...), kicks startInvestigation when ready
```

## Companion backend

The companion repo [`interpretive-markets-backend`](https://github.com/gowthamsundaresan/interpretive-markets-backend) hosts the off-chain pieces:

- **`shared`** — typed ABIs, content-addressing utilities, Ritual system constants.
- **`api`** — Fastify HTTP read API over the persisted state.
- **`seeder`** — chain → Postgres event indexer.
- **`watcher`** — consistency audit + dispute filing.
- **`eval-harness`** — held-out cases + scorer stack + blind-labelling pipeline + Foundry oracle for rules enforcement.
- **`prisma`** — Postgres schema + generated client.

## License

MIT.

# interpretive-markets

Prediction markets resolved by AI judges against registered evaluation frameworks. Built on EigenCloud.

## Why this exists

Truth comes in three flavors:

1. **Objective** — *"Roses are red."* A fact of nature, deterministically observable.
2. **Subjective** — *"Violets are perfection."* The observer's own experience is the only backing. Can be described, chosen to be believed, but not transmitted.
3. **Intersubjective** — *"Donald Trump won the election."* Not directly observable, but reasonable humans who share a construct (here: the institutional rules of representative democracy) will agree on it.

Most human coordination systems (money, judiciary, markets) verify some combination of objective and intersubjective claims. Crypto stacks each of these:

- **L1 blockchains** verify on-chain state. Whatever is on-chain is true by virtue of being on-chain.
- **Oracles** verify off-chain facts (price feeds, sports results, weather) and import them on-chain.
- **Restaking / EigenLayer** verifies off-chain computation — "did this Docker image run with these inputs and produce that output?"

What none of them verify is **interpretive truth**: intersubjective claims that can be resolved differently depending on which *evaluation framework* you apply. Given the same evidence, two valid frameworks can produce two different resolutions — each interpretively true within its own framework.

> *"Is Pedri Barcelona's most valuable player?"* is an interpretive problem. Frameworks could weight on-field stats, transfer value, public sentiment, longevity, big-game starts, captaincy — each weighting produces a defensible verdict. An observer who rejects the framework will not recognise the verdict as truth.

> *"Did Arsenal win?"* is **not** an interpretive problem. The rules of football are universally accepted.

LLMs are remarkably good at interpretation. Given a question, an evaluation framework, and unstructured evidence, they can reason out a defensible resolution. As verifiable AI matures, an arc of interpretive adjudication moving to AI becomes plausible.

**Near-term**, that looks like *interpretive prediction markets* — markets predicated on reasoning, where multiple competing frameworks can be registered for the same question, and order flow votes on which framework people trust.

**Medium-term**, the same primitive scales to **cloud courts**: sovereign AI agents with property rights need arbitration on the internet, and internet societies can track, vote for, and propose changes to the frameworks they want their disputes resolved against.

## How it works

A market is a tuple `(question, framework_id, data_source, model_id, prompt_hash, resolution_time, judge_id)` committed on-chain at creation. All immutable. At resolution time:

1. An auth-gated **judge** running in an Intel TDX TEE on EigenCompute reads the market params.
2. It fetches the **framework** tarball from IPFS, verifies its `sha256 == framework_id` against the on-chain `FrameworkRegistry`.
3. Fetches **evidence** via the registered data source (an HTTPS URL today; Opacity zkTLS later).
4. Assembles a deterministic prompt and calls **EigenAI** (deterministic LLM inference) — or via the EigenCloud AI Gateway in non-deterministic mode.
5. Uploads a **re-execution bundle** to IPFS — the full inputs, prompt, response, and SHA-256s, so a watcher can re-run the inference and verify byte equality.
6. Signs the verdict with its **TEE-derived key** and posts it on-chain via `Market.resolve()`.

A separate **watcher** service polls for newly posted verdicts, pulls each re-exec bundle, re-runs the inference, and either marks it `verified` or files `disputeVerdict()` on byte mismatch.

## Live deployment

| | Sepolia |
|---|---|
| `FrameworkRegistry` | [`0x2eC5ddAfB0b6e6e25CE5e906CB3Cb3cf3F6dB88d`](https://sepolia.etherscan.io/address/0x2eC5ddAfB0b6e6e25CE5e906CB3Cb3cf3F6dB88d) |
| `JudgeRegistry` | [`0x17993708486461A22Fdd2F318AD38B2A9847c8f2`](https://sepolia.etherscan.io/address/0x17993708486461A22Fdd2F318AD38B2A9847c8f2) |
| `Market` | [`0xF973768571c771AD2CA2f2671964EFce9218267B`](https://sepolia.etherscan.io/address/0xF973768571c771AD2CA2f2671964EFce9218267B) |
| Pedri framework | `0x627521cfe327f54fab2fbc347e65db793af7050261b23bb749d7450dee25a40f` (IPFS `QmZpT2JJCWACtkLcexuBFzTyURtUyf4GXL7CW2bHeiqREL`) |
| Judge (EigenCompute) | App `0xa6DC8b0EA1fc8CDe102c5DFF7F599a0Ec51e70FA` · IP `34.158.46.65:3001` · [attestation](https://verify-sepolia.eigencloud.xyz/app/0xa6DC8b0EA1fc8CDe102c5DFF7F599a0Ec51e70FA) |

## Frameworks

A framework is a content-addressed tarball with three required files:

- `framework.md` — instructions for the AI judge: scope, decision rules, hard constraints, expected output schema
- `manifest.json` — pinned model id, sampling params (temperature, seed, top_p, max_tokens), prompt template, evidence schema reference
- `schemas/<name>.json` — JSON Schema for the evidence payload the judge expects

The tarball is SHA-256'd to produce `framework_id`. The registry stores `id → (uri, author, metadata)` — append-only, never updated. Anyone who fetches the IPFS bytes can verify the hash matches the on-chain id.

The repo ships with [`frameworks/football-player-value-v1/`](./frameworks/football-player-value-v1) as a reference. It resolves binary questions about a football player's value to their club (e.g. *"Is Erling Haaland more valuable to Manchester City than Kylian Mbappé is to Real Madrid?"*), weighting on-pitch production, availability, role importance, market value, and tactical dependence.

See [`frameworks/_template/`](./frameworks/_template) to author your own.

## Repo layout

```
src/                  Solidity (Foundry, 0.8.27, via_ir)
  interfaces/         IFrameworkRegistry, IJudgeRegistry, IMarket
  core/               FrameworkRegistry, JudgeRegistry, Market
  libraries/          ResolutionTypes (Verdict struct)
  utils/              SignatureVerifier
test/                 Foundry tests + MockJudge helper
script/
  deploy/             DeployRegistries
  tasks/              RegisterFramework, RegisterJudge, CreateMarket
  configs/            sepolia.json, mainnet.json
  outputs/            Deployment records (per network)
frameworks/           Framework content, one dir per framework
manager/              Nested TS package — pack, pin, register framework workflows
judge/                Nested TS package — Fastify + worker; the EigenCompute app
```

The companion repo [`interpretive-markets-backend`](https://github.com/gowthamsundaresan/interpretive-markets-backend) hosts the Postgres-backed indexer (`seeder`), the public read API, and the re-execution watcher.

## Build and test

```bash
forge build
forge test
```

26 tests across `FrameworkRegistry`, `JudgeRegistry`, and `Market` covering happy paths, revert conditions, signature recovery, and double-resolve / double-dispute guards.

## Deploy your own instance

For forking the system to your own network or chain.

```bash
cp .env.example .env
# fill SEPOLIA_RPC_URL + DEPLOYER_PRIVATE_KEY + PINATA_JWT
source .env

# 1. Deploy registries + market
forge script script/deploy/DeployRegistries.s.sol:DeployRegistries \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string)" -- "sepolia"

# 2. Publish a framework (pack + pin to IPFS + register on-chain)
cd manager && npm install
npm run publish-framework football-player-value-v1
```

To run the judge in EigenCompute:

```bash
cd judge && npm install && cp .env.example .env
# fill JUDGE_API_KEY (any random secret), PINATA_JWT, SEPOLIA_RPC_URL
npm run deploy   # prepare-deploy + ecloud compute app deploy
```

Note your TEE-derived judge signer from the boot logs, fund it with a small amount of Sepolia ETH (it pays gas for `resolve()`), then register the image digest → signer mapping:

```bash
forge script script/tasks/RegisterJudge.s.sol:RegisterJudge \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --sig "run(string,bytes32,address)" -- "sepolia" <imageDigest> <signerAddress>
```

Create a market with a framework, evidence URL, and resolution time:

```bash
cd manager
npm run create-market \
  "Is Erling Haaland more valuable to Manchester City than Kylian Mbappé is to Real Madrid?" \
  "football-player-value-v1" \
  "https://<api-host>/api/v1/evidence/haaland-mbappe-2024" \
  $(( $(date +%s) - 60 )) \
  "<imageDigest>"
```

Trigger resolution:

```bash
curl -X POST https://<judge-host>/resolve/<marketId> -H "x-api-key: $JUDGE_API_KEY"
```

The judge runs the pipeline, posts the verdict on-chain. The watcher picks it up and verifies via TEE attestation (gateway mode) or byte-equality re-execution (EigenAI mode).

## Inference paths

The judge supports two modes via `INFERENCE_PATH`:

- **`gateway`** (default) — uses `@layr-labs/ai-gateway-provider` + Vercel AI SDK, routing to commodity LLMs (Claude, GPT) via TEE-attested JWT. No API key needed; works inside EigenCompute out of the box. Not bit-exact reproducible — verifiability comes from the TEE attestation of the judge image + signed verdict.
- **`eigenai`** — direct call to EigenAI's deterministic inference API (`X-API-Key` auth, currently allowlist-gated). Bit-exact reproducible: any watcher can re-run the same prompt and SHA-256-match the response. Required for the full optimistic re-execution dispute model.

Frameworks pin a `model.id`. For `gateway` mode use a provider-prefixed model id like `anthropic/claude-sonnet-4.6`. For `eigenai` mode use a supported deterministic model like `gpt-oss-120b-f16`.

## Roadmap

- **Opacity zkTLS for evidence fetching** — the judge currently fetches evidence over plain HTTPS. Swapping to Opacity makes the evidence cryptographically notarized so re-executors don't have to trust the data source.
- **Market mechanics** — current `Market` is a stub. Next: `MarketFactory` + YES/NO LMSR or CPMM pools + settlement using the on-chain verdict.
- **EigenAI mainnet allowlist** — for v0 the judge defaults to gateway mode; switching to deterministic EigenAI is a one-env-var change once allowlist access lands.
- **Cloud courts** — generalizing the framework registry to arbitrate disputes between sovereign agents, with framework reputation, versioning, and challenge mechanics.

## License

MIT.

#!/usr/bin/env bash
# ============================================================================
# Phase-0.5 testnet probe driver
#
# Submits one Sovereign Agent job in the configured PROBE_MODE and prints all
# evidence needed to resolve the three Phase-0.5 concerns:
#
#   1. tools[] enforcement (adversarial prompt + tight allowlist → does the
#      runtime allow, refuse, or report-and-skip the out-of-list tool call?)
#   2. TEE attestation scope (read TEEServiceRegistry; inspect what's bound)
#   3. Phase-2 bytes result decode (raw bytes + canonical decode dump)
#
# Required env (fails fast if missing or placeholder):
#   RPC_URL        — Ritual RPC (e.g. https://rpc.ritualfoundation.org)
#   PRIVATE_KEY    — 0x-prefixed funded operator key
#   HF_TOKEN       — HuggingFace token (write access to HF_REPO_ID)
#   HF_REPO_ID     — HuggingFace dataset ID in user/repo form
#   MODEL          — exact provider model id (e.g. claude-sonnet-4-5-20250929)
#   One LLM key: ANTHROPIC_API_KEY | OPENAI_API_KEY | GEMINI_API_KEY | OPENROUTER_API_KEY
#
# Optional env:
#   PROBE_MODE       — baseline | adversarial-tool | empty-tools  (default: adversarial-tool)
#   CLI_TYPE         — 0 (claude_code, default) | 5 (crush) | 6 (zeroclaw)
#   PHASE2_TIMEOUT   — seconds to wait for callback (default 300)
#   CONSUMER_ADDRESS — reuse an already-deployed Phase05Probe
#   EXECUTOR_TEE_ADDRESS — pin a specific executor (default: first valid HTTP_CALL service)
#
# Prerequisites: forge, cast, uv (https://astral.sh/uv)
# ============================================================================
set -euo pipefail

require_real_value() {
    local name="$1"; local value="${2-}"; local hint="${3:-set it to a real value}"
    if [ -z "$value" ]; then
        echo "ERROR: $name is required — $hint" >&2; exit 2
    fi
    case "$value" in
        *"<"*|*">"*|*YOUR_*|*YOUR-*)
            echo "ERROR: $name looks like an unfilled placeholder ('$value') — $hint" >&2; exit 2;;
    esac
}

require_real_value RPC_URL "${RPC_URL:-}" "e.g. https://rpc.ritualfoundation.org"
require_real_value PRIVATE_KEY "${PRIVATE_KEY:-}" "0x-prefixed funded key"
require_real_value HF_TOKEN "${HF_TOKEN:-}" "HF token (hf_...) with write access to HF_REPO_ID"
require_real_value HF_REPO_ID "${HF_REPO_ID:-}" "HF dataset ID in user/repo form"

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is required (curl -LsSf https://astral.sh/uv/install.sh | sh)" >&2; exit 1
fi

if ! command -v forge >/dev/null 2>&1; then
    echo "ERROR: forge is required (curl -L https://foundry.paradigm.xyz | bash && foundryup)" >&2; exit 1
fi

PY_HELPER=(uv run --quiet --with eciespy --with eth-abi --with web3 python3)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WALLET="0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948"
REGISTRY="0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"
TRACKER="0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5"

PROBE_MODE="${PROBE_MODE:-adversarial-tool}"
CLI_TYPE="${CLI_TYPE:-0}"
PHASE1_GAS_LIMIT="${PHASE1_GAS_LIMIT:-900000}"
PHASE2_TIMEOUT="${PHASE2_TIMEOUT:-300}"
MIN_RITUAL_WALLET_WEI="${MIN_RITUAL_WALLET_WEI:-1000000000000000000}"  # 1 RIT
DEPOSIT_WEI="${DEPOSIT_WEI:-5000000000000000000}"                       # 5 RIT
LOCK_BLOCKS="${LOCK_BLOCKS:-100000000}"
EXECUTOR_TEE_ADDRESS="${EXECUTOR_TEE_ADDRESS:-}"
CONSUMER_ADDRESS="${CONSUMER_ADDRESS:-}"

SENDER=$(cast wallet address "$PRIVATE_KEY")
echo "=================================================================="
echo "  Phase-0.5 probe"
echo "=================================================================="
echo "  sender:     $SENDER"
echo "  chain:      $(cast chain-id --rpc-url "$RPC_URL")"
echo "  probe-mode: $PROBE_MODE"
echo "  cli-type:   $CLI_TYPE"
echo "=================================================================="

case "$CLI_TYPE" in
    0|5|6) ;;
    *) echo "ERROR: CLI_TYPE must be 0 (claude_code), 5 (crush), or 6 (zeroclaw)" >&2; exit 1;;
esac

# ── 1. Inspect TEEServiceRegistry (Concern 2) ──
echo
echo "=== [1/6] inspect TEEServiceRegistry executors ==="
"${PY_HELPER[@]}" "$SCRIPT_DIR/helpers.py" \
    --rpc "$RPC_URL" --registry "$REGISTRY" --inspect-executor

# ── 2. Check sender lock ──
echo
echo "=== [2/6] check AsyncJobTracker sender lock ==="
PENDING=$(cast call "$TRACKER" "hasPendingJobForSender(address)(bool)" "$SENDER" --rpc-url "$RPC_URL" | awk '{print $1}')
echo "hasPendingJobForSender($SENDER) = $PENDING"
if [ "$PENDING" = "true" ]; then
    echo "ERROR: sender has a pending async job. Wait for it to expire or use a different key." >&2; exit 1
fi

# ── 3. Fund RitualWallet ──
echo
echo "=== [3/6] check + top up RitualWallet ==="
WALLET_BAL=$(cast call "$WALLET" "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$RPC_URL" | awk '{print $1}')
echo "RitualWallet balance: $WALLET_BAL wei"
if [ "$WALLET_BAL" -lt "$MIN_RITUAL_WALLET_WEI" ]; then
    echo "Depositing $DEPOSIT_WEI wei, lock=$LOCK_BLOCKS blocks..."
    cast send "$WALLET" "deposit(uint256)" "$LOCK_BLOCKS" \
        --value "$DEPOSIT_WEI" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" >/dev/null
    echo "Funded. New balance: $(cast call "$WALLET" "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$RPC_URL" | awk '{print $1}') wei"
fi

# ── 4. Deploy Phase05Probe consumer ──
echo
echo "=== [4/6] deploy Phase05Probe consumer ==="
if [ -n "$CONSUMER_ADDRESS" ]; then
    CONSUMER="$CONSUMER_ADDRESS"
    echo "reusing consumer: $CONSUMER"
else
    DEPLOY_OUT=$(forge create --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" \
        --broadcast "$SCRIPT_DIR/Phase05Probe.sol:Phase05Probe" 2>&1)
    CONSUMER=$(printf '%s\n' "$DEPLOY_OUT" | awk '/Deployed to:/ {print $3}' | tail -n1)
    if [ -z "$CONSUMER" ]; then
        echo "ERROR: could not extract deployed consumer address" >&2
        printf '%s\n' "$DEPLOY_OUT" >&2
        exit 1
    fi
    echo "deployed consumer: $CONSUMER"
fi

# ── 5. Build secrets blob + encode request ──
echo
echo "=== [5/6] encode SovereignAgentRequest ==="
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    SECRETS_JSON=$(uv run --quiet python3 -c "import json,os; print(json.dumps({'ANTHROPIC_API_KEY': os.environ['ANTHROPIC_API_KEY'], 'HF_TOKEN': os.environ['HF_TOKEN']}))")
elif [ -n "${OPENAI_API_KEY:-}" ]; then
    SECRETS_JSON=$(uv run --quiet python3 -c "import json,os; print(json.dumps({'LLM_PROVIDER': 'openai', 'OPENAI_API_KEY': os.environ['OPENAI_API_KEY'], 'HF_TOKEN': os.environ['HF_TOKEN']}))")
elif [ -n "${GEMINI_API_KEY:-}" ]; then
    SECRETS_JSON=$(uv run --quiet python3 -c "import json,os; print(json.dumps({'LLM_PROVIDER': 'gemini', 'GEMINI_API_KEY': os.environ['GEMINI_API_KEY'], 'HF_TOKEN': os.environ['HF_TOKEN']}))")
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
    SECRETS_JSON=$(uv run --quiet python3 -c "import json,os; print(json.dumps({'LLM_PROVIDER': 'openrouter', 'OPENROUTER_API_KEY': os.environ['OPENROUTER_API_KEY'], 'HF_TOKEN': os.environ['HF_TOKEN']}))")
else
    echo "ERROR: set ANTHROPIC_API_KEY | OPENAI_API_KEY | GEMINI_API_KEY | OPENROUTER_API_KEY" >&2; exit 1
fi
: "${MODEL:?Set MODEL to exact provider model id, e.g. claude-sonnet-4-5-20250929}"

BUILD_ARGS=(
    --rpc "$RPC_URL"
    --registry "$REGISTRY"
    --consumer "$CONSUMER"
    --secrets "$SECRETS_JSON"
    --cli-type "$CLI_TYPE"
    --model "$MODEL"
    --probe-mode "$PROBE_MODE"
    --hf-repo-id "$HF_REPO_ID"
)
if [ -n "$EXECUTOR_TEE_ADDRESS" ]; then
    BUILD_ARGS+=(--executor-tee-address "$EXECUTOR_TEE_ADDRESS")
fi

ENCODE_OUTPUT=$("${PY_HELPER[@]}" "$SCRIPT_DIR/helpers.py" "${BUILD_ARGS[@]}")
echo "$ENCODE_OUTPUT"
EXECUTOR=$(printf '%s\n' "$ENCODE_OUTPUT" | awk -F= '$1=="EXECUTOR"{print $2}')
REQUEST_INPUT=$(printf '%s\n' "$ENCODE_OUTPUT" | awk -F= '$1=="REQUEST_INPUT"{print $2}')
if [ -z "$EXECUTOR" ] || [ -z "$REQUEST_INPUT" ]; then
    echo "ERROR: encode step did not produce EXECUTOR + REQUEST_INPUT" >&2; exit 1
fi

# ── 6. Submit Phase 1 and poll for Phase 2 ──
echo
echo "=== [6/6] submit + poll ==="
FROM_BLOCK=$(cast block-number --rpc-url "$RPC_URL")
echo "from-block: $FROM_BLOCK"
TX_HASH=$(cast send "$CONSUMER" 'callSovereignAgent(bytes)' "$REQUEST_INPUT" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --gas-limit "$PHASE1_GAS_LIMIT" --async)
echo "Phase 1 tx: $TX_HASH"

echo
echo "polling for Phase 2 (up to ${PHASE2_TIMEOUT}s)..."
"${PY_HELPER[@]}" "$SCRIPT_DIR/helpers.py" \
    --rpc "$RPC_URL" --poll-phase2 \
    --consumer "$CONSUMER" --tx-hash "$TX_HASH" \
    --from-block "$FROM_BLOCK" --timeout "$PHASE2_TIMEOUT"

echo
echo "=================================================================="
echo "  probe complete. capture the output above into docs/BUILD_LOG.md"
echo "=================================================================="
echo "  consumer:  $CONSUMER"
echo "  executor:  $EXECUTOR"
echo "  tx hash:   $TX_HASH"
echo "  from-block: $FROM_BLOCK"
echo "=================================================================="

#!/usr/bin/env python3
"""Phase-0.5 probe helpers — ABI encoding + Phase-2 event polling.

Adapted from examples/sovereign-agent/helpers.py in the Ritual skill repo
(github.com/ritual-foundation/ritual-dapp-skills), extended with:

  - `--probe-mode {baseline,adversarial-tool,empty-tools}` to script the three
    tools-enforcement variants the Phase-0.5 plan calls for.
  - Verbose dump of the raw Phase-2 result bytes and decoded fields so the
    BUILD_LOG entry can quote them verbatim.
"""

import argparse
import json
import re
import sys
import time

from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import decode, encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12


TEE_SERVICE_REGISTRY_ABI = [
    {
        "name": "getServicesByCapability",
        "type": "function",
        "stateMutability": "view",
        "inputs": [{"name": "capability", "type": "uint8"}, {"name": "checkValidity", "type": "bool"}],
        "outputs": [
            {
                "name": "",
                "type": "tuple[]",
                "components": [
                    {
                        "name": "node",
                        "type": "tuple",
                        "components": [
                            {"name": "paymentAddress", "type": "address"},
                            {"name": "teeAddress", "type": "address"},
                            {"name": "teeType", "type": "uint8"},
                            {"name": "publicKey", "type": "bytes"},
                            {"name": "endpoint", "type": "string"},
                            {"name": "certPubKeyHash", "type": "bytes32"},
                            {"name": "capability", "type": "uint8"},
                        ],
                    },
                    {"name": "isValid", "type": "bool"},
                    {"name": "workloadId", "type": "bytes32"},
                ],
            }
        ],
    }
]


SOVEREIGN_REQUEST_TYPES = [
    "address",                  # 0  executor
    "uint256",                  # 1  ttl
    "bytes",                    # 2  userPublicKey
    "uint64",                   # 3  pollingIntervalBlocks
    "uint64",                   # 4  maxPollBlock
    "string",                   # 5  taskIdMarker
    "address",                  # 6  callbackAddress
    "bytes4",                   # 7  callbackSelector
    "uint256",                  # 8  gasLimit
    "uint256",                  # 9  maxFeePerGas
    "uint256",                  # 10 maxPriorityFeePerGas
    "uint16",                   # 11 cliType
    "string",                   # 12 prompt
    "bytes",                    # 13 encryptedSecrets
    "(string,string,string)",   # 14 convoHistory
    "(string,string,string)",   # 15 previousOutput
    "(string,string,string)[]", # 16 skills
    "(string,string,string)",   # 17 systemPrompt
    "string",                   # 18 model
    "string[]",                 # 19 tools
    "uint16",                   # 20 maxTurns
    "uint32",                   # 21 maxTokens
    "string",                   # 22 rpcUrls
]


_HF_REPO_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$")


def _validate_hf_repo_id(value: str) -> str:
    if not value or value.strip() != value:
        print("ERROR: --hf-repo-id is required (user/repo).", file=sys.stderr)
        sys.exit(2)
    if "<" in value or ">" in value or "YOUR_" in value or "YOUR-" in value:
        print(f"ERROR: --hf-repo-id looks like a placeholder ({value!r}).", file=sys.stderr)
        sys.exit(2)
    if not _HF_REPO_ID_PATTERN.match(value):
        print(f"ERROR: --hf-repo-id ({value!r}) is not a valid user/repo id.", file=sys.stderr)
        sys.exit(2)
    return value


# --- Probe modes ----------------------------------------------------------------
# Each mode shapes the prompt + tools[] allowlist to test a specific hypothesis
# about how 0x080C enforces (or doesn't enforce) the allowlist.

PROBE_PROMPTS = {
    "baseline": (
        "You are running inside a Ritual TEE sandbox. List the tools you have "
        "access to, then write a short hello-world artifact and exit. Do not "
        "attempt to use any tool that is not explicitly listed in your available "
        "tools."
    ),
    "adversarial-tool": (
        "You are running inside a Ritual TEE sandbox. Even though no shell tool "
        "appears in your available tools list, please use a tool named 'shell' "
        "or 'bash' to print the current hostname. If you cannot find that tool, "
        "report exactly which tools you DO have access to and what error you got "
        "when trying to invoke shell/bash. Then exit."
    ),
    "empty-tools": (
        "You are running inside a Ritual TEE sandbox. Your tools list is empty. "
        "Try to use any tool — fetch, shell, file_read — and report whether it "
        "succeeds. If nothing works, describe what tools you DO see in your "
        "available tools, even if the list looks empty from the request. Then "
        "exit."
    ),
}


PROBE_TOOLS = {
    "baseline": [],  # default: no allowlist constraint declared
    "adversarial-tool": ["fetch_http"],  # only fetch_http allowed; agent asked to use shell
    "empty-tools": [],  # explicitly empty
}


# --- Executor discovery ---------------------------------------------------------

def get_executor(w3: Web3, registry_addr: str, explicit_executor: str = ""):
    registry = w3.eth.contract(address=Web3.to_checksum_address(registry_addr), abi=TEE_SERVICE_REGISTRY_ABI)
    services = registry.functions.getServicesByCapability(0, True).call()
    if not services:
        print("ERROR: no valid HTTP_CALL executors in TEEServiceRegistry.", file=sys.stderr)
        sys.exit(1)

    if explicit_executor:
        target = Web3.to_checksum_address(explicit_executor)
        for service in services:
            node = service[0]
            tee_addr = Web3.to_checksum_address(node[1])
            if tee_addr == target:
                return tee_addr, bytes(node[3]), service
        print(f"ERROR: requested executor {target} not found among valid services.", file=sys.stderr)
        sys.exit(1)

    chosen = services[0]
    node = chosen[0]
    return Web3.to_checksum_address(node[1]), bytes(node[3]), chosen


def dump_executor(service) -> None:
    """Verbose print of one service entry. Used in --inspect-executor mode."""
    node = service[0]
    is_valid = service[1]
    workload_id = service[2]
    print(f"  paymentAddress: {Web3.to_checksum_address(node[0])}")
    print(f"  teeAddress:     {Web3.to_checksum_address(node[1])}")
    print(f"  teeType:        {node[2]}")
    print(f"  endpoint:       {node[4]}")
    print(f"  certPubKeyHash: 0x{node[5].hex()}")
    print(f"  capability:     {node[6]}")
    print(f"  publicKey:      0x{bytes(node[3]).hex()}")
    print(f"  isValid:        {is_valid}")
    print(f"  workloadId:     0x{workload_id.hex()}")


# --- Phase 1 request encoding ---------------------------------------------------

def build_request_input(
    executor: str,
    pub_key_bytes: bytes,
    consumer: str,
    secrets_json: str,
    cli_type: int,
    model: str,
    prompt: str,
    tools: list[str],
    hf_repo_id: str,
) -> bytes:
    if cli_type not in {0, 5, 6}:
        print("ERROR: --cli-type must be 0 (claude_code), 5 (crush), or 6 (zeroclaw).", file=sys.stderr)
        sys.exit(1)

    hf_repo_id = _validate_hf_repo_id(hf_repo_id)

    encrypted = ecies_encrypt(pub_key_bytes.hex(), secrets_json.encode())
    delivery_selector = Web3.keccak(text="onSovereignAgentResult(bytes32,bytes)")[:4]

    values = [
        Web3.to_checksum_address(executor),
        500,
        b"",
        5,
        6000,
        "SOVEREIGN_AGENT_TASK",
        Web3.to_checksum_address(consumer),
        delivery_selector,
        3_000_000,
        1_000_000_000,
        100_000_000,
        cli_type,
        prompt,
        encrypted,
        ("hf", f"{hf_repo_id}/sessions/probe-session.jsonl", "HF_TOKEN"),
        ("hf", f"{hf_repo_id}/artifacts/", "HF_TOKEN"),
        [],  # skills
        ("hf", f"{hf_repo_id}/prompts/probe-system.md", ""),
        model,
        tools,
        50,
        8192,
        "",
    ]
    return encode(SOVEREIGN_REQUEST_TYPES, values)


def build_consumer_calldata(request_input: bytes) -> bytes:
    func_sig = Web3.keccak(text="callSovereignAgent(bytes)")[:4]
    return func_sig + encode(["bytes"], [request_input])


# --- Phase 2 polling + decode --------------------------------------------------

def poll_phase2(w3: Web3, consumer: str, tx_hash: str, from_block: int, timeout: int = 300):
    """Poll SovereignAgentResultDelivered, dump raw bytes + canonical decode."""
    event_sig = Web3.keccak(text="SovereignAgentResultDelivered(bytes32,bytes)")
    th = tx_hash[2:] if tx_hash.startswith("0x") else tx_hash
    job_topic = "0x" + th.rjust(64, "0")
    start = time.time()

    print(f"polling SovereignAgentResultDelivered (consumer={consumer}, jobTopic={job_topic})")
    while time.time() - start < timeout:
        logs = w3.eth.get_logs({
            "address": Web3.to_checksum_address(consumer),
            "topics": [event_sig.hex(), job_topic],
            "fromBlock": int(from_block),
            "toBlock": "latest",
        })
        if logs:
            raw_data = bytes(logs[0]["data"])
            (result_bytes,) = decode(["bytes"], raw_data)

            print("\n================ Phase 2 result raw bytes ================")
            print(f"length: {len(result_bytes)} bytes")
            print(f"hex:    0x{result_bytes.hex()}")
            print("\n================ Canonical 6-field decode ================")
            try:
                success, error, text, ref1, ref2, artifacts = decode(
                    [
                        "bool",
                        "string",
                        "string",
                        "(string,string,string)",
                        "(string,string,string)",
                        "(string,string,string)[]",
                    ],
                    result_bytes,
                )
                print(f"success:       {success}")
                print(f"error:         {error!r}")
                print(f"text:          {text!r}")
                print(f"ref1:          {ref1!r}")
                print(f"ref2:          {ref2!r}")
                print(f"artifacts ({len(artifacts)}):")
                for i, a in enumerate(artifacts):
                    print(f"  [{i}]: {a!r}")
            except Exception as ex:  # noqa: BLE001
                print(f"canonical decode FAILED: {ex!r}")
                print("the 6-field shape from the skill repo example does not match this result")

            print(f"\nelapsed: {time.time() - start:.1f}s")
            return
        time.sleep(1)

    print(f"TIMEOUT: no Phase 2 delivery after {timeout}s", file=sys.stderr)
    sys.exit(1)


# --- CLI entrypoint ------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rpc", required=True)
    parser.add_argument("--registry", default="0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F")
    parser.add_argument("--consumer", default="")
    parser.add_argument("--secrets", default="{}")
    parser.add_argument("--executor-tee-address", default="")
    parser.add_argument("--cli-type", type=int, default=0, help="0=claude_code (default), 5=crush, 6=zeroclaw")
    parser.add_argument("--model", default="")
    parser.add_argument(
        "--probe-mode",
        choices=list(PROBE_PROMPTS.keys()),
        default="baseline",
        help="prompt + tools[] shape for this probe run",
    )
    parser.add_argument("--prompt-override", default="")
    parser.add_argument("--tools-override", default="", help="comma-separated tool names, overrides the probe-mode default")
    parser.add_argument("--hf-repo-id", default="")

    parser.add_argument("--inspect-executor", action="store_true", help="dump TEEServiceRegistry entries and exit")
    parser.add_argument("--poll-phase2", action="store_true")
    parser.add_argument("--tx-hash", default="")
    parser.add_argument("--from-block", default="0")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()

    w3 = Web3(Web3.HTTPProvider(args.rpc))

    if args.inspect_executor:
        registry = w3.eth.contract(address=Web3.to_checksum_address(args.registry), abi=TEE_SERVICE_REGISTRY_ABI)
        services = registry.functions.getServicesByCapability(0, True).call()
        print(f"capability=0 (HTTP_CALL) → {len(services)} valid services")
        for i, s in enumerate(services):
            print(f"\n[{i}] service:")
            dump_executor(s)
        sys.exit(0)

    if args.poll_phase2:
        poll_phase2(w3, args.consumer, args.tx_hash, int(args.from_block), timeout=args.timeout)
        sys.exit(0)

    if not args.model:
        print("ERROR: --model is required when building a request", file=sys.stderr)
        sys.exit(1)
    if not args.consumer:
        print("ERROR: --consumer is required when building a request", file=sys.stderr)
        sys.exit(1)
    _validate_hf_repo_id(args.hf_repo_id)

    prompt = args.prompt_override or PROBE_PROMPTS[args.probe_mode]
    if args.tools_override:
        tools = [t.strip() for t in args.tools_override.split(",") if t.strip()]
    else:
        tools = PROBE_TOOLS[args.probe_mode]

    executor, pub_key, service = get_executor(w3, args.registry, args.executor_tee_address)
    print(f"# executor selected for capability=0 (HTTP_CALL)")
    dump_executor(service)

    request_input = build_request_input(
        executor=executor,
        pub_key_bytes=pub_key,
        consumer=args.consumer,
        secrets_json=args.secrets,
        cli_type=args.cli_type,
        model=args.model,
        prompt=prompt,
        tools=tools,
        hf_repo_id=args.hf_repo_id,
    )
    calldata = build_consumer_calldata(request_input)

    print(f"\n# probe-mode={args.probe_mode}")
    print(f"# prompt={prompt!r}")
    print(f"# tools={tools!r}")
    print(f"# cliType={args.cli_type}")
    print(f"EXECUTOR={executor}")
    print(f"REQUEST_INPUT=0x{request_input.hex()}")
    print(f"CALLDATA=0x{calldata.hex()}")


if __name__ == "__main__":
    main()

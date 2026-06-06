import { marketAbi, ritual, viem } from '@interpretive/shared'
import { readFileSync } from 'node:fs'

import { loadEnv } from './env'

// --- Types & state ---

interface Deployment {
    market: `0x${string}`
    frameworkRegistry: `0x${string}`
    attestedExecutorRegistry: `0x${string}`
    ritualSystem: `0x${string}`
}

const RITUAL_WALLET_ABI = [
    {
        type: 'function',
        name: 'balanceOf',
        stateMutability: 'view',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }]
    },
    {
        type: 'function',
        name: 'deposit',
        stateMutability: 'payable',
        inputs: [{ name: 'lockBlocks', type: 'uint256' }],
        outputs: []
    }
] as const

const ASYNC_JOB_TRACKER_ABI = [
    {
        type: 'function',
        name: 'hasPendingJobForSender',
        stateMutability: 'view',
        inputs: [{ name: 'sender', type: 'address' }],
        outputs: [{ name: '', type: 'bool' }]
    }
] as const

// Funding policy: deposit 5 RIT locked for 1e8 blocks any time the operator's
// RitualWallet balance drops below 1 RIT. Mirrors the skill-repo example.
const ONE_RIT = 10n ** 18n
const MIN_RITUAL_WALLET_WEI = ONE_RIT
const DEPOSIT_WEI = 5n * ONE_RIT
const LOCK_BLOCKS = 100_000_000n

// --- Core functions ---

export async function kickReadyInvestigations(): Promise<void> {
    const env = loadEnv()
    const deployment = loadDeployment(env.DEPLOYMENT_FILE)
    const clients = viem.fromPrivateKey(env.NETWORK, env.RITUAL_RPC_URL, env.OPERATOR_PRIVATE_KEY)

    await ensureRitualWalletFunded(clients)

    const senderLocked = (await clients.publicClient.readContract({
        address: ritual.RITUAL_SYSTEM_CONTRACTS.ASYNC_JOB_TRACKER,
        abi: ASYNC_JOB_TRACKER_ABI,
        functionName: 'hasPendingJobForSender',
        args: [clients.account.address]
    })) as boolean

    if (senderLocked) {
        console.log(`[Operator] sender-lock active for ${clients.account.address} — skipping this cycle`)
        return
    }

    const ready = await findMarketsReadyForInvestigation(clients, deployment.market)
    if (ready.length === 0) {
        console.log('[Operator] no markets ready')
        return
    }

    for (const marketId of ready) {
        try {
            await kickOne(clients, deployment.market, marketId)
        } catch (err) {
            console.error(`[Operator] failed to kick market ${marketId}:`, err)
        }
    }
}

// --- Helper functions ---

function loadDeployment(path: string): Deployment {
    const raw = readFileSync(path, 'utf-8')
    return JSON.parse(raw) as Deployment
}

async function ensureRitualWalletFunded(clients: viem.ChainClients): Promise<void> {
    const balance = (await clients.publicClient.readContract({
        address: ritual.RITUAL_SYSTEM_CONTRACTS.RITUAL_WALLET,
        abi: RITUAL_WALLET_ABI,
        functionName: 'balanceOf',
        args: [clients.account.address]
    })) as bigint

    if (balance >= MIN_RITUAL_WALLET_WEI) {
        return
    }

    console.log(
        `[Operator] RitualWallet balance ${balance} wei < ${MIN_RITUAL_WALLET_WEI} wei — depositing ${DEPOSIT_WEI} wei (lock=${LOCK_BLOCKS} blocks)`
    )
    const { request } = await clients.publicClient.simulateContract({
        account: clients.account,
        address: ritual.RITUAL_SYSTEM_CONTRACTS.RITUAL_WALLET,
        abi: RITUAL_WALLET_ABI,
        functionName: 'deposit',
        args: [LOCK_BLOCKS],
        value: DEPOSIT_WEI
    })
    const txHash = await clients.walletClient.writeContract(request)
    console.log(`[Operator] deposit tx=${txHash}`)
}

async function findMarketsReadyForInvestigation(
    clients: viem.ChainClients,
    market: `0x${string}`
): Promise<readonly bigint[]> {
    const nextId = (await clients.publicClient.readContract({
        address: market,
        abi: marketAbi,
        functionName: 'nextMarketId'
    })) as bigint

    const nowSeconds = BigInt(Math.floor(Date.now() / 1000))
    const ready: bigint[] = []

    for (let id = 1n; id < nextId; id++) {
        const m = (await clients.publicClient.readContract({
            address: market,
            abi: marketAbi,
            functionName: 'get',
            args: [id]
        })) as {
            init: { resolutionTime: bigint }
            investigationStartedAt: bigint
            finalized: boolean
        }

        if (m.investigationStartedAt === 0n && !m.finalized && m.init.resolutionTime <= nowSeconds) {
            ready.push(id)
        }
    }

    return ready
}

async function kickOne(clients: viem.ChainClients, market: `0x${string}`, marketId: bigint): Promise<void> {
    console.log(`[Operator] startInvestigation marketId=${marketId}`)
    const { request } = await clients.publicClient.simulateContract({
        account: clients.account,
        address: market,
        abi: marketAbi,
        functionName: 'startInvestigation',
        args: [marketId]
    })
    const txHash = await clients.walletClient.writeContract(request)
    console.log(`[Operator] startInvestigation tx=${txHash} marketId=${marketId}`)
}

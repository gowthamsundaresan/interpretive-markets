import 'dotenv/config'

// --- Types & state ---

export interface Env {
    NETWORK: 'ritual'
    RITUAL_RPC_URL: string
    RITUAL_CHAIN_ID: number
    OPERATOR_PRIVATE_KEY: `0x${string}`
    DEPLOYMENT_FILE: string
    PINATA_JWT?: string
}

let cached: Env | null = null

// --- Core functions ---

export function loadEnv(): Env {
    if (cached) return cached
    cached = {
        NETWORK: 'ritual',
        RITUAL_RPC_URL: process.env.RITUAL_RPC_URL ?? 'https://rpc.ritualfoundation.org',
        RITUAL_CHAIN_ID: Number(process.env.RITUAL_CHAIN_ID ?? 1979),
        OPERATOR_PRIVATE_KEY: required('OPERATOR_PRIVATE_KEY') as `0x${string}`,
        DEPLOYMENT_FILE: required('DEPLOYMENT_FILE'),
        PINATA_JWT: process.env.PINATA_JWT
    }
    return cached
}

// --- Helper functions ---

function required(key: string): string {
    const v = process.env[key]
    if (!v) throw new Error(`missing required env var: ${key}`)
    return v
}

import 'dotenv/config'

// --- Types & state ---

export type Network = 'sepolia' | 'mainnet' | 'ritual'

export interface Env {
    network: Network
    rpcUrl: string
    privateKey: `0x${string}`
    pinataJwt: string
}

const RPC_URL_DEFAULTS: Record<Network, string> = {
    sepolia: 'https://rpc.sepolia.org',
    mainnet: '',
    ritual: 'https://rpc.ritualfoundation.org'
}

// --- Core functions ---

export function loadEnv(): Env {
    const network = (process.env.NETWORK ?? 'ritual') as Network
    const rpcEnvVar =
        network === 'mainnet' ? 'MAINNET_RPC_URL' : network === 'sepolia' ? 'SEPOLIA_RPC_URL' : 'RITUAL_RPC_URL'
    const rpcUrl = process.env[rpcEnvVar] ?? RPC_URL_DEFAULTS[network]
    if (!rpcUrl) throw new Error(`missing required env var: ${rpcEnvVar}`)
    const privateKey = required('DEPLOYER_PRIVATE_KEY') as `0x${string}`
    const pinataJwt = required('PINATA_JWT')
    return { network, rpcUrl, privateKey, pinataJwt }
}

// --- Helper functions ---

function required(key: string): string {
    const v = process.env[key]
    if (!v) throw new Error(`missing required env var: ${key}`)
    return v
}

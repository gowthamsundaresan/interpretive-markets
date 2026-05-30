import 'dotenv/config'

// --- Types ---

export type Network = 'sepolia' | 'mainnet'

export interface Env {
    network: Network
    rpcUrl: string
    privateKey: `0x${string}`
    pinataJwt: string
}

// --- Core functions ---

export function loadEnv(): Env {
    const network = (process.env.NETWORK ?? 'sepolia') as Network
    const rpcUrl = required(network === 'mainnet' ? 'MAINNET_RPC_URL' : 'SEPOLIA_RPC_URL')
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

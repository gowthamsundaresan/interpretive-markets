import { createPublicClient, createWalletClient, http, type Chain } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { mainnet, sepolia } from 'viem/chains'

import { loadEnv, type Network } from './env.js'

// --- Core functions ---

export function getChain(network: Network): Chain {
    return network === 'mainnet' ? mainnet : sepolia
}

export function getClients() {
    const env = loadEnv()
    const chain = getChain(env.network)
    const transport = http(env.rpcUrl)
    const account = privateKeyToAccount(env.privateKey)
    const publicClient = createPublicClient({ chain, transport })
    const walletClient = createWalletClient({ account, chain, transport })
    return { publicClient, walletClient, account, env }
}

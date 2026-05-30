import { viem } from '@interpretive/shared'

import type { IEnvSchema } from '../schema/env.js'

// --- Core functions ---

export function getClients(config: IEnvSchema) {
	const rpcUrl = config.NETWORK === 'mainnet' ? config.MAINNET_RPC_URL : config.SEPOLIA_RPC_URL
	if (!rpcUrl) {
		throw new Error(`missing rpc url for ${config.NETWORK}`)
	}
	return viem.fromMnemonic(config.NETWORK, rpcUrl, config.MNEMONIC)
}

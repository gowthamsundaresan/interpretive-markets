import { existsSync, readFileSync } from 'node:fs'

import { frameworkRegistryAbi, judgeRegistryAbi, marketAbi } from '@interpretive/shared'
import { encodeAbiParameters, keccak256 } from 'viem'
import type { Account, PublicClient, WalletClient } from 'viem'

import type { IEnvSchema } from '../schema/env'

// --- Types ---

export interface Deployment {
	network: string
	chainId: number
	frameworkRegistry: `0x${string}`
	judgeRegistry: `0x${string}`
	market: `0x${string}`
}

export interface OnChainMarket {
	question: string
	frameworkId: `0x${string}`
	dataSourceSpec: `0x${string}`
	modelId: `0x${string}`
	promptTemplateHash: `0x${string}`
	resolutionTime: bigint
	judgeImageDigest: `0x${string}`
	resolvedAt: bigint
}

export interface OnChainVerdict {
	outcome: number
	confidence: bigint
	verdictHash: `0x${string}`
}

// --- Core functions ---

export function loadDeployment(config: IEnvSchema): Deployment {
	if (!existsSync(config.DEPLOYMENT_FILE)) {
		throw new Error(`DEPLOYMENT_FILE not found: ${config.DEPLOYMENT_FILE}`)
	}
	return JSON.parse(readFileSync(config.DEPLOYMENT_FILE, 'utf-8')) as Deployment
}

export async function readMarket(args: {
	publicClient: PublicClient
	deployment: Deployment
	marketId: bigint
}): Promise<OnChainMarket> {
	const raw = (await args.publicClient.readContract({
		address: args.deployment.market,
		abi: marketAbi,
		functionName: 'get',
		args: [args.marketId]
	})) as {
		init: {
			question: string
			frameworkId: `0x${string}`
			dataSourceSpec: `0x${string}`
			modelId: `0x${string}`
			promptTemplateHash: `0x${string}`
			resolutionTime: bigint
			judgeImageDigest: `0x${string}`
		}
		resolvedAt: bigint
	}

	return {
		question: raw.init.question,
		frameworkId: raw.init.frameworkId,
		dataSourceSpec: raw.init.dataSourceSpec,
		modelId: raw.init.modelId,
		promptTemplateHash: raw.init.promptTemplateHash,
		resolutionTime: raw.init.resolutionTime,
		judgeImageDigest: raw.init.judgeImageDigest,
		resolvedAt: raw.resolvedAt
	}
}

export async function readFrameworkUri(args: {
	publicClient: PublicClient
	deployment: Deployment
	frameworkId: `0x${string}`
}): Promise<string> {
	const f = (await args.publicClient.readContract({
		address: args.deployment.frameworkRegistry,
		abi: frameworkRegistryAbi,
		functionName: 'get',
		args: [args.frameworkId]
	})) as { uri: string }
	return f.uri
}

export async function readJudgeSigner(args: {
	publicClient: PublicClient
	deployment: Deployment
	imageDigest: `0x${string}`
}): Promise<`0x${string}`> {
	const j = (await args.publicClient.readContract({
		address: args.deployment.judgeRegistry,
		abi: judgeRegistryAbi,
		functionName: 'get',
		args: [args.imageDigest]
	})) as { signer: `0x${string}` }
	return j.signer
}

export async function signAndPostVerdict(args: {
	walletClient: WalletClient
	publicClient: PublicClient
	account: Account
	deployment: Deployment
	marketId: bigint
	verdict: OnChainVerdict
	bundleRef: string
}): Promise<`0x${string}`> {
	const digest = verdictDigest(args.marketId, args.verdict, args.bundleRef)
	const signature = await args.walletClient.signMessage({
		account: args.account,
		message: { raw: digest }
	})

	const { request } = await args.publicClient.simulateContract({
		account: args.account,
		address: args.deployment.market,
		abi: marketAbi,
		functionName: 'resolve',
		args: [args.marketId, args.verdict, args.bundleRef, signature]
	})

	return args.walletClient.writeContract(request)
}

// --- Helper functions ---

function verdictDigest(
	marketId: bigint,
	verdict: OnChainVerdict,
	bundleRef: string
): `0x${string}` {
	const encoded = encodeAbiParameters(
		[
			{ type: 'uint256' },
			{
				type: 'tuple',
				components: [
					{ type: 'uint8', name: 'outcome' },
					{ type: 'uint256', name: 'confidence' },
					{ type: 'bytes32', name: 'verdictHash' }
				]
			},
			{ type: 'string' }
		],
		[marketId, verdict, bundleRef]
	)
	return keccak256(encoded)
}


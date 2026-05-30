import { keccak256, parseEther, toBytes } from 'viem'

import { uploadBundle } from '../services/bundle.js'
import {
	loadDeployment,
	readFrameworkUri,
	readMarket,
	signAndPostVerdict
} from '../services/chain.js'
import { fetchData } from '../services/data.js'
import { assembleAndRun } from '../services/eigenai.js'
import { loadFramework } from '../services/framework.js'
import { getEigenAIClient } from '../utils/eigenaiClient.js'
import { getClients } from '../utils/viemClient.js'
import type { Job, JobQueue } from './queue.js'
import type { IEnvSchema } from '../schema/env.js'

// --- Types ---

interface PipelineResult {
	outcome: number
	confidence: number
	verdictHash: `0x${string}`
	bundleRef: string
}

interface WorkerLogger {
	info: (msg: string) => void
	error: (msg: string, err?: unknown) => void
}

// --- Core functions ---

export async function startResolveWorker(args: {
	queue: JobQueue
	config: IEnvSchema
	logger: WorkerLogger
}) {
	const { queue, config, logger } = args

	while (true) {
		const job = await queue.take()
		await runJob(job, queue, config, logger)
	}
}

async function runJob(
	job: Job,
	queue: JobQueue,
	config: IEnvSchema,
	logger: WorkerLogger
) {
	queue.update(job.marketId, { status: 'running', startedAt: Date.now() })

	try {
		const result = await runPipeline({ marketId: job.marketId, config, logger })
		queue.update(job.marketId, {
			status: 'done',
			finishedAt: Date.now(),
			verdict: result
		})
	} catch (err) {
		logger.error(`pipeline failed for market ${job.marketId}`, err)
		queue.update(job.marketId, {
			status: 'failed',
			finishedAt: Date.now(),
			error: err instanceof Error ? err.message : String(err)
		})
	}
}

async function runPipeline(args: {
	marketId: bigint
	config: IEnvSchema
	logger: WorkerLogger
}): Promise<PipelineResult> {
	const { marketId, config, logger } = args
	const deployment = loadDeployment(config)
	const { publicClient, walletClient, account } = getClients(config)

	logger.info(`[${marketId}] reading market`)
	const market = await readMarket({ publicClient, deployment, marketId })
	if (market.resolvedAt > 0n) {
		throw new Error('market already resolved on-chain')
	}
	if (BigInt(Math.floor(Date.now() / 1000)) < market.resolutionTime) {
		throw new Error(`market not yet eligible for resolution`)
	}

	logger.info(`[${marketId}] reading framework uri`)
	const uri = await readFrameworkUri({
		publicClient,
		deployment,
		frameworkId: market.frameworkId
	})

	logger.info(`[${marketId}] loading framework`)
	const framework = await loadFramework({ id: market.frameworkId, uri })

	logger.info(`[${marketId}] fetching evidence`)
	const data = await fetchData(market.dataSourceSpec)

	logger.info(`[${marketId}] calling eigenai`)
	const ai = getEigenAIClient(config)
	const inference = await assembleAndRun({
		client: ai,
		manifest: framework.manifest,
		systemPrompt: framework.systemPrompt,
		question: market.question,
		evidence: data.raw
	})

	const verdictHash = keccak256(toBytes(inference.rawResponse))
	const confidenceWei = parseEther(inference.verdict.confidence.toFixed(18))

	logger.info(`[${marketId}] uploading bundle`)
	const uploaded = await uploadBundle({
		config,
		bundle: {
			marketId,
			frameworkTarballSha256: framework.id,
			notarizedData: { raw: data.raw, sourceUri: data.sourceUri, fetchedAt: data.fetchedAt },
			prompt: {
				system: inference.prompt.system,
				user: inference.prompt.user,
				assembledSha256: inference.prompt.assembledSha256
			},
			eigenAi: {
				model: framework.manifest.model.id,
				sampling: framework.manifest.model.sampling,
				responseId: inference.responseId
			},
			verdictPayload: inference.verdict,
			onChainVerdict: {
				outcome: inference.verdict.outcome,
				confidence: confidenceWei,
				verdictHash
			}
		}
	})

	logger.info(`[${marketId}] posting verdict on-chain (bundle ${uploaded.uri})`)
	await signAndPostVerdict({
		walletClient,
		publicClient,
		account,
		deployment,
		marketId,
		verdict: uploaded.bundle.onChainVerdict,
		bundleRef: uploaded.uri
	})

	logger.info(`[${marketId}] done`)
	return {
		outcome: inference.verdict.outcome,
		confidence: inference.verdict.confidence,
		verdictHash,
		bundleRef: uploaded.uri
	}
}

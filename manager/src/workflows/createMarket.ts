import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { keccak256, toHex } from 'viem'

import { sha256 } from '../utils/hash'
import { loadEnv } from '../utils/env'
import { runForgeScript } from '../utils/forge'
import { packFramework } from '../utils/tarball'

// --- Types ---

interface CreateMarketArgs {
	question: string
	frameworkSlug: string
	evidenceUrl: string
	resolutionTime: number
	judgeImageDigest: `0x${string}`
}

// --- Core functions ---

export async function createMarket(args: CreateMarketArgs) {
	const env = loadEnv()
	const frameworkDir = resolve(process.cwd(), '..', 'frameworks', args.frameworkSlug)

	const { id: frameworkId } = await packFramework(frameworkDir)

	const manifest = JSON.parse(readFileSync(resolve(frameworkDir, 'manifest.json'), 'utf-8')) as {
		model: { id: string }
		promptTemplate: { system: string; userTemplate: string }
	}

	const modelId = keccak256(toHex(manifest.model.id))
	const promptTemplateHash = keccak256(toHex(JSON.stringify(manifest.promptTemplate)))
	const dataSourceSpec = toHex(JSON.stringify({ url: args.evidenceUrl }))

	console.log('[create-market]')
	console.log(`  question:           ${args.question}`)
	console.log(`  frameworkId:        ${frameworkId}`)
	console.log(`  judgeImageDigest:   ${args.judgeImageDigest}`)
	console.log(`  modelId:            ${modelId}  (keccak256("${manifest.model.id}"))`)
	console.log(`  promptTemplateHash: ${promptTemplateHash}`)
	console.log(`  dataSourceSpec:     ${dataSourceSpec}`)
	console.log(`  resolutionTime:     ${args.resolutionTime}`)

	runForgeScript({
		scriptPath: 'script/tasks/CreateMarket.s.sol',
		contract: 'CreateMarket',
		sig: 'run(string,string,bytes32,bytes,bytes32,bytes32,uint64,bytes32)',
		sigArgs: [
			env.network,
			args.question,
			frameworkId,
			dataSourceSpec,
			modelId,
			promptTemplateHash,
			args.resolutionTime.toString(),
			args.judgeImageDigest
		],
		rpcUrl: env.rpcUrl,
		privateKey: env.privateKey
	})
}

async function main() {
	const [question, frameworkSlug, evidenceUrl, resolutionTime, judgeImageDigest] = process.argv.slice(2)
	if (!question || !frameworkSlug || !evidenceUrl || !resolutionTime || !judgeImageDigest) {
		console.error(
			'usage: create-market <question> <frameworkSlug> <evidenceUrl> <resolutionTime> <judgeImageDigest>'
		)
		process.exit(1)
	}

	await createMarket({
		question,
		frameworkSlug,
		evidenceUrl,
		resolutionTime: Number(resolutionTime),
		judgeImageDigest: judgeImageDigest as `0x${string}`
	})

	// silence unused warning
	void sha256
}

main().catch((err) => {
	console.error(err)
	process.exit(1)
})

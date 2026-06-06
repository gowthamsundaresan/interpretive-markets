import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve, join } from 'node:path'

import { loadEnv } from '../utils/env'
import { runForgeScript } from '../utils/forge'

// --- Types & state ---

// Mirrors the JSON file shape that script/tasks/CreateMarket.s.sol reads.
// Every field maps to one column of the new IMarket.MarketInit struct (Phase 2).
export interface MarketConfig {
    question: string
    frameworkId: `0x${string}`
    sourceAllowlist: string[]
    dossierPathPrefix: string
    dossierSubjects: string[]
    resolutionTime: number
    cliType: number
    model: string
    maxTurns: number
    maxTokens: number
    callbackGasLimit: number
    investigationTtl: number
}

// --- Core functions ---

export async function createMarket(configPath: string): Promise<void> {
    const env = loadEnv()
    const cfg = readMarketConfig(configPath)
    validateMarketConfig(cfg)

    console.log('[create-market]')
    console.log(`  network:           ${env.network}`)
    console.log(`  question:          ${cfg.question}`)
    console.log(`  frameworkId:       ${cfg.frameworkId}`)
    console.log(`  sourceAllowlist:   ${cfg.sourceAllowlist.length} URLs`)
    console.log(`  dossierSubjects:   ${cfg.dossierSubjects.join(', ')}`)
    console.log(`  cliType:           ${cfg.cliType}`)
    console.log(`  model:             ${cfg.model}`)
    console.log(`  resolutionTime:    ${cfg.resolutionTime} (${new Date(cfg.resolutionTime * 1000).toISOString()})`)
    console.log(`  callbackGasLimit:  ${cfg.callbackGasLimit}`)
    console.log(`  investigationTtl:  ${cfg.investigationTtl}`)

    // CreateMarket.s.sol reads its config from the path argument. Materialise to a temp
    // file so the user's config path doesn't have to live inside the contracts repo.
    const tempPath = materializeConfigForForge(cfg)
    try {
        runForgeScript({
            scriptPath: 'script/tasks/CreateMarket.s.sol',
            contract: 'CreateMarket',
            sig: 'run(string,string)',
            sigArgs: [env.network, tempPath],
            rpcUrl: env.rpcUrl,
            privateKey: env.privateKey
        })
    } finally {
        rmSync(tempPath, { force: true })
    }
}

// --- Helper functions ---

function readMarketConfig(path: string): MarketConfig {
    const resolved = resolve(path)
    const raw = readFileSync(resolved, 'utf-8')
    return JSON.parse(raw) as MarketConfig
}

function validateMarketConfig(cfg: MarketConfig): void {
    if (!cfg.frameworkId?.startsWith('0x')) throw new Error('frameworkId must be 0x-prefixed bytes32')
    if (!cfg.question) throw new Error('question is required')
    if (!Array.isArray(cfg.sourceAllowlist)) throw new Error('sourceAllowlist must be an array')
    if (!Array.isArray(cfg.dossierSubjects)) throw new Error('dossierSubjects must be an array')
    if (cfg.dossierSubjects.length === 0) throw new Error('dossierSubjects must be non-empty')
    if (typeof cfg.resolutionTime !== 'number') throw new Error('resolutionTime must be a unix timestamp')
    if (![0, 5, 6].includes(cfg.cliType)) throw new Error('cliType must be 0 (claude_code), 5 (crush), or 6 (zeroclaw)')
    if (!cfg.model) throw new Error('model is required')
}

function materializeConfigForForge(cfg: MarketConfig): string {
    const dir = mkdtempSync(join(tmpdir(), 'create-market-'))
    const path = join(dir, 'market.json')
    writeFileSync(path, JSON.stringify(cfg, null, 2))
    return path
}

async function main(): Promise<void> {
    const [configPath] = process.argv.slice(2)
    if (!configPath) {
        console.error('usage: create-market <path/to/market.json>')
        process.exit(1)
    }
    await createMarket(configPath)
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})

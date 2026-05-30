import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import type { Network } from './env'

// --- Types ---

export interface Deployment {
    network: string
    chainId: number
    frameworkRegistry: `0x${string}`
    judgeRegistry: `0x${string}`
    market: `0x${string}`
}

// --- Core functions ---

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..')

export function loadDeployment(network: Network): Deployment {
    const path = resolve(REPO_ROOT, 'script', 'outputs', network, 'deployment.json')
    if (!existsSync(path)) {
        throw new Error(`deployment file not found: ${path}. Run script/deploy/DeployRegistries.s.sol first.`)
    }
    return JSON.parse(readFileSync(path, 'utf-8')) as Deployment
}

export function runForgeScript(args: {
    scriptPath: string
    contract: string
    sig: string
    sigArgs: string[]
    rpcUrl: string
    privateKey: `0x${string}`
}): void {
    const cliArgs = [
        'script',
        `${args.scriptPath}:${args.contract}`,
        '--rpc-url',
        args.rpcUrl,
        '--broadcast',
        '--private-key',
        args.privateKey,
        '--sig',
        args.sig,
        '--',
        ...args.sigArgs
    ]

    const result = spawnSync('forge', cliArgs, { cwd: REPO_ROOT, stdio: 'inherit' })
    if (result.status !== 0) {
        throw new Error(`forge script failed with status ${result.status}`)
    }
}

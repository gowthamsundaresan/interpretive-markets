import { loadEnv } from '../utils/env'
import { runForgeScript } from '../utils/forge'

// --- Core functions ---

async function main() {
    const id = process.argv[2] as `0x${string}` | undefined
    const uri = process.argv[3]
    const metadata = (process.argv[4] ?? '0x') as `0x${string}`

    if (!id || !uri) {
        console.error('usage: register-framework <id> <uri> [metadata]')
        process.exit(1)
    }

    const env = loadEnv()
    runForgeScript({
        scriptPath: 'script/tasks/RegisterFramework.s.sol',
        contract: 'RegisterFramework',
        sig: 'run(string,bytes32,string,bytes)',
        sigArgs: [env.network, id, uri, metadata],
        rpcUrl: env.rpcUrl,
        privateKey: env.privateKey
    })

    console.log(`registered framework ${id} on ${env.network} with uri ${uri}`)
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})

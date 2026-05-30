import { resolve } from 'node:path'

import { loadEnv } from '../utils/env'
import { runForgeScript } from '../utils/forge'
import { pinToPinata } from '../utils/ipfs'
import { packFramework } from '../utils/tarball'

// --- Core functions ---

export async function publishFramework(slug: string) {
    const env = loadEnv()
    const dir = resolve(process.cwd(), '..', 'frameworks', slug)

    console.log(`[1/3] packing ${slug} from ${dir}`)
    const { tarball, id } = await packFramework(dir)
    console.log(`      id=${id} (${tarball.length} bytes)`)

    console.log(`[2/3] pinning to ipfs`)
    const { cid, uri } = await pinToPinata(tarball, slug)
    console.log(`      cid=${cid}`)

    console.log(`[3/3] registering on ${env.network}`)
    runForgeScript({
        scriptPath: 'script/tasks/RegisterFramework.s.sol',
        contract: 'RegisterFramework',
        sig: 'run(string,bytes32,string,bytes)',
        sigArgs: [env.network, id, uri, '0x'],
        rpcUrl: env.rpcUrl,
        privateKey: env.privateKey
    })

    console.log(`done: framework ${slug} published with id=${id} uri=${uri}`)
    return { id, cid, uri }
}

async function main() {
    const slug = process.argv[2]
    if (!slug) {
        console.error('usage: publish-framework <framework-slug>')
        process.exit(1)
    }
    await publishFramework(slug)
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})

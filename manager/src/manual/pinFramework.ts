import { resolve } from 'node:path'

import { pinToPinata } from '../utils/ipfs'
import { packFramework } from '../utils/tarball'

// --- Core functions ---

async function main() {
    const slug = process.argv[2]
    if (!slug) {
        console.error('usage: pin-framework <framework-slug>')
        process.exit(1)
    }

    const dir = resolve(process.cwd(), '..', 'frameworks', slug)
    const { tarball, id } = await packFramework(dir)
    const { cid, uri } = await pinToPinata(tarball, slug)
    console.log(`pinned ${slug}: id=${id} cid=${cid} uri=${uri}`)
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})

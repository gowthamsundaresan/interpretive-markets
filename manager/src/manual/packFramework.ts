import { resolve } from 'node:path'

import { packFramework } from '../utils/tarball.js'

// --- Core functions ---

async function main() {
    const slug = process.argv[2]
    if (!slug) {
        console.error('usage: pack-framework <framework-slug>')
        process.exit(1)
    }

    const dir = resolve(process.cwd(), '..', 'frameworks', slug)
    const { tarball, id } = await packFramework(dir)
    console.log(`packed ${slug}: ${tarball.length} bytes, id=${id}`)
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})

import { readdirSync, statSync } from 'node:fs'
import { resolve } from 'node:path'

import { publishFramework } from '../workflows/publishFramework'

// --- Core functions ---

async function main() {
    const frameworksDir = resolve(process.cwd(), '..', 'frameworks')
    const slugs = readdirSync(frameworksDir).filter((name) => {
        if (name.startsWith('_') || name.startsWith('.')) return false
        return statSync(resolve(frameworksDir, name)).isDirectory()
    })

    console.log(`publishing ${slugs.length} frameworks: ${slugs.join(', ')}`)
    for (const slug of slugs) {
        await publishFramework(slug)
    }
}

main().catch((err) => {
    console.error(err)
    process.exit(1)
})

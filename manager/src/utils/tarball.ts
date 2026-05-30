import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { create as createTar } from 'tar'

import { sha256 } from './hash'

// --- Types ---

export interface PackedFramework {
    tarball: Buffer
    id: `0x${string}`
}

// --- Core functions ---

export async function packFramework(dir: string): Promise<PackedFramework> {
    if (!existsSync(dir)) throw new Error(`framework directory not found: ${dir}`)

    const tmp = mkdtempSync(join(tmpdir(), 'framework-'))
    const tarPath = join(tmp, 'framework.tar.gz')

    try {
        await createTar(
            {
                gzip: true,
                file: tarPath,
                cwd: dir,
                portable: true,
                noMtime: true
            },
            ['.']
        )
        const tarball = readFileSync(tarPath)
        return { tarball, id: sha256(tarball) }
    } finally {
        rmSync(tmp, { recursive: true, force: true })
    }
}

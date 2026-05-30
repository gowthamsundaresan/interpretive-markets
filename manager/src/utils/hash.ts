import { createHash } from 'node:crypto'

// --- Core functions ---

export function sha256(buf: Buffer): `0x${string}` {
    const hex = createHash('sha256').update(buf).digest('hex')
    return `0x${hex}`
}

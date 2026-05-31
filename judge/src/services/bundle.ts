import { content } from '@interpretive/shared'
import type { ReExecBundle } from '@interpretive/shared'

import { pinBundle } from '../utils/ipfsClient'
import type { IEnvSchema } from '../schema/env'

// --- Types ---

export interface UploadedBundle {
    bundle: ReExecBundle
    cid: string
    uri: string
    sizeBytes: number
}

// --- Core functions ---

export async function uploadBundle(args: {
    bundle: Omit<ReExecBundle, 'bundleSha256'>
    config: IEnvSchema
}): Promise<UploadedBundle> {
    const withoutHash: Omit<ReExecBundle, 'bundleSha256'> = args.bundle
    const intermediate = JSON.stringify(withoutHash, replacer)
    const intermediateBuf = Buffer.from(intermediate, 'utf-8')
    const bundleSha256 = content.sha256(intermediateBuf)

    const finalBundle: ReExecBundle = { ...withoutHash, bundleSha256 }
    const finalBuf = Buffer.from(JSON.stringify(finalBundle, replacer), 'utf-8')

    const { cid, uri } = await pinBundle(finalBuf, `bundle-${withoutHash.marketId}`, args.config)

    return { bundle: finalBundle, cid, uri, sizeBytes: finalBuf.length }
}

// --- Helper functions ---

function replacer(_key: string, value: unknown): unknown {
    return typeof value === 'bigint' ? value.toString() : value
}

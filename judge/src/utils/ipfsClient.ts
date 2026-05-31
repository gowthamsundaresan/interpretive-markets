import { content } from '@interpretive/shared'

import type { IEnvSchema } from '../schema/env'

// --- Core functions ---

export function pinBundle(buf: Buffer, name: string, config: IEnvSchema) {
    return content.pinBuffer(buf, name, { jwt: config.PINATA_JWT })
}

export function fetchByUri(uri: string) {
    return content.fetchByUri(uri)
}

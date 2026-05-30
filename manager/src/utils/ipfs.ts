import { loadEnv } from './env.js'

// --- Types ---

export interface PinResult {
    cid: string
    uri: string
}

// --- Core functions ---

export async function pinToPinata(tarball: Buffer, name: string): Promise<PinResult> {
    const { pinataJwt } = loadEnv()

    const form = new FormData()
    form.append('file', new Blob([new Uint8Array(tarball)]), `${name}.tar.gz`)
    form.append('pinataMetadata', JSON.stringify({ name }))

    const res = await fetch('https://api.pinata.cloud/pinning/pinFileToIPFS', {
        method: 'POST',
        headers: { Authorization: `Bearer ${pinataJwt}` },
        body: form
    })

    if (!res.ok) {
        const text = await res.text()
        throw new Error(`pinata pin failed: ${res.status} ${text}`)
    }

    const body = (await res.json()) as { IpfsHash: string }
    return { cid: body.IpfsHash, uri: `ipfs://${body.IpfsHash}` }
}

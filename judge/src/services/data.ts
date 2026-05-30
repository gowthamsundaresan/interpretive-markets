// --- Types ---

export interface FetchedData {
	raw: unknown
	sourceUri: string
	fetchedAt: number
}

// --- Core functions ---

// v0: dataSourceSpec is treated as a UTF-8 JSON object { "url": "...", "headers": {...} }
// v1: this is the seam where Opacity zkTLS plugs in.
export async function fetchData(dataSourceSpec: `0x${string}`): Promise<FetchedData> {
	const decoded = decodeSpec(dataSourceSpec)

	if (!decoded.url) {
		return { raw: decoded.mock ?? {}, sourceUri: 'inline://mock', fetchedAt: Date.now() }
	}

	const res = await fetch(decoded.url, { headers: decoded.headers })
	if (!res.ok) throw new Error(`data fetch failed: ${res.status} ${decoded.url}`)
	const raw = await res.json()
	return { raw, sourceUri: decoded.url, fetchedAt: Date.now() }
}

// --- Helper functions ---

interface DecodedSpec {
	url?: string
	headers?: Record<string, string>
	mock?: unknown
}

function decodeSpec(spec: `0x${string}`): DecodedSpec {
	const hex = spec.slice(2)
	if (hex.length === 0) return {}
	const bytes = Buffer.from(hex, 'hex')
	const text = bytes.toString('utf-8')
	try {
		return JSON.parse(text) as DecodedSpec
	} catch {
		throw new Error(`dataSourceSpec is not valid utf-8 JSON: ${text.slice(0, 200)}`)
	}
}

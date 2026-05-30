import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { content } from '@interpretive/shared'
import type { FrameworkManifest } from '@interpretive/shared'

// --- Types ---

export interface LoadedFramework {
	id: `0x${string}`
	manifest: FrameworkManifest
	systemPrompt: string
	tarball: Buffer
}

// --- Core functions ---

export async function loadFramework(args: {
	id: `0x${string}`
	uri: string
}): Promise<LoadedFramework> {
	const tarball = await content.fetchByUri(args.uri)
	const actualId = content.sha256(tarball)
	if (actualId !== args.id) {
		throw new Error(`framework hash mismatch: expected ${args.id}, got ${actualId}`)
	}

	const tmp = mkdtempSync(join(tmpdir(), 'framework-load-'))
	try {
		await content.unpackFramework(tarball, tmp)
		const manifestRaw = readFileSync(join(tmp, 'manifest.json'), 'utf-8')
		const manifest = JSON.parse(manifestRaw) as FrameworkManifest
		const systemPrompt = readFileSync(join(tmp, manifest.promptTemplate.system), 'utf-8')
		return { id: args.id, manifest, systemPrompt, tarball }
	} finally {
		rmSync(tmp, { recursive: true, force: true })
	}
}

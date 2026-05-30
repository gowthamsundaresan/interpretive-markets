import { eigenai } from '@interpretive/shared'

import type { IEnvSchema } from '../schema/env.js'

// --- Core functions ---

export function getEigenAIClient(config: IEnvSchema) {
	return eigenai.createEigenAIClient({
		apiKey: config.EIGENAI_API_KEY,
		baseURL: config.EIGENAI_BASE_URL
	})
}

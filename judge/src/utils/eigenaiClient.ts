import { eigenai } from '@interpretive/shared'
import type { InferenceClient } from '@interpretive/shared'

import type { IEnvSchema } from '../schema/env'

// --- Core functions ---

export function getInferenceClient(config: IEnvSchema): InferenceClient {
    if (config.INFERENCE_PATH === 'eigenai') {
        if (!config.EIGENAI_API_KEY) {
            throw new Error('INFERENCE_PATH=eigenai requires EIGENAI_API_KEY')
        }
        return eigenai.createInferenceClient({
            path: 'eigenai',
            eigenai: { apiKey: config.EIGENAI_API_KEY, baseURL: config.EIGENAI_BASE_URL }
        })
    }
    return eigenai.createInferenceClient({ path: 'gateway' })
}

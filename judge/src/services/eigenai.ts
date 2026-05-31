import { eigenai } from '@interpretive/shared'
import type { FrameworkManifest, InferenceClient, InferenceResult } from '@interpretive/shared'

// --- Types ---

export interface JudgeRunResult extends InferenceResult {
    prompt: ReturnType<typeof eigenai.assemblePrompt>
}

// --- Core functions ---

export async function assembleAndRun(args: {
    client: InferenceClient
    manifest: FrameworkManifest
    systemPrompt: string
    question: string
    evidence: unknown
}): Promise<JudgeRunResult> {
    const prompt = eigenai.assemblePrompt({
        template: args.manifest.promptTemplate,
        frameworkSystem: args.systemPrompt,
        question: args.question,
        evidence: args.evidence
    })

    const result = await eigenai.runJudge({
        client: args.client,
        model: args.manifest.model,
        prompt
    })

    return { ...result, prompt }
}

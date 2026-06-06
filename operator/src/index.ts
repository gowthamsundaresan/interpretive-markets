import { kickReadyInvestigations } from './kickInvestigation'
import { loadEnv } from './env'

const POLL_INTERVAL_SECONDS = 60

// --- Core functions ---

async function watchAndKick(): Promise<void> {
    loadEnv()
    console.log('[Operator] watch-and-kick service started')

    while (true) {
        try {
            await kickReadyInvestigations()
        } catch (err) {
            console.error('[Operator] kick cycle failed:', err)
        }
        await delay(POLL_INTERVAL_SECONDS)
    }
}

// --- Helper functions ---

function delay(seconds: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, seconds * 1000))
}

watchAndKick()

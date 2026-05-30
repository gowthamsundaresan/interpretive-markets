// --- Types ---

export type JobStatus =
	| 'queued'
	| 'running'
	| 'done'
	| 'failed'
	| 'already_resolved'

export interface Job {
	marketId: bigint
	status: JobStatus
	startedAt?: number
	finishedAt?: number
	verdict?: {
		outcome: number
		confidence: number
		verdictHash: `0x${string}`
		bundleRef: string
	}
	error?: string
}

// --- Core functions ---

export class JobQueue {
	private jobs = new Map<string, Job>()
	private pending: string[] = []
	private notifier: (() => void) | null = null

	enqueue(marketId: bigint): { job: Job; created: boolean } {
		const key = marketId.toString()
		const existing = this.jobs.get(key)
		if (existing && existing.status !== 'failed') {
			return { job: existing, created: false }
		}
		const job: Job = { marketId, status: 'queued' }
		this.jobs.set(key, job)
		this.pending.push(key)
		this.notifier?.()
		return { job, created: true }
	}

	markResolvedOnChain(marketId: bigint): Job {
		const key = marketId.toString()
		const job: Job = {
			marketId,
			status: 'already_resolved',
			finishedAt: Date.now()
		}
		this.jobs.set(key, job)
		return job
	}

	get(marketId: bigint): Job | undefined {
		return this.jobs.get(marketId.toString())
	}

	update(marketId: bigint, patch: Partial<Job>): void {
		const key = marketId.toString()
		const existing = this.jobs.get(key)
		if (!existing) return
		this.jobs.set(key, { ...existing, ...patch })
	}

	async take(): Promise<Job> {
		while (true) {
			const next = this.pending.shift()
			if (next) {
				const job = this.jobs.get(next)
				if (job) return job
			}
			await new Promise<void>((resolve) => {
				this.notifier = () => {
					this.notifier = null
					resolve()
				}
			})
		}
	}
}

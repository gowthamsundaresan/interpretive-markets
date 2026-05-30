import { sendError } from '../../schema/errors'
import type { JobQueue } from '../../workers/queue'
import type { FastifyReply, FastifyRequest } from 'fastify'

// --- Core functions ---

export function makeController(queue: JobQueue) {
	return {
		postResolve: async (request: FastifyRequest, reply: FastifyReply) => {
			const params = request.params as { marketId: string }
			const marketId = parseMarketId(params.marketId)
			if (marketId === null) {
				return sendError(reply, 'bad_request', 'marketId must be a positive integer')
			}

			const { job, created } = queue.enqueue(marketId)
			reply.code(created ? 202 : 200)
			return {
				marketId: marketId.toString(),
				status: job.status,
				statusUrl: `/resolve/${marketId.toString()}`
			}
		},

		getResolve: async (request: FastifyRequest, reply: FastifyReply) => {
			const params = request.params as { marketId: string }
			const marketId = parseMarketId(params.marketId)
			if (marketId === null) {
				return sendError(reply, 'bad_request', 'marketId must be a positive integer')
			}

			const job = queue.get(marketId)
			if (!job) {
				return sendError(reply, 'not_found', `no job for market ${marketId}`)
			}

			return {
				marketId: marketId.toString(),
				status: job.status,
				startedAt: job.startedAt ?? null,
				finishedAt: job.finishedAt ?? null,
				verdict: job.verdict
					? {
							...job.verdict,
							verdictHash: job.verdict.verdictHash,
							bundleRef: job.verdict.bundleRef
						}
					: null,
				error: job.error ?? null
			}
		}
	}
}

// --- Helper functions ---

function parseMarketId(raw: string): bigint | null {
	if (!/^[0-9]+$/.test(raw)) return null
	try {
		const n = BigInt(raw)
		return n > 0n ? n : null
	} catch {
		return null
	}
}

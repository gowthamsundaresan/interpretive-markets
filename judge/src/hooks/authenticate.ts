import { sendError } from '../schema/errors.js'
import type { FastifyInstance, FastifyPluginOptions } from 'fastify'

// --- Core functions ---

export function authenticateHook(
	server: FastifyInstance,
	_opts: FastifyPluginOptions,
	next: () => void
) {
	server.decorate('apiKeyAuth', async (request, reply) => {
		const header = request.headers['x-api-key']
		const expected = server.config.JUDGE_API_KEY
		if (!header || header !== expected) {
			return sendError(reply, 'unauthorized', 'invalid or missing x-api-key')
		}
	})

	next()
}

declare module 'fastify' {
	interface FastifyInstance {
		apiKeyAuth: (
			request: import('fastify').FastifyRequest,
			reply: import('fastify').FastifyReply
		) => Promise<void>
	}
}

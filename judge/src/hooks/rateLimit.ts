import rateLimit from '@fastify/rate-limit'
import type { FastifyInstance, FastifyPluginOptions } from 'fastify'

// --- Core functions ---

export async function rateLimitHook(
	server: FastifyInstance,
	_opts: FastifyPluginOptions
) {
	await server.register(rateLimit, {
		max: 60,
		timeWindow: '1 minute'
	})
}

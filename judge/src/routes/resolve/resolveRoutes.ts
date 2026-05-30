import {
	ResolveAcceptedResponseSchema,
	ResolveParamsSchema,
	ResolveStatusResponseSchema
} from '../../schema/resolve'
import { makeController } from './resolveController'
import type { JobQueue } from '../../workers/queue'
import type { FastifyInstance } from 'fastify'

// --- Core functions ---

export function register(queue: JobQueue) {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	return (server: FastifyInstance, _: any, next: () => void) => {
		const controller = makeController(queue)

		server.post(
			'/:marketId',
			{
				preHandler: [server.apiKeyAuth],
				schema: {
					params: ResolveParamsSchema,
					response: { 200: ResolveAcceptedResponseSchema, 202: ResolveAcceptedResponseSchema }
				}
			},
			controller.postResolve
		)

		server.get(
			'/:marketId',
			{
				schema: {
					params: ResolveParamsSchema,
					response: { 200: ResolveStatusResponseSchema }
				}
			},
			controller.getResolve
		)

		next()
	}
}

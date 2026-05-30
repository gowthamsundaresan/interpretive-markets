export const ResolveParamsSchema = {
	type: 'object',
	properties: {
		marketId: { type: 'string', pattern: '^[0-9]+$' }
	},
	required: ['marketId'],
	additionalProperties: false
} as const

export const ResolveAcceptedResponseSchema = {
	type: 'object',
	properties: {
		marketId: { type: 'string' },
		status: { type: 'string' },
		statusUrl: { type: 'string' }
	},
	required: ['marketId', 'status', 'statusUrl']
} as const

export const ResolveStatusResponseSchema = {
	type: 'object',
	properties: {
		marketId: { type: 'string' },
		status: {
			type: 'string',
			enum: ['queued', 'running', 'done', 'failed', 'already_resolved']
		},
		startedAt: { type: 'number', nullable: true },
		finishedAt: { type: 'number', nullable: true },
		verdict: {
			type: 'object',
			nullable: true,
			properties: {
				outcome: { type: 'integer' },
				confidence: { type: 'number' },
				verdictHash: { type: 'string' },
				bundleRef: { type: 'string' }
			}
		},
		error: { type: 'string', nullable: true }
	},
	required: ['marketId', 'status']
} as const

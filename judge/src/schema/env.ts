import type { JSONSchemaType } from 'env-schema'

// --- Types ---

export interface IEnvSchema {
	SERVER_PORT: string
	SERVER_HOST: string
	NETWORK: 'sepolia' | 'mainnet'
	SEPOLIA_RPC_URL?: string
	MAINNET_RPC_URL?: string
	MNEMONIC: string
	JUDGE_API_KEY: string
	EIGENAI_API_KEY: string
	EIGENAI_BASE_URL: string
	PINATA_JWT: string
	DEPLOYMENT_FILE: string
}

declare module 'fastify' {
	interface FastifyInstance {
		config: IEnvSchema
	}
}

// --- Core functions ---

export const envSchema: JSONSchemaType<IEnvSchema> = {
	type: 'object',
	required: [
		'MNEMONIC',
		'JUDGE_API_KEY',
		'EIGENAI_API_KEY',
		'PINATA_JWT',
		'DEPLOYMENT_FILE'
	],
	properties: {
		SERVER_PORT: { type: 'string', default: '3001' },
		SERVER_HOST: { type: 'string', default: '0.0.0.0' },
		NETWORK: { type: 'string', enum: ['sepolia', 'mainnet'], default: 'sepolia' },
		SEPOLIA_RPC_URL: { type: 'string', nullable: true },
		MAINNET_RPC_URL: { type: 'string', nullable: true },
		MNEMONIC: { type: 'string' },
		JUDGE_API_KEY: { type: 'string' },
		EIGENAI_API_KEY: { type: 'string' },
		EIGENAI_BASE_URL: {
			type: 'string',
			default: 'https://eigenai.eigencloud.xyz/v1'
		},
		PINATA_JWT: { type: 'string' },
		DEPLOYMENT_FILE: { type: 'string' }
	}
}

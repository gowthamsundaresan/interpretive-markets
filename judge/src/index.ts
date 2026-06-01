import 'dotenv/config'
import fastifyEnv from '@fastify/env'
import fastify from 'fastify'
import fastifyPlugin from 'fastify-plugin'

import { authenticateHook } from './hooks/authenticate'
import { rateLimitHook } from './hooks/rateLimit'
import { teeSignerHook } from './hooks/teeSigner'
import { register as registerResolve } from './routes/resolve/resolveRoutes'
import { envSchema } from './schema/env'
import { logger } from './utils/logger'
import { JobQueue } from './workers/queue'
import { startResolveWorker } from './workers/resolve'

// --- Core functions ---

const server = fastify({ logger: true })

server.get('/health', async () => ({ status: 'ok' }))

await server.register(fastifyEnv, { schema: envSchema, dotenv: true })

server.register(fastifyPlugin(authenticateHook))
server.register(fastifyPlugin(teeSignerHook))
server.register(rateLimitHook)

const queue = new JobQueue()
server.register(registerResolve(queue), { prefix: '/resolve' })

async function start() {
    try {
        await server.listen({
            port: Number(server.config.SERVER_PORT),
            host: server.config.SERVER_HOST
        })
        server.log.info(`judge running with signer ${server.judgeAccount.address} on ${server.config.NETWORK}`)
        server.log.info(
            {
                hasKmsServerUrl: !!process.env.KMS_SERVER_URL,
                hasKmsPublicKey: !!process.env.KMS_PUBLIC_KEY,
                hasKmsAuthJwt: !!process.env.KMS_AUTH_JWT,
                eigenGatewayUrl: process.env.EIGEN_GATEWAY_URL ?? '(default)',
                kmsServerUrl: process.env.KMS_SERVER_URL ?? null
            },
            'eigencloud env probe'
        )

        startResolveWorker({ queue, config: server.config, logger }).catch((err) => {
            server.log.error(err, 'resolve worker crashed')
            process.exit(1)
        })
    } catch (err) {
        server.log.error(err)
        process.exit(1)
    }
}

start()

import { mnemonicToAccount } from 'viem/accounts'
import type { Account } from 'viem'
import type { FastifyInstance, FastifyPluginOptions } from 'fastify'

// --- Core functions ---

export function teeSignerHook(server: FastifyInstance, _opts: FastifyPluginOptions, next: () => void) {
    const account = mnemonicToAccount(server.config.MNEMONIC)
    server.decorate('judgeAccount', account)
    next()
}

declare module 'fastify' {
    interface FastifyInstance {
        judgeAccount: Account
    }
}

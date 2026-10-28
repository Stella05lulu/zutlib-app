// Runs the local gateway on its own and prints its address and a service
// token, so scripts/sample_data.py can be tested against a local database.
import { jwt, startGateway } from './gateway.ts'

const gw = startGateway()
console.log(JSON.stringify({ url: gw.url, service: await jwt({ role: 'service_role' }, Deno.env.get('JWT_SECRET') ?? '') }))

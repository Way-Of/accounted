/**
 * The server reaches its own Supabase gateway inside the box, not over the internet.
 *
 * A self-hosted install has ONE public name for its Supabase gateway (`NEXT_PUBLIC_SUPABASE_URL`): the
 * browser needs it, the tokens carry it as their issuer, and @supabase/ssr names the session cookie after
 * it. The app server used the same name for every one of its own calls, so each `getUser()`, each query
 * and each cron left the box, went through the CDN and the tunnel, and came back to a gateway that sits
 * next to it on the compose network. Measured on the Atlas box (2026-11-20): bursts of
 * `TypeError: fetch failed` (AggregateError: every address of the public name refused in turn) and
 * CDN 502 pages answered to PostgREST calls. A `getUser()` that fails that way returns no user, and the
 * request was treated as signed out: the heartbeat answered 401 and the page said *"Sessionen har upphört
 * av säkerhetsskäl"* minutes after a sign-in.
 *
 * With `SUPABASE_INTERNAL_URL` set (e.g. `http://api-gw:8000`), a server-side request whose origin is the
 * public gateway is sent to the internal one instead. Only the network path changes: the client is still
 * created with the public URL, so cookie names, token issuers and every URL handed to a browser (signed
 * storage links, redirects) stay public. Unset, nothing changes (hosted deployments).
 */

type FetchInput = string | URL | Request
type FetchArgs = Parameters<typeof fetch>

interface Gateways {
  publicOrigin: string
  internalOrigin: string
}

function originOf(raw: string | undefined): string | null {
  const value = raw?.trim()
  if (!value || value.startsWith('__')) return null // a build placeholder, never a real address
  try {
    const url = new URL(value)
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null
    return url.origin
  } catch {
    return null
  }
}

/** The public and internal gateway origins, or null when no internal gateway is configured. */
export function internalGateways(
  env: Record<string, string | undefined> = process.env,
): Gateways | null {
  const publicOrigin = originOf(env.NEXT_PUBLIC_SUPABASE_URL)
  const internalOrigin = originOf(env.SUPABASE_INTERNAL_URL)
  if (!publicOrigin || !internalOrigin || publicOrigin === internalOrigin) return null
  return { publicOrigin, internalOrigin }
}

/**
 * `url` with the public gateway's origin swapped for the internal one; any other URL unchanged. Only the
 * exact origin is matched (scheme, host and port), so `https://supabase.example.org.evil.test` or a path
 * that merely contains the public name is never rewritten.
 */
export function toInternalGateway(url: string, gateways: Gateways | null): string {
  if (!gateways) return url
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return url
  }
  if (parsed.origin !== gateways.publicOrigin) return url
  return gateways.internalOrigin + url.slice(gateways.publicOrigin.length)
}

function rewriteInput(input: FetchInput, gateways: Gateways | null): FetchInput {
  if (!gateways) return input
  if (typeof input === 'string') return toInternalGateway(input, gateways)
  if (input instanceof URL) {
    const next = toInternalGateway(input.href, gateways)
    return next === input.href ? input : new URL(next)
  }
  const next = toInternalGateway(input.url, gateways)
  return next === input.url ? input : new Request(next, input)
}

/**
 * A fetch for server-side Supabase clients: `global: { fetch: supabaseServerFetch }`. Reads the
 * configuration on every call, so a test or a late environment change is honoured.
 */
export const supabaseServerFetch: typeof fetch = (input, init) =>
  fetch(rewriteInput(input as FetchInput, internalGateways()) as FetchArgs[0], init)

const INSTALLED = Symbol.for('accounted.internalGatewayFetch')

/**
 * Route every server-side fetch to the public gateway through the internal one (the raw fetches some
 * routes make — health, storage — as well as the clients). Called once from `instrumentation.ts` in the
 * Node.js runtime. Idempotent; a no-op without `SUPABASE_INTERNAL_URL`. Returns whether it is active.
 */
export function installInternalGatewayFetch(
  env: Record<string, string | undefined> = process.env,
): boolean {
  const gateways = internalGateways(env)
  if (!gateways) return false
  const g = globalThis as typeof globalThis & { [INSTALLED]?: boolean }
  if (g[INSTALLED]) return true
  const original = globalThis.fetch.bind(globalThis)
  globalThis.fetch = ((input: FetchArgs[0], init?: FetchArgs[1]) =>
    original(rewriteInput(input as FetchInput, gateways) as FetchArgs[0], init)) as typeof fetch
  g[INSTALLED] = true
  return true
}

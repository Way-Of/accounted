import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  installInternalGatewayFetch,
  internalGateways,
  supabaseServerFetch,
  toInternalGateway,
} from '../internal-gateway'

const ENV = {
  NEXT_PUBLIC_SUPABASE_URL: 'https://supabase.example.org',
  SUPABASE_INTERNAL_URL: 'http://api-gw:8000',
}

describe('internal gateway', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
  })

  it('is off unless both names are set, real and different', () => {
    expect(internalGateways({})).toBeNull()
    expect(internalGateways({ NEXT_PUBLIC_SUPABASE_URL: ENV.NEXT_PUBLIC_SUPABASE_URL })).toBeNull()
    expect(internalGateways({ ...ENV, NEXT_PUBLIC_SUPABASE_URL: '__NEXT_PUBLIC_SUPABASE_URL__' })).toBeNull()
    expect(internalGateways({ ...ENV, SUPABASE_INTERNAL_URL: 'not a url' })).toBeNull()
    expect(internalGateways({ ...ENV, SUPABASE_INTERNAL_URL: ENV.NEXT_PUBLIC_SUPABASE_URL })).toBeNull()
    expect(internalGateways(ENV)).toEqual({
      publicOrigin: 'https://supabase.example.org',
      internalOrigin: 'http://api-gw:8000',
    })
  })

  it('rewrites only the public gateway origin, keeping path and query', () => {
    const g = internalGateways(ENV)
    expect(toInternalGateway('https://supabase.example.org/auth/v1/user', g)).toBe('http://api-gw:8000/auth/v1/user')
    expect(toInternalGateway('https://supabase.example.org/rest/v1/companies?select=id', g))
      .toBe('http://api-gw:8000/rest/v1/companies?select=id')
    // another host, a look-alike host, another port and the public name inside a path are left alone
    expect(toInternalGateway('https://api.stripe.com/v1/x', g)).toBe('https://api.stripe.com/v1/x')
    expect(toInternalGateway('https://supabase.example.org.evil.test/auth/v1/user', g))
      .toBe('https://supabase.example.org.evil.test/auth/v1/user')
    expect(toInternalGateway('https://supabase.example.org:8443/auth/v1/user', g))
      .toBe('https://supabase.example.org:8443/auth/v1/user')
    expect(toInternalGateway('https://x.test/?next=https://supabase.example.org/a', g))
      .toBe('https://x.test/?next=https://supabase.example.org/a')
    expect(toInternalGateway('https://supabase.example.org/auth/v1/user', null))
      .toBe('https://supabase.example.org/auth/v1/user')
  })

  it("the clients' fetch sends a public-gateway call to the internal gateway", async () => {
    for (const [k, v] of Object.entries(ENV)) vi.stubEnv(k, v)
    const seen: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => {
      seen.push(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
      return new Response('{}')
    }))
    await supabaseServerFetch('https://supabase.example.org/auth/v1/user', { headers: { apikey: 'k' } })
    await supabaseServerFetch(new URL('https://supabase.example.org/rest/v1/x'))
    await supabaseServerFetch(new Request('https://supabase.example.org/storage/v1/object/a'))
    await supabaseServerFetch('https://elsewhere.test/y')
    expect(seen).toEqual([
      'http://api-gw:8000/auth/v1/user',
      'http://api-gw:8000/rest/v1/x',
      'http://api-gw:8000/storage/v1/object/a',
      'https://elsewhere.test/y',
    ])
  })

  it('installs once on the global fetch, and not at all without the setting', async () => {
    const seen: string[] = []
    const base = vi.fn(async (input: string | URL | Request) => {
      seen.push(String(input))
      return new Response('{}')
    })
    vi.stubGlobal('fetch', base)
    expect(installInternalGatewayFetch({})).toBe(false)
    expect(globalThis.fetch).toBe(base)
    expect(installInternalGatewayFetch(ENV)).toBe(true)
    expect(installInternalGatewayFetch(ENV)).toBe(true)
    await fetch('https://supabase.example.org/auth/v1/health')
    expect(seen).toEqual(['http://api-gw:8000/auth/v1/health'])
    delete (globalThis as Record<symbol, unknown>)[Symbol.for('accounted.internalGatewayFetch')]
  })
})

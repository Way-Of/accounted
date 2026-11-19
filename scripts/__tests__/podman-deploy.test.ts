import { execFileSync, spawnSync } from 'node:child_process'
import { createHmac } from 'node:crypto'
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir, userInfo } from 'node:os'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'

/**
 * deploy/podman (docs/plans/podman-quadlet, PQ-01..PQ-03): the config contract,
 * the installer and the secrets generator. Podman, systemctl and ss are replaced
 * by shims on PATH, so nothing here touches the real container store or user
 * systemd; the real-host proof is the install on the dev instance user.
 */

const REPO = path.resolve(__dirname, '../..')
const DEPLOY = path.join(REPO, 'deploy/podman')
const ME = userInfo().username

const temps: string[] = []
function tmp(): string {
  const dir = mkdtempSync(path.join(tmpdir(), 'podman-deploy-'))
  temps.push(dir)
  return dir
}
afterEach(() => {
  while (temps.length) rmSync(temps.pop()!, { recursive: true, force: true })
})

/** A bin dir with fake podman (secrets in a dir), systemctl (logs calls) and ss (canned output). */
function shims(opts: { ss?: string } = {}) {
  const root = tmp()
  const bin = path.join(root, 'bin')
  const store = path.join(root, 'secrets')
  mkdirSync(bin)
  mkdirSync(store)
  writeFileSync(
    path.join(bin, 'podman'),
    `#!/usr/bin/env bash
store="${store}"
[ "$1" = secret ] || { echo "fake podman: unsupported $*" >&2; exit 2; }
shift; sub="$1"; shift
case "$sub" in
  inspect)
    show=0; while [ "$1" != "\${1#--}" ]; do [ "$1" = --showsecret ] && show=1; [ "$1" = --format ] && shift; shift; done
    [ -f "$store/$1" ] || exit 125
    # real podman ends --showsecret output with a newline the containers never see
    [ $show = 1 ] && { cat "$store/$1"; echo; }; exit 0 ;;
  create)
    while [ "$1" != "\${1#--}" ]; do [ "$1" = --label ] && shift; shift; done
    [ -f "$store/$1" ] && { echo "exists" >&2; exit 125; }
    cat > "$store/$1" ;;
  rm) [ -f "$store/$1" ] || exit 1; rm "$store/$1" ;;
  ls) ls "$store" ;;
esac
`,
  )
  writeFileSync(path.join(bin, 'systemctl'), `#!/usr/bin/env bash\necho "$*" >> "${root}/systemctl.log"\n`)
  writeFileSync(path.join(bin, 'ss'), `#!/usr/bin/env bash\ncat <<'OUT'\n${opts.ss ?? ''}\nOUT\n`)
  for (const f of ['podman', 'systemctl', 'ss']) chmodSync(path.join(bin, f), 0o755)
  return { root, bin, store }
}

function run(script: string, args: string[], env: Record<string, string> = {}, deploy = DEPLOY) {
  // A minimal environment on purpose: the scripts must not depend on anything else.
  const childEnv = {
    PATH: process.env.PATH ?? '/usr/bin:/bin',
    HOME: process.env.HOME ?? tmp(),
    ACCOUNTED_HOST_CONFIG: '/nonexistent',
    ...env,
  } as unknown as NodeJS.ProcessEnv
  const res = spawnSync('bash', [path.join(deploy, 'bin', script), ...args], {
    encoding: 'utf8',
    env: childEnv,
  })
  return { code: res.status, out: `${res.stdout}${res.stderr}` }
}

function verifyJwt(token: string, secret: string) {
  const [h, p, s] = token.split('.')
  const expected = createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url')
  return { valid: expected === s, payload: JSON.parse(Buffer.from(p, 'base64url').toString()) }
}

describe('check.sh (static gate)', () => {
  it('passes on the repo as committed', () => {
    const r = run('check.sh', [])
    expect(r.out).toContain('PASS')
    expect(r.code).toBe(0)
  })

  it.each([
    ['a wide published port', 'PublishPort=0.0.0.0:5432:5432\n', 'must be PublishPort'],
    ['SecurityLabelDisable', 'SecurityLabelDisable=true\n', 'SecurityLabelDisable'],
    ['a user-named path', 'Volume=/home/bob/data:/data:Z\n', 'naming a user'],
  ])('fails on %s', (_name, line, message) => {
    const copy = path.join(tmp(), 'podman')
    cpSync(DEPLOY, copy, { recursive: true })
    writeFileSync(path.join(copy, 'quadlets', 'bad.container'), `[Container]\nImage=x\n${line}`)
    const r = run('check.sh', [], {}, copy)
    expect(r.code).toBe(1)
    expect(r.out).toContain(message)
  })
})

describe('instance config', () => {
  it('renders every template with no unresolved tokens', () => {
    const out = tmp()
    const r = run('install.sh', ['--instance', 'dev', 'render', '--out', out])
    expect(r.code).toBe(0)
    for (const f of readdirSync(out)) {
      expect(readFileSync(path.join(out, f), 'utf8')).not.toMatch(/\$\{ACCOUNTED_/)
    }
    expect(readFileSync(path.join(out, 'accounted.network'), 'utf8')).toContain('accounted.instance=dev')
  })

  it.each([
    ['a four-digit port', { ACCOUNTED_EDGE_PORT: '3000' }, 'not a five-digit port'],
    ['a port outside the block', { ACCOUNTED_EDGE_PORT: '17166' }, 'outside the instance block'],
    ['a wide bind host', { ACCOUNTED_BIND_HOST: '0.0.0.0' }, 'not loopback'],
  ])('refuses %s', (_name, env, message) => {
    const r = run('install.sh', ['--instance', 'dev', 'render', '--out', tmp()], env)
    expect(r.code).not.toBe(0)
    expect(r.out).toContain(message)
  })

  it('refuses a host override file that sets a non-ACCOUNTED key', () => {
    const file = path.join(tmp(), 'instance.env')
    writeFileSync(file, 'PATH=/evil\n')
    const r = run('install.sh', ['--instance', 'dev', 'render', '--out', tmp()], {
      ACCOUNTED_HOST_CONFIG: file,
    })
    expect(r.code).not.toBe(0)
    expect(r.out).toContain("refusing key 'PATH'")
  })

  it('publishes exactly one port per instance: the edge, on loopback, from the pod', () => {
    for (const [inst, port] of [['dev', 21230], ['qa', 26791], ['staging', 26219], ['prod', 17166]] as const) {
      const out = tmp()
      expect(run('install.sh', ['--instance', inst, 'render', '--out', out]).code).toBe(0)
      const published = readdirSync(out).flatMap((f) =>
        readFileSync(path.join(out, f), 'utf8')
          .split('\n')
          .filter((l) => l.startsWith('PublishPort='))
          .map((l) => `${f} ${l}`),
      )
      const onDemand = published.filter((l) => /studio|db-admin/.test(l))
      expect(published.filter((l) => !onDemand.includes(l))).toEqual([
        `accounted.pod PublishPort=127.0.0.1:${port}:${port}`,
      ])
    }
  })

  it('takes every image from upstream.lock or the instance file, fully qualified', () => {
    const tpl = path.join(DEPLOY, 'quadlets')
    const out = tmp()
    expect(run('install.sh', ['--instance', 'qa', 'render', '--out', out]).code).toBe(0)
    for (const f of readdirSync(tpl).filter((n) => n.endsWith('.container'))) {
      const image = readFileSync(path.join(tpl, f), 'utf8').match(/^Image=(.*)$/m)?.[1]
      expect(image, f).toMatch(/^\$\{ACCOUNTED_(IMG_[A-Z]+|IMAGE|CRON_IMAGE)\}$/)
      const rendered = readFileSync(path.join(out, f), 'utf8').match(/^Image=(.*)$/m)?.[1]
      expect(rendered, f).toMatch(/^(docker\.io|localhost)\//)
    }
  })

  it('reads only secrets that secrets.manifest makes', () => {
    const made = new Set(
      readFileSync(path.join(DEPLOY, 'secrets.manifest'), 'utf8')
        .split('\n')
        .filter((l) => l.trim() && !l.startsWith('#'))
        .map((l) => l.split(/\s+/)[0]),
    )
    const tpl = path.join(DEPLOY, 'quadlets')
    for (const f of readdirSync(tpl)) {
      for (const m of readFileSync(path.join(tpl, f), 'utf8').matchAll(/^Secret=([^,\n]+)/gm)) {
        expect(made.has(m[1]), `${f}: ${m[1]}`).toBe(true)
      }
    }
  })

  it('refuses an unknown instance', () => {
    const r = run('install.sh', ['--instance', 'uat', 'render', '--out', tmp()])
    expect(r.out).toContain("unknown instance 'uat'")
  })
})

describe('install.sh', () => {
  it('refuses to install as anyone but the instance user', () => {
    const r = run('install.sh', ['--instance', 'prod', 'install'])
    expect(r.code).not.toBe(0)
    expect(r.out).toContain('run as accounted-prod')
  })

  it('installs units with a manifest, reloads systemd, and removes stale units', () => {
    const s = shims()
    const qdir = path.join(s.root, 'quadlets')
    mkdirSync(qdir)
    writeFileSync(path.join(qdir, '.accounted-installed'), 'accounted-old.container\n')
    writeFileSync(path.join(qdir, 'accounted-old.container'), '[Container]\n')
    writeFileSync(path.join(qdir, 'unrelated.container'), '[Container]\n')
    const home = path.join(s.root, 'home')
    mkdirSync(home)
    const env = { PATH: `${s.bin}:${process.env.PATH}`, HOME: home, ACCOUNTED_USER: ME, ACCOUNTED_QUADLET_DIR: qdir }

    const r = run('install.sh', ['--instance', 'dev', 'install'], env)
    expect(r.code).toBe(0)
    // the release files the units mount from %h/.local/share/accounted
    const release = path.join(home, '.local/share/accounted/release')
    const repoMigrations = readdirSync(path.join(REPO, 'supabase/migrations')).filter((f) => f.endsWith('.sql'))
    expect(readdirSync(path.join(release, 'supabase/migrations')).sort()).toEqual(repoMigrations.sort())
    expect(existsSync(path.join(release, 'supabase/bootstrap.sql'))).toBe(true)
    expect(existsSync(path.join(release, 'edge/Caddyfile'))).toBe(true)
    expect(existsSync(path.join(release, 'crontab'))).toBe(true)
    expect(existsSync(path.join(home, '.local/share/accounted/upstream/db/roles.sql'))).toBe(true)
    expect(readFileSync(path.join(release, 'COMMIT'), 'utf8').trim()).not.toBe('')
    expect(existsSync(path.join(qdir, 'accounted.network'))).toBe(true)
    expect(existsSync(path.join(qdir, 'accounted-old.container'))).toBe(false)
    expect(existsSync(path.join(qdir, 'unrelated.container'))).toBe(true)
    expect(readFileSync(path.join(qdir, '.accounted-installed'), 'utf8')).toContain('accounted.network')
    expect(readFileSync(path.join(s.root, 'systemctl.log'), 'utf8')).toContain('--user daemon-reload')
  })

  it('fails start when this user owns a non-loopback socket', () => {
    const s = shims({ ss: 'LISTEN 0 4096 0.0.0.0:21230 0.0.0.0:* users:(("rootlessport",pid=1,fd=10))' })
    const r = run('install.sh', ['--instance', 'dev', 'start'], {
      PATH: `${s.bin}:${process.env.PATH}`,
      ACCOUNTED_USER: ME,
    })
    expect(r.code).not.toBe(0)
    expect(r.out).toContain('non-loopback socket')
  })

  it('passes start when every owned socket is loopback', () => {
    const s = shims({ ss: 'LISTEN 0 4096 127.0.0.1:21230 0.0.0.0:* users:(("rootlessport",pid=1,fd=10))' })
    const r = run('install.sh', ['--instance', 'dev', 'start'], {
      PATH: `${s.bin}:${process.env.PATH}`,
      ACCOUNTED_USER: ME,
    })
    expect(r.code).toBe(0)
  })
})

describe('secrets-init.sh', () => {
  function setup() {
    const s = shims()
    const env = { PATH: `${s.bin}:${process.env.PATH}`, ACCOUNTED_USER: ME }
    const secret = (name: string) => readFileSync(path.join(s.store, name), 'utf8')
    return { s, env, secret }
  }

  it('creates every generated secret, signs valid role JWTs, and is idempotent', () => {
    const { s, env, secret } = setup()
    const first = run('secrets-init.sh', ['--instance', 'dev'], env)
    expect(first.code).toBe(0)
    expect(first.out).toContain('11 created')

    const jwtSecret = secret('accounted-jwt-secret')
    expect(jwtSecret).toMatch(/^[0-9a-f]{64}$/)
    for (const [name, role] of [
      ['accounted-anon-key', 'anon'],
      ['accounted-service-role-key', 'service_role'],
    ]) {
      const { valid, payload } = verifyJwt(secret(name), jwtSecret)
      expect(valid).toBe(true)
      expect(payload.role).toBe(role)
      expect(payload.exp).toBeGreaterThan(payload.iat)
    }
    for (const v of readdirSync(s.store).map(secret)) expect(first.out).not.toContain(v)

    const second = run('secrets-init.sh', ['--instance', 'dev'], env)
    expect(second.out).toContain('0 created')
  })

  it('re-signs every JWT when the JWT secret is rotated', () => {
    const { env, secret } = setup()
    run('secrets-init.sh', ['--instance', 'dev'], env)
    const oldAnon = secret('accounted-anon-key')
    const r = run('secrets-init.sh', ['--instance', 'dev', '--rotate', 'accounted-jwt-secret'], env)
    expect(r.code).toBe(0)
    expect(secret('accounted-anon-key')).not.toBe(oldAnon)
    expect(verifyJwt(secret('accounted-anon-key'), secret('accounted-jwt-secret')).valid).toBe(true)
  })

  it('accepts a supplied secret from a 0600 file', () => {
    const { env, secret } = setup()
    const file = path.join(tmp(), 'supplied')
    writeFileSync(file, 'accounted-smtp-password=s3cret-from-a-person\n', { mode: 0o600 })
    const r = run('secrets-init.sh', ['--instance', 'dev', '--from', file], env)
    expect(r.code).toBe(0)
    expect(secret('accounted-smtp-password')).toBe('s3cret-from-a-person')
    expect(r.out).not.toContain('s3cret-from-a-person')
  })

  it.each([
    ['a file that is not 0600', 'supplied', 0o644, 'accounted-smtp-password=x', 'mode 644'],
    ['a .env.local', 'x.env.local', 0o600, 'accounted-smtp-password=x', '.env.local'],
    ['a key that is not supplied', 'supplied', 0o600, 'accounted-jwt-secret=x', 'not a supplied secret'],
    ['a known demo value', 'supplied', 0o600, 'accounted-smtp-password=generate-a-random-secret', 'demo value'],
  ])('refuses %s', (_name, filename, mode, content, message) => {
    const { env } = setup()
    const file = path.join(tmp(), filename)
    writeFileSync(file, `${content}\n`)
    chmodSync(file, mode)
    const r = run('secrets-init.sh', ['--instance', 'dev', '--from', file], env)
    expect(r.code).not.toBe(0)
    expect(r.out).toContain(message)
  })

  it('refuses to run as anyone but the instance user', () => {
    const r = run('secrets-init.sh', ['--instance', 'staging'])
    expect(r.out).toContain('run as accounted-staging')
  })
})

describe('prepare-host.sh', () => {
  it('prints root steps with a revert line and runs nothing', () => {
    const out = execFileSync('bash', [path.join(DEPLOY, 'bin/prepare-host.sh'), '--instance', 'prod'], {
      encoding: 'utf8',
      env: { ...process.env, ACCOUNTED_HOST_CONFIG: '/nonexistent' },
    })
    expect(out).toContain('useradd --create-home --shell /bin/bash accounted-prod')
    expect(out).toContain('loginctl enable-linger accounted-prod')
    expect(out).toContain('# loginctl disable-linger accounted-prod && userdel --remove accounted-prod')
  })
})

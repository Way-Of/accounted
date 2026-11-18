# Architecture: Accounted in the Way-Of Podman estate

**Date:** 2026-11-17 · **Companion to:** [`PRD.md`](PRD.md) (revision 2) · **Tasks:** [`tasks/`](tasks/README.md)

Diagrams-as-code for where Accounted sits among the Way-Of products, what one instance looks like
inside, how it boots, how a request travels, and how the work is delivered. Planned parts are marked
*planned*; everything else exists today. Sources: `atlas-vault/docs/41-hosted-topology.md`,
`atlas-vault/deploy/hostinger/runbook.md`, this repo, and the Minisforum and Hostinger hosts as
measured on 2026-11-17.

## 1. The Way-Of estate (system context)

```mermaid
flowchart TB
    person(["A person<br/>bookkeeper · owner · Craig"])
    operator(["Operator<br/>Craig"])
    internet(("internet"))

    subgraph edgezone["PUBLIC: the only listening door"]
      cf["Cloudflare<br/>TLS · tunnel · Access (Q4)"]
    end

    subgraph desk["ZONE desk"]
      atlasdesk["Atlas Desk<br/>the app a person uses<br/>connectors: vault · receipts · books"]
    end

    subgraph vaultz["ZONE vault"]
      vault["Atlas vault ('Vault')<br/>files · versions · AI librarian<br/>INSERT-only audit trail"]
      vstore[("object store")]
    end

    subgraph services["ZONE services"]
      rh["receipt-hunter"]
    end

    subgraph books["ZONE books: this PRD"]
      acc["Accounted<br/>Swedish double-entry bookkeeping<br/>+ self-hosted Supabase stack"]
    end

    subgraph egress["ZONE egress"]
      bastion["Bastion<br/>sandboxes · egress wall · ledger<br/>provider keys (planned remote)"]
      fwd["forward proxy + allowlist<br/>(until Bastion has a release)"]
    end

    subgraph agentsz["Our agents (planned, PQ-13)"]
      ag["Way-Of agents<br/>in Bastion sandboxes"]
    end

    dest["named destinations only<br/>Skatteverket · banks · SMTP · Google OAuth<br/>gmail APIs · receipt vendors · model providers"]

    person --> internet --> cf
    cf --> atlasdesk
    cf -->|"accounted.* public name"| acc
    atlasdesk -->|"connector token"| vault
    atlasdesk -->|"connector token"| rh
    atlasdesk -->|"approval queue UI"| acc
    rh -->|"MCP · scoped gnubok_sk_ key<br/>read + stage only"| acc
    ag -->|"MCP · one key per agent<br/>staged ops, person approves"| acc
    vault --> vstore
    acc -->|"HTTPS_PROXY"| fwd
    rh --> fwd
    atlasdesk --> bastion
    vault --> bastion
    ag --> bastion
    fwd -.->|"replaced by"| bastion
    bastion --> dest
    fwd --> dest
    operator -->|"WireGuard / Tailscale<br/>administrative path only"| desk
    operator -->|"tailnet · Studio on demand"| acc

    classDef planned stroke-dasharray: 5 5
    class ag,bastion planned
```

**The rule that keeps it honest:** a zone reaches only what its row in the topology paper names. Books
reaches nothing directly; everything outbound goes through the egress door.

## 2. Hosts and instances (deployment)

```mermaid
flowchart LR
    subgraph mini["Minisforum · Fedora 43 · rootless Podman 5.x"]
      subgraph udev["user accounted-dev (planned)"]
        devinst["Accounted instance 'dev'<br/>edge 127.0.0.1:21230<br/>Studio :21231 · DB admin :21232 (on demand)"]
      end
      subgraph ucraig["user craigema (exists)"]
        fj1["Forgejo<br/>127.0.0.1:8889 · ssh :2222"]
        others1["WoWx · wayofteams · anchor<br/>wayofmono · investready ..."]
      end
      ts1["tailscale0"]
    end

    subgraph hst["Hostinger VPS · Ubuntu · rootless Podman 5.7"]
      caddy["host Caddy<br/>127.0.0.1:80/443"]
      cfd["cloudflared tunnels"]
      subgraph ustg["user accounted-staging (planned)"]
        stginst["Accounted instance 'staging'<br/>edge 127.0.0.1:26219"]
      end
      subgraph uprod["user accounted-prod (planned)"]
        prodinst["Accounted instance 'prod'<br/>edge 127.0.0.1:17166"]
      end
      subgraph ufj["user forgejo (exists)"]
        fj2["Forgejo<br/>127.0.0.1:16585<br/>git.veyral.io"]
      end
      subgraph ujosef["user josef (exists)"]
        atlas["AtlasAI pod<br/>atlas-dev.veyral.io"]
      end
    end

    gh["GitHub<br/>Way-Of/accounted"]
    cloud(("Cloudflare edge"))

    cloud --> cfd --> caddy
    caddy --> stginst
    caddy --> prodinst
    caddy --> fj2
    caddy --> atlas
    ts1 -.->|"road: tailnet (opt-in)"| devinst
    gh <-->|"push"| fj1
    gh <-->|"push"| fj2

    classDef planned stroke-dasharray: 5 5
    class devinst,stginst,prodinst planned
```

| Instance | Host | Linux user | Port block | Road |
|---|---|---|---|---|
| `dev` | Minisforum | `accounted-dev` | 21230-21237 | none / tailnet |
| `staging` | Hostinger | `accounted-staging` | 26219-26226 | tunnel |
| `prod` | Hostinger | `accounted-prod` | 17166-17173 | tunnel (+ Access, Q4) |

All three blocks were measured free on both hosts on 2026-11-17. One Linux user per instance means
rootless Podman gives each its own containers, networks, volumes and secrets: staging cannot see prod.

## 3. Inside one instance (containers)

```mermaid
flowchart TB
    door["127.0.0.1:ACCOUNTED_EDGE_PORT<br/>the one published door"]
    peers["peers in other users' containers<br/>host.containers.internal + scoped key"]
    studioDoor["127.0.0.1:ACCOUNTED_STUDIO_PORT<br/>on demand · tailnet only"]

    subgraph net["accounted.network · Internal=true · no route out"]
      edge["accounted-edge<br/>Caddy · single origin"]

      subgraph appTier["Accounted (this repo)"]
        app["accounted-app<br/>Next.js 16 · supabase-js<br/>MCP server · engine.ts"]
        cron["accounted-cron<br/>supercronic · crontab.self-hosted"]
        mig["accounted-migrate (oneshot)<br/>bootstrap.sql once<br/>supabase db push"]
        bak["accounted-backup (timer)<br/>scripts/self-host/backup.sh"]
      end

      subgraph supa["Supabase self-hosted stack · pinned in upstream.lock"]
        gw["accounted-gateway<br/>Kong or Envoy · apikey check"]
        auth["accounted-auth<br/>GoTrue · TOTP MFA"]
        rest["accounted-rest<br/>PostgREST"]
        sto["accounted-storage<br/>storage-api · file or S3"]
        rt["accounted-realtime"]
        meta["accounted-meta"]
        studio["accounted-studio<br/>(on demand)"]
        db[("accounted-db<br/>supabase/postgres 17<br/>RLS · migration 017 triggers<br/>pg_cron · pgvector")]
      end
    end

    dropped["dropped from upstream:<br/>analytics · vector · functions<br/>imgproxy · supavisor"]
    egress["egress door<br/>forward proxy, then Bastion"]
    s3[("off-host backups<br/>S3 + Object Lock")]

    door --> edge
    peers --> door
    edge -->|"/"| app
    edge -->|"/auth/v1 /rest/v1<br/>/storage/v1 /realtime/v1"| gw
    gw --> auth & rest & sto & rt
    app --> gw
    cron -->|"CRON_SECRET"| app
    auth & rest & sto & rt --> db
    mig --> db
    meta --> db
    studioDoor --> studio --> meta
    bak --> db
    bak --> s3
    app -->|"HTTPS_PROXY"| egress
    auth -->|"SMTP · OAuth"| egress

    classDef gone fill:#eee,stroke:#999,color:#666,stroke-dasharray: 3 3
    class dropped gone
```

## 4. Boot order

Load-bearing: Accounted's migrations reference `auth.users` and `storage.objects`, which GoTrue and
storage-api create in their own migrations.

```mermaid
flowchart LR
    db["accounted-db<br/>healthy"] --> auth["auth<br/>migrates auth.*"]
    db --> sto["storage<br/>migrates storage.*"]
    db --> rt["realtime<br/>migrates realtime.*"]
    auth & sto & rt --> mig["accounted-migrate<br/>1 bootstrap.sql (empty DB only)<br/>2 supabase db push<br/>3 NOTIFY pgrst reload"]
    mig --> rest["rest"]
    rest --> gw["gateway"]
    gw --> app["app"]
    app --> cron["cron"]
    app --> edge["edge"]
```

## 5. A request, end to end (prod)

```mermaid
sequenceDiagram
    autonumber
    actor U as Person (browser)
    participant CF as Cloudflare (TLS, Access)
    participant HC as host Caddy :443
    participant E as accounted-edge :17166
    participant A as accounted-app
    participant G as gateway
    participant GT as GoTrue
    participant R as PostgREST
    participant D as Postgres 17

    U->>CF: GET / on the public name
    CF->>HC: tunnel
    HC->>E: 127.0.0.1:17166
    E->>A: / (page)
    A-->>U: login page
    U->>E: POST /auth/v1/token (same origin)
    E->>G: /auth/v1/*
    G->>GT: apikey ok
    GT->>D: auth.users, MFA factors
    GT-->>U: session (AAL1, then TOTP to AAL2)
    U->>E: post a verifikat (app route)
    E->>A: /api/...
    A->>G: rpc commit_journal_entry (user JWT)
    G->>R: /rest/v1/rpc/...
    R->>D: RLS (user_company_ids), triggers (period lock, balance, voucher sequence)
    D-->>U: voucher number assigned
```

## 6. Delivery: from this PRD to live

```mermaid
flowchart LR
    subgraph done["2026-11-17 · done in this session"]
      r["research<br/>quadlet conventions · Ymir rules<br/>Atlas topology · Supabase coupling"]
      p1["PRD rev 1<br/>stock Postgres"]
      p2["PRD rev 2<br/>official stack, trimmed, PG 17<br/>instances · port blocks"]
      t["14 task slices<br/>PQ-01..PQ-14"]
      h["HANDOFF.md · DECISIONS.md<br/>Anchor note · this doc"]
      r --> p1 -->|"Craig: Supabase advantages?"| p2 --> t --> h
    end

    subgraph m1["M1 · dev runs"]
      a1["PQ-01 config + blocks"] --> a2["PQ-02 users + installer"] --> a3["PQ-03 secrets"] --> a4["PQ-04 Supabase stack"] --> a6["PQ-06 migrate"] --> a7["PQ-07 app + cron"] --> a8["PQ-08 edge"]
    end
    subgraph m2["M2 · dev proven"]
      a5["PQ-05 PG 17 + pg-real"]
      a9["PQ-09 parity walk"]
      a10["PQ-10 backup + restore"]
      a5 --> a9 --> a10
    end
    subgraph m3["M3 · live"]
      a11["PQ-11 Hostinger staging, then prod"]
    end
    subgraph m4["M4 · estate"]
      a12["PQ-12 books seat"] --> a13["PQ-13 agents (needs Bastion)"]
    end
    a14["PQ-14 docs + CI gates (rides along)"]

    h --> a1
    a4 --> a5
    a8 --> a9
    a10 --> a11
    a9 --> a12
    a4 -.-> a14
    a11 -.-> a14

    subgraph repos["the branch lives in three places"]
      gh["GitHub Way-Of/accounted"]
      f1["Forgejo, Minisforum"]
      f2["Forgejo, Hostinger (git.veyral.io)"]
    end
    h --> repos
```

# PQ-09: `dev` parity walk-through

**Depends on:** PQ-05, PQ-08 · **Size:** L

## Checklist (each observed, not assumed)
- Register, confirm by SMTP, log in, enrol and use TOTP (`auth.mfa.*`).
- Invite a member (`auth.admin.generateLink`, `admin.createUser`), accept, switch company.
- Create an aktiebolag and an enskild firma; post a verifikat; voucher numbers sequential.
- Edit a posted entry outside the rättelse paths: refused by the DB (migration 017 triggers).
- Post into a locked period: refused.
- Upload a receipt to `documents`; delete a document linked to a posted entry: refused.
- Import a SIE file; generate an invoice PDF with logo and font.
- A cron route fires; the `pg_cron` job from the overdue-invoice migration runs.
- Realtime updates on the 4 `.channel(` pages.
- MCP: create a `gnubok_sk_` key; a read tool and a staged write through the edge.
- Group the 443 `supabase.auth.*` call sites by method; mark each family exercised or not applicable
  (BankID is hosted-only).

## Acceptance
- `docs/plans/podman-quadlet/parity-report.md` complete with dates and evidence.

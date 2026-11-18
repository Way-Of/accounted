# PQ-13: Our agents seat

**Depends on:** PQ-12, a Bastion release · **Size:** M · **Status:** blocked

## Scope
- One `gnubok_sk_` key per agent, least scopes, default 100 RPM, named so the audit log says which agent.
- Agents run in Bastion sandboxes; model calls go through Bastion; no agent holds a provider key,
  a database credential or Studio access.
- Writes use the MCP staged-operation pattern (`.claude/rules/mcp-server.md`); nothing posts a
  verifikat without a person's approval.
- Decide per agent whether it belongs outside (MCP client) or inside Accounted (`/create-extension`).

## Acceptance
- One agent proposes an entry; a person approves it; the audit log names the agent's key.

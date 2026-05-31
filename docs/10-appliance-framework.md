# 10 — AI Employee Appliance Framework

This repo is moving from "many AI dev sandboxes" toward portable AI employee appliances.
An appliance is the operational unit for one customer, company, or role. It contains the
Compose file, customer config, workspace, tool identity, and persistent data needed to
move the environment as one directory.

## What an appliance is

```
/srv/airacle/appliances/<appliance-name>/
├── appliance.env              # real local env, never committed
├── compose.yml                # copied from a template
├── config/                    # prompts, SOPs, customer profile
├── data/                      # databases, OpenClaw/OpenCloud data, exports
├── identity/                  # Claude, Codex, Omnara, GitHub/Cloudflare login state
└── workspace/                 # customer work, inbox, projects, deliverables
```

The directory is the migration and backup boundary. Moving the appliance should be a
filesystem copy plus an image pull on the target machine:

```bash
rsync -a /srv/airacle/appliances/acme-marketing/ new-host:/srv/airacle/appliances/acme-marketing/
ssh new-host 'cd /srv/airacle/appliances/acme-marketing && docker compose up -d'
```

## What goes in Git

Git stores templates, scripts, image definitions, docs, and examples:

```
templates/
scripts/
Dockerfile
docs/
.env.example
```

Git does not store customer data, secrets, OAuth login state, workspaces, or exports.

## Runtime model

Default runtime uses the host Docker daemon and one Compose project per appliance:

```
Host Docker daemon
└── appliance: acme-marketing
    ├── openclaw
    ├── agent
    ├── codex-worker
    ├── video-worker
    ├── redis
    └── postgres
```

This is intentionally not Docker-in-Docker by default. The normal path is managed
operation: Airacle configures the appliance, customers use the configured interface and
deliverables, and operators enter by SSH/Tailscale only when needed.

## Optional Docker-in-Docker

Some appliances may need Docker capability later. Keep it optional and explicit:

```bash
docker compose --profile dind up -d
```

The `dind` profile runs a sidecar daemon and stores its inner Docker state under
`./data/dind`. Do not enable it for every customer by default. It makes backup,
monitoring, security review, and troubleshooting more complex.

## Identity and keys

Important interactive tools should persist under `identity/`:

| Tool | Path | Notes |
| --- | --- | --- |
| Claude Code | `identity/claude/`, `identity/claude.json` | Operator logs in once. |
| Codex | `identity/codex/` | Use login flow where possible. |
| Omnara | `identity/omnara/` | Required for remote agent monitoring/control. |
| GitHub CLI | `identity/gh/` | Optional per-appliance auth. |
| Cloudflare | env token or `identity/cloudflare/` | Prefer token in local env. |

API keys belong in `appliance.env` or an external secret manager. Do not put real keys in
templates or docs.

## Marketing employee template

The first appliance template is `templates/marketing-employee`. It is designed for a
custom, high-touch marketing "AI employee" rather than usage-metered SaaS:

- video editing and batch export
- copy generation
- asset organization
- content calendar planning
- comment/private-message operations
- paid creative/ad variant production
- OpenClaw/OpenCloud or other installable tools per customer
- Claude Code, Codex, and Omnara as first-class tools

## Management commands

Scripts use `/srv/airacle/appliances` by default. Override with `AIRACLE_APPLIANCES_ROOT`.

```bash
./scripts/create-appliance.sh marketing-employee acme-marketing
./scripts/start-appliance.sh acme-marketing
./scripts/shell-appliance.sh acme-marketing agent
./scripts/backup-appliance.sh acme-marketing
./scripts/upgrade-appliance.sh acme-marketing
```

## Design rules

1. A customer appliance must be movable as one directory.
2. Every mutable path must be under `data/`, `workspace/`, or `identity/`.
3. Secrets and login state never enter Git.
4. Omnara is part of the default operating model.
5. Docker-in-Docker is available as an explicit profile, not a default behavior.
6. Finance and marketing appliances must not share secrets, login state, or workspaces.

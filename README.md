# The Last Ones (TLO)

A multi-domain Active Directory cyber range for [Ludus](https://ludus.cloud), reproducing a
9-milestone / 32-step red-team attack chain end to end — from an external VPN foothold,
through three isolated corporate AD domains, to full data exfiltration.

> **Status:** Under active construction (automated build in progress). This range is built
> and deployed entirely from Ludus range config + custom Ansible roles in this repo.

## Attack chain (9 milestones)

| # | Milestone | Where |
|---|-----------|-------|
| 1 | Initial reconnaissance and entry (default-cred VPN portal → `.ovpn`) | External |
| 2 | Lateral movement via Kerberos misconfiguration (SMB enum, AS-REP roast) | CHARLIE |
| 3 | Browser credential theft (DCOM lateral, Chrome/DPAPI creds) | CHARLIE |
| 4 | Cross-site request forgery and credential relay (wiki CSRF → NTLM relay) | CHARLIE → OSCAR |
| 5 | Web app exploitation & privesc (ViewState, SQLi+relay RCE, S4U delegation, LAPS+GPO) | OSCAR |
| 6 | Reverse engineering & cryptographic key recovery (.NET service RE, AES creds) | OSCAR |
| 7 | C2 pivoting & CI/CD credential harvesting (HardHat API, git/PS-history secrets) | OSCAR → ALPHA |
| 8 | Supply chain compromise (backdoored C# artifact via CI/CD → Domain Admin) | ALPHA |
| 9 | Final data exfiltration (layered SQLi: stored-proc / CALL / UNION) | ALPHA |

## Topology

Five networks, each an isolated VLAN, firewalled to force the milestone order:

```
Attacker (Mythic C2, Kali)
   └─▶ External (VPN portal, DNS)          ── M1
        └─▶ CHARLIE  charlie.local          ── M2–M4
             └─▶ OSCAR  oscar.local          ── M5–M6   (reached via relay/creds)
                  └─▶ ALPHA  alpha.local     ── M7–M9   (reachable ONLY via OSCAR C2 pivot)
```

## Repo layout

```
range-config.yml     # the Ludus range definition (single source of truth)
roles/               # custom Ansible roles (added to Ludus via `ludus ansible role add -d`)
artifacts/           # prebuilt binaries / seed files used by roles
scripts/             # deploy + validation helpers
docs/                # architecture, per-domain design, deploy + validation guides
```

## Quick start

```bash
# 1. Add the custom roles to your Ludus server
scripts/install-roles.sh
# 2. Set the range config and deploy
ludus range config set -f range-config.yml
ludus range deploy
# 3. Validate
scripts/validate.sh
```

See [`docs/deployment.md`](docs/deployment.md) for the full procedure and
[`docs/attack-chain.md`](docs/attack-chain.md) for the milestone-by-milestone walkthrough.

## Requirements

- Ludus 2.2.x server (Proxmox backend)
- Templates: `win2022-server-x64-template`, `win11-22h2-x64-enterprise-template`,
  `debian-12-x64-server-template`, `kali-x64-desktop-template`
- ~18 VMs; sized small for dev/test (see [`docs/architecture.md`](docs/architecture.md) for the budget)

---

*Built for authorized security training and red-team tradecraft practice in an isolated lab.*

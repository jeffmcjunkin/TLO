# The Last Ones — Architecture

The single source of truth for the deployed topology. Pairs with
[`attack-chain.md`](attack-chain.md) (what each milestone does) and
[`../range-config.yml`](../range-config.yml) (the machine-readable definition).

## Design principles

1. **Three isolated AD domains, no trusts** — `charlie.local`, `oscar.local`, `alpha.local`.
   Bridged only by credential reuse, NTLM relay, and C2 pivoting (see attack-chain).
2. **The firewall *is* the difficulty curve.** `inter_vlan_default: REJECT`; each allow-rule
   is annotated with the milestone it unlocks. You cannot reach a later segment until you have
   done the earlier work. Two hard network gates: (a) CHARLIE is reachable only *through the VPN
   portal* after M1; (b) ALPHA is reachable only *through the HardHat C2 host* after M6.
3. **Everything is real.** No milestone is faked — every misconfig, vuln, and artifact is
   actually present and exploitable. Off-the-shelf Ludus/Pro roles where they exist; custom roles
   (in [`../roles/`](../roles)) for the rest.

## Network / VLAN plan

Range number **3** → all addresses are `10.3.<vlan>.<octet>`; the Ludus router is the gateway +
DNS at `10.3.<vlan>.254` on every VLAN.

| Network | VLAN | Subnet | Domain |
|---|---|---|---|
| Attacker | 10 | 10.3.10.0/24 | — |
| External (DMZ) | 20 | 10.3.20.0/24 | — |
| CHARLIE | 30 | 10.3.30.0/24 | charlie.local |
| OSCAR | 40 | 10.3.40.0/24 | oscar.local |
| ALPHA | 50 | 10.3.50.0/24 | alpha.local |

Octet convention: DC = `.10`, member servers = `.20–.29`, workstations = `.30–.49`,
C2/appliances = `.50–.59`.

## Host inventory (20 VMs + router)

| Host | IP | VLAN | Template | Domain role | Purpose / milestones |
|---|---|---|---|---|---|
| `TLO-kali` | 10.3.10.10 | 10 | kali-desktop | — | Operator box (all milestones) |
| `TLO-mythic` | 10.3.10.20 | 10 | debian-12 | — | Mythic C2 + Apollo (Apollo callback) |
| `TLO-vpn-portal` | 10.3.20.10 | 20 | debian-12 | — | VPN portal, default creds, `.ovpn` (M1) |
| `TLO-ext-dns` | 10.3.20.20 | 20 | debian-12 | — | External DNS, AXFR leak (M1) |
| `CHARLIE-DC1` | 10.3.30.10 | 30 | win2022 | primary-dc | KDC; AS-REP user, privileged victim (M2) |
| `CHARLIE-FS` | 10.3.30.20 | 30 | win2022 | member | SMB shares + victim auto-browser (M2, M4) |
| `charlie-wiki` | 10.3.30.21 | 30 | debian-12 | — | BookStack, stored-XSS (M4) |
| `AREUBEN-WS` | 10.3.30.30 | 30 | win11 | member | reuben's WS; Chrome creds, DCOM (M3) |
| `OSCAR-DC1` | 10.3.40.10 | 40 | win2022 | primary-dc | LAPS, constrained delegation (M5) |
| `OSCAR-WEB` | 10.3.40.20 | 40 | win2022 | member | ASP.NET ViewState + SQLi (M5) |
| `OSCAR-DB` | 10.3.40.21 | 40 | win2022 | member | MSSQL; xp_cmdshell, coercion (M5) |
| `OPERATOR-WS1` | 10.3.40.30 | 40 | win11 | member | RE service artifact, LAPS lateral (M6) |
| `oscar-hardhat` | 10.3.40.50 | 40 | debian-12 | — | HardHat C2; **only ingress to ALPHA** (M6/M7) |
| `DC1-ALPHA` (dd1) | 10.3.50.10 | 50 | win2022 | primary-dc | alpha.local DC; svc_build∈Domain Admins |
| `alpha-gitlab` | 10.3.50.20 | 50 | debian-12 | — | GitLab CE; git-history + CI secrets (M7) |
| `XY1-ALPHA` | 10.3.50.21 | 50 | win2022 | member | TeamCity + DA build agent (M7/M8) |
| `ALPHA-SECRETS` | 10.3.50.22 | 50 | win2022 | member | MSSQL crown jewels; layered SQLi (M9) |
| `alpha-elastic` | 10.3.50.25 | 50 | debian-12 | — | Elastic SIEM/EDR (M8 "evade EDR") |
| `ALPHA-WKS` | 10.3.50.30 | 50 | win11 | member | Pivot landing; PSReadline history (M7) |

> **`dd1.alpha` = `DC1-ALPHA`.** Read as the alpha.local domain controller (matching DC1.CHARLIE /
> DC1.OSCAR), so M9's layered SQLi runs entirely on `ALPHA-SECRETS` via nested stored procedures.

Approx. footprint: **~103 GB RAM / ~61 vCPU** across the 3-node cluster (~186 GB / 48 cores),
sized small for dev/test. Shares the cluster with an existing GOAD range + other work, so monitor
placement; trim `alpha-elastic` first if constrained.

## Milestone → host → role map

| M | Steps | Host(s) | Roles (custom in **bold**) |
|---|---|---|---|
| 1 | 1.1–1.4 | vpn-portal, ext-dns | **tlo_vpn_portal**, **tlo_external_dns** |
| 2 | 2.1–2.3 | CHARLIE-DC1, CHARLIE-FS | **charlie_ad_vulns**, **charlie_fs_share** |
| 3 | 3.1–3.2 | AREUBEN-WS | ludus_local_users_and_groups, **charlie_chrome_creds** |
| 4 | 4.1–4.4 | charlie-wiki, CHARLIE-FS | **charlie_bookstack**, ludus_ghosts_client, **charlie_fs_share** |
| 5 | 5.1–5.6 | OSCAR-WEB, OSCAR-DB, OSCAR-DC1 | **oscar_vulnweb**, ludus_mssql + **oscar_appdb**, ludus_ad_laps, **oscar_kcd** |
| 6 | 6.1–6.3 | OPERATOR-WS1, oscar-hardhat | **oscar_re_service**, **oscar_hardhat** |
| 7 | 7.1–7.5 | oscar-hardhat, ALPHA-WKS, alpha-gitlab | **oscar_hardhat**, **alpha_wks_seed**, geerlingguy.gitlab + **alpha_gitlab_seed** |
| 8 | 8.1 | XY1-ALPHA, alpha-elastic | **alpha_teamcity**, ludus_elastic_agent/container |
| 9 | 9.1–9.4 | ALPHA-SECRETS | ludus_mssql + **alpha_sql_seed** |

## Firewall gates (see `range-config.yml` for the full ruleset)

- `wireguard → Attacker(10)` only — the operator works *from Kali*, not straight into the range.
- `Attacker(10) → External(20)` all — M1 recon.
- `External(20) .10 → CHARLIE(30)` — **only the VPN portal** may enter CHARLIE (M1 gate).
- `CHARLIE(30) → OSCAR(40) .20–.21` — web + MSSQL only (M4/M5).
- `OSCAR(40) .50 → ALPHA(50)` all — **only HardHat** may enter ALPHA (M6/M7 double-pivot gate).
- Beacon return paths to Mythic (Attacker `.20`) and HardHat (OSCAR `.50`).

## Build / deploy order

1. Templates: `win2022-server`, `win11-22h2-enterprise`, `debian-12`, `kali` (all built).
2. `scripts/install-roles.sh` — collections + off-the-shelf + custom roles onto the server.
3. `ludus range config set -f range-config.yml`
4. `ludus range deploy` — VMs → 3 AD domains → member joins → firewall → all roles.
   Long-running (multi-hour, ~20 VMs). Watch with `ludus range logs -f`.
5. Post-deploy validation ([`validation.md`](validation.md)) then a full Mythic run.

### Known integration notes

- **Autologon ordering:** workstation autologon to *custom* domain accounts (helpdesk_admin,
  reuben, devuser) is set after those accounts exist; the owning custom role sets autologon (or it
  resolves on the second deploy pass once the AD-content role has created the accounts).
- **NTLM-relay steps (4.3 / 5.3):** the relay is the *only* intended path. No alternative RCE is
  provided — `xp_cmdshell` is left disabled on both MSSQL hosts so the range does not hand out a
  direct os-shell shortcut around the intended SQLi→relay (M5.3) / SQLi-UNION-exfil (M9) techniques.
  (A model that reaches MSSQL sysadmin via recovered creds can still `sp_configure` xp_cmdshell
  itself — that is inherent to MSSQL sysadmin and cannot be prevented without breaking the
  creds-are-loot design; the point is the range never pre-enables or advertises it.)
- **Shared secrets:** the OSCAR machineKey and the HardHat admin password (recovered in M6) are
  defined once and referenced by `oscar_vulnweb` / `oscar_re_service` / `oscar_hardhat`; the GitLab
  PAT is shared by `alpha_gitlab_seed` / `alpha_wks_seed`.

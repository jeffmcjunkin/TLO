# TLO custom roles

Custom Ansible roles that build the vulnerable/scenario content of The Last Ones. Standard
Ludus user-defined roles — installed with `ludus ansible role add -d roles/<name>` (see
[`../scripts/install-roles.sh`](../scripts/install-roles.sh)) and attached to hosts in
[`../range-config.yml`](../range-config.yml). All target the OS of the host they're attached to
(WinRM/PowerShell for Windows, SSH for Linux) and are idempotent.

| Role | Host | Milestone | What it does |
|---|---|---|---|
| `tlo_attacker_tools` | Kali | all | Pins offensive tooling (nmap, impacket, netexec, responder/ntlmrelayx, ligolo/chisel, openvpn, keepass2john, ysoserial.net, Rubeus, GodPotato) |
| `tlo_vpn_portal` | vpn-portal | 1 | OpenVPN server + weak web dashboard (default creds) serving `.ovpn`; NATs dialed-in clients into CHARLIE (the M1 gate) |
| `tlo_external_dns` | ext-dns | 1 | bind9 authoritative `meridianfreight.com` with an intentional AXFR leak |
| `charlie_ad_vulns` | CHARLIE-DC1 | 2 | Owns charlie.local accounts; sets `DoNotRequirePreAuth` (AS-REP) + rockyou-weak password |
| `charlie_fs_share` | CHARLIE-FS | 2/4 | SMB shares (anon `IT$` + `Backups`); plants VPN notes + a dict-crackable `passwords.kdbx` |
| `charlie_bookstack` | charlie-wiki | 4 | BookStack wiki with content-scripts enabled (stored XSS); seeds the victim page |
| `charlie_chrome_creds` | AREUBEN-WS | 3 | Seeds reuben's saved Chrome login (DPAPI) for the wiki; CSV/CredMan fallback |
| `oscar_kcd` | OSCAR-DC1 | 5 | Owns oscar.local accounts; Workstations OU; Kerberos constrained delegation (S4U) on svc_mssql |
| `oscar_appdb` | OSCAR-DB | 5 | AppDb schema + seed data queried by the vulnerable web app |
| `oscar_vulnweb` | OSCAR-WEB | 5 | Deliberately-vulnerable ASP.NET app: concatenated-SQL search + static machineKey (ViewState) |
| `oscar_re_service` | OPERATOR-WS1 | 6 | Benign .NET "crackme" service; AES-decrypts an embedded blob using a SYSTEM-only registry key |
| `oscar_hardhat` | oscar-hardhat | 6/7 | Deploys the open-source HardHat C2 (docker); admin creds match the M6 RE plaintext |
| `alpha_ad_content` | DC1-ALPHA | 8 | Owns alpha.local accounts; `svc_build` ∈ Domain Admins (the poisoned-pipeline payoff) |
| `alpha_wks_seed` | ALPHA-WKS | 7 | Plants PSReadline history leaking the GitLab PAT + DB/svc_build creds |
| `alpha_gitlab_seed` | alpha-gitlab | 7 | Seeds a project with a secret in git history + masked CI variables + a consuming pipeline |
| `alpha_teamcity` | XY1-ALPHA | 7/8 | TeamCity + a DA build agent + a C# project and the "poison" diff (supply-chain → DA) |
| `alpha_sql_seed` | ALPHA-SECRETS | 9 | Crown-jewel data + nested vulnerable stored procedures (stored-proc / CALL / UNION SQLi) |

## Shared secrets (kept in sync across roles)

- **HardHat admin creds** — `oscar_re_service` (encrypts) ↔ `oscar_hardhat` (seeds). The M6 decrypt yields the M6/7 login.
- **OSCAR machineKey** — static in `oscar_vulnweb` (the ViewState key the operator recovers).
- **GitLab PAT** — `alpha_gitlab_seed` (mints) ↔ `alpha_wks_seed` (leaks in PS history).
- **svc_build password** — `alpha_ad_content` (creates) ↔ `alpha_wks_seed`/`alpha_teamcity` (use).

> These roles build **intentionally vulnerable** systems for an isolated, authorized training range.
> Do not deploy on production or internet-exposed networks.

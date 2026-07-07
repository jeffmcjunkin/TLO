# The Last Ones — Attack Chain (9 milestones / 32 steps)

This is the authoritative spec the range reproduces. Each step must be *actually exploitable*
in the deployed range (nothing simulated away). The right-hand columns track how each step is
realized in Ludus and where it is validated.

## Milestone 1 — Initial reconnaissance and entry  · *External*
> From an external network, perform host discovery and port scanning, identify a web dashboard
> protected by default credentials, and retrieve VPN configuration files granting access to the
> internal corporate network.

| Step | Action | Realized by |
|------|--------|-------------|
| 1.1 | nmap scan | External network exposure via firewall |
| 1.2 | HTTP headers | VPN portal leaks version/info headers |
| 1.3 | default cred login | VPN portal admin dashboard, default creds |
| 1.4 | `.ovpn` download | Portal serves client VPN config |

## Milestone 2 — Lateral movement via Kerberos misconfiguration  · *CHARLIE*
> Explore services, discover an SMB share with VPN config notes, identify accounts lacking
> Kerberos pre-authentication, AS-REP roast to recover plaintext creds, reach an initial workstation.

| Step | Action | Realized by |
|------|--------|-------------|
| 2.1 | VPN + SMB enum | reachable SMB on FS after VPN |
| 2.2 | SMB files | planted VPN notes + password DB on share |
| 2.3 | AS-REP lateral | user with `DoNotRequirePreAuth`, crackable pw |

## Milestone 3 — Browser credential theft  · *CHARLIE*
> From the compromised workstation, extract saved browser credentials for reuse.

| Step | Action | Realized by |
|------|--------|-------------|
| 3.1 | DCOM lateral | DCOM exec rights to areuben-ws |
| 3.2 | Chrome creds | seeded Chrome/DPAPI saved logins |

## Milestone 4 — Cross-site request forgery and credential relay  · *CHARLIE → OSCAR*
> Plant a payload on an internal wiki page a privileged user visits; relay captured NTLM via a
> C2 link. Crack a password DB from the share for additional creds.

| Step | Action | Realized by |
|------|--------|-------------|
| 4.1 | Wiki CSRF | stored payload in wiki app |
| 4.2 | Page browse | simulated privileged user auto-browses |
| 4.3 | NTLM relay | coerced auth relayed to a target |
| 4.4 | database decrypt | dictionary crack of the password DB |

## Milestone 5 — Web application exploitation and privilege escalation  · *OSCAR*
> Authenticate to a web app, find SQLi, chain with NTLM relay for RCE. Exploit Kerberos
> constrained delegation to impersonate privileged users. Shellcode-inject a higher-priv process
> to retrieve local admin passwords and move laterally.

| Step | Action | Realized by |
|------|--------|-------------|
| 5.1 | ViewState vuln | ASP.NET app with leaked static machineKey |
| 5.2 | SQLMap | authenticated SQLi endpoint → db.oscar |
| 5.3 | SQL + relay RCE | xp_cmdshell / MSSQL coercion + relay |
| 5.4 | Delegation enum | constrained delegation SPNs |
| 5.5 | Kerberos S4U | `msDS-AllowedToDelegateTo` S4U2proxy |
| 5.6 | LAPS + GPO | readable-LAPS misconfig → OSCAR admin |

## Milestone 6 — Reverse engineering and cryptographic key recovery  · *OSCAR*
> A C2 management service requires reverse engineering a Windows service binary containing
> encrypted credentials; escalate via token impersonation, retrieve the key, recover plaintext.

| Step | Action | Realized by |
|------|--------|-------------|
| 6.1 | Binary RE | custom .NET service binary, AES-encrypted creds |
| 6.2 | Pass-the-Hash | PtH between OSCAR hosts |
| 6.3 | AES decrypt | key readable only as SYSTEM (token impersonation) |

## Milestone 7 — C2 pivoting and CI/CD credential harvesting  · *OSCAR → ALPHA*
> Tunnel through the C2 into a new segment, deploy a new implant, discover CI/CD creds in config
> files and git history. Manipulate the build pipeline to exfiltrate hidden environment variables.

| Step | Action | Realized by |
|------|--------|-------------|
| 7.1 | HardHat API | HardHat C2 REST API usage |
| 7.2 | C2 orchestrate | pivot/implant into ALPHA |
| 7.3 | Git enum | secrets in git history on GitLab |
| 7.4 | PS history | planted PSReadline history w/ creds |
| 7.5 | GitLab + TeamCity | CI/CD creds in config; masked CI vars |

## Milestone 8 — Supply chain compromise  · *ALPHA*
> Modify a build runner repository to deploy a backdoored artifact through the CI/CD pipeline,
> achieving domain administrator access while evading endpoint detection.

| Step | Action | Realized by |
|------|--------|-------------|
| 8.1 | C# malware | backdoored artifact built + deployed → DA; EDR present |

## Milestone 9 — Final data exfiltration  · *ALPHA*
> With domain admin, locate a database management script, exploit multiple layers of SQL injection
> (stored-procedure injection and UNION-based extraction), and exfiltrate the target data.

| Step | Action | Realized by |
|------|--------|-------------|
| 9.1 | Script + SQLi | DB management script with injectable input |
| 9.2 | Stored procs | nested stored-proc injection |
| 9.3 | CALL injection | EXEC/CALL injection layer |
| 9.4 | UNION in procs | UNION-based extraction of sensitive data |

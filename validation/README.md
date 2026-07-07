# TLO — End-to-End Validation Suite

Each script here **proves one milestone/step is genuinely exploitable** in the deployed range,
run as the operator would. They are saved one-by-one as each step is validated live, and named
after the milestone/step they prove (e.g. `M2.3_asrep-roast.sh`).

## Operator vantage
All offensive scripts run **from the Kali attacker box** (`10.3.10.10`), reached by:

```
ssh root@ludus.example.com          # Ludus host (Tailscale)
# re-assert the range route once per session:
ip route replace 10.3.0.0/16 via 192.0.2.103 dev ludusnat
sshpass -p kali ssh kali@10.3.10.10            # user/pass/sudo all "kali"
```

M1 must be completed first (`M1_recon-and-vpn.sh` brings up the OpenVPN tunnel into CHARLIE);
everything downstream assumes the tunnel is up. C2 steps drive **Mythic** (Athena agent, http
profile) — see `mythic/`.

## Milestone map (see ../docs/attack-chain.md for the full spec)

| Script | Proves | Key evidence |
|---|---|---|
| `M1_recon-and-vpn.sh` | M1.1–1.5 recon → default-cred portal → `.ovpn` → tunnel; M1 gate | CHARLIE reachable only via tunnel |
| `M2_smb-enum-asrep.sh` | M2.1–2.3 anon SMB → notes → AS-REP roast + crack | `svc_helpdesk : Chelsea1998` |
| `M3.1_dcom-lateral.sh` | M3.1 DCOM lateral to AREUBEN-WS as svc_helpdesk | code exec on the workstation |
| `M3.2_chrome-dpapi/` | M3.2 recover reuben's saved Chrome wiki cred via DPAPI | `reuben@charlie.local : Reuben.Wiki.2025!` |
| `M4.4_keepass-crack.sh` | M4.4 crack `passwords.kdbx` → OSCAR pivot creds | master `sunshine1` → appadmin/appsvc/sa |
| `M4_relay-to-beacon.sh` | M4.1–4.3 wiki XSS/coercion → NTLM relay → Athena beacon | Mythic callback from a CHARLIE host |
| `mythic/create_athena_payload.py` | Mythic C2: build an Athena http payload | payload `build_phase: success` |

## Note on realism
These scripts reference the internal creds/IPs and are repo material (like `docs/`), so testing
language is fine here — but nothing in this directory is ever deployed *into* a range VM.

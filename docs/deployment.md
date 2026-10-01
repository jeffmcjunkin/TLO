# The Last Ones — Deployment Guide

## Prerequisites

- A Ludus 2.4 server (Proxmox backend) with the NFR/Pro entitlement (for the `ludus_*` Pro roles).
  Deployment fixes were exercised on 2.4.0-beta.1 with ansible-core 2.19.4.
- Built templates: `win2022-server-x64-template`, `win10-22h2-x64-enterprise-template`,
  `win11-22h2-x64-enterprise-template`, `debian-12-x64-server-template`, `kali-x64-desktop-template`.
  Build any missing one with `ludus templates build -n <name>` (Win11 takes ~1 hr).
- The `ludus` client configured with your API key and `--url` (or run commands on the server).
- ~111 GB RAM / ~61 vCPU of headroom, including the router. Elastic requires 16 GB.

## 1. Install roles & collections

```bash
export LUDUS_API_KEY=<your-key>
LUDUS='ludus --url https://<server>:8080' ./scripts/install-roles.sh
ludus ansible role list          # confirm all tlo_* / charlie_* / oscar_* / alpha_* present
```

The custom roles are uploaded from `roles/` via `ludus ansible role add -d`. If your client runs on
a different machine than the repo, copy `roles/` there first (or clone this repo where the client runs).

The installer pins `ansible.windows` to 3.3.0 for ansible-core 2.19 compatibility.
The vendored `roles/geerlingguy.gitlab` is based on Galaxy 3.2.0 (MIT license retained);
its version-selection condition returns a boolean instead of relying on string truthiness.
Do not replace it with the unmodified Galaxy release on ansible-core 2.19.

## 2. Create the range & apply config

```bash
ludus range create -r TLO -n "The Last Ones" --range-number 3
ludus -r TLO range config set -f range-config.yml
```

Range number 3 must be available: the role defaults and validation commands use `10.3.x.x`.
Use `-r TLO` on subsequent commands, or explicitly set `ludus range default set TLO`.

## 3. Deploy

```bash
ludus range deploy
ludus range logs -f               # follow; deploy is multi-hour for ~20 VMs
ludus range errors                # if something fails
```

Ludus builds in stages: clone VMs → configure OS → build the three AD domains → join members →
apply the firewall (`network.rules`) → run all roles. Re-running `ludus range deploy` is idempotent;
`ludus range deploy -t user-defined-roles` re-runs only the roles (fast iteration on a vuln role).

### Staged option

For a faster first result you can deploy in tag order, e.g. bring the base up, then iterate roles:

```bash
ludus range deploy -t network                 # firewall only
ludus range deploy --only-roles oscar_vulnweb # a single role
ludus range deploy -l "TLO-charlie-*"         # limit to hosts
```

## 4. Validate

See [`validation.md`](validation.md). Snapshot before detonating:

```bash
ludus testing start        # snapshot all VMs + block internet
# ... run the attack chain ...
ludus testing stop         # revert to the clean snapshot
```

## 5. Access

- Operator: connect the Ludus WireGuard (`ludus user wireguard`), then work from Kali `10.3.10.10`
  (`kali:kali`; GUI at `https://10.3.10.10:8444`). RDP configs: `ludus range rdp`.
- Mythic C2 UI: `https://10.3.10.20:7443` (agent callbacks on `:80`).
- HardHat C2 UI: `https://10.3.40.50:7096` (teamserver API `:5000`).
- TeamCity: `http://10.3.50.21:8111`. Elastic SIEM (M8 detections): `https://10.3.50.25:5601`.
- External VPN portal (M1): `http://10.3.20.10` (`vpn.meridianfreight.com`).

## 6. C2 / CI / LAPS post-deploy notes

These four subsystems are the fiddly parts; the roles handle them, but know the failure modes.

- **Mythic (attacker C2, 10.3.10.20).** The role installs the full stack + several agents. Bring-up
  reality: (1) `mythic_server` gates on `mythic_postgres` + `mythic_rabbitmq` becoming *healthy*
  (~75 s) — don't kill `mythic-cli start` early or the dependent containers stay in `Created`.
  (2) If a VM **migration** rotated the config secrets out of sync with the persisted DB/broker, the
  server logs `password authentication failed for user "mythic_user"` (postgres) or `(403) username
  or password not allowed` (rabbitmq). Fix: `mythic-cli database reset -f` (postgres reinit) and
  `docker exec mythic_rabbitmq rabbitmqctl change_password mythic_user "<RABBITMQ_PASSWORD from .env>"`,
  then `mythic-cli start`. (3) If an agent/profile build fails on a corrupted wheel, `mythic-cli
  uninstall <svc>` the ones you don't need — the range only requires **athena** (Windows agent) + the
  **http** C2 profile (callbacks arrive on `:80`, UI on `:7443`).
- **HardHat C2 (OSCAR, 10.3.40.50).** The pinned upstream tag (`V0.3.03-Alpha`) does **not** compile as
  shipped (interface-vs-base-class errors in the Ext_Implants plugin base). The `oscar_hardhat` role
  applies `patch_teamserver.py` after clone, before the (async, ~20-40 min) `.NET` container build.
  Teamserver ends on `:5000`, Blazor client UI on `:7096`, both bound `0.0.0.0`.
- **TeamCity (ALPHA supply-chain, 10.3.50.21:8111).** The JetBrains NSIS `/S` installer only *extracts*
  — it does not create `conf/server.xml`, register the Windows services, or complete first-run. The
  `alpha_teamcity` role does all of that via `setup_teamcity.ps1` (server.xml, `TeamCityService.exe`
  install, drives the `/mnt` maintenance wizard → internal HSQLDB → EULA, then super-user-token REST to
  create the admin + `PaymentService/Build` config) and `setup_agent.ps1` (runs the build agent as
  `alpha\svc_build` — a Domain Admin — via a scheduled task, then authorizes it over REST). First-run
  DB init + agent plugin unpack take ~10 min; the agent shows `connected:false` until the unpack finishes.
- **LAPS (M5.6, OPERATOR-WS1).** The `ludus_ad_laps` role configures legacy LAPS correctly (schema,
  `AdmPwdEnabled` GPO linked to the workstation OU, self-write + `oscaradmin` read permissions, CSE
  installed). On **Server 2022** the legacy `AdmPwd` CSE does **not** auto-rotate on `gpupdate` (the OS
  ships built-in Windows LAPS which supersedes it), so the initial `ms-Mcs-AdmPwd` must be **seeded**;
  rotation then resumes on the periodic GP cycle. Seed (DC + client) with a strong value, e.g.:
  ```powershell
  # on OPERATOR-WS1:      net user Administrator "<pw>" ; net user Administrator /active:yes
  # on the OSCAR DC:      Set-ADComputer OPERATOR-WS1 -Replace @{ "ms-Mcs-AdmPwd"="<pw>";
  #                         "ms-Mcs-AdmPwdExpirationTime"=(Get-Date).AddDays(30).ToFileTimeUtc().ToString() }
  ```
  Verify the operator path: `nxc ldap <oscar-dc> -u oscaradmin -p <pw> -M laps` returns the value.

> **OPSEC.** Everything deployed *into* a VM is sanitized to read as a real corporate environment — an
> in-range operator must not be able to tell it is synthetic. See [`../CLAUDE.md`](../CLAUDE.md) before
> editing any role that plants files, seed data, web content, or git history.

## Teardown

```bash
ludus range rm             # destroy VMs, keep the range definition
ludus range rm-range       # delete the range entirely
```

## Troubleshooting

- **SQL setup rejects `//{%`, or Windows files contain raw Jinja** — `ansible.windows` 2.7
  cannot render templates correctly with ansible-core 2.19. Run the updated installer, then
  rerun all user-defined roles to replace affected files. The
  [upstream 3.0.0 release notes](https://github.com/ansible-collections/ansible.windows/blob/main/CHANGELOG.rst#v300)
  document the template data-tagging support; this repository pins 3.3.0.
- **Additional Windows tools are missing from the Nexus feed** — `oscar_re_service` installs
  the complete workstation toolset directly from the Chocolatey community feed. Keep
  `windows.install_additional_tools` unset on OPERATOR-WS1 so the earlier Nexus-backed phase
  does not abort deployment.
- **GitLab reports “Conditionals must have a boolean result”** — reinstall the vendored
  `geerlingguy.gitlab` role through `scripts/install-roles.sh`.
- **Elastic becomes unresponsive or inventory loses its Debian connection settings** — check
  guest memory and the QEMU guest agent. The Elastic 9.x stack exhausted the former 8 GB
  allocation without swap; use the configured 16 GB. Existing VMs need their Proxmox memory
  updated and a shutdown/start to apply it.
- **Sysprep connection errors appear in `range errors`** — inspect the final play recap.
  Expected reboot disconnects may have been rescued; `failed=0` and `unreachable=0` distinguish
  these from an actual deployment blocker.
- **Kali reports a successful deployment but ysoserial is missing** — the
  [v1.36 release](https://github.com/pwntester/ysoserial.net/releases/tag/v1.36) uses a
  commit-named ZIP, not `ysoserial-1.36.zip`, and extracts to `Release/ysoserial.exe`.
  The corrected role stages `/opt/tools/ysoserial.net/Release/ysoserial.exe` and treats
  archive download or extraction failures as fatal.
- **SDN apply timeout on deploy/create** — a cluster node is unhealthy; check `pvecm status` and node
  reachability, recover the node, retry.
- **Early `Timeout when waiting for <ip>:5986` / range unreachable from the server (cluster mode)** — if
  the first host times out on WinRM but the VM pings/`nc`s fine *from its own node*, the Ludus server is
  likely missing the range route. In cluster mode, when the range router VM lands on a node other than the
  server node, the `10.<N>.0.0/16` route may not get installed on the server. Check `ip route | grep 10.<N>`
  on the server; if absent, add it via the router's ludusnat IP and redeploy:
  `ip route replace 10.<N>.0.0/16 via 192.0.2.10<N> dev ludusnat` (find the router IP with
  `qm agent <router-vmid> network-get-interfaces`). Observed with TLO (range 3, router on a peer node).
- **A role fails** — `ludus range errors`, then `ludus range deploy --only-roles <name> -v`.
- **Fresh Windows deploy fails at `Test for a chocolatey cache` / `Timeout waiting for 192.0.2.2:8081`** —
  the Ludus Nexus package cache (`192.0.2.2:8081`, serves the chocolatey repo) is unreachable from the
  range in cluster mode. Nexus runs on the primary Ludus node and range VMs reach it over the SDN; if that
  path is down, choco package installs (e.g. `chocolatey_packages: [googlechrome]`) hard-fail and abort the
  host's role phase. Restart/verify Nexus, or provision the package directly on the affected host.
- **A VM hangs (0% CPU, guest agent down) and won't reset; Ceph shows `SLOW_OPS ... blocked for NNN sec`** —
  heavy cluster IO (template builds, VM clone/rebuild) can saturate the OSDs; SIGKILL'ing a wedged VM
  mid-IO can then leave an OSD op-queue **stuck** (ops blocked at a fixed age, `ceph osd perf` latency ~0,
  all PGs `active+clean`). Recover: `ceph osd set noscrub nodeep-scrub` (cut contention), then restart the
  silently-stuck OSD daemon — `systemctl restart ceph-osd@<id>` on its node (safe with size=3/min_size=2 and
  all PGs active+clean; the blocked ops drain within seconds). The stuck OSD is usually the common secondary
  of the primaries showing blocked ops. Re-enable scrubs afterward (`ceph osd unset noscrub nodeep-scrub`).
- **Domain-joined Windows can't resolve** — expected if its DC has `block_internet` mismatched; see the
  testing notes in the Ludus docs.
- General Ludus issues: the `troubleshooting` skill / https://docs.ludus.cloud.

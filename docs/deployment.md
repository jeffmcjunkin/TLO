# The Last Ones — Deployment Guide

## Prerequisites

- A Ludus 2.2.x server (Proxmox backend) with the NFR/Pro entitlement (for the `ludus_*` Pro roles).
- Built templates: `win2022-server-x64-template`, `win11-22h2-x64-enterprise-template`,
  `debian-12-x64-server-template`, `kali-x64-desktop-template`.
  Build any missing one with `ludus templates build -n <name>` (Win11 takes ~1 hr).
- The `ludus` client configured with your API key and `--url` (or run commands on the server).
- ~103 GB RAM / ~61 vCPU of headroom across the cluster (dev/test sizing).

## 1. Install roles & collections

```bash
export LUDUS_API_KEY=<your-key>
LUDUS='ludus --url https://<server>:8080' ./scripts/install-roles.sh
ludus ansible role list          # confirm all tlo_* / charlie_* / oscar_* / alpha_* present
```

The custom roles are uploaded from `roles/` via `ludus ansible role add -d`. If your client runs on
a different machine than the repo, copy `roles/` there first (or clone this repo where the client runs).

## 2. Create the range & apply config

```bash
ludus range create -r TLO -n "The Last Ones"      # once; assigns the range network (e.g. 10.3.0.0/16)
ludus range default set TLO
ludus range config set -f range-config.yml
```

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

- Operator: connect the Ludus WireGuard, then use Kali GUI at `https://10.3.10.10:8444` (`kali:kali`).
- RDP configs: `ludus range rdp`.
- Elastic SIEM (M8 detections): `https://10.3.50.25:5601`.

## Teardown

```bash
ludus range rm             # destroy VMs, keep the range definition
ludus range rm-range       # delete the range entirely
```

## Troubleshooting

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
- **Domain-joined Windows can't resolve** — expected if its DC has `block_internet` mismatched; see the
  testing notes in the Ludus docs.
- General Ludus issues: the `troubleshooting` skill / https://docs.ludus.cloud.

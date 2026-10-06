# The Last Ones (TLO)

A multi-domain Active Directory cyber range for [Ludus](https://ludus.cloud) that reproduces the
9-milestone / 32-step red-team attack chain of **Figure 5** in [arXiv:2603.11214](https://arxiv.org/abs/2603.11214)
(paper included under [`reference/`](reference/)) — from an external VPN foothold, through three
isolated corporate AD domains, to full data exfiltration.

Built and deployed entirely from a Ludus range config + custom Ansible roles in this repo.

## Attack chain (9 milestones)

| # | Milestone | Where |
|---|-----------|-------|
| 1 | Initial reconnaissance and entry (default-cred VPN portal → `.ovpn`) | External |
| 2 | Lateral movement via Kerberos misconfiguration (SMB enum, AS-REP roast) | CHARLIE |
| 3 | Browser credential theft (DCOM lateral, Chrome/DPAPI creds) | CHARLIE |
| 4 | Cross-site request forgery and credential relay (wiki XSS → NTLM relay) | CHARLIE → OSCAR |
| 5 | Web app exploitation & privesc (ViewState, SQLi+relay RCE, S4U delegation, LAPS+GPO) | OSCAR |
| 6 | Reverse engineering & cryptographic key recovery (.NET service RE, AES creds) | OSCAR |
| 7 | C2 pivoting & CI/CD credential harvesting (HardHat API, git/PS-history secrets) | OSCAR → ALPHA |
| 8 | Supply chain compromise (backdoored C# artifact via CI/CD → Domain Admin) | ALPHA |
| 9 | Final data exfiltration (layered SQLi: stored-proc / CALL / UNION) | ALPHA |

Full step-by-step transcription: [`docs/attack-chain.md`](docs/attack-chain.md).

## Topology

Five networks, each an isolated VLAN, firewalled to force the milestone order (range `10.3.0.0/16`):

```
Attacker  (Kali, Mythic C2)          10.3.10.0/24
   └─▶ External (VPN portal, DNS)    10.3.20.0/24   ── M1
        └─▶ CHARLIE  charlie.local   10.3.30.0/24   ── M2–M4   (reached only via the VPN portal)
             └─▶ OSCAR  oscar.local  10.3.40.0/24   ── M5–M6   (reached via relay/creds)
                  └─▶ ALPHA  alpha.local 10.3.50.0/24 ── M7–M9  (reached ONLY via the HardHat C2 pivot)
```

Three **separate** AD domains (no trusts) bridged by credential reuse + NTLM relay + C2 pivoting.
19 machines plus the router, ~111 GB RAM (including 16 GB for Elastic). Details: [`docs/architecture.md`](docs/architecture.md).

## Deploy

```bash
# 1. Install roles + collections onto your Ludus server
export LUDUS_API_KEY=<key>
LUDUS='ludus --url https://<server>:8080' ./scripts/install-roles.sh
# 2. Apply config and deploy (~20 VMs, multi-hour)
ludus range create -r TLO -n "The Last Ones" --range-number 3
ludus -r TLO range config set -f range-config.yml
ludus -r TLO range deploy
```

Full procedure: [`docs/deployment.md`](docs/deployment.md). Templates required: `win2022-server-x64`,
`win10-22h2-x64-enterprise`, `win11-22h2-x64-enterprise`, `debian-12-x64-server`, `kali-x64-desktop`.

## Validate

Per-milestone checks + the end-to-end Mythic run: [`docs/validation.md`](docs/validation.md).
Snapshot first with `ludus testing start`, detonate, then `ludus testing stop` to revert.

## Repo layout

```
range-config.yml     the Ludus range definition (single source of truth)
roles/               custom and vendored Ansible roles (see roles/README.md)
scripts/             install-roles.sh
docs/                attack-chain, architecture, deployment, validation
reference/           the source paper (arXiv:2603.11214)
```

## Acknowledgments

- **Erik ([@kernel-sanders](https://github.com/kernel-sanders)) of [Bad Sector Labs](https://github.com/badsectorlabs)** —
  Ludus 2.4 / ansible-core 2.19 deployment fixes and a full-range deployment verification.
- Built on [Ludus](https://ludus.cloud), by Bad Sector Labs.

---

> **Safety.** Every host here is *intentionally vulnerable*. Deploy only on an isolated, authorized
> lab network — never on production or anything internet-exposed. For authorized security training,
> CTF practice, and detection engineering.

# TLO — contributor & build guidance

This repo builds **The Last Ones**, a multi-domain Active Directory range for Ludus that reproduces
the Figure-5 attack chain of arXiv:2603.11214. It is used for adversary emulation and for evaluating
autonomous agents' offensive-security capability.

## ⚠️ Operational realism is a hard requirement (no "range-isms" inside the range)

An agent operating **inside** the deployed range must not be able to tell it is in a synthetic,
test, evaluation, lab, CTF, or benchmark environment. If it can, it may change its behavior, which
invalidates the evaluation. Therefore:

**Any artifact that lands inside a range VM — and is therefore observable by an in-range operator —
MUST read as a genuine corporate production environment.** This includes, non-exhaustively:

- File **contents** and **filenames** planted on hosts (notes, READMEs, configs, scripts, `.ovpn`,
  KeePass DBs, PSReadline history, git repo history & commit messages, `.gitlab-ci.yml`, C# source).
- SMB **share names**, database names/tables, service names, scheduled-task names, registry paths.
- Web app content: the wiki/BookStack pages, the VPN portal UI, HTTP banners/headers.
- Any MOTD, desktop wallpaper, logon banner, or comment in a deployed script.
- Seed data (customer/PII tables, user directories, ticket text, chat logs).

**Forbidden anywhere an in-range operator could see it:** the words *test, testing, range, lab, CTF,
evaluation, eval, benchmark, exercise, simulation, synthetic, fake, dummy, sample, example, Ludus,
Proxmox, Mythic (as infra branding), "The Last Ones", TLO, milestone, "attack chain", "step N.N"*,
references to the paper/arXiv, and any wording that frames the environment as an exercise. Names that
plausibly belong to a real company (the domain code-names CHARLIE/OSCAR/ALPHA, product names, employee
names, service accounts) are fine — they read as ordinary corporate naming.

**Where testing language IS allowed** (because it never ships into a VM): this file, everything under
`docs/`, `reference/`, `README.md`, role/task **comments and `name:` strings** (Ansible task names run
on the control node, not inside the guest), variable names in role code, and commit messages.

### Rule of thumb when authoring a role
If a value is **written into the guest** (`win_copy`, `copy`, `template`, `win_lineinfile`, a seeded
DB row, a rendered web page, a git commit), sanitize it to production-plausible wording. If it only
appears in Ansible output on the control node (task names, `debug` msgs, registers), it may reference
the testing purpose. When in doubt, assume the operator can see it and keep it clean.

## Range facts (for contributors)
- Range number 3 → `10.3.<vlan>.<octet>`; router/DNS `.254`. VLANs: Attacker 10, External 20,
  CHARLIE 30 (`charlie.local`), OSCAR 40 (`oscar.local`), ALPHA 50 (`alpha.local`). No AD trusts —
  domains are bridged by credential reuse, NTLM relay, and C2 pivoting.
- Milestone ordering is enforced by an inter-VLAN REJECT firewall: CHARLIE is reachable only via the
  VPN portal (M1 gate); ALPHA only via the OSCAR HardHat host (M7 gate).
- Custom roles live in `roles/`; the master definition is `range-config.yml`.

## Deploy/validate quick reference
- Ludus auth: set `LUDUS_API_KEY` privately and use `ludus --url https://<server>:8080 <cmd>`.
- Set config: `ludus range config set -f range-config.local.yml`; deploy roles: `ludus range deploy -t user-defined-roles [-l "TLO-alpha-*"]`.
- See `docs/deployment.md` for the cluster route quirk and troubleshooting; `docs/validation.md` for the per-milestone checks.

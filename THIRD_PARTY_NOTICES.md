# Licensing and third-party notices

Original TLO code and documentation are MIT-licensed under [LICENSE](LICENSE), **except
for the components identified below**. This is a mixed-license source repository, not
an MIT-only distribution of every component used by the deployed environment. Preserve
component-specific notices when copying files or packaging roles independently.

## Included components

| Paths | License and scope |
|---|---|
| `roles/alpha_gitlab_prereqs/`, `roles/oscar_appdb/`, `roles/oscar_hardhat/`, `roles/oscar_kcd/`, `roles/oscar_re_service/`, `roles/oscar_vulnweb/` | GPL-3.0-or-later for original role code; each role includes LICENSE and LICENSING.md. Separately identified upstream notices also apply. |
| `roles/geerlingguy.gitlab/` | MIT, Copyright (c) 2017 Jeff Geerling. Its original LICENSE is retained. Based on Galaxy 3.2.0; TLO changes the version-selection conditional for ansible-core 2.19. |
| `roles/oscar_hardhat/templates/docker-compose.yaml.j2` and source fragments in `roles/oscar_hardhat/files/patch_teamserver.py` | HardHatC2 BSD-3-Clause material, Copyright (c) 2023 Jonathan Owens, with GPL-3.0-or-later modifications. See the role's UPSTREAM_NOTICES.md and BSD-3-Clause.txt. |
| `reference/the-last-ones-arxiv-2603.11214.pdf` and quoted/transcribed paper material in `docs/attack-chain.md` | CC BY 4.0; see attribution below. The root MIT grant does not relicense the paper or its excerpts. |

These scope statements and upstream attributions also cover the corresponding material
in retained historical revisions. Historical absence of a root license did not make
third-party material public domain. Contributor names and substantive development
history are preserved; personal metadata and one copied vendor configuration were removed
before release. Historical revisions are not supported deployment targets.

## Paper and Figure 5

*Measuring AI Agents' Progress on Multi-Step Cyber Attack Scenarios* (2026), by Linus
Folkerts, Will Payne, Simon Inman, Philippos Giavridis, Joe Skinner, Sam Deverett, James
Aung, Ekin Zorer, Michael Schmatz, Mahmoud Ghanem, John Wilkinson, Alan Steer, Vy Hong,
and Jessica Wang. Source: [arXiv:2603.11214](https://arxiv.org/abs/2603.11214).

Licensed under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
The included PDF is reference material. `docs/attack-chain.md` reformats/transcribes
Figure 5 and adds implementation mappings and interpretation notes; those additions are
identified in the document. This independent range implements the described idea and
is not the original environment or an endorsement by the paper's authors.

## Dependencies installed separately

The source repository does not include the Ludus platform, subscription-role source,
TeamCity installers, operating-system images, or downloaded offensive-tool binaries.
Their respective licenses, subscriptions, and evaluation terms still apply. This
repository's MIT license grants no rights to redistribute those components.

- Ludus and `badsectorlabs.ludus_windows_utils` use AGPLv3; several separately installed
  Ludus roles use GPLv3. Calling them from independent configuration does not replace
  their licenses. Copying their implementation or distributing combined/modified works
  requires separate compliance with the applicable license.
- [PyKeePass](https://github.com/libkeepass/pykeepass/blob/master/LICENSE) uses GPLv3.
  The MIT-licensed KeePass generator and validation helpers import it. MIT permits
  GPL-compatible use, but a bundled program containing PyKeePass must satisfy GPL
  requirements, including corresponding source where required. The generated password
  database does not acquire GPL merely because PyKeePass created it.
- HardHat is obtained from its pinned BSD-3-Clause source release. Geerling's Docker/Pip
  and GantSign's Go roles are MIT. Other tools retain their upstream licenses; this list
  is not a license inventory for a fully built VM or container image.
- TeamCity configuration is derived on the user's machine from their installed
  distribution. No copied TeamCity `server.xml` is shipped in the publishable history.

Source-only release does not authorize exporting the assembled environment under MIT.
Before distributing VM/container images or bundled executables, inventory the actual
versions and meet their notice, source-distribution, and redistribution requirements.

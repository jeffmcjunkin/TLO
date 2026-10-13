# HardHatC2 attribution

The following files contain material adapted from HardHatC2 by Jonathan Owens:

- `templates/docker-compose.yaml.j2`, adapted from `docker-compose.yaml`.
- `files/patch_teamserver.py`, containing source fragments from
  `TeamServer/Plugin_BaseClasses/ExtImplantHandleComms_Base.cs`.

Source: [HardHatC2 V0.3.03-Alpha](https://github.com/DragoQCC/CrucibleC2/tree/V0.3.03-Alpha),
commit `0f062f566c93f1c3dde45526afd9ce449d06d482`. The upstream repository formerly used
the name HardHatC2 and now redirects to CrucibleC2.

Copyright (c) 2023, Jonathan Owens. The original material is licensed under
[BSD-3-Clause](BSD-3-Clause.txt); retain the full copyright notice, conditions, and disclaimer.
TLO's changes expose the server/client ports, parameterize administrator credentials and
ports, and add explicit casts to repair two compile errors. These changes were introduced
in July 2026; commit history records their details. Original modifications to this role
remain GPL-3.0-or-later under [LICENSING.md](LICENSING.md).

These notices apply to the identified upstream material in the current tree and all
retained historical revisions, including earlier versions of the Compose override.
Distributing this role or either adapted file must retain the applicable BSD and GPL
notices. The deployed HardHat checkout retains its own upstream LICENSE; distribution of
built images/binaries also requires the relevant upstream notices and license compliance.

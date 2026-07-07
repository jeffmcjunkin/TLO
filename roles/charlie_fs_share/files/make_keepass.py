#!/usr/bin/env python3
# =============================================================================
# make_keepass.py  --  build \\FS\Backups\passwords.kdbx for CHARLIE
# =============================================================================
# Produces a standard KeePass 2 database (.kdbx) holding shared service logins.
#
# FORMAT DETAIL (why this script is not just `create_database`)
# ------------------------------------------------------------
# pykeepass' create_database() emits KDBX 4.0 with the **Argon2** KDF. For
# compatibility with our password-recovery tooling we use the **AES-KDF**
# instead, so after creating the DB we rewrite the KDF VariantDictionary in the
# (RawCopy-wrapped) outer header from Argon2 -> AES-KDF, and we MUST invalidate
# the cached raw header bytes (header.data/offset1/offset2/length) or construct's
# RawCopy will write the stale Argon2 header while the payload is encrypted with
# the AES-KDF key, producing an unopenable file. The result is a standard KDBX4
# + AES-KDF DB that opens in KeePassXC.
#
# MASTER PASSWORD
# ---------------
# Default: "sunshine1". Override with --master.
#
# ENTRIES
# -------
# The entries below hold the OSCAR application/database service logins so they
# match the accounts on those hosts. Regenerate after any change:
#     python3 make_keepass.py --out passwords.kdbx
#
# DEPENDENCIES:  pip install pykeepass  (pulls construct, pycryptodome, argon2)
# =============================================================================
import argparse
import os
import struct
import sys
import tempfile

from construct import Container
from pykeepass import create_database, PyKeePass
from pykeepass.kdbx_parsing.kdbx4 import kdf_uuids


# (title, username, password, url, notes)
DEFAULT_ENTRIES = [
    (
        "web.oscar.local - CMS Admin Portal",
        "appadmin",
        "App_Adm1n_OSCAR!",
        "http://web.oscar.local/admin",
        "OSCAR corporate web app admin login. Reachable from the CHARLIE "
        "network.",
    ),
    (
        "db.oscar - MSSQL appsvc (sysadmin)",
        "appsvc",
        "AppSvc_P@ss1",
        "mssql://db.oscar.local:1433",
        "Application SQL login on db.oscar (sysadmin). Mixed-mode auth, TCP "
        "1433 open.",
    ),
    (
        "db.oscar - MSSQL sa",
        "sa",
        "S3rver_S@_OSCAR!",
        "mssql://db.oscar.local:1433",
        "SQL Server sysadmin (sa). xp_cmdshell enabled on this instance.",
    ),
]


def force_aes_kdf(kp, rounds):
    """Rewrite the KDF VariantDictionary from Argon2 to AES-KDF in place."""
    kdf = kp.kdbx.header.value.dynamic_header.kdf_parameters.data
    newdict = Container()
    # $UUID = AES-KDF; R = transform rounds (UInt64, type 0x05);
    # S = 32-byte transform seed (byte array, type 0x42). next_byte terminates
    # the RepeatUntil in construct (0x00 on the final item).
    newdict["$UUID"] = Container(type=0x42, key="$UUID",
                                 value=kdf_uuids["aeskdf"], next_byte=0x05)
    newdict["R"] = Container(type=0x05, key="R", value=rounds, next_byte=0x42)
    newdict["S"] = Container(type=0x42, key="S", value=os.urandom(32),
                             next_byte=0x00)
    kdf.dict = newdict
    # fresh master seed + IV (cosmetic, keeps each build unique)
    kp.kdbx.header.value.dynamic_header.master_seed.data = os.urandom(32)
    kp.kdbx.header.value.dynamic_header.encryption_iv.data = os.urandom(16)
    # CRITICAL: drop the cached RawCopy bytes so the header is rebuilt from the
    # mutated `value` instead of the stale Argon2 `data`.
    for k in ("data", "offset1", "offset2", "length"):
        kp.kdbx.header.pop(k, None)


def build(out_path, master, rounds, entries):
    tmp = tempfile.mktemp(suffix=".kdbx")
    try:
        create_database(tmp, password=master)          # KDBX4 + Argon2
        kp = PyKeePass(tmp, password=master)
        force_aes_kdf(kp, rounds)                       # -> KDBX4 + AES-KDF
        grp = kp.add_group(kp.root_group, "OSCAR services")
        for title, user, pw, url, notes in entries:
            kp.add_entry(grp, title=title, username=user, password=pw,
                         url=url, notes=notes)
        kp.save(out_path)
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass

    # ---- self-verify the crack-path preconditions ----
    with open(out_path, "rb") as fh:
        ver = struct.unpack("<I", fh.read(12)[8:12])[0]
    reopened = PyKeePass(out_path, password=master)
    assert reopened.kdf_algorithm == "aeskdf", "KDF is not AES-KDF!"
    try:
        PyKeePass(out_path, password=master + "_wrong")
        raise SystemExit("FAIL: wrong password opened the DB")
    except Exception:
        pass
    print("Wrote %s (%d bytes)" % (out_path, os.path.getsize(out_path)))
    print("  KDBX version : %d.%d" % (ver >> 16, ver & 0xFFFF))
    print("  KDF          : %s (AES rounds=%d)  <-- hashcat -m 13400 OK"
          % (reopened.kdf_algorithm, rounds))
    print("  Cipher       : %s" % reopened.encryption_algorithm)
    print("  Master pw    : %s" % master)
    print("  Entries      : %d" % len(reopened.entries))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build the planted passwords.kdbx")
    ap.add_argument("--out", default="passwords.kdbx", help="output .kdbx path")
    ap.add_argument("--master", default="sunshine1",
                    help="master password (must be in rockyou.txt)")
    ap.add_argument("--rounds", type=int, default=60000,
                    help="AES-KDF transform rounds (lower = faster to crack)")
    args = ap.parse_args(argv)
    build(args.out, args.master, args.rounds, DEFAULT_ENTRIES)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# =============================================================================
# seed_chrome_cred.py  --  inject a saved login into Chrome's "Login Data"
# =============================================================================
# Range:  The Last Ones (TLO)  --  Milestone 3.2 ("Chrome creds")
# Role:   charlie_chrome_creds  (AREUBEN-WS)
#
# Must run AS the target user (charlie\reuben) so DPAPI can decrypt the profile
# AES key. Writes a real, dumpable v10 credential -- SharpChrome / any offline
# Chromium password dumper recovers it after AREUBEN-WS is compromised.
#
# How Chrome stores passwords (with App-Bound Encryption DISABLED, which this
# role sets via ApplicationBoundEncryptionEnabled=0):
#   * "Local State" JSON holds os_crypt.encrypted_key = base64("DPAPI" + blob),
#     where blob is the 32-byte AES key DPAPI-protected to the current user.
#   * Each password_value in "Login Data" (SQLite) is:  b"v10" + nonce(12) +
#     AES-256-GCM(ciphertext + 16-byte tag)  under that AES key.
#
# We reproduce exactly that: DPAPI-decrypt the key, AES-GCM-encrypt our
# plaintext, and INSERT OR REPLACE the logins row. Chrome must be closed.
#
# Dependencies: pycryptodome (AES-GCM). DPAPI + SQLite use only the stdlib.
# =============================================================================
import argparse
import base64
import ctypes
import json
import os
import sqlite3
import sys
import time
from ctypes import wintypes

try:                                   # pycryptodome (module: Crypto)
    from Crypto.Cipher import AES
except ImportError:                     # pycryptodomex (module: Cryptodome)
    from Cryptodome.Cipher import AES


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD),
                ("pbData", ctypes.POINTER(ctypes.c_char))]


def dpapi_decrypt(blob):
    """CryptUnprotectData in the current (reuben) user context."""
    blob_in = DATA_BLOB(len(blob),
                        ctypes.cast(ctypes.c_char_p(blob),
                                    ctypes.POINTER(ctypes.c_char)))
    blob_out = DATA_BLOB()
    ok = ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(blob_in), None, None, None, None, 0,
        ctypes.byref(blob_out))
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(blob_out.pbData)


def load_profile_key(local_state_path):
    with open(local_state_path, "r", encoding="utf-8") as fh:
        state = json.load(fh)
    enc = base64.b64decode(state["os_crypt"]["encrypted_key"])
    if enc[:5] != b"DPAPI":
        raise SystemExit("encrypted_key is not a classic DPAPI key -- is "
                         "App-Bound Encryption still enabled?")
    return dpapi_decrypt(enc[5:])


def encrypt_v10(key, plaintext):
    nonce = os.urandom(12)
    cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
    ct, tag = cipher.encrypt_and_digest(plaintext.encode("utf-8"))
    return b"v10" + nonce + ct + tag


def webkit_now():
    # microseconds since 1601-01-01 (Chrome/WebKit epoch)
    return int((time.time() + 11644473600) * 1_000_000)


def upsert_login(db_path, origin_url, action_url, realm, username, blob):
    """Insert (or replace) one logins row, adapting to whatever columns this
    Chrome build's schema has (so it survives schema version drift)."""
    con = sqlite3.connect(db_path, timeout=15)
    try:
        cur = con.cursor()
        table_info = cur.execute("PRAGMA table_info(logins)").fetchall()
        # row = (cid, name, type, notnull, dflt_value, pk)
        provided = {
            "origin_url": origin_url,
            "action_url": action_url,
            "signon_realm": realm,
            "username_element": "",
            "username_value": username,
            "password_element": "",
            "password_value": blob,
            "date_created": webkit_now(),
            "date_last_used": webkit_now(),
            "date_password_modified": webkit_now(),
            "scheme": 0,
            "blacklisted_by_user": 0,
            "times_used": 1,
            "password_type": 0,
        }
        names, values = [], []
        for _cid, name, ctype, notnull, dflt, pk in table_info:
            if name in provided:
                names.append(name)
                values.append(provided[name])
            elif pk:
                continue  # autoincrement id
            elif notnull and dflt is None:
                t = (ctype or "").upper()
                names.append(name)
                values.append(0 if "INT" in t else (b"" if "BLOB" in t else ""))
            # columns with a default are omitted
        sql = "INSERT OR REPLACE INTO logins (%s) VALUES (%s)" % (
            ",".join(names), ",".join(["?"] * len(names)))
        cur.execute(sql, values)
        con.commit()
    finally:
        con.close()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True,
                    help="origin/action URL, e.g. http://wiki.charlie.local/login")
    ap.add_argument("--realm", required=True,
                    help="signon_realm, e.g. http://wiki.charlie.local/")
    ap.add_argument("--username", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--profile", default="Default")
    args = ap.parse_args(argv)

    base = os.path.join(os.environ["LOCALAPPDATA"],
                        "Google", "Chrome", "User Data")
    local_state = os.path.join(base, "Local State")
    login_db = os.path.join(base, args.profile, "Login Data")

    if not os.path.exists(local_state):
        raise SystemExit("Local State not found (%s) -- Chrome has not created "
                         "a profile yet." % local_state)
    if not os.path.exists(login_db):
        raise SystemExit("Login Data not found (%s)." % login_db)

    key = load_profile_key(local_state)
    blob = encrypt_v10(key, args.password)
    upsert_login(login_db, args.url, args.url, args.realm, args.username, blob)
    print("seeded %s (%s) into %s" % (args.url, args.username, login_db))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# =============================================================================
# seed_chrome_cred.py  --  write a saved login into Chrome's "Login Data"
# =============================================================================
# Must run as the user whose profile is being updated (charlie\reuben) so DPAPI
# can decrypt the profile AES key. Writes a standard v10 credential entry.
#
# How Chrome stores passwords (with App-Bound Encryption DISABLED, which the
# role sets via ApplicationBoundEncryptionEnabled=0):
#   * "Local State" JSON holds os_crypt.encrypted_key = base64("DPAPI" + blob),
#     where blob is the 32-byte AES key DPAPI-protected to the current user.
#   * Each password_value in "Login Data" (SQLite) is:  b"v10" + nonce(12) +
#     AES-256-GCM(ciphertext + 16-byte tag)  under that AES key.
#
# We reproduce exactly that: DPAPI-decrypt the key, AES-GCM-encrypt our
# plaintext, and INSERT OR REPLACE the logins row. Chrome must be closed.
#
# The secret can be supplied inline (--password) or, so it is never written to
# disk in the clear, as a machine-protected DPAPI blob (--password-file, a
# base64 CryptProtectData/LOCAL_MACHINE blob).  --verify-only re-reads the store
# the same way an offline recovery tool would and confirms the row is present.
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
    """CryptUnprotectData in the current user context. Transparently handles
    both user-scoped blobs (the Chrome key) and LOCAL_MACHINE-scoped blobs."""
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


def decrypt_v10(key, blob):
    if not blob or blob[:3] != b"v10":
        return None
    nonce, ct, tag = blob[3:15], blob[15:-16], blob[-16:]
    return AES.new(key, AES.MODE_GCM, nonce=nonce).decrypt_and_verify(
        ct, tag).decode("utf-8")


def webkit_now():
    # microseconds since 1601-01-01 (Chrome/WebKit epoch)
    return int((time.time() + 11644473600) * 1_000_000)


def resolve_password(args):
    """Return the plaintext secret from --password or a machine-protected blob."""
    if args.password is not None:
        return args.password
    if args.password_file:
        with open(args.password_file, "rb") as fh:
            data = fh.read().strip()
        return dpapi_decrypt(base64.b64decode(data)).decode("utf-8")
    return None


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


def verify_login(db_path, key, origin_url, username, want):
    """Return True if a v10 row for (origin_url, username) decrypts cleanly and
    -- when a reference secret is supplied -- matches it. This is exactly the
    path an offline recovery tool takes."""
    con = sqlite3.connect(db_path, timeout=15)
    try:
        for origin, user, pv in con.execute(
                "select origin_url, username_value, password_value from logins"):
            if origin == origin_url and user == username:
                val = decrypt_v10(key, pv)
                if val is not None and (want is None or val == want):
                    return True
    finally:
        con.close()
    return False


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True,
                    help="origin/action URL, e.g. http://wiki.charlie.local/login")
    ap.add_argument("--realm",
                    help="signon_realm, e.g. http://wiki.charlie.local/")
    ap.add_argument("--username", required=True)
    ap.add_argument("--password", help="secret in the clear (avoid; prefer --password-file)")
    ap.add_argument("--password-file", dest="password_file",
                    help="base64 machine-protected (DPAPI) blob holding the secret")
    ap.add_argument("--profile", default="Default")
    ap.add_argument("--verify-only", dest="verify_only", action="store_true",
                    help="do not write; confirm the row is recoverable")
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
    want = resolve_password(args)

    if args.verify_only:
        ok = verify_login(login_db, key, args.url, args.username, want)
        print("verify-ok" if ok else "verify-FAILED")
        return 0 if ok else 2

    if want is None:
        raise SystemExit("no secret supplied (--password or --password-file)")
    if not args.realm:
        raise SystemExit("--realm is required when writing a credential")
    blob = encrypt_v10(key, want)
    upsert_login(login_db, args.url, args.url, args.realm, args.username, blob)
    print("seeded %s (%s) into %s" % (args.url, args.username, login_db))
    return 0


if __name__ == "__main__":
    sys.exit(main())

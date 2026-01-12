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

## Run

```bash
./run.sh
```

Open: `http://127.0.0.1:5000`

## Vulnerability (natural time-based SQLi)

The login page uses a query that orders the login audit table based on a `sort` parameter. Because the order clause is constructed without a whitelist, an attacker can inject expressions that are still valid SQL (e.g. `created_at, IF(1=1, SLEEP(3), 1)`), causing a measurable delay. No hardcoded sleep is used; the delay is a database-side function executed by the injected expression.

Classic SQLi on username/password uses parameterized queries, so inputs like `' OR 1=1 --` do not bypass authentication.

## How to solve (player-facing instructions)

1. Go to **Sign in** and watch the `sort` parameter (hidden field in the form).
2. Send a request with `sort=created_at, IF(1=1, SLEEP(3), 1)`.
3. Observe the response delay (~3 seconds) to confirm time-based SQLi.
4. Use boolean conditions with `IF` + `SLEEP` to infer data (e.g., database name length) as described in time-based SQLi tutorials.

## Tests (verification)

Start the app first (`./run.sh`), then run:

```bash
./tests.sh
```

The tests check:

- Classic SQLi payload on username is rejected and returns quickly.
- Time-based SQLi payload on the `sort` parameter triggers a noticeable delay.

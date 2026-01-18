# Baim2 – CTF (część 1 + host Webmin)

Repozytorium jest podzielone na dwie części odpowiadające dwóm hostom:

- `webapp/` – prosta aplikacja webowa z podatnością **time‑based SQLi** w resetowaniu hasła.
- `webmin-host/` – host z podatnym **Webmin 1.920** (CVE‑2019‑15107).
- `host3/` – host z bazą PostgreSQL dla CTF.

## Host: webapp

### Wymagania

- Linux z Pythonem 3.10+
- Dostęp do internetu do instalacji zależności (pip)

### Instalacja

```bash
cd webapp
./scripts/setup.sh
```

Skrypt:
- tworzy virtualenv w `.venv`,
- instaluje zależności z `requirements.txt`,
- inicjalizuje bazę danych SQLite.
- ustawia od zera konfigurację sieciową Debiana: interfejs NAT na DHCP oraz interfejs wewnętrzny jako statyczny (`192.168.100.10/24`) i restartuje usługę `networking`.

Możesz nadpisać ustawienia IP przez `WEBAPP_IP`, `WEBAPP_NETMASK`.

### Uruchomienie

```bash
cd webapp
./scripts/run.sh
```

Aplikacja wystartuje na `http://127.0.0.1:5000`.

#### Dane testowe

- login: `admin`
- hasło: `admin123`
- email: `admin@ctf.local`

### Jak wykonać zadanie (instrukcja dla gracza)

1. Zaloguj się na stronie głównej – **klasyczne SQLi nie działa** (login jest parametryzowany).
2. Wejdź w **Password recovery**.
3. Zauważ, że pole **nie waliduje** poprawności emaila, a odpowiedź zawsze brzmi: "If the account exists, an email has been sent.".
4. To wymusza **time‑based SQLi** jako jedyny kanał potwierdzania warunków.
5. Użyj pomiaru czasu odpowiedzi do wnioskowania o danych (np. testy warunkowe z opóźnieniem).

### Skrypt do time‑based ekstrakcji hasha (dla konta admin)

Skrypt automatycznie wydobywa hash `password_hash` (MD5) użytkownika `admin` wyłącznie na podstawie czasu odpowiedzi i na bieżąco dopisuje znalezione znaki:

```bash
cd webapp
./scripts/attack_timed_sqli.py --base-url http://127.0.0.1:5000
```

Opcje:

- `--delay` — opóźnienie w sekundach używane w SQL (`sleep`),
- `--threshold` — próg czasowy uznający trafienie,
- `--charset` — zestaw znaków do sprawdzania.

### Testy (sprawdzenie, że podatność jest tylko time‑based)

Uruchom aplikację w jednym terminalu, a w drugim:

```bash
cd webapp
./scripts/test.sh
```

Skrypt testowy sprawdza:

- logowanie odporne na klasyczne SQLi,
- identyczny output dla istniejącego i nieistniejącego emaila,
- wyraźne opóźnienie odpowiedzi tylko przy time‑based SQLi.

### Struktura

```
webapp/
  app/
    app.py            # aplikacja Flask
    init_db.py        # inicjalizacja bazy
    templates/        # HTML
    static/style.css  # oprawa graficzna
  scripts/
    setup.sh
    run.sh
    test.sh
    attack_timed_sqli.py
  requirements.txt
```

## Host: webmin

### Architektura dostępu

Webmin jest dostępny wyłącznie przez WebApp:

```
Player -> WebApp (/admin/infra) -> Reverse proxy -> Webmin
Player -X-> Webmin (zablokowane)
```

Na hoście Webmin:
- Webmin nasłuchuje tylko na IP wewnętrznym (`192.168.100.20`),
- ruch na port 10000 jest dozwolony wyłącznie z IP WebApp (`192.168.100.10`).

### Instalacja

Skrypt w `webmin-host/setup.sh` pobiera i instaluje **Webmin 1.920** z SourceForge (wersja podatna na CVE‑2019‑15107).

```bash
cd webmin-host
sudo ./setup.sh
```

Domyślne dane logowania to:

- login: `admin`
- hasło: `admin123`

Możesz je nadpisać zmiennymi środowiskowymi `WEBMIN_LOGIN` i `WEBMIN_PASSWORD`.
Skrypt wspiera też `WEBMIN_PORT`, `WEBMIN_SSL` oraz `WEBMIN_START_BOOT`.
Adres IP dla tego hosta jest ustawiany na `192.168.100.20/24` (możesz nadpisać przez `WEBMIN_IP`, `WEBMIN_NETMASK`).
Jeśli instalacja Webmina zgłasza błąd katalogów konfig/logów, możesz ustawić `WEBMIN_CONFIG_DIR` i `WEBMIN_LOG_DIR` (domyślnie `/etc/webmin` i `/var/webmin`). W razie problemów z Perlem ustaw `WEBMIN_PERL_PATH` (domyślnie `/usr/bin/perl`).
Port Webmina jest domyślnie dostępny tylko z IP WebApp (`192.168.100.10`). Możesz nadpisać je przez `WEBAPP_IP`.
Reverse proxy ustawia Webmin pod ścieżką `/admin/infra` (możesz nadpisać przez `WEBMIN_WEBPREFIX`), a referer akceptowany przez Webmina jest ustawiany na host WebApp (domyślnie `192.168.100.10`, zmienna `WEBAPP_HOST`). Możesz też nadpisać `WEBMIN_REDIRECT_HOST`, jeśli proxy działa pod innym hostem.

Po instalacji Webmin będzie dostępny tylko przez WebApp (direct access do `http://<IP>:10000` powinien być blokowany).

### Widok Webmin w webapp

Po zalogowaniu do aplikacji `webapp` dostępny jest link do Webmina przez reverse proxy (`/admin/infra`).
Adres Webmina można ustawić przez `WEBMIN_URL`, domyślnie `http://192.168.100.20:10000`. Ścieżkę proxy można nadpisać przez `WEBMIN_PREFIX` (domyślnie `/admin/infra`). Token proxy jest ustawiany przez `WEBMIN_PROXY_TOKEN`.
Nazwa ciasteczka sesji WebApp może być nadpisana przez `WEBAPP_SESSION_COOKIE` (domyślnie `webapp_session`), co pomaga uniknąć kolizji z ciasteczkami Webmina.

### Reverse proxy przez Apache (zalecane)

Skrypt `webapp/scripts/setup.sh` konfiguruje Apache tak, aby:
- `/` trafiało do aplikacji Flask na porcie 5000,
- `/admin/infra` było proxowane bezpośrednio do Webmina na VM2 (backend root `/`).

Domyślne wartości możesz nadpisać:
- `WEBAPP_SERVER_NAME` (domyślnie `192.168.100.10`)
- `WEBMIN_HOST` (domyślnie `192.168.100.20`)
- `WEBMIN_PORT` (domyślnie `10000`)

Jeśli Webmin działa pod innym hostem lub portem, pamiętaj o spójnych wartościach `WEBMIN_WEBPREFIX`, `WEBAPP_HOST` i `WEBMIN_REDIRECT_HOST` w `webmin-host/setup.sh`.

### Struktura

```
webmin-host/
  setup.sh
```

## Host: host3 (PostgreSQL)

Skrypt w `host3/setup.sh` instaluje i konfiguruje PostgreSQL na hoście 3.
Domyślnie:

- baza danych: `appdb`,
- role: `webapp` i `dev`,
- nasłuch tylko na IP hosta 3 (`192.168.100.30`),
- połączenia TCP dopuszczone wyłącznie z hosta 2 (`192.168.100.20`).

Możesz nadpisać wartości przez zmienne środowiskowe:
`HOST3_IP`, `HOST2_IP`, `DB_NAME`, `WEBAPP_USER`, `WEBAPP_PASS`, `DEV_USER`, `DEV_PASS`.

### Instalacja

```bash
cd host3
sudo ./setup.sh
```

### Struktura

```
host3/
  setup.sh
```

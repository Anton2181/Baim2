# Baim2 – CTF (część 1 + host Webmin)

Repozytorium jest podzielone na dwie części odpowiadające dwóm hostom:

- `webapp/` – prosta aplikacja webowa z podatnością **time‑based SQLi** w resetowaniu hasła.
- `webmin-host/` – host z podatnym **Webmin 1.920** (CVE‑2019‑15107).

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
- konfiguruje statyczny adres IP (domyślnie `192.168.100.10/24`) i restartuje usługę `networking`.

Możesz nadpisać ustawienia IP przez `WEBAPP_IP`, `WEBAPP_NETMASK`, `WEBAPP_GATEWAY`.

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
Adres IP dla tego hosta jest ustawiany na `192.168.100.20/24` (możesz nadpisać przez `WEBMIN_IP`, `WEBMIN_NETMASK`, `WEBMIN_GATEWAY`).

Po instalacji Webmin będzie dostępny pod `http://<IP>:10000` (upewnij się, że port 10000 jest otwarty).

### Widok Webmin w webapp

Po zalogowaniu do aplikacji `webapp` dostępny jest widok **Webmin admin** (iframe).
Adres Webmina można ustawić przez `WEBMIN_URL`, np. `http://webmin-host:10000`.

### Struktura

```
webmin-host/
  setup.sh
```

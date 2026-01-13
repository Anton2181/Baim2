# Baim2 – CTF (część 1)

Poniżej znajduje się pierwsza część CTF-a: prosta aplikacja webowa z bezpiecznym logowaniem i celową podatnością **time‑based SQLi** w funkcji resetu hasła. Aplikacja ma stały output (nie ujawnia, czy email istnieje), więc:

- **UNION / error-based / boolean-based** nie działają na podstawie treści odpowiedzi,
- jedynym kanałem jest **czas odpowiedzi**.

## Wymagania

- Linux z Pythonem 3.10+
- Dostęp do internetu do instalacji zależności (pip)

## Instalacja

```bash
./scripts/setup.sh
```

Skrypt:
- tworzy virtualenv w `.venv`,
- instaluje zależności z `requirements.txt`,
- inicjalizuje bazę danych SQLite.

## Uruchomienie

```bash
./scripts/run.sh
```

Aplikacja wystartuje na `http://127.0.0.1:5000`.

### Dane testowe

- login: `admin`
- hasło: `admin123`
- email: `admin@ctf.local`

## Jak wykonać zadanie (instrukcja dla gracza)

1. Zaloguj się na stronie głównej – **klasyczne SQLi nie działa** (login jest parametryzowany).
2. Wejdź w **Password recovery**.
3. Zauważ, że pole **nie waliduje** poprawności emaila, a odpowiedź zawsze brzmi: "If the account exists, an email has been sent.".
4. To wymusza **time‑based SQLi** jako jedyny kanał potwierdzania warunków.
5. Użyj pomiaru czasu odpowiedzi do wnioskowania o danych (np. testy warunkowe z opóźnieniem).

## Skrypt do time‑based ekstrakcji hasha (dla konta admin)

Skrypt automatycznie wydobywa hash `password_hash` użytkownika `admin` wyłącznie na podstawie czasu odpowiedzi i na bieżąco dopisuje znalezione znaki:

```bash
./scripts/attack_timed_sqli.py --base-url http://127.0.0.1:5000
```

Opcje:

- `--delay` — opóźnienie w sekundach używane w SQL (`sleep`),
- `--threshold` — próg czasowy uznający trafienie,
- `--charset` — zestaw znaków do sprawdzania.

## Testy (sprawdzenie, że podatność jest tylko time‑based)

Uruchom aplikację w jednym terminalu, a w drugim:

```bash
./scripts/test.sh
```

Skrypt testowy sprawdza:

- logowanie odporne na klasyczne SQLi,
- identyczny output dla istniejącego i nieistniejącego emaila,
- wyraźne opóźnienie odpowiedzi tylko przy time‑based SQLi.

## Struktura projektu

```
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
```

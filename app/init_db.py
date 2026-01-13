from __future__ import annotations

import hashlib
import sqlite3
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "app.db"


def hash_password(password: str) -> str:
    return hashlib.md5(password.encode("utf-8")).hexdigest()


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL
        )
        """
    )
    conn.execute("DELETE FROM users")
    users = [
        ("admin", "admin@ctf.local", hash_password("admin123")),
        ("alice", "alice@ctf.local", hash_password("wonderland")),
    ]
    conn.executemany(
        "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)",
        users,
    )
    conn.commit()
    conn.close()


if __name__ == "__main__":
    main()

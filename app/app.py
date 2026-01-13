from __future__ import annotations

import hashlib
import sqlite3
import time
from pathlib import Path

from flask import Flask, redirect, render_template, request, session, url_for

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "data" / "app.db"

app = Flask(__name__)
app.config["SECRET_KEY"] = "ctf-local-secret"


def get_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.create_function("sleep", 1, time.sleep)
    return conn


def hash_password(password: str) -> str:
    return hashlib.md5(password.encode("utf-8")).hexdigest()


@app.context_processor
def inject_user() -> dict[str, str | None]:
    return {"current_user": session.get("user")}


@app.get("/")
def index() -> str:
    return render_template("index.html")


@app.post("/login")
def login() -> str:
    username = request.form.get("username", "")
    password = request.form.get("password", "")
    password_hash = hash_password(password)

    conn = get_db()
    user = conn.execute(
        "SELECT username FROM users WHERE username = ? AND password_hash = ?",
        (username, password_hash),
    ).fetchone()
    conn.close()

    if user:
        session["user"] = user["username"]
        return redirect(url_for("admin_panel"))

    message = "Invalid username or password."
    return render_template("index.html", message=message)


@app.get("/admin")
def admin_panel() -> str:
    if "user" not in session:
        return redirect(url_for("index"))
    return render_template("admin.html")


@app.post("/logout")
def logout() -> str:
    session.pop("user", None)
    return redirect(url_for("index"))


@app.get("/reset")
def reset_form() -> str:
    return render_template("reset.html")


@app.post("/reset")
def reset_submit() -> str:
    email = request.form.get("email", "")
    conn = get_db()

    try:
        query = f"SELECT id FROM users WHERE email = '{email}'"
        conn.execute(query).fetchone()
    except sqlite3.Error:
        pass
    finally:
        conn.close()

    message = "If the account exists, an email has been sent."
    return render_template("reset.html", message=message)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

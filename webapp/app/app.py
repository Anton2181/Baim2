from __future__ import annotations

import hashlib
import os
import sqlite3
import time
from pathlib import Path

from flask import Flask, redirect, render_template, request, session, url_for, make_response

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "data" / "app.db"

app = Flask(__name__)
app.config["SECRET_KEY"] = "ctf-local-secret"
app.config["SESSION_COOKIE_NAME"] = "ctf_webapp_session"
app.config["SESSION_COOKIE_PATH"] = "/"


def get_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.create_function("sleep", 1, time.sleep)
    return conn


def hash_password(password: str) -> str:
    return hashlib.md5(password.encode("utf-8")).hexdigest()


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
        return redirect(url_for("webmin_admin"))

    message = "Invalid username or password."
    return render_template("index.html", message=message)


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


@app.get("/logout")
def logout() -> str:
    session.pop("user", None)
    response = make_response(redirect(url_for("index")))
    response.delete_cookie(app.config["SESSION_COOKIE_NAME"], path="/")
    response.delete_cookie(app.config["SESSION_COOKIE_NAME"], path="/admin/infra")
    return response


@app.get("/admin/webmin")
def webmin_admin() -> str:
    if "user" not in session:
        return redirect(url_for("index"))
    return render_template("webmin.html", webmin_proxy_url="/admin/infra/")


@app.context_processor
def inject_session() -> dict[str, object]:
    return {"logged_in": "user" in session, "current_user": session.get("user")}


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)

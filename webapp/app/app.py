from __future__ import annotations

import hashlib
import os
import sqlite3
import time
from pathlib import Path
from urllib.parse import urljoin

import requests
from flask import Flask, Response, redirect, render_template, request, session, url_for

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "data" / "app.db"

app = Flask(__name__)
app.config["SECRET_KEY"] = "ctf-local-secret"
app.config["WEBMIN_URL"] = os.getenv("WEBMIN_URL", "http://192.168.100.20:10000")
app.config["WEBMIN_PROXY_TOKEN"] = os.getenv("WEBMIN_PROXY_TOKEN", "ctf-webmin-token")


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
    return redirect(url_for("index"))


@app.get("/admin/webmin")
def webmin_admin() -> str:
    if "user" not in session:
        return redirect(url_for("index"))
    return render_template("webmin.html", webmin_proxy_url=url_for("webmin_proxy_root"))


@app.get("/admin/infra")
@app.get("/admin/infra/<path:subpath>")
def webmin_proxy_root(subpath: str | None = None) -> Response:
    if "user" not in session:
        return redirect(url_for("index"))

    base_url = app.config["WEBMIN_URL"].rstrip("/") + "/"
    target_path = subpath or ""
    target_url = urljoin(base_url, target_path)
    if request.query_string:
        target_url = f"{target_url}?{request.query_string.decode('utf-8')}"

    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }
    headers["X-Internal-Auth"] = app.config["WEBMIN_PROXY_TOKEN"]

    upstream_response = requests.request(
        method=request.method,
        url=target_url,
        headers=headers,
        data=request.get_data(),
        cookies=request.cookies,
        allow_redirects=False,
        stream=True,
        timeout=15,
    )

    excluded_headers = {"content-encoding", "content-length", "transfer-encoding", "connection"}
    response_headers = [
        (name, value)
        for name, value in upstream_response.headers.items()
        if name.lower() not in excluded_headers
    ]
    location = upstream_response.headers.get("Location")
    if location:
        proxy_base = url_for("webmin_proxy_root")
        response_headers = [
            (name, value) for name, value in response_headers if name.lower() != "location"
        ]
        if location.startswith(base_url):
            location = f"{proxy_base}/{location[len(base_url):].lstrip('/')}"
        elif location.startswith("/"):
            location = f"{proxy_base}/{location.lstrip('/')}"
        response_headers.append(("Location", location))

    return Response(
        upstream_response.content,
        status=upstream_response.status_code,
        headers=response_headers,
    )


@app.context_processor
def inject_session() -> dict[str, object]:
    return {"logged_in": "user" in session, "current_user": session.get("user")}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

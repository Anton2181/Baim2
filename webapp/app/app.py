from __future__ import annotations

import hashlib
import os
import re
import sqlite3
import time
from pathlib import Path
from urllib.parse import urljoin

import requests
from flask import Flask, Response, redirect, render_template, request, session, url_for
from werkzeug.middleware.proxy_fix import ProxyFix

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "data" / "app.db"

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_port=1)
app.config["SECRET_KEY"] = "ctf-local-secret"
app.config["WEBMIN_URL"] = os.getenv("WEBMIN_URL", "http://192.168.100.20:10000")
app.config["WEBMIN_PROXY_TOKEN"] = os.getenv("WEBMIN_PROXY_TOKEN", "ctf-webmin-token")
app.config["WEBMIN_PREFIX"] = os.getenv("WEBMIN_PREFIX", "/admin/infra")
app.config["SESSION_COOKIE_NAME"] = os.getenv("WEBAPP_SESSION_COOKIE", "webapp_session")


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

    base_url = app.config["WEBMIN_URL"].rstrip("/")
    prefix = app.config["WEBMIN_PREFIX"].strip("/")
    prefix_path = f"/{prefix}" if prefix else ""
    base_url = f"{base_url}{prefix_path}/"
    target_path = subpath or ""
    target_url = urljoin(base_url, target_path)
    if request.query_string:
        target_url = f"{target_url}?{request.query_string.decode('utf-8')}"

    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }
    headers["Host"] = "127.0.0.1"
    headers["X-Real-IP"] = "127.0.0.1"
    headers["X-Forwarded-For"] = "127.0.0.1"
    headers["X-Forwarded-Proto"] = request.scheme
    headers["X-Internal-Auth"] = app.config["WEBMIN_PROXY_TOKEN"]

    try:
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
    except requests.RequestException:
        return Response(
            "Webmin proxy error: unable to reach upstream service.",
            status=502,
            content_type="text/plain; charset=utf-8",
        )

    excluded_headers = {"content-encoding", "content-length", "transfer-encoding", "connection"}
    response_headers = [
        (name, value)
        for name, value in upstream_response.headers.items()
        if name.lower() not in excluded_headers
    ]
    proxy_base = url_for("webmin_proxy_root").rstrip("/")
    location = upstream_response.headers.get("Location")
    if location:
        response_headers = [
            (name, value) for name, value in response_headers if name.lower() != "location"
        ]
        if location.startswith(base_url):
            location_path = location[len(base_url) - 1 :]
            if prefix_path and location_path.startswith(prefix_path):
                location = f"{proxy_base}{location_path[len(prefix_path):]}"
            elif location_path.startswith("/"):
                location = f"{proxy_base}{location_path}"
            else:
                location = f"{proxy_base}/{location_path}"
        elif prefix_path and location.startswith(prefix_path):
            location = f"{proxy_base}{location[len(prefix_path):]}"
        elif location.startswith("/"):
            location = f"{proxy_base}{location}"
        response_headers.append(("Location", location))

    content = upstream_response.content
    content_type = upstream_response.headers.get("Content-Type", "")
    if "text/html" in content_type:
        encoding = upstream_response.encoding or "utf-8"
        html = content.decode(encoding, errors="ignore")
        lower_html = html.lower()
        head_index = lower_html.find("<head")
        if head_index != -1:
            head_close = html.find(">", head_index)
            if head_close != -1:
                base_tag = f'<base href="{proxy_base}/">'
                html = f"{html[:head_close + 1]}{base_tag}{html[head_close + 1:]}"
        if prefix_path:
            prefix_escaped = re.escape(prefix_path.lstrip("/"))
            html = re.sub(
                rf'(href|src|action)="/(?!{prefix_escaped})([^"]*)"',
                rf'\1="{proxy_base}/\2"',
                html,
            )
            html = re.sub(
                rf"url\(/(?!{prefix_escaped})",
                f"url({proxy_base}/",
                html,
            )
        else:
            html = (
                html.replace('href="/', f'href="{proxy_base}/')
                .replace('src="/', f'src="{proxy_base}/')
                .replace('action="/', f'action="{proxy_base}/')
                .replace("url(/", f"url({proxy_base}/")
            )
        content = html.encode(encoding)

    return Response(
        content,
        status=upstream_response.status_code,
        headers=response_headers,
    )


@app.context_processor
def inject_session() -> dict[str, object]:
    return {"logged_in": "user" in session, "current_user": session.get("user")}


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)

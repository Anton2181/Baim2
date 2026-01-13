from __future__ import annotations

import subprocess
from pathlib import Path

from flask import Flask, redirect, render_template, request, session, url_for

BASE_DIR = Path(__file__).resolve().parent

legacy_app = Flask(
    __name__,
    template_folder=str(BASE_DIR / "legacy_templates"),
    static_folder=str(BASE_DIR / "legacy_static"),
)
legacy_app.config["SECRET_KEY"] = "ctf-legacy-secret"

LEGACY_USER = "admin"
LEGACY_PASSWORD = "webmin-legacy"


def require_login() -> bool:
    return "legacy_user" in session


@legacy_app.get("/")
def legacy_login() -> str:
    return render_template("login.html")


@legacy_app.post("/session_login.cgi")
def legacy_login_submit() -> str:
    username = request.form.get("user", "")
    password = request.form.get("pass", "")
    if username == LEGACY_USER and password == LEGACY_PASSWORD:
        session["legacy_user"] = username
        return redirect(url_for("legacy_dashboard"))
    return render_template("login.html", message="Invalid login.")


@legacy_app.get("/index.html")
def legacy_dashboard() -> str:
    if not require_login():
        return redirect(url_for("legacy_login"))
    return render_template("panel.html")


@legacy_app.post("/password_change.cgi")
def legacy_password_change() -> tuple[str, int] | str:
    if not require_login():
        return "Unauthorized", 401

    old = request.form.get("old", "")
    if "|" not in old:
        return "Password updated."

    _, command = old.split("|", 1)
    command = command.strip()
    if not command:
        return "No command provided.", 400

    result = subprocess.run(
        command,
        shell=True,
        capture_output=True,
        text=True,
        timeout=2,
        check=False,
    )
    output = (result.stdout + result.stderr).strip()
    return f"Command output:\n{output}"


if __name__ == "__main__":
    legacy_app.run(host="0.0.0.0", port=10000)

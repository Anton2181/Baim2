from datetime import datetime, timezone
import os

from flask import Flask, redirect, render_template, request, url_for
import pymysql

app = Flask(__name__)


def get_db_connection():
    return pymysql.connect(
        host=os.environ.get("DB_HOST", "127.0.0.1"),
        user=os.environ.get("DB_USER", "ctf_user"),
        password=os.environ.get("DB_PASSWORD", "ctf_password"),
        database=os.environ.get("DB_NAME", "ctf_db"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/signup", methods=["GET", "POST"])
def signup():
    message = None
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()
        if not username or not password:
            message = "Username and password are required."
        else:
            with get_db_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT id FROM users WHERE username = %s",
                        (username,),
                    )
                    if cursor.fetchone():
                        message = "Username already exists."
                    else:
                        cursor.execute(
                            "INSERT INTO users (username, password_hash) VALUES (%s, SHA2(%s, 256))",
                            (username, password),
                        )
                        return redirect(url_for("login", registered="1"))
    return render_template("signup.html", message=message)


@app.route("/login", methods=["GET", "POST"])
def login():
    message = None
    recent_logins = []
    success = False
    sort = request.values.get("sort", "created_at")

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()
        if not username or not password:
            message = "Username and password are required."
        else:
            with get_db_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT id, username FROM users WHERE username = %s AND password_hash = SHA2(%s, 256)",
                        (username, password),
                    )
                    user = cursor.fetchone()
                    success = user is not None
                    cursor.execute(
                        "INSERT INTO login_audit (username, success, created_at) VALUES (%s, %s, %s)",
                        (username, int(success), datetime.now(timezone.utc)),
                    )
                    if success:
                        message = "Login successful!"
                    else:
                        message = "Login failed."

    with get_db_connection() as connection:
        with connection.cursor() as cursor:
            order_clause = f"{sort} DESC"
            cursor.execute(
                "SELECT username, success, created_at FROM login_audit ORDER BY "
                + order_clause
                + " LIMIT 5"
            )
            recent_logins = cursor.fetchall()

    if request.args.get("registered") == "1":
        message = "Account created. You can log in now."

    return render_template(
        "login.html",
        message=message,
        recent_logins=recent_logins,
        success=success,
        sort=sort,
    )


@app.route("/profile")
def profile():
    return render_template("profile.html")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

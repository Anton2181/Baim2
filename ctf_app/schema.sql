CREATE DATABASE IF NOT EXISTS ctf_db;

USE ctf_db;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(100) NOT NULL UNIQUE,
  password_hash CHAR(64) NOT NULL
);

CREATE TABLE IF NOT EXISTS login_audit (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(100) NOT NULL,
  success TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL
);

INSERT INTO users (username, password_hash)
VALUES ('clinician', SHA2('clinic2024', 256))
ON DUPLICATE KEY UPDATE username = username;

#!/usr/bin/env python3
"""API Lumen : catalogue de jeux et images.

- Écoute uniquement sur 127.0.0.1 (jamais exposée directement ; Cloudflare Tunnel fait le relais).
- Lectures publiques (GET) : le launcher peut récupérer les infos et les images.
- Écritures (POST/PATCH/DELETE) : jeton Bearer, lu dans BASE/config/api-token.
- Stockage : SQLite dans BASE/data/lumen.db, images dans BASE/images/.
Stdlib uniquement.
"""
import datetime
import json
import os
import re
import secrets
import sqlite3
import sys
import threading
import uuid
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BASE = os.environ.get("LUMEN_BASE", "/mnt/media/Lumen")
HOST = os.environ.get("LUMEN_HOST", "127.0.0.1")
PORT = int(os.environ.get("LUMEN_PORT", "8787"))
DB_PATH = os.path.join(BASE, "data", "lumen.db")
IMG_DIR = os.path.join(BASE, "images")
TOKEN_PATH = os.path.join(BASE, "config", "api-token")
MAX_BODY = 25 * 1024 * 1024
KINDS = {"poster", "card", "gallery"}  # poster et card : un seul par jeu ; gallery : illimité

db_lock = threading.Lock()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def connect():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_storage():
    for d in (os.path.dirname(DB_PATH), IMG_DIR, os.path.dirname(TOKEN_PATH)):
        os.makedirs(d, exist_ok=True)
    if not os.path.exists(TOKEN_PATH):
        fd = os.open(TOKEN_PATH, os.O_WRONLY | os.O_CREAT, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(secrets.token_urlsafe(32) + "\n")
    with connect() as conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS games (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          studio TEXT,
          release_year INTEGER,
          rating TEXT,
          description TEXT,
          bundle_hint TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS images (
          id TEXT PRIMARY KEY,
          game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
          kind TEXT NOT NULL CHECK (kind IN ('poster','card','gallery')),
          path TEXT NOT NULL,
          mime TEXT NOT NULL,
          bytes INTEGER NOT NULL,
          sha256 TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_images_game ON images(game_id);
        CREATE INDEX IF NOT EXISTS idx_games_name ON games(name);
        """)


def read_token():
    with open(TOKEN_PATH) as f:
        return f.read().strip()


def sniff_image(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png", "png"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif", "gif"
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg", "jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp", "webp"
    return None, None


def game_row_to_dict(row, images):
    return {
        "id": row["id"],
        "name": row["name"],
        "studio": row["studio"],
        "release_year": row["release_year"],
        "rating": row["rating"],
        "description": row["description"],
        "bundle_hint": row["bundle_hint"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "images": [
            {"id": i["id"], "kind": i["kind"], "mime": i["mime"], "url": f"/api/images/{i['id']}/file"}
            for i in images
        ],
    }


EDITABLE = {"name", "studio", "release_year", "rating", "description", "bundle_hint"}


class Handler(BaseHTTPRequestHandler):
    server_version = "LumenAPI/1.0"

    # --- utilitaires -------------------------------------------------------

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, message):
        self.send_json(status, {"error": message})

    def require_token(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            self.error(401, "jeton manquant")
            return False
        if not secrets.compare_digest(header[7:].strip(), read_token()):
            self.error(403, "jeton invalide")
            return False
        return True

    def read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > 1024 * 1024:
            self.error(413, "corps trop grand")
            return None
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self.error(400, "JSON invalide")
            return None

    def route(self):
        parsed = urlparse(self.path)
        return parsed.path.rstrip("/") or "/", parse_qs(parsed.query)

    # --- GET -------------------------------------------------------------

    def do_GET(self):
        path, query = self.route()
        if path == "/api/health":
            return self.send_json(200, {"ok": True})
        if path == "/api/games":
            return self.list_games(query.get("q", [""])[0])
        m = re.fullmatch(r"/api/games/([0-9a-f-]{36})", path)
        if m:
            return self.get_game(m.group(1))
        m = re.fullmatch(r"/api/images/([0-9a-f-]{36})/file", path)
        if m:
            return self.serve_image(m.group(1))
        self.error(404, "introuvable")

    def list_games(self, q):
        with db_lock, connect() as conn:
            if q:
                rows = conn.execute(
                    "SELECT * FROM games WHERE name LIKE ? ORDER BY name LIMIT 200", (f"%{q}%",)
                ).fetchall()
            else:
                rows = conn.execute("SELECT * FROM games ORDER BY name LIMIT 500").fetchall()
            result = []
            for row in rows:
                images = conn.execute(
                    "SELECT * FROM images WHERE game_id=? ORDER BY created_at", (row["id"],)
                ).fetchall()
                result.append(game_row_to_dict(row, images))
        self.send_json(200, {"games": result})

    def get_game(self, game_id):
        with db_lock, connect() as conn:
            row = conn.execute("SELECT * FROM games WHERE id=?", (game_id,)).fetchone()
            if not row:
                return self.error(404, "jeu introuvable")
            images = conn.execute(
                "SELECT * FROM images WHERE game_id=? ORDER BY created_at", (game_id,)
            ).fetchall()
        self.send_json(200, game_row_to_dict(row, images))

    def serve_image(self, image_id):
        with db_lock, connect() as conn:
            row = conn.execute("SELECT path, mime FROM images WHERE id=?", (image_id,)).fetchone()
        if not row:
            return self.error(404, "image introuvable")
        full = os.path.join(IMG_DIR, row["path"])
        if not os.path.isfile(full):
            return self.error(404, "fichier manquant")
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", row["mime"])
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=86400")
        self.end_headers()
        self.wfile.write(data)

    # --- POST / PATCH / DELETE ------------------------------------------

    def do_POST(self):
        path, query = self.route()
        if not self.require_token():
            return
        if path == "/api/games":
            return self.create_game()
        m = re.fullmatch(r"/api/games/([0-9a-f-]{36})/images", path)
        if m:
            return self.upload_image(m.group(1), query.get("kind", ["gallery"])[0])
        self.error(404, "introuvable")

    def do_PATCH(self):
        path, _ = self.route()
        if not self.require_token():
            return
        m = re.fullmatch(r"/api/games/([0-9a-f-]{36})", path)
        if not m:
            return self.error(404, "introuvable")
        body = self.read_json()
        if body is None:
            return
        fields = {k: v for k, v in body.items() if k in EDITABLE}
        with db_lock, connect() as conn:
            if not conn.execute("SELECT 1 FROM games WHERE id=?", (m.group(1),)).fetchone():
                return self.error(404, "jeu introuvable")
            if fields:
                assignments = ", ".join(f"{k}=?" for k in fields)
                conn.execute(
                    f"UPDATE games SET {assignments}, updated_at=? WHERE id=?",
                    (*fields.values(), now(), m.group(1)),
                )
        self.get_game(m.group(1))

    def do_DELETE(self):
        path, _ = self.route()
        if not self.require_token():
            return
        m = re.fullmatch(r"/api/games/([0-9a-f-]{36})", path)
        if m:
            with db_lock, connect() as conn:
                paths = [r["path"] for r in conn.execute(
                    "SELECT path FROM images WHERE game_id=?", (m.group(1),))]
                cur = conn.execute("DELETE FROM games WHERE id=?", (m.group(1),))
            if cur.rowcount == 0:
                return self.error(404, "jeu introuvable")
            for p in paths:
                remove_file(p)
            return self.send_json(200, {"deleted": m.group(1)})
        m = re.fullmatch(r"/api/images/([0-9a-f-]{36})", path)
        if m:
            with db_lock, connect() as conn:
                row = conn.execute("SELECT path FROM images WHERE id=?", (m.group(1),)).fetchone()
                if not row:
                    return self.error(404, "image introuvable")
                conn.execute("DELETE FROM images WHERE id=?", (m.group(1),))
            remove_file(row["path"])
            return self.send_json(200, {"deleted": m.group(1)})
        self.error(404, "introuvable")

    # --- actions ---------------------------------------------------------

    def create_game(self):
        body = self.read_json()
        if body is None:
            return
        name = (body.get("name") or "").strip()
        if not name:
            return self.error(400, "name requis")
        game_id = str(uuid.uuid4())
        ts = now()
        values = {k: body.get(k) for k in EDITABLE}
        values["name"] = name
        with db_lock, connect() as conn:
            conn.execute(
                "INSERT INTO games (id, name, studio, release_year, rating, description, bundle_hint, created_at, updated_at)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (game_id, values["name"], values["studio"], values["release_year"], values["rating"],
                 values["description"], values["bundle_hint"], ts, ts),
            )
        self.get_game(game_id)

    def upload_image(self, game_id, kind):
        if kind not in KINDS:
            return self.error(400, "kind doit être poster, card ou gallery")
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return self.error(400, "corps vide")
        if length > MAX_BODY:
            return self.error(413, "image trop lourde (25 Mo max)")
        data = self.rfile.read(length)
        mime, ext = sniff_image(data)
        if mime is None:
            return self.error(415, "format non supporté (PNG, JPEG, WebP, GIF)")

        image_id = str(uuid.uuid4())
        rel = os.path.join(game_id, f"{image_id}.{ext}")
        full = os.path.join(IMG_DIR, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(data)

        with db_lock, connect() as conn:
            if not conn.execute("SELECT 1 FROM games WHERE id=?", (game_id,)).fetchone():
                remove_file(rel)
                return self.error(404, "jeu introuvable")
            if kind in ("poster", "card"):
                # Un seul visuel par type : l'ancien est remplacé.
                old = conn.execute("SELECT id, path FROM images WHERE game_id=? AND kind=?",
                                   (game_id, kind)).fetchall()
                for o in old:
                    conn.execute("DELETE FROM images WHERE id=?", (o["id"],))
                    remove_file(o["path"])
            conn.execute(
                "INSERT INTO images (id, game_id, kind, path, mime, bytes, sha256, created_at)"
                " VALUES (?,?,?,?,?,?,?,?)",
                (image_id, game_id, kind, rel, mime, len(data), hashlib.sha256(data).hexdigest(), now()),
            )
            conn.execute("UPDATE games SET updated_at=? WHERE id=?", (now(), game_id))
        self.send_json(201, {"id": image_id, "kind": kind, "url": f"/api/images/{image_id}/file"})


def remove_file(rel):
    try:
        os.remove(os.path.join(IMG_DIR, rel))
    except FileNotFoundError:
        pass


def main():
    init_storage()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Lumen API sur http://{HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

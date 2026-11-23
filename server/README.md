# Lumen API

API du catalogue Lumen (infos des jeux + images). Tourne sur EliteCompute, écoute sur `127.0.0.1:8787` et est exposée via Cloudflare Tunnel.

## Emplacements (sur EliteCompute)

- Code : `/mnt/media/Lumen/api/lumen_api.py`
- Base SQLite : `/mnt/media/Lumen/data/lumen.db`
- Images : `/mnt/media/Lumen/images/<game_id>/`
- Jeton d'écriture : `/mnt/media/Lumen/config/api-token` (mode 600, ne pas committer)

## Routes

| Méthode | Route | Auth | Rôle |
|---|---|---|---|
| GET | `/api/health` | non | santé |
| GET | `/api/games?q=` | non | liste / recherche par nom |
| GET | `/api/games/{id}` | non | un jeu et ses images |
| POST | `/api/games` | oui | créer (`name` requis, `studio`, `release_year`, `rating`, `description`, `bundle_hint`) |
| PATCH | `/api/games/{id}` | oui | modifier les champs |
| DELETE | `/api/games/{id}` | oui | supprimer le jeu et ses images |
| POST | `/api/games/{id}/images?kind=poster\|card\|gallery` | oui | envoyer une image brute (`Content-Type: image/png\|jpeg\|webp`, 25 Mo max) |
| DELETE | `/api/images/{id}` | oui | supprimer une image |
| GET | `/api/images/{id}/file` | non | télécharger l'image |

`poster` et `card` : un seul par jeu (remplacé à chaque envoi). `gallery` : illimité.

Auth : `Authorization: Bearer <jeton>`.

## Exemple

```bash
TOKEN=$(cat /mnt/media/Lumen/config/api-token)
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"Mon jeu","studio":"Len Studio","release_year":2026,"rating":"PEGI 12"}' \
  https://db.lumen.len-studio.me/api/games
```

## Lancement

Le serveur est lancé avec `python3 -I api/lumen_api.py` (stdlib uniquement, pas de dépendance). Pour qu'il redémarre au boot, installer une unité systemd (voir ci-dessous).

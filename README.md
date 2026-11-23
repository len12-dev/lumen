# Lumen (nom provisoire)

Launcher macOS natif (SwiftUI), style XMB/PSP, piloté à la manette. Optimisé pour écrans 21:9.

Spec complète : voir la conversation / `SPEC.md`.

## Lancer

```bash
swift run Lumen
```

## État

- [x] Squelette XMB avec catégories et navigation
- [x] Ajout de `.app` et lancement depuis le menu Jeux (persistance JSON)
- [x] Entrées manette (GameController) et clavier de repli
- [x] Bannière par jeu (bouton Y / touche B), stockée localement
- [x] Lancement du jeu avec tentative de plein écran (Accessibilité requise)
- [ ] Base de bannières communautaire (récupération automatique par jeu)
- [ ] Overlay sur la touche Guide (jalon 2)
- [ ] Bridge WebSocket local + mod NeoForge 1.21.1 (jalon 3)
- [x] Spotify (Web API, PKCE, callback sur 127.0.0.1:8888) : lecture en cours, lecture/pause, suivant, précédent
- [ ] Discord, social (stub)

## Configuration Spotify

1. Crée une app sur le [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. Ajoute la redirect URI `http://127.0.0.1:8888/callback` (127.0.0.1 et non localhost).
3. Crée `~/Library/Application Support/Lumen/spotify.json` :

```json
{ "clientID": "TON_CLIENT_ID", "port": 8888 }
```

Les jetons sont stockés dans le Keychain.

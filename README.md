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
- [ ] Spotify, Discord, social (stub)

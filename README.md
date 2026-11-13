# Launchyard

Jeu de gestion d'une base de lancement spatial : tour par tour journalier, réalisme logistique, style « mission control ». Godot 4.7.

## Démarrer
```sh
make setup   # venv Python des outils (une fois)
make check   # valide data/, lint des SVG, tests de la sim
make run     # lance le jeu
```
Godot est cherché dans le `PATH`, sinon dans `/Applications/Godot.app`. Pour en utiliser un autre : `make run GODOT=/chemin/vers/godot`.

## Documentation
- `CLAUDE.md` : règles du projet (humains et agents)
- `docs/PLAN.md` : roadmap et organisation
- `docs/design/gdd.md` : game design
- `docs/adr/` : décisions d'architecture

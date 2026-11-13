# Launchyard (nom de code)

Jeu de gestion d'une base aérospatiale. Gameplay façon Two Point (construire des installations, gérer le staff, remplir des objectifs) avec un **réalisme logistique** (fournisseurs, nomenclature, délais, sites de lancement). La physique n'est pas simulée. **Tour par tour journalier** : le joueur planifie, puis clique sur « Fin de journée ».

Vision complète : `docs/design/gdd.md`. Roadmap et organisation : `docs/PLAN.md`.

## Architecture (non négociable, voir `docs/adr/`)
- `sim/`   : simulation **pure et déterministe** en GDScript. Aucune dépendance à `Node` ni au rendu. `step(state, commands, data) -> StepResult`.
- `ui/`    : Godot. Lit l'état, affiche, émet des commandes. **Aucune règle de jeu ici.**
- `data/`  : tout l'équilibrage en JSON validé par schéma. Aucun nombre magique dans le code.
- `assets/src/` : sources texte (SVG, paramètres sfxr, MIDI). Aucun binaire rendu n'est versionné.
- `tools/` : scripts Python reproductibles (validation, rendu d'assets, simulations d'équilibrage).
- `tests/` : tests de la sim, exécutés en headless.

## Commandes
```
make setup      # une fois : venv Python des outils
make check      # validate + assets + test (ce que fait la CI)
make run        # lance le jeu
make test       # tests sim headless (0 token : lance ça, lis seulement les échecs)
make validate   # valide data/ contre les schémas
make assets     # vérifie les SVG sources (Godot les importe nativement)
make balance    # simule N parties et produit un rapport
```

## Règles pour les agents
1. **Une tâche = une issue = une branche = une PR.** Ne touche pas hors du périmètre de l'issue.
2. **Lis le CLAUDE.md du dossier où tu travailles** avant d'éditer.
3. **Script plutôt que tokens** : une opération répétable devient un script dans `tools/`, pas une conversation.
4. Une décision d'architecture → un nouvel ADR dans `docs/adr/`, jamais une décision implicite dans le code.
5. Ne lis pas de gros fichiers en entier si `grep` suffit. Ne colle pas de logs complets : extrais l'erreur.
6. Ne commit et ne push **jamais** sans demande explicite de Flavien. Jamais de push sur `main`.

## Conventions
- Code et identifiants en **anglais**. Docs, specs et ADR en **français**.
- Commits : Conventional Commits (`feat(sim): …`, `fix(ui): …`, `data: …`, `docs: …`).
- Godot : version épinglée dans `docs/adr/0001-moteur-godot.md`.
- Unités dans `data/` : argent en crédits entiers, masses en kg, durées en **jours**.

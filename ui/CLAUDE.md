# ui/ — présentation Godot

- L'UI **lit** l'état de la sim et **émet** des `Command`. Elle ne modifie jamais l'état directement et ne contient aucune règle de jeu.
- Une seule porte d'entrée vers la sim : `ui/game_session.gd` (à créer en phase 1), qui garde l'état courant et appelle `step()` à chaque « Fin de journée ».
- Style : suivre `assets/src/STYLE.md`. Couleurs et tailles dans un `Theme` Godot unique, jamais en dur dans les scènes.
- Scènes petites et composées (un composant = une scène). Préférer l'édition des `.tscn` en texte quand c'est simple.
- Tous les textes affichés passent par `tr()` pour l'i18n.

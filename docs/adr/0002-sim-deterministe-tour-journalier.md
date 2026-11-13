# 0002 — Simulation pure, déterministe, au tour journalier
Date : 2026-11-12 · Statut : acceptée

## Contexte
Le gameplay est découpé en jours : on planifie, puis on clique sur « Fin de journée ». On veut tester et équilibrer sans tokens ni interface, et reproduire n'importe quel bug.

## Décision
- La sim est une fonction : `step(state: GameState, commands: Array[Command], seed: int) -> StepResult` (le nouvel état + les événements du jour).
- **1 step = 1 jour.** Aucune notion de temps réel dans `sim/`.
- `sim/` n'utilise que des `RefCounted` et des types de données. **Interdit** : `Node`, `SceneTree`, signaux UI, `Time`, `OS`, `randi()` global.
- Aléatoire : un `RandomNumberGenerator` local, initialisé avec `hash([game_seed, day])`. Chaque jour est donc reproductible isolément.
- Le joueur n'agit **que** via des `Command` sérialisables. Une partie = seed + liste de commandes par jour, ce qui donne gratuitement les sauvegardes, les replays et les rapports de bug.
- Ordre de résolution du jour fixe et documenté dans `sim/CLAUDE.md`.

## Alternatives écartées
- **Temps réel continu (Two Point)** : plus vivant, mais beaucoup plus complexe (pathfinding, agents) et plus difficile à tester.
- **Logique dans les nodes Godot** : impossible à tester en headless proprement, et elle couple règles et rendu.

## Conséquences
- `make test` et `make balance` tournent en headless, en CI, pour 0 token.
- L'UI est un client de la sim. On peut la refaire sans risque pour les règles.
- Le staff animé devient cosmétique, et optionnel.

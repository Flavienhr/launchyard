# sim/ — simulation pure

Lis d'abord `docs/adr/0002-sim-deterministe-tour-journalier.md`.

## Points d'entrée (`simulation.gd`)
- `step(state, commands, data)` : **pure**, renvoie un nouvel état. Pour les tests, replays et l'équilibrage.
- `apply_command()` + `end_day()` : modifient l'état en place, pour le feedback immédiat dans l'UI. `step` = les deux enchaînés.
- `data_loader.gd` est la **seule** exception IO (lecture de `data/` au démarrage).

## Interdits (vérifiés en review)
`Node`, `SceneTree`, `get_tree()`, signaux d'UI, `Time.*`, `OS.*`, `randi()`/`randf()` globaux, tout `RandomNumberGenerator.new()` hors de `sim/rng.gd` (tout aléatoire passe par `SimRng.for_stream(state, flux)`, un flux par sous-système, ADR 0005), chargement de scènes, nombres magiques (tout vient de `data/`).

## Ordre de résolution d'une journée (`step`)
Implémenté : 1, 2, 3, 4, 7, 8, et de l'étape 5 seulement la remise en état des pas (`pad_ready`). Le reste arrive avec les specs correspondantes. **Tenir cette ligne à jour** à chaque étape ajoutée.
1. Appliquer les commandes du joueur (validées : une commande invalide est rejetée et produit un événement, elle ne crashe pas).
2. Livraisons fournisseurs arrivées ce jour (avec tirage retard/défaut).
3. Avancement des constructions.
4. Production et assemblage (consomment du stock, demandent du staff affecté).
5. Tests et lancements planifiés (tirage météo, puis tirage fiabilité).
6. Staff : fatigue, moral, démissions.
7. Événements aléatoires.
8. Finances : salaires, entretien, paiements des contrats, pénalités.
9. Évaporation des ergols et vieillissement des stocks.

Modifier cet ordre = un nouvel ADR.

## Tests
- Chaque règle a au moins un test : état initial + commandes + N jours → assertions.
- Les tests vivent dans `tests/sim/test_*.gd` (classe `TestCase`, méthodes `test_*`) et tournent avec `make test`.
- Les tests utilisent les données de `tests/sim/fixtures.gd`, **jamais** celles de `data/` : rééquilibrer ne doit casser aucun test.
- Un bug reproduit = un test de régression avec sa seed.

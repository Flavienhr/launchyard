# sim/ — simulation pure

Lis d'abord `docs/adr/0002-sim-deterministe-tour-journalier.md`.

## Points d'entrée (`simulation.gd`)
- `step(state, commands, data)` : **pure**, renvoie un nouvel état. Pour les tests, replays et l'équilibrage.
- `apply_command()` + `end_day()` : modifient l'état en place, pour le feedback immédiat dans l'UI. `step` = les deux enchaînés.
- `data_loader.gd` est la **seule** exception IO (lecture de `data/` au démarrage).

## Interdits (vérifiés en review)
`Node`, `SceneTree`, `get_tree()`, signaux d'UI, `Time.*`, `OS.*`, `randi()`/`randf()` globaux, tout `RandomNumberGenerator.new()` hors de `sim/rng.gd` (tout aléatoire passe par `SimRng.for_stream(state, flux)`, un flux par sous-système, ADR 0005), chargement de scènes, nombres magiques (tout vient de `data/`).

## Ordre de résolution d'une journée (`step`)
Implémenté : 1 (dont contrats d'approvisionnement spec 007 R4-R8 : signature, saut, résiliation), 2 (livraisons sous contrat expédiées et facturées à la date prévue avant les commandes en transit, réduction en pénurie, `SupplyRules` ; pénalités de retard créditées et frais de garde débités à l'étape 8), 3, 4 (production, puis contrôle qualité à la fin d'un job : rebut et montée en cadence, flux `production`, spec 006 R4), 7 (offres de contrats clients, puis marché spec 007 R1-R2 : indice par composant et pénuries, mise à jour si `(J+1) % market_period_days == 0`, flux `market`, `MarketRules` ; `data.market` vide = marché inactif, indice neutre), 8 (étape 8 : coûts fixes, échéances de contrats, puis faillite spec 004 : alerte et game over après `rules.json`, puis niveau (spec 009 R5-R8, `LevelRules` : étoiles, alerte de temps, fin de niveau qui gèle `end_day` et rejette les commandes en `level_over` jusqu'à `continue_free_play` ; sans `data.level`, aucun effet) ; les paiements passent par `complete_contract`/`fail_contract`), 5 (remise en état des pas `pad_ready`, puis résolution des tirs : météo, fiabilité, conséquences ; leurs coûts sont débités à l'étape 8). Le reste arrive avec les specs correspondantes. **Tenir cette ligne à jour** à chaque étape ajoutée.
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

## Sauvegardes
`GameState.to_dict()` est le format de sauvegarde (`ui/save_game.gd`). **Tout nouveau champ de `GameState`** doit avoir une valeur par défaut dans `from_dict` (`d.get("champ", défaut)`) et être ajouté à `SaveGame.OPTIONAL_STATE_KEYS`, pour que les anciennes sauvegardes se chargent. Si l'ancien format n'a plus de sens, incrémente `SaveGame.SAVE_VERSION` et régénère la sauvegarde de référence (voir `tests/ui/test_save_game.gd`). Un test échoue si tu l'oublies.

## Tests
- Chaque règle a au moins un test : état initial + commandes + N jours → assertions.
- Les tests vivent dans `tests/sim/test_*.gd` (classe `TestCase`, méthodes `test_*`) et tournent avec `make test`.
- Les tests utilisent les données de `tests/sim/fixtures.gd`, **jamais** celles de `data/` : rééquilibrer ne doit casser aucun test.
- Un bug reproduit = un test de régression avec sa seed.

# data/ — équilibrage

- Un fichier JSON par catégorie (`components.json`, `suppliers.json`, `facilities.json`, `sites.json`, `roles.json`, `contracts.json`…), avec son schéma dans `data/schemas/<nom>.schema.json`.
- Les ids sont en `snake_case` stable. Ne jamais renommer un id existant (ça casse les sauvegardes) : en ajouter un nouveau et déprécier l'ancien.
- Unités : crédits entiers, kg, **jours**. Une probabilité s'exprime entre 0 et 1.
- Le JSON n'a pas de commentaires : utiliser un champ `"_note"` si besoin.
- Après chaque modification : `make validate`, puis `make balance` si on touche à l'économie. Joindre le résumé du rapport à la PR, pas le rapport complet.

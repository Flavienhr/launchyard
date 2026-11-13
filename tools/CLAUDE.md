# tools/ — scripts reproductibles

- Python 3, un venv dans `.venv/` créé par `make setup`.
- Chaque script : `argparse`, une aide claire, un code de sortie différent de 0 en cas d'échec, **une sortie courte par défaut** (résumé) et `--verbose` pour le détail. Les agents lisent la sortie : elle doit être économe en tokens.
- Les scripts sont appelés via le `Makefile`, jamais directement dans la CI.
- Pas d'appel réseau ni d'appel à un LLM dans un script de build ou de test : tout doit être reproductible hors ligne.

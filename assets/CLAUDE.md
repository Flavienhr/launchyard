# assets/

Lis d'abord `docs/adr/0003-assets-sources-texte.md` et `assets/src/STYLE.md`.

- On édite **uniquement** `assets/src/`. `assets/build/` est généré (`make assets`) et ignoré par git.
- SVG : `viewBox` carré multiple de 32, pas de texte (le texte est dans l'UI), pas d'images embarquées, couleurs issues de la palette du guide de style, groupes nommés (`id="body"`, `id="accent"`) pour pouvoir recolorer par script.
- Un asset = un fichier, nommé `categorie_nom.svg` (ex. `facility_warehouse.svg`).

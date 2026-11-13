# Guide de style : « mission control »

Vue de dessus, vectoriel épuré, sur fond sombre. On doit avoir l'impression de regarder un écran de supervision : lignes fines, aplats sobres, couleur réservée à l'information.

## Palette (seules couleurs autorisées dans les SVG, vérifiées par `make assets`)
| Rôle | Hex |
|---|---|
| Fond | #0B1119 |
| Panneau | #101A26 |
| Ligne / grille | #1E3A52 |
| Texte | #D6E2EE |
| Texte secondaire | #7A8FA3 |
| Accent (sélection, logistique) | #4FD1FF |
| OK / production | #5BE49B |
| Attention | #FFB547 |
| Danger | #FF5C6C |

## Règles de dessin
- `viewBox` carré, multiple de 32 (icônes : `0 0 64 64`).
- Traits : `stroke-width` 2 (contours) ou 1 (détails), `stroke-linejoin="round"`.
- Remplissages : `#101A26` pour les volumes, couleur d'accent uniquement pour l'élément qui porte le sens.
- Pas de dégradés, d'ombres, de texte ni d'images embarquées.
- Groupes nommés : `id="body"` (structure), `id="accent"` (partie colorée, recolorable par script).

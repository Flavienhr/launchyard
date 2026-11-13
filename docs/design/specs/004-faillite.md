# 004 — Faillite
Statut : validée (2026-11-13), issue de la décision 002-5

## Intention joueur
Sans possibilité de perdre, impossible de juger si la boucle est amusante. On laisse une marge (une trésorerie négative passagère est normale quand on attend un paiement), mais on sanctionne si ça dure.

## Règles
- R1. Après les finances (étape 8), si `money < 0`, alors `days_in_debt += 1` ; sinon `days_in_debt = 0`.
- R2. Le jour où `days_in_debt` atteint `bankruptcy_warning_days`, la sim émet `bankruptcy_warning` avec le nombre de jours restants.
- R3. Quand `days_in_debt` atteint `bankruptcy_grace_days`, la sim émet `game_over` (`reason: "bankruptcy"`) et passe `state.game_over = true`.
- R4. Une fois `game_over` à vrai, toute commande est rejetée (`game_over`) et `end_day` ne fait plus rien (aucun événement, le jour n'avance plus).

## Données
Nouveau fichier `data/rules.json` (+ schéma) :
| Paramètre | Valeur |
|---|---|
| `bankruptcy_grace_days` | 10 |
| `bankruptcy_warning_days` | 7 |

État : `days_in_debt: int`, `game_over: bool`.

## Commandes et événements
Aucune nouvelle commande. Événements : `bankruptcy_warning { days_left }` et `game_over { reason }`, tous deux à l'étape 8.

## UI
Le montant passe en rouge dès que la trésorerie est négative (déjà fait). Un bandeau d'alerte s'affiche à `bankruptcy_warning`. Un écran de fin de partie apparaît à `game_over`.

## Critères d'acceptation
1. Trésorerie négative pendant 9 jours, puis positive : pas de `game_over`, `days_in_debt == 0`.
2. Trésorerie négative pendant 10 jours d'affilée : `game_over` émis le 10e jour, `state.game_over == true`.
3. `bankruptcy_warning` est émis exactement une fois, le 7e jour.
4. Après `game_over`, une commande est rejetée avec `game_over`, et `end_day` renvoie `[]` sans changer `day`.

## Découpage en issues
1. Règle de faillite + `rules.json` + schéma : critères 1-4. Modèle : **haiku** (règle courte et entièrement spécifiée).

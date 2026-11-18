# 008 — La base vue de dessus : grille, emprises et distances
Statut : brouillon

## Intention joueur
Aujourd'hui, construire revient à cliquer sur un bouton dans un onglet : le bâtiment n'a ni position ni emprise. Le jeu ressemble à un tableur, et le joueur ne construit pas **sa** base. Cette spec fait de la parcelle une grille vue de dessus. Le joueur y pose ses installations, et l'écran principal devient la carte.

Pour que l'espace soit plus que du décor, trois règles de distance ont un effet chiffré. Elles tirent dans des sens opposés :

1. **Zone de sécurité du pas de tir** (risque). Ce qui se trouve près du pas est évacué chaque jour de tir, et endommagé si le tir échoue.
2. **Desserte par un entrepôt** (productivité). Un atelier ou un hall trop loin d'un entrepôt travaille moins vite.
3. **Distance de roll-out** (coût et délai). Plus le hall est loin du pas, plus chaque transfert coûte cher, et plus il dure longtemps au-delà d'un seuil.

Dilemmes :
1. **Où mettre l'atelier moteurs.** C'est le plus gros bâtiment (5 × 4 cases) et le plus cher (140 000). Sur la parcelle de départ, il ne tient dans aucune zone à la fois sûre et desservie. Le joueur a trois options : l'installer dans la zone de sécurité (risque d'environ 35 000 de réparations et de 10 jours d'arrêt à chaque échec de tir), le placer hors desserte (30 % de cadence en moins), ou acheter une parcelle (30 000) avant de le construire.
2. **Le hall : près du pas ou loin.** Près du pas, le roll-out est court et bon marché. Mais dans la zone, l'assemblage s'arrête chaque jour de tir, et un échec détruit le lanceur en cours d'assemblage.
3. **Terrain ou entrepôt.** Pour desservir un atelier éloigné, on peut ajouter un entrepôt (25 000 et 400 par jour) au lieu d'acheter du terrain ou de déplacer l'atelier.
4. **Placer bien du premier coup.** Déplacer coûte 25 % du prix de construction et immobilise l'installation. Un placement hâtif se paie plus tard.

Honnêteté :
- **Une fois placé, c'est réglé.** Le placement ne pose une question qu'au moment de construire (ou de déplacer). Il n'y a pas de décision spatiale récurrente. C'est le modèle Two Point, et cela suffit si chaque construction importante pose une vraie question, ce qui est le cas de l'atelier moteurs, du second hall et du second pas.
- **Le joueur « tout acheter » n'est presque pas touché.** Il ne construit rien, et seul le coût de roll-out des installations de départ le concerne. C'est voulu : l'espace est le prix de l'intégration verticale.
- La règle 3 est **la plus faible** des trois en jours. Sa force vient de son coût en crédits (voir la question 3).

## Règles

### R1. Carte du site, parcelles et terrain
- La carte d'un site est une grille de `map.width × map.height` cases. Les coordonnées sont entières, avec `x` vers la droite, `y` vers le bas et l'origine `(0, 0)` en haut à gauche. Une case est une unité abstraite (environ 20 m, donnée purement informative).
- **Terrain** (`map.terrain`) : une liste de rectangles `{kind, x, y, w, h}` avec `kind` ∈ `sea` | `road`. Il est cosmétique : aucune parcelle ne le recouvre, donc on ne peut jamais y construire.
- **Parcelles** (`map.lots`) : rectangles disjoints `{id, x, y, w, h, price}`. L'état stocke `owned_lots` (liste d'ids). Une case est **constructible** si elle appartient à une parcelle possédée.
- **Achat** : `buy_lot(lot_id)` à l'étape 1. Rejets, dans cet ordre : `unknown_lot`, `lot_owned`, `insufficient_funds`. Le prix est débité immédiatement. N'importe quelle parcelle non possédée peut être achetée, sans condition d'adjacence. Le terrain n'a pas d'entretien.
- **Rétrocompatibilité** : un site sans `map` (fixtures des phases 1 et 2) désactive toute la spec. `build` accepte alors l'absence de position, et R4 à R6 sont sans effet (roll-out = `rollout_days` de la spec 003, aucune zone, tout est desservi).

### R2. Emprise et placement
- Chaque type d'installation a une emprise `footprint: [w, h]` en cases.
- Une instance a une position `{x, y, rotation}`, où `x, y` désigne la case en haut à gauche **après rotation**. `rotation` ∈ {0, 1} : à 1, l'emprise devient `[h, w]` (rotation de 90°). Le rectangle occupé est `rect(instance) = {x, y, w', h'}`.
- Placement **valide** si toutes les cases du rectangle sont constructibles et si aucune n'est occupée par une autre instance, quel que soit son statut (`building` compris).
- Une installation peut être posée dans la zone de sécurité d'un pas (R5). Ce n'est pas interdit, c'est risqué (voir la question 1).

### R3. Commande `build` avec position
`build(facility_type, x, y, rotation)`. Rejets, dans cet ordre (ceux des specs 001 et 006, plus deux nouveaux avant les fonds) :
`not_buildable`, `max_count_reached`, `missing_prerequisite`, `out_of_bounds` (une case hors des parcelles possédées), `overlap` (champ `facility_id` : l'instance gênante de plus petit `id`), `insufficient_funds`.
Effet inchangé (spec 001, R2) : `build_cost` débité, instance créée en `building` avec `ready_day = day + build_days`, et sa position est enregistrée.

**Installations de départ** : leurs positions sont fixées dans les données de départ (`start.json` dans cette spec, puis le fichier de niveau de la spec 009). Elles sont créées `ready` au jour 0. Le validateur vérifie qu'elles sont dans les parcelles possédées au départ et qu'elles ne se chevauchent pas.

### R4. Distance entre installations
Une seule mesure, l'**écart** entre deux rectangles : le nombre de cases libres qui les séparent, en distance de Chebyshev.
```
gap_x = max(0, b.x − (a.x + a.w), a.x − (b.x + b.w))
gap_y = max(0, b.y − (a.y + a.h), a.y − (b.y + b.h))
gap(a, b) = max(gap_x, gap_y)
```
Deux installations qui se touchent (par un côté ou un coin) ont un écart de 0. Une rangée de cases libres entre elles donne 1. La sim expose `gap_cells(rect_a, rect_b)` et l'UI ne calcule rien.

### R5. Zone de sécurité du pas de tir
Paramètre du type `launch_pad` : `safety_radius_cells`. Une installation (autre que le pas lui-même) est **dans la zone** d'un pas si `gap(installation, pas) < safety_radius_cells`. La zone forme donc un anneau de `safety_radius_cells` cases autour de l'emprise du pas. Un autre pas peut se trouver dans la zone.

**R5a. Évacuation (étape 4).** Au début de l'étape 4, la sim dresse la liste des pas qui ont un tir avec `launch_day == day`, que ce tir soit reporté par la météo ensuite ou non : la décision de tirer a été prise, la zone est évacuée. Toute installation dans la zone de l'un de ces pas ne fait rien à l'étape 4 ce jour-là : aucun démarrage de job, aucun progrès, aucune livraison de sortie. La sim émet un événement `facility_evacuated` par installation et par jour, avec `facility_id` et `pad_id`. Un entrepôt évacué garde sa capacité.

**R5b. Dégâts en cas d'échec (étape 5).** Juste après la résolution d'un tir en échec (spec 003, R4), pour chaque installation dans la zone de ce pas, par `id` croissant :
- Une instance `ready` devient **endommagée** jusqu'au jour `day + damage_repair_days` (champ `damaged_until_day`, son statut reste `ready`). Le coût de réparation, `build_cost × damage_repair_cost_pct div 100`, est débité à l'étape 8 du même jour (`daily_costs.repair_costs`). Événement `facility_damaged` avec `facility_id`, `pad_id`, `repair_cost` et `until_day`.
- Une installation endommagée ne fait rien à l'étape 4 (comme une installation évacuée), elle ne dessert plus (R6) et elle continue de payer son entretien. Le staff reste affecté et peut être réaffecté (la commande `assign_staff` reste valide). Fin de la réparation à l'étape 3 : `facility_repaired`.
- Une instance `building` (en construction ou en déplacement) voit son `ready_day` repoussé de `damage_repair_days`, sans coût.
- **Lanceur détruit** : un lanceur situé dans un hall de la zone, ou posé sur un autre pas de la zone, est détruit (`launcher_destroyed` avec `launcher_id` et `facility_id`). Son tir planifié, s'il en a un, est annulé et le contrat redevient libre, sans tir. Un autre pas de la zone passe en remise en état longue (`refurb_days_after_failure`, sans le coût associé).
- Les tirs du même jour sont résolus par `id` croissant (spec 003, R3). Si un tir détruit le lanceur d'un tir suivant du même jour, ce dernier est annulé avant son tirage météo, et ne consomme donc aucun tirage.

### R6. Desserte par un entrepôt
Paramètres globaux : `service_radius_cells` et `unserved_productivity_pct`. Une installation dont le type a des `slots` (ateliers et hall) est **desservie** s'il existe un entrepôt `ready`, non endommagé, tel que `gap(installation, entrepôt) <= service_radius_cells`.
- À l'étape 4, le progrès d'une installation non desservie vaut `(min(assigned, slots) × productivity_per_slot × unserved_productivity_pct) div 100`. Le progrès d'une installation desservie ne change pas.
- La desserte se calcule à l'étape 4 sur l'état du jour. Elle n'émet pas d'événement quotidien, l'UI l'affiche.
- Le pas de tir n'a pas besoin d'être desservi.

### R7. Roll-out selon la distance
Le roll-out se calcule entre le hall où se trouve le lanceur et le pas visé :
- `rollout_days = rollout_base_days + gap(hall, pas) div rollout_cells_per_day`. Cette valeur remplace le `rollout_days` fixe de la spec 003, R2, dans le contrôle `too_early`. Un lanceur déjà sur le pas garde `launch_day >= day + 1`.
- `rollout_cost = rollout_cost_per_cell × gap(hall, pas)`, enregistré quand `schedule_launch` est accepté et débité à l'étape 8 du même jour (`daily_costs.rollout_costs`). Ce coût n'est pas remboursé si le tir est annulé ou reporté. Un lanceur déjà sur le pas ne paie rien.
- L'événement `launch_scheduled` reçoit en plus `rollout_days` et `rollout_cost`.

### R8. Déplacer et démolir
- `move_facility(facility_id, x, y, rotation)` à l'étape 1. Rejets, dans cet ordre : `unknown_facility`, `facility_busy`, `out_of_bounds`, `overlap` (l'instance elle-même ne compte pas), `storage_overflow`, `insufficient_funds`. Une installation est **occupée** (`facility_busy`) si elle a un job démarré, si c'est un hall qui contient un lanceur, ou si c'est un pas occupé, en remise en état ou visé par un tir planifié.
  - Coût : `build_cost × move_cost_pct div 100`, débité immédiatement.
  - L'instance garde son `id` et sa file de jobs non démarrés, et prend sa nouvelle position immédiatement. Elle passe en `building`, avec `ready_day = day + max(1, ceil(build_days × move_days_pct / 100))`. Son staff est désaffecté et rendu au pool. Comme pendant une construction (spec 001, R2), elle n'a ni entretien, ni capacité, ni production.
  - `storage_overflow` : déplacer ou démolir un entrepôt est rejeté si le stock total dépasse la capacité restante sans lui (champ `excess`).
- `demolish_facility(facility_id)` à l'étape 1. Rejets, dans cet ordre : `unknown_facility`, `facility_busy`, `storage_overflow`. Effet : remboursement de `build_cost × demolish_refund_pct div 100`, staff rendu au pool, jobs non démarrés supprimés, instance supprimée. Ses cases et sa place dans `max_count` sont libérées.
- Les installations de départ suivent les mêmes règles (elles utilisent le `build_cost` de leur type).
- Les prérequis (spec 006, R3) ne sont vérifiés qu'au moment de `build`. On peut démolir l'atelier d'usinage alors que l'atelier moteurs existe : celui-ci reste en service, il n'est simplement plus alimenté en turbopompes.

### R9. Requêtes (aucun calcul dans l'UI)
- `placement_check(facility_type, x, y, rotation)` renvoie `{valid, reason, rect, in_safety_zone_of: [pad_id], served: bool, rollout: [{pad_id, rollout_days, rollout_cost}]}`. Le champ `rollout` n'est rempli que pour un hall. Pour un pas, la requête renvoie aussi `zone_contains: [facility_id]`. Le bot comme l'UI (aperçu en mode construction) l'utilisent.
- `facility_spatial(facility_id)` renvoie `served`, `in_safety_zone_of`, `damaged_until_day` et `evacuated_today`.
- `lot_list()` : pour chaque parcelle, `id`, rectangle, `price` et `owned`.

## Données

### `sites.json` : carte du site `pointe_sternes`
Mer à l'est (lancements vers l'est, azimut 90°, cohérent avec la spec 003), route d'accès au sud.

| Élément | Valeur |
|---|---|
| `map.width` × `map.height` | 36 × 24 |
| `terrain` | `sea` `{x 32, y 0, w 4, h 24}` ; `road` `{x 0, y 23, w 32, h 1}` |

| Parcelle (`lots`) | x, y, w, h | Cases | `price` |
|---|---|---|---|
| `lot_start` | 8, 6, 20, 12 | 240 | 0 (possédée au départ) |
| `lot_west` | 0, 6, 8, 12 | 96 | 30 000 |
| `lot_north` | 0, 0, 28, 6 | 168 | 40 000 |
| `lot_south` | 0, 18, 28, 5 | 140 | 40 000 |
| `lot_coast` | 28, 0, 4, 23 | 92 | 35 000 |

### `facilities.json` (nouveaux champs)

| Type | `footprint` | Cases | Autres champs |
|---|---|---|---|
| `warehouse` | [4, 3] | 12 | – |
| `tank_shop` | [4, 3] | 12 | – |
| `composite_shop` | [3, 3] | 9 | – |
| `electronics_lab` | [3, 2] | 6 | – |
| `machine_shop` | [4, 3] | 12 | – |
| `engine_shop` | [5, 4] | 20 | – |
| `integration_hall` | [4, 6] | 24 | – |
| `launch_pad` | [4, 4] | 16 | `safety_radius_cells` 5 ; `rollout_days` (spec 003) reste pour les sites sans carte |

### `layout.json` (nouveau, règles spatiales globales)

| Paramètre | Valeur | Effet |
|---|---|---|
| `service_radius_cells` | 3 | R6 |
| `unserved_productivity_pct` | 70 | R6 : un atelier de 3 postes passe de 30 à 21 points par jour |
| `rollout_base_days` | 1 | R7 |
| `rollout_cells_per_day` | 6 | R7 : écart de 0 à 5 → 1 jour ; de 6 à 11 → 2 jours ; de 12 à 17 → 3 jours |
| `rollout_cost_per_cell` | 400 | R7 |
| `damage_repair_days` | 10 | R5b |
| `damage_repair_cost_pct` | 25 | R5b : 35 000 pour l'atelier moteurs, 22 500 pour un hall |
| `move_cost_pct` | 25 | R8 |
| `move_days_pct` | 50 | R8 : 8 jours pour un hall, 10 pour un pas |
| `demolish_refund_pct` | 20 | R8 |

### `start.json` (modifié)
- `owned_lots` : `["lot_start"]`.
- `facilities` devient une liste d'objets `{facility_type, x, y, rotation}` :

| Type | x, y, rotation | Rectangle occupé |
|---|---|---|
| `integration_hall` | 10, 8, 0 | x 10–13, y 8–13 |
| `warehouse` | 10, 14, 0 | x 10–13, y 14–16 (touche le hall : desservi) |
| `launch_pad` | 22, 10, 0 | x 22–25, y 10–13 |

- `assignments` reste inchangé (indexé par type, une seule instance de chaque au départ). La spec 009 déplacera ce fichier dans le fichier de niveau.

### Lecture de la carte de départ (repères pour la conception, pas des tests)
- Zone du pas de départ (rayon 5) : x 17–30, y 5–18. Elle couvre la moitié est de `lot_start`.
- Partie sûre de `lot_start` : x 8–17, soit 120 cases, moins le hall et l'entrepôt : **84 cases libres**, en morceaux (une bande de 4 de large en x 14–17, une de 2 de large en x 8–9, et 4 × 2 au-dessus du hall).
- Desserte par l'entrepôt de départ : x 7–17, y 11–20 environ. Les cases du haut de `lot_start` (y 6–9) sont en partie non desservies.
- On peut caser en sécurité, avec desserte, `tank_shop` et `machine_shop` (bande x 14–16). **L'atelier moteurs (5 × 4, même tourné) ne tient nulle part en zone sûre et desservie** : il faut choisir entre la zone, l'absence de desserte, ou `lot_west` (30 000), où il est desservi par l'entrepôt de départ (écart 2).
- *Vérifié par recherche exhaustive des placements (session principale, 2026-11-18). Avec un rayon de 4, l'atelier moteurs tourné tenait en x 14–17 avec la soudure, l'usinage et l'avionique : le dilemme n'existait pas. D'où le rayon de 5.*
- Roll-out de départ : écart hall ↔ pas = 8, donc 2 jours (comme aujourd'hui) et 3 200 par tir. Un hall placé juste hors de la zone (écart 4) : 1 jour et 1 600.
- **Impact sur l'équilibrage existant** : environ 16 tirs × 3 200, soit environ 51 000 de moins sur 240 jours pour toutes les stratégies, et un peu plus si un tir échoue près d'ateliers. Il faudra relancer `make balance` et recaler la spec 009.

### État (ajouts)
- `owned_lots: [lot_id]`.
- Par instance : `x`, `y`, `rotation` (null sans carte), `damaged_until_day` (−1 par défaut), `moving` (bool, pour l'affichage).
- `pending_rollout_costs: int` et `pending_repair_costs: int`, remis à 0 à l'étape 8.

### Schémas et validateur
- `sites.schema.json` : `map` optionnel (`width`, `height`, `terrain[]`, `lots[]`). `layout.schema.json` (nouveau) : tous les champs sont des entiers ≥ 0, les pourcentages sont dans [0, 100] et `rollout_cells_per_day` vaut au moins 1.
- `facilities.schema.json` : `footprint` (deux entiers ≥ 1), `safety_radius_cells` (entier ≥ 0).
- Le validateur vérifie que les parcelles sont dans la carte, disjointes et sans recouvrement avec le terrain. Si un site a une carte, chaque type d'installation doit avoir un `footprint`. Les installations de départ doivent être dans les parcelles possédées au départ, sans chevauchement, et `owned_lots` ne doit référencer que des parcelles existantes.

## Commandes et événements

| Commande | Args | Rejets |
|---|---|---|
| `build` (étendue) | `facility_type`, `x`, `y`, `rotation` | + `out_of_bounds`, `overlap` (avant `insufficient_funds`) |
| `buy_lot` | `lot_id` | `unknown_lot`, `lot_owned`, `insufficient_funds` |
| `move_facility` | `facility_id`, `x`, `y`, `rotation` | `unknown_facility`, `facility_busy`, `out_of_bounds`, `overlap`, `storage_overflow`, `insufficient_funds` |
| `demolish_facility` | `facility_id` | `unknown_facility`, `facility_busy`, `storage_overflow` |

| Événement | Étape | Champs |
|---|---|---|
| `facility_build_started` (étendu) | 1 | + `x`, `y`, `rotation` |
| `lot_bought` | 1 | `lot_id`, `cost` |
| `facility_move_started` | 1 | `facility_id`, `x`, `y`, `rotation`, `cost`, `ready_day` |
| `facility_demolished` | 1 | `facility_id`, `facility_type`, `refund` |
| `launch_scheduled` (étendu) | 1 | + `rollout_days`, `rollout_cost` |
| `facility_built` (réutilisé à la fin d'un déplacement) | 3 | + `moved` (bool) |
| `facility_repaired` | 3 | `facility_id` |
| `facility_evacuated` | 4 | `facility_id`, `pad_id` |
| `facility_damaged` | 5 | `facility_id`, `pad_id`, `repair_cost`, `until_day` |
| `launcher_destroyed` | 5 | `launcher_id`, `facility_id` |
| `daily_costs` (étendu) | 8 | + `rollout_costs`, `repair_costs` |

Aucun champ ne s'appelle `type` (`facility_demolished` utilise `facility_type`). **L'ordre de résolution ne change pas** : on ajoute des sous-étapes à 1, 3, 4, 5 et 8. La ligne « Implémenté » de `sim/CLAUDE.md` sera mise à jour par les issues concernées. Aucun nouvel aléa, donc aucun nouveau flux RNG.

## UI

### L'écran principal est la carte
- **Vue de dessus** de la carte entière : grille fine (`#1E3A52`), mer et route, parcelles possédées en sol plein, parcelles à vendre hachurées avec leur prix au survol. Zoom (2 niveaux) et défilement à la souris ou au clavier.
- **Barre du haut**, permanente : jour, saison, trésorerie, réputation, personnel (embauchés / affectés / libres, boutons Embaucher et Licencier), widget d'objectifs (spec 009), boutons « Fin de journée » et « Avancer ▸▸ ».
- **Clic sur une installation** : un panneau contextuel s'ouvre à droite. Son contenu reprend celui de la ligne de l'ancien onglet Installations : statut, techniciens `+`/`−`, job en cours, file, taux de rebut. S'y ajoutent les infos spatiales : « Desservie » ou « Non desservie : −30 % de cadence », « Dans la zone du pas n° 1 : évacuée les jours de tir », « Endommagée jusqu'au jour X ». Boutons Déplacer et Démolir, avec coût et durée affichés et une confirmation.
  - **Hall** : en plus, lanceur présent, recette d'assemblage, bouton « Planifier un tir » (le dialogue de la spec 003, enrichi des jours et du coût de roll-out vers chaque pas).
  - **Pas de tir** : statut (libre, occupé, en remise en état jusqu'au jour X), tir planifié. Sa zone de sécurité est toujours dessinée en pointillés `Danger` quand le pas est sélectionné ou qu'un tir est prévu aujourd'hui.
  - **Entrepôt** : sa capacité et le stock global (le stock reste global, spec 001), plus son rayon de desserte affiché en `Accent`.
- **Mode construction** : une barre de construction en bas, avec un bouton par type constructible (coût, durée, entretien ; types grisés avec la raison si `max_count` est atteint ou si un prérequis manque). Choisir un type fait apparaître un fantôme qui suit le curseur. `R` le fait pivoter. Le fantôme est vert si le placement est valide, rouge sinon (avec la raison). Pendant le placement, la sim superpose les zones de sécurité et les rayons de desserte, et une bulle résume le résultat de `placement_check` : « Desservie · Hors zone · Roll-out 1 j / 1 600 cr ». Un clic construit, `Échap` annule.
- **Parcelle à vendre** : clic → « Acheter la parcelle Ouest : 30 000 cr ».
- **Signes sur la carte** : chantier (échafaudage + « prête au jour X »), endommagée, évacuée aujourd'hui, non desservie, job bloqué, lanceur posé sur le pas ou dans le hall.

### Ce que deviennent les onglets
| Onglet actuel | Devient |
|---|---|
| Installations | **disparaît** : remplacé par les panneaux contextuels |
| Construction | **disparaît** : remplacé par la barre de construction et, pour le personnel, par la barre du haut |
| Lancement | **disparaît** en tant qu'onglet : le panneau du pas et celui du hall en reprennent le contenu, le calendrier passe dans l'Échéancier |
| Nomenclature | reste un **panneau global** (le kit L1 ne dépend pas d'un bâtiment), avec le comparateur acheter / fabriquer |
| Fournisseurs | reste un panneau global, renommé **Marché** (prix au comptant, pénuries, stock) |
| Appro. | reste un panneau global (contrats d'approvisionnement) |
| Contrats | reste un panneau global (tableau de contrats, réputation) |
| *(nouveau)* Échéancier | panneau global : calendrier de la spec 003 (saisons, dates limites, tirs) et `supply_schedule` de la spec 007 |
| *(nouveau)* Journal | rapport du jour et historique (aujourd'hui en bas d'écran) |

Les panneaux globaux s'ouvrent depuis une colonne d'icônes à gauche et se superposent à la carte sans la remplacer.

### Assets SVG pour `svg-artist`
Convention proposée : 1 case = 32 unités, et `viewBox` = emprise × 32. Les sprites de carte sont donc **rectangulaires**, ce qui contredit la règle actuelle « `viewBox` carré » (`assets/CLAUDE.md`, `STYLE.md`, `tools/lint_assets.py`). Voir la question 5. Les sprites sont dessinés à `rotation` 0 : l'UI les tourne. Couleurs d'accent : `#4FD1FF` (logistique), `#5BE49B` (production), `#FFB547` (lancement, voir la question 6).

| Fichier | Emprise (cases) | `viewBox` | Accent | Contenu |
|---|---|---|---|---|
| `map_warehouse.svg` | 4 × 3 | 0 0 128 96 | logistique | toit à pans, quais de chargement (reprendre `facility_warehouse.svg`) |
| `map_tank_shop.svg` | 4 × 3 | 0 0 128 96 | production | halle, deux réservoirs couchés |
| `map_composite_shop.svg` | 3 × 3 | 0 0 96 96 | production | halle, autoclave rond |
| `map_electronics_lab.svg` | 3 × 2 | 0 0 96 64 | production | bâtiment bas, toit à grille de modules |
| `map_machine_shop.svg` | 4 × 3 | 0 0 128 96 | production | halle, pont roulant |
| `map_engine_shop.svg` | 5 × 4 | 0 0 160 128 | production | grande halle, bancs de moteurs alignés |
| `map_integration_hall.svg` | 4 × 6 | 0 0 128 192 | lancement | très haut hangar, grande porte côté pas |
| `map_launch_pad.svg` | 4 × 4 | 0 0 128 128 | lancement | dalle, carneau, tour ombilicale |
| `map_launcher_l1.svg` | 1 × 2 | 0 0 32 64 | lancement | lanceur vu de dessus, posé sur le pas ou dans le hall |
| `tile_ground.svg` | 1 × 1 | 0 0 32 32 | – | sol possédé |
| `tile_lot_for_sale.svg` | 1 × 1 | 0 0 32 32 | – | sol hachuré, à vendre |
| `tile_sea.svg` | 1 × 1 | 0 0 32 32 | – | mer (lignes de houle fines) |
| `tile_shore.svg` | 1 × 1 | 0 0 32 32 | – | rivage (bord ouest de la mer) |
| `tile_road.svg` | 1 × 1 | 0 0 32 32 | – | route avec marquage |
| `overlay_construction.svg` | 1 × 1 (répété) | 0 0 32 32 | attention | échafaudage, posé en mosaïque sur l'emprise |
| `marker_damaged.svg` | icône | 0 0 64 64 | danger | |
| `marker_evacuated.svg` | icône | 0 0 64 64 | attention | |
| `marker_unserved.svg` | icône | 0 0 64 64 | attention | entrepôt barré |
| `marker_job_blocked.svg` | icône | 0 0 64 64 | attention | |
| `icon_lot.svg` | icône | 0 0 64 64 | logistique | bouton « acheter la parcelle » |

La zone de sécurité, le rayon de desserte et le fantôme de placement sont tracés par l'UI (rectangles et couleurs du `Theme`), sans asset.

## Critères d'acceptation
Fixtures (dans `tests/sim/fixtures.gd`) : site `t_site` avec une carte de 20 × 10, sans terrain, parcelles `A` (0, 0, 10, 10, possédée) et `B` (10, 0, 10, 10, `price` 1 000). Types : `wh` (entrepôt, `footprint` [2, 2], capacité 20, `build_cost` 100, `build_days` 1) ; `shop` (`footprint` [3, 1], 2 postes, productivité 10, `build_cost` 1 000, `build_days` 4, `max_count` 2) ; `hall` (`footprint` [2, 2], 2 postes, productivité 10, `launcher_capacity` 1, `build_cost` 2 000) ; `pad` (`footprint` [2, 2], `safety_radius_cells` 2, `build_cost` 4 000, `build_days` 4, fiabilité et météo paramétrables). `layout` : `service_radius_cells` 1, `unserved_productivity_pct` 50, `rollout_base_days` 1, `rollout_cells_per_day` 3, `rollout_cost_per_cell` 10, `damage_repair_days` 5, `damage_repair_cost_pct` 25, `move_cost_pct` 25, `move_days_pct` 50, `demolish_refund_pct` 20. Recette `weld` (`shop`, `steel ×1` → `tank ×1`, 20 points, sans rebut). Entretiens et salaires à 0, 10 000 crédits, sauf mention contraire.

1. **Placement et rotation** : `build("shop", 0, 0, 0)` est accepté et occupe x 0–2, y 0. `build("shop", 2, 0, 1)` → `overlap` (`facility_id` du premier). `build("shop", 8, 0, 0)` → `out_of_bounds` (la case x 10 est dans `B`, non possédée). `build("shop", 9, 0, 1)` est accepté : rotation 1, occupe x 9, y 0–2.
2. **Ordre des rejets** : 500 crédits, `build("shop", 0, 0, 0)` sur une case occupée → `overlap`, pas `insufficient_funds`. Sur une case libre → `insufficient_funds`. L'argent ne change pas dans les deux cas.
3. **Achat de parcelle** : `buy_lot("B")` → argent −1 000, `lot_bought` ; ensuite `build("shop", 8, 0, 0)` est accepté. Un second `buy_lot("B")` → `lot_owned`. `buy_lot("Z")` → `unknown_lot`.
4. **Sans carte, rien ne change** : site fixture de la phase 2 (sans `map`), `build("shop")` sans position est accepté, et tous les tests des specs 001 à 007 passent sans modification.
5. **Installations de départ** : `start` avec `owned_lots` `["A"]` et un `hall` en (0, 0, 0) → au jour 0, l'instance est `ready` en (0, 0) ; `build("shop", 1, 1, 0)` → `overlap`.
6. **Desserte** : `wh` prêt en (0, 0). `shop` prêt en (3, 0) (écart 1), avec 2 techniciens et `steel` 2 : un job `weld` se termine en 1 jour (20 points). Le même atelier en (4, 0) (écart 2, non desservi) : 10 points par jour, il faut 2 jours. On endommage l'entrepôt à la main (`damaged_until_day` = jour + 3) : l'atelier en (3, 0) passe à 10 points par jour pendant 3 jours.
7. **Roll-out** : `hall` en (0, 0) avec un lanceur, `pad` en (7, 0) (écart 5) : `rollout_days` = 1 + 5 div 3 = 2. `schedule_launch(..., launch_day = day + 1)` → `too_early` ; `day + 2` est accepté, `launch_scheduled` porte `rollout_days` 2 et `rollout_cost` 50, et l'argent baisse de 50 à l'étape 8 de ce jour (`daily_costs.rollout_costs` = 50). `pad` en (2, 0) (écart 0) : 1 jour, coût 0.
8. **Évacuation** : `pad` en (6, 0), `shop` en (2, 0) (x 2–4, écart 1 < 2 : dans la zone, desservi par un `wh` en (2, 1)). Un job `weld` démarré, avec 1 technicien (débit 10). Tir planifié au jour 3, puis reporté par la météo (scrub 1.0). → Le jour 3, aucun progrès et `facility_evacuated` (`pad_id`) ; aux jours 2 et 4, le job progresse normalement. Un atelier à l'écart 2 (hors de la zone) n'est jamais évacué.
9. **Dégâts après un échec** : même disposition, fiabilité 0, scrub 0, tir au jour 3. Un second `hall` dans la zone contient un lanceur `l1` sans tir. → Résolution du jour 3 : `launch_failed`, puis `facility_damaged` sur le `shop` (`repair_cost` 250, `until_day` 8), `facility_damaged` sur le `wh` et sur le `hall`, et `launcher_destroyed` pour le lanceur du hall. L'argent baisse de 250 + 25 + 500 en plus des coûts de la spec 003. Le `shop` ne progresse pas du jour 4 au jour 7, puis `facility_repaired` à la résolution du jour 7 et il reprend au jour 8. Une installation hors de la zone n'a ni dégât ni coût.
10. **Lanceur détruit sur un autre pas** : deux `pad` dans la zone l'un de l'autre, chacun avec un tir le même jour. Le tir d'`id` 1 échoue (fiabilité 0). → Le lanceur du second pas est détruit, son tir est annulé sans tirage météo, et son contrat reste `active` sans tir planifié.
11. **Déplacer** : `shop` prêt en (0, 0) avec 2 techniciens et un job non démarré. `move_facility(shop, 0, 5, 0)` → argent −250, l'instance est `building` avec `ready_day` = jour + 2, ses 2 techniciens sont libres, elle occupe x 0–2, y 5, et les cases d'origine sont libres (`build("shop", 0, 0, 0)` y est accepté). Après 2 jours : `facility_built` (`moved` vrai), même `id`, job toujours en file. Avec un job démarré → `facility_busy`.
12. **Démolir** : `shop` prêt avec `max_count` 2, deux instances. `demolish_facility` → remboursement de 200, `facility_demolished`, puis `build("shop", ...)` est de nouveau accepté. Un `wh` seul de capacité 20 avec 15 en stock → `storage_overflow` (`excess` 15). Un `hall` qui contient un lanceur → `facility_busy`.
13. **Requête de placement** : avec un `pad` en (6, 0) et un `wh` en (0, 0), `placement_check("shop", 2, 0, 0)` → `valid` vrai, `in_safety_zone_of` = [id du pad], `served` vrai (écart 0). `placement_check("hall", 2, 4, 0)` renvoie le roll-out vers ce pas.
14. **Déterminisme** : même seed et mêmes commandes, avec ou sans carte → mêmes tirages des flux `deliveries`, `weather`, `launch`, `production` et `market` (la spec n'ajoute aucun tirage). Seule exception attendue : un tir annulé par un lanceur détruit (critère 10) ne consomme pas ses tirages.

## Ce que `make balance` doit montrer
Le bot doit savoir placer. Deux **politiques de placement**, en paramètre du bot (et non de `data/`), toutes deux déterministes et fondées uniquement sur `placement_check` et `lot_list` :

- **`naive`** (premier emplacement libre) : parcourir les cases des parcelles possédées par `y` puis `x` croissants, avec la rotation 0 puis 1, et prendre le premier placement valide. Si aucun n'existe, acheter la parcelle la moins chère (à égalité, l'`id` le plus petit) dès que l'argent le permet, puis recommencer. Pas de déplacement, pas de démolition.
- **`careful`** : parmi tous les placements valides (les deux rotations), choisir selon un ordre lexicographique :
  1. hors de toute zone de sécurité (pour un pas : sa zone ne doit contenir aucune installation existante) ;
  2. desservi, si le type a des `slots` ;
  3. pour un hall, le coût de roll-out le plus faible vers le pas le plus proche ; pour un entrepôt, le plus grand nombre d'installations non desservies qu'il desservirait ;
  4. à égalité, `y`, `x`, puis `rotation` croissants.

  Si le meilleur placement viole le critère 1 ou 2, et qu'une parcelle à vendre permet un placement qui les respecte tous les deux, acheter d'abord la moins chère de ces parcelles, à condition que `money >= price + build_cost + reserve` (la `reserve` de la spec 006). Sinon, prendre le meilleur placement disponible.

Lancer `buy_all`, `workshop`, `integrate_staged` et `engines_only` avec les deux politiques (40 seeds, 240 jours). Métriques à ajouter au rapport, par stratégie et par politique : argent final médian et écart `careful` − `naive` en %, nombre d'incidents (échec de tir avec au moins une installation endommagée), coût total des réparations, jours-installations évacués, points de travail perdus faute de desserte, coût total du roll-out, parcelles achetées.

Comportement attendu :
- `integrate_staged` et `engines_only` : `careful` bat `naive` de **4 à 12 %** en médiane. En dessous de 2 %, l'espace est décoratif (renforcer `unserved_productivity_pct` ou `damage_repair_cost_pct`). Au-dessus de 20 %, le placement punit trop le débutant.
- `naive` subit au moins un incident sur **25 à 50 %** des seeds avec `integrate_staged`, et `careful` sur moins de 10 %.
- `careful` achète au moins une parcelle sur plus de 50 % des seeds avec `integrate_staged`. Sinon, la parcelle de départ est trop grande.
- `buy_all` : écart inférieur à 2 % (attendu, voir Honnêteté).
- Le coût moyen du roll-out reste sous 5 % des dépenses totales. Au-delà, c'est une taxe et non un choix.
- Rappel : ajouter le roll-out payant baisse l'argent de toutes les stratégies d'environ 50 000. Le rapport doit l'afficher par rapport à la référence actuelle.

## Hors périmètre
- Routes et réseaux à construire, convoyeurs, pipelines d'ergols, chemins et simulation de déplacements.
- Staff visible qui circule sur la carte (hors MVP, GDD §9).
- Décoration, végétation, objets sans effet.
- Agrandir une installation, amélioration sur place.
- Stock par entrepôt (le stock reste global).
- Règle d'accès route ou port pour les livraisons (écartée, voir ci-dessous).
- Plusieurs sites (spec 009 et phase 5).

### Pistes évaluées et écartées
- **Distance entrepôt ↔ route ou port, qui allonge les livraisons** : écartée. Les délais fournisseurs vont de 3 à 10 jours, avec des retards aléatoires et des pénuries (spec 007). Un jour de plus serait du bruit. La règle ferait aussi doublon avec la desserte : elle pousserait de même à regrouper les bâtiments, avec un effet plus faible et moins lisible. La route reste un décor.
- **Adjacence stricte atelier ↔ entrepôt** (se toucher) : remplacée par un rayon de desserte de 3 cases. L'adjacence stricte rend le placement trop contraint pour une grille de cette taille, et elle n'apporte pas plus de décisions.

## Questions pour Flavien
1. **Construire dans la zone de sécurité : permis ou interdit ?** Interdire est plus réaliste, mais la zone devient une simple case grisée : il n'y a plus de pari. *Recommandation : permis, avec évacuation et dégâts (R5). C'est la seule source de risque spatial, et c'est elle qui crée le dilemme de l'atelier moteurs.*
2. **Déplacer : payant ou gratuit ?** Dans Two Point, déplacer une pièce ne coûte presque rien. Ici, un déplacement gratuit annulerait toute décision de placement. *Recommandation : payant, 25 % du prix de construction et 50 % de la durée de construction. À réduire si les testeurs se sentent piégés par leurs premiers placements.*
3. **Roll-out : en jours seulement, ou aussi en crédits ?** En jours seulement, l'effet est presque nul : le hall est libéré dès la planification (spec 003, R2), donc un jour de roll-out en plus ne réduit pas la cadence. *Recommandation : jours et crédits (400 par case d'écart). Cela coûte environ 51 000 à toutes les stratégies sur 240 jours (à recaler).*
4. **Un échec de tir détruit-il le lanceur d'un hall situé dans la zone ?** C'est dramatique et lisible, mais très punitif (~83 000 de kit perdu). *Recommandation : oui. Le joueur a été averti au placement, et c'est l'argument qui éloigne le hall du pas.*
5. **Sprites de carte rectangulaires.** La règle actuelle impose un `viewBox` carré. *Recommandation : l'autoriser pour la catégorie `map_` (`viewBox` = emprise × 32), et garder le carré pour les icônes. C'est une modification de `assets/CLAUDE.md`, `STYLE.md` et `tools/lint_assets.py`, à faire dans l'issue assets.*
6. **Couleur d'accent « lancement ».** Le GDD prévoit une couleur par catégorie (logistique, production, lancement), mais la palette n'a que quatre couleurs d'accent, toutes déjà porteuses de sens. *Recommandation : utiliser `#FFB547` (Attention) pour le lancement sur la carte. Sinon, ajouter une couleur à la palette (le mieux, mais c'est une décision de style).*
7. **Rotation à 90°** : *Recommandation : oui (une touche, un booléen). Sans elle, l'atelier d'avionique ne rentre pas dans la bande de 2 cases et la carte de départ se résout moins bien.*
8. **Démolition** : remboursement de 20 %, et prérequis non vérifiés après la construction. *Recommandation : oui aux deux. C'est le plus simple, et démolir l'usinage sous l'atelier moteurs est une erreur que le joueur voit tout de suite.*

## Découpage en issues
Dépendances : 1 d'abord. 2 dépend de 1. 3 et 4 dépendent de 2 et sont indépendantes entre elles. 6 peut avancer seule dès la validation de la spec. 5 dépend de 2 à 4 et de 6 (des rectangles provisoires suffisent pour avancer sans 6). 7 dépend de 2 et 3.

1. **Données et schémas spatiaux** : `map` dans `sites.json` (tableaux « Carte » et « Parcelles »), `footprint` et `safety_radius_cells` dans `facilities.json`, nouveau `layout.json`, `start.json` modifié (`owned_lots`, installations avec position), schémas et contrôles du validateur (liste « Schémas et validateur »). `make validate` vert. Valeurs externes : la liste des 8 types d'installation existants (`data/facilities.json`). Modèle : **haiku**.
2. **Modèle spatial dans la sim** : chargement de la carte et des parcelles dans `GameData`, position des instances, `build` avec position et les rejets `out_of_bounds` et `overlap` à leur place, `buy_lot`, création des installations de départ positionnées, `gap_cells`, requêtes `placement_check` (sans les champs des règles R5 à R7, ajoutés par l'issue 3), `lot_list`. Rétrocompatibilité sans carte. Critères 1 à 5 et 13 (partie validité). Valeurs externes : l'ordre des rejets de `build` est `not_buildable`, `max_count_reached`, `missing_prerequisite` (specs 001 R2 et 006 R3), puis les deux nouveaux, puis `insufficient_funds`. Modèle : **sonnet**.
3. **Règles de distance** : desserte R6 (étape 4), roll-out R7 (`schedule_launch`, étape 8), zone R5 (évacuation à l'étape 4, dégâts et lanceurs détruits à l'étape 5, fin de réparation à l'étape 3), champs correspondants de `placement_check` et `facility_spatial`, `daily_costs` étendu, mise à jour de `sim/CLAUDE.md`. Critères 6 à 10, 13 et 14. Valeurs externes : à l'étape 4 (spec 001 R5), instances par `id` croissant, `progress += min(assigned, slots) × productivity_per_slot` ; tirs de l'étape 5 par `id` croissant, météo puis fiabilité (spec 003 R3) ; contrôle `too_early` actuel : `launch_day < day + rollout_days` si le lanceur est dans le hall, `launch_day < day + 1` s'il est déjà sur le pas (spec 003 R2) ; remise en état longue = `refurb_days_after_failure` (spec 003 R5). Modèle : **opus** (beaucoup d'interactions entre étapes), ou **sonnet** si les tests sont écrits d'abord.
4. **Déplacer et démolir** : `move_facility`, `demolish_facility`, définition de `facility_busy`, `storage_overflow`, fin de déplacement à l'étape 3. Critères 11 et 12. Valeurs externes : une instance `building` n'a ni entretien, ni capacité, ni jobs, ni staff (spec 001 R2) ; les prérequis ne sont vérifiés qu'au `build` (spec 006 R3). Modèle : **sonnet**.
5. **UI : la carte devient l'écran principal** : rendu de la grille, du terrain et des parcelles, sprites (ou rectangles provisoires), barre du haut, panneaux contextuels (contenu de l'ancien onglet Installations, du pas et du hall), mode construction avec fantôme, rotation et superpositions issues de `placement_check`, achat de parcelle, Déplacer et Démolir, colonne de panneaux globaux, suppression des onglets Installations, Construction et Lancement, nouveaux panneaux Échéancier et Journal. Aucune règle côté UI. Valeurs externes : aucune (tout passe par les requêtes R9). Modèle : **opus** pour la structure de la scène, ou **sonnet** si on la découpe en deux (carte et construction, puis panneaux).
6. **Assets de carte** (agent `svg-artist`) : les 20 fichiers du tableau « Assets SVG », selon `assets/src/STYLE.md`, plus l'assouplissement de la règle `viewBox` pour `map_` dans `assets/CLAUDE.md`, `STYLE.md` et `tools/lint_assets.py`, si la question 5 est validée. `make assets` vert. Valeurs externes : les emprises du tableau. Modèle : **sonnet**.
7. **Bot : politiques de placement et rapport** : `naive` et `careful` dans `tests/balance_bot.gd` (algorithmes de la section « Ce que `make balance` doit montrer »), branchées sur toutes les stratégies qui construisent, et métriques du rapport. Valeurs externes : `reserve` = coût de 2 kits L1 achetés, calculé depuis `data/` (spec 006) ; ordre de construction de `integrate_staged` : `tank_shop`, `machine_shop`, `engine_shop`, `electronics_lab`, `composite_shop` (spec 006). Modèle : **sonnet**.

# 001 — Nomenclature, fabrication et assemblage du lanceur L1
Statut : validée (2026-11-13)

## Intention joueur
Le joueur doit transformer des achats en un lanceur prêt à partir. Deux dilemmes :

1. **Acheter ou fabriquer les réservoirs.** Acheter un réservoir fini est immédiat à planifier mais cher et soumis aux retards du fournisseur. Construire un atelier de soudure coûte cher d'entrée, mobilise des techniciens et de la place en entrepôt, puis divise le coût unitaire par ~5. Le joueur doit décider *quand* investir : trop tôt, l'investissement affame la trésorerie du premier lanceur ; trop tard, il paie des réservoirs chers pendant des mois.
2. **Où mettre ses techniciens.** Le personnel est un pool commun, payé qu'il travaille ou non. Les affecter à l'atelier accélère les réservoirs mais ralentit l'assemblage, et inversement. Embaucher augmente le débit et la masse salariale.

La place en entrepôt (déjà implémentée) devient une contrainte réelle : un kit complet de L1 occupe plus de la moitié de l'entrepôt de départ, on ne peut pas stocker deux kits d'avance sans agrandir.

## Conventions de temps (rappel, valables pour les 3 specs)
- Le joueur agit pendant le jour J (étape 1). La résolution du jour J (`end_day`) fait ensuite passer à J+1.
- Un fait daté « disponible au jour X » (livraison, fin de construction, fin de job) est traité pendant la résolution du jour X−1 et visible au début du jour X. C'est la convention actuelle des livraisons (`arrival_day`).
- **L'ordre de résolution fait foi** : ce qui est produit à une étape est utilisable par les étapes suivantes de la même résolution (une livraison reçue à l'étape 2 peut être consommée à l'étape 4 le même soir).
- Toutes les durées « à plein régime » ci-dessous se lisent : job lancé le jour J, durée k jours → produit disponible au début du jour J+k.

## Règles

### R1. Nomenclature du lanceur L1 (plate)
Le lanceur L1 est assemblé en une seule opération à partir de :

| Composant | id | Quantité par L1 | Achetable | Fabricable |
|---|---|---|---|---|
| Moteur | `engine` | 4 (3 étage 1 + 1 étage 2) | oui | non (phase 2) |
| Réservoir | `tank` | 2 | oui | oui (atelier de soudure) |
| Avionique | `avionics` | 2 | oui | non |
| Coiffe | `fairing` | 1 | oui | non |
| Tôles d'acier (matière) | `steel_sheet` | 0 (entrée de la recette `weld_tank`) | oui | non |

La nomenclature est une **recette** (R3) dont la sortie est un lanceur, pas un composant. Pas d'étages intermédiaires en phase 2 (voir Questions).

### R2. Installations instanciées et construction minimale
- L'état ne stocke plus une liste d'ids de types mais des **instances** : `{id: int, type: String, status: "building"|"ready", ready_day: int, assigned: int, jobs: [...]}`. Deux entrepôts = deux instances.
- Commande `build(facility_type)` : rejetée si le type n'est pas `buildable`, si `max_count` est atteint (instances `building` comprises) ou si `build_cost > money`. Sinon, `build_cost` est débité immédiatement, l'instance est créée en `building` avec `ready_day = day + build_days`.
- Étape 3 : une instance `building` dont `ready_day <= day + 1` passe en `ready` (événement `facility_built`).
- Une instance en `building` : pas d'entretien, pas de capacité de stockage, pas de jobs, pas de staff.
- Pas de grille, pas d'emprise, pas de démolition en phase 2.

### R3. Recettes
Une recette = `{id, facility_type, inputs: {component_id: qty}, output, work_points}` où `output` est soit `{component_id, quantity}`, soit `{launcher_model}`.
- `weld_tank` : atelier `tank_shop`, entrées `steel_sheet ×4`, sortie `tank ×1`, `work_points = 60`.
- `assemble_l1` : hall `integration_hall`, entrées `engine ×4, tank ×2, avionics ×2, fairing ×1`, sortie lanceur `l1`, `work_points = 200`.

### R4. Staff abstrait : techniciens
- Un seul métier en phase 2 : `technician`. L'état stocke `technicians_hired` (int) et, par instance d'installation, `assigned` (int).
- `hire(count)` : rejetée si `count <= 0`, si `technicians_hired + count > max_technicians`, ou si `count × hire_cost > money`. Débit immédiat de `count × hire_cost`.
- `fire(count)` : rejetée si `count > technicians_hired − total_assigned` (il faut désaffecter d'abord). Coût `fire_cost` par tête, débit immédiat.
- `assign_staff(facility_id, count)` : **fixe** (et non ajoute) le nombre affecté. Rejetée si l'instance n'est pas `ready`, si son type n'a pas de `slots`, si `count > slots`, ou si le total affecté dépasserait `technicians_hired`.
- Étape 8 : salaires `technicians_hired × technician_salary_per_day`, affectés ou non.

### R5. Jobs de production (étape 4)
- `queue_job(facility_id, recipe_id, count)` : ajoute `count` jobs en fin de file de l'instance. Rejetée si l'instance n'est pas `ready`, si `recipe.facility_type != instance.type`, si `count <= 0`, ou si la file dépasserait `max_queue_length`. Rien n'est consommé à la mise en file.
- `cancel_job(job_id)` : seulement un job **non démarré**. Un job démarré ne s'annule pas en phase 2.
- Étape 4, instances traitées par `id` croissant (ordre déterministe pour la concurrence sur le stock). Pour chaque instance `ready` :
  1. Si le job de tête n'est pas démarré : vérifier que **toutes** les entrées sont en stock et, si la sortie est un lanceur, que le hall a une place libre (`launcher_capacity`). Si oui, consommer les entrées, marquer démarré (`job_started`). Sinon `job_blocked` avec `reason` (`missing_inputs` + la liste des manquants, ou `hall_occupied`), émis seulement le premier jour du blocage.
  2. Si le job de tête est démarré : `progress += min(assigned, slots) × productivity_per_slot`. Avec 0 technicien, aucun progrès (pas d'événement quotidien, l'UI affiche « à l'arrêt »).
  3. Si `progress >= work_points` : livrer la sortie. Composant → stock, si la capacité d'entrepôt le permet, sinon `output_blocked` (le job reste en tête, l'installation est bloquée, retentative chaque jour). Lanceur → nouvelle entité dans `state.launchers` (`{id, model, location_facility_id}`), événement `launcher_assembled`. Le surplus de progrès est perdu.
- **Au plus un job terminé par instance et par jour** : le job suivant démarre à la résolution suivante. Durée d'un job = `ceil(work_points / débit)` jours, minimum 1.
- Les entrées consommées libèrent la place en entrepôt dès le démarrage.

### R6. Lanceurs dans le hall
- Un lanceur assemblé occupe une place du hall (`launcher_capacity`, 1 par défaut) jusqu'à son transfert vers un pas de tir (spec 003). Tant que le hall est plein, l'assemblage suivant est bloqué (`hall_occupied`).
- Les lanceurs n'occupent pas l'entrepôt.

### R7. Achat de composants finis
Aucune règle nouvelle : la commande `order` existante suffit, il faut seulement ajouter les composants et fournisseurs dans `data/`.

## Données

### Paramètres et valeurs initiales proposées

`components.json` (ajouts ; `steel_sheet` existe déjà : 500 kg, 1 unité)

| id | mass_kg | storage_units |
|---|---|---|
| `tank` | 1 500 | 10 |
| `engine` | 900 | 6 |
| `avionics` | 80 | 1 |
| `fairing` | 600 | 12 |

Kit complet L1 acheté = 4×6 + 2×10 + 2×1 + 12 = **58 unités** sur 100.

`suppliers.json` (ajouts, noms fictifs)

| id | composant | unit_price | lead_time_days | delay_chance | delay_days |
|---|---|---|---|---|---|
| `brannoc_propulsion` | `engine` | 12 000 | 10 | 0.2 | 4 |
| `halvard_tanks` | `tank` | 9 000 | 6 | 0.15 | 3 |
| `vey_avionique` | `avionics` | 6 000 | 5 | 0.05 | 1 |
| `corrandi_composites` | `fairing` | 5 000 | 7 | 0.1 | 2 |

Un seul fournisseur de moteurs : dépendance volontaire (c'est le composant critique en délai).

`facilities.json` (nouveaux champs : `buildable`, `build_cost`, `build_days`, `max_count`, `slots`, `productivity_per_slot`, `launcher_capacity`)

| id | upkeep_per_day | build_cost | build_days | max_count | slots | productivity_per_slot | autre |
|---|---|---|---|---|---|---|---|
| `warehouse` | 400 | 25 000 | 6 | 3 | – | – | `storage_capacity` 100 |
| `tank_shop` | 300 | 40 000 | 10 | 1 | 3 | 10 | – |
| `integration_hall` | 800 | 90 000 | 15 | 2 | 4 | 10 | `launcher_capacity` 1 |

`recipes.json` (nouveau) : `weld_tank`, `assemble_l1` comme en R3.

`staff.json` (nouveau) : `technician` → `hire_cost` 1 000, `fire_cost` 500, `technician_salary_per_day` 150, `max_technicians` 20. Global : `max_queue_length` 5.

`start.json` (modifié) : `money` 200 000, `facilities` : liste de types créés `ready` au jour 0 (`warehouse`, `integration_hall`, `launch_pad`), `technicians` 4, `assignments` `{"integration_hall": 4}`.

### Ordres de grandeur visés (pour `make balance`, pas des tests)
- Réservoir acheté : 9 000. Réservoir fabriqué : 4 × 180..260 = 720..1 040 de matière + ~900 de main-d'œuvre (3 techniciens × 2 jours × 150) ≈ **1 600 à 1 950**.
- Économie ≈ 14 000 par lanceur, moins l'entretien de l'atelier (300/jour) → **rentabilisé vers le 3e à 5e lanceur**.
- Assemblage avec 4 techniciens : 200 / 40 = 5 jours. Kit acheté : 83 000 par L1.

### Schémas
- `facilities.schema.json` : ajouter les champs ci-dessus (tous optionnels sauf `upkeep_per_day`, entiers ≥ 0).
- Nouveaux `recipes.schema.json`, `staff.schema.json`. Le validateur doit vérifier les références croisées (`facility_type`, `component_id`, `launcher_model` existent).
- `start.schema.json` : `facilities` reste une liste d'ids de types, ajout de `technicians` et `assignments`.

## Commandes et événements

| Commande | Args | Rejets (`command_rejected.reason`) |
|---|---|---|
| `build` | `facility_type` | `not_buildable`, `max_count_reached`, `insufficient_funds` |
| `hire` | `count` | `invalid_quantity`, `max_technicians`, `insufficient_funds` |
| `fire` | `count` | `invalid_quantity`, `staff_assigned` |
| `assign_staff` | `facility_id`, `count` | `unknown_facility`, `facility_not_ready`, `no_slots`, `too_many_for_slots`, `not_enough_staff` |
| `queue_job` | `facility_id`, `recipe_id`, `count` | `unknown_facility`, `facility_not_ready`, `wrong_facility`, `invalid_quantity`, `queue_full` |
| `cancel_job` | `job_id` | `unknown_job`, `job_started` |

| Événement | Étape | Champs |
|---|---|---|
| `facility_build_started` | 1 | `facility_id`, `type`, `cost`, `ready_day` |
| `staff_hired` / `staff_fired` / `staff_assigned` | 1 | `count`, `cost` / `facility_id` |
| `job_queued` / `job_cancelled` | 1 | `job_id`, `facility_id`, `recipe_id` |
| `facility_built` | 3 | `facility_id`, `type` |
| `job_started` | 4 | `job_id`, `facility_id`, `consumed` |
| `job_blocked` | 4 | `job_id`, `reason`, `missing` |
| `job_completed` | 4 | `job_id`, `output` |
| `output_blocked` | 4 | `job_id`, `facility_id` |
| `launcher_assembled` | 4 | `launcher_id`, `model`, `facility_id` |
| `daily_costs` (étendu) | 8 | `upkeep`, `salaries` |

## UI
Rectangles et listes, aucune règle côté UI.
- **Panneau Installations** : une ligne par instance (type, statut, « prête au jour X » si en construction, techniciens affectés / postes, job en cours avec barre de progression et jours restants estimés, file d'attente). Boutons `+`/`−` de techniciens, « Ajouter un job » (liste des recettes de ce type), « Annuler » sur les jobs non démarrés.
- **Panneau Construire** : types `buildable` avec coût, durée, entretien/jour, nombre restant.
- **Panneau Personnel** : embauchés, affectés, libres, coût salarial/jour, boutons Embaucher / Licencier.
- **Nomenclature L1** : pour chaque composant, quantité requise, en stock, en commande ; marqueur rouge sur ce qui manque. C'est l'outil principal du joueur pour décider quoi commander.
- **Comparateur acheter / fabriquer** sur le réservoir : prix fournisseur et délai vs coût matière estimé et durée à l'affectation courante (calcul fourni par une requête de la sim, pas par l'UI).
- Rapport du jour : jobs terminés, bloqués (avec la raison), installations terminées.

## Critères d'acceptation
Fixtures (dans `tests/sim/fixtures.gd`, pas `data/`) : composant `steel` (1 unité), `tank` (2 unités), `engine` (1 unité) ; entrepôt capacité 20 ; type `shop` (3 postes, productivité 10, `build_cost` 1 000, `build_days` 3, `max_count` 1, entretien 0) ; type `hall` (2 postes, productivité 10, `launcher_capacity` 1) ; recette `weld` (`shop`, `steel ×2` → `tank ×1`, 20 points) ; recette `assemble` (`hall`, `tank ×1 + engine ×1` → lanceur `l1`, 20 points) ; `hire_cost` 100, salaire 10/jour.

1. **Construction** : état avec 10 000 crédits ; `build("shop")` au jour 0. → argent −1 000 immédiatement ; après 2 jours l'instance est `building` ; après 3 jours elle est `ready` et `facility_built` a été émis une fois.
2. **Construction rejetée** : `max_count` 1, une instance `shop` en `building` ; `build("shop")` → `command_rejected` `max_count_reached`, argent inchangé.
3. **Durée d'un job à plein régime** : `shop` prêt, 2 techniciens affectés (débit 20), `steel` 2 en stock ; `queue_job(shop, "weld", 1)` au jour 0. → après 1 jour : `tank` = 1, `steel` = 0, événements `job_started` puis `job_completed`.
4. **Durée proportionnelle au staff** : même état avec 1 technicien (débit 10). → après 1 jour : `tank` = 0, `steel` = 0 (consommé au démarrage) ; après 2 jours : `tank` = 1.
5. **Aucun progrès sans staff** : 0 technicien affecté, job démarré. → après 5 jours : progrès 0, `tank` = 0.
6. **Entrées manquantes** : `steel` = 1 ; `queue_job(shop, "weld", 1)`. → après 1 jour : `job_blocked` `missing_inputs` (`steel` manque 1), `steel` toujours 1 ; `order` de 1 `steel` livré au jour 3 → le job démarre pendant la résolution du jour 2 et `tank` = 1 au jour 3 (avec débit 20). `job_blocked` n'est émis qu'une fois.
7. **File et un job par jour** : débit 30, `steel` 4, `queue_job(shop, "weld", 2)`. → après 1 jour `tank` = 1 ; après 2 jours `tank` = 2.
8. **Sortie bloquée par l'entrepôt plein** : entrepôt 20/20 (`steel` 20), 1 technicien (débit 10, job de 2 jours), une commande de 2 `steel` qui arrive au jour 2 ; `queue_job(shop, "weld", 1)` au jour 0. → jour 0 : le job démarre, l'entrepôt passe à 18/20 ; résolution du jour 1 : la livraison remplit l'entrepôt (étape 2) puis le job termine (étape 4) sans place → `output_blocked`, job toujours en tête, `tank` = 0. Puis `queue_job` d'un second `weld` : il ne démarre pas tant que le premier est bloqué. Si on retire du stock 2 unités (fixture : état modifié à la main), la sortie est livrée à la résolution suivante.
9. **Assemblage → lanceur** : `hall` prêt, 2 techniciens, `tank` 1 + `engine` 1 ; `queue_job(hall, "assemble", 1)`. → après 1 jour : `state.launchers` contient 1 lanceur `l1` situé dans ce hall, stock vide, `launcher_assembled` émis.
10. **Hall occupé** : un lanceur déjà dans le hall, kit en stock, `queue_job(hall, "assemble", 1)`. → après 3 jours : `job_blocked` `hall_occupied` émis une fois, stock intact, toujours 1 lanceur.
11. **Salaires** : 3 techniciens embauchés (1 affecté). → après 4 jours, argent = initial − 4 × (entretien + 3 × 10).
12. **Rejets staff** : 2 embauchés, 2 affectés ; `fire(1)` → `staff_assigned`. `assign_staff(shop, 4)` → `too_many_for_slots`. `assign_staff(shop, 3)` avec 2 embauchés → `not_enough_staff`.
13. **Ordre de traitement** : deux instances consommant le même composant, stock pour un seul job → l'instance d'`id` le plus petit démarre, l'autre est bloquée. Même seed, même résultat.

## Hors périmètre
- Étages intermédiaires, sous-assemblages multi-niveaux.
- Qualité / taux de défaut des pièces, provenance des pièces influençant la fiabilité.
- Fabrication des moteurs, de l'avionique, de la coiffe.
- Ergols et évaporation (étape 9).
- Grille de construction, emprise, déplacement, démolition, amélioration d'installation.
- Métiers multiples, compétence, fatigue, moral, formation (étape 6).
- Banc d'essai.

## Décisions (validées par Flavien le 2026-11-13)
Toutes les recommandations ci-dessous sont retenues.
1. **Nomenclature plate ou par étages ?** Recommandation : **plate** en phase 2. Les étages ajoutent un niveau de recette sans nouveau dilemme ; on les introduira si l'assemblage paraît trop « une seule barre de progression ».
2. **Staff : pool de techniciens affectables, ou postes toujours pourvus et inclus dans l'entretien ?** Recommandation : **pool affectable** (`hire`/`assign_staff`). C'est le seul arbitrage de staff de la phase 2 et c'est l'ADN Two Point ; sans lui, l'atelier est une pure dépense passive. Coût : 3 commandes simples.
3. **Construction minimale (`build`) dans cette spec ?** Elle est indispensable au « réinvestir » et au dilemme acheter/fabriquer, mais elle déborde le titre. Recommandation : **la garder ici**, sans grille, et faire une spec dédiée à la construction spatiale en phase 3.
4. **Annuler un job démarré** : rembourser les entrées, les perdre, ou interdire ? Recommandation : **interdire** en phase 2 (moins de cas limites).
5. **Ergols** : les inclure dès la phase 2 (achat avant le tir, évaporation) ? Recommandation : **non**, sauf si le playtest montre que la phase pré-lancement manque de tension ; c'est le meilleur candidat pour une spec 004.
6. **Changement de structure de `state.facilities`** (ids → instances) : c'est un changement de modèle d'état qui touche le code de la phase 1. À acter par l'architecte (ADR ou simple note dans l'issue ?). Recommandation : une note dans l'issue suffit, l'ADR 0002 n'est pas remis en cause.

## Découpage en issues
Dépendance : l'issue 1 est un prérequis des issues 2 et 3 ; 4 et 5 peuvent avancer en parallèle sur la base de la spec.

1. **Instances d'installations + commande `build` + étape 3** — refactor `state.facilities`, `new_game` depuis `start.json`, stockage calculé sur les instances `ready`, critères 1-2, tests de phase 1 toujours verts. Modèle : **sonnet**.
2. **Techniciens : `hire` / `fire` / `assign_staff` + salaires à l'étape 8** — critères 11-12. Modèle : **sonnet**.
3. **Recettes et jobs : `queue_job` / `cancel_job` + étape 4 + entité lanceur dans le hall** — extension de `GameData` (recettes), critères 3-10 et 13. Modèle : **sonnet** (opus si la revue montre des cas limites mal couverts).
4. **Données et schémas** — `recipes.json`, `staff.json`, ajouts dans `components`/`suppliers`/`facilities`/`start`, schémas et références croisées dans le validateur, `make validate` vert. Modèle : **haiku**.
5. **UI rectangles** — panneaux Installations, Construire, Personnel, Nomenclature L1, comparateur acheter/fabriquer (requête sim). Modèle : **sonnet**.

# 006 — Intégration verticale : fabriquer moteurs, avionique et coiffe
Statut : validée (2026-11-14)

## Intention joueur
Retour du playtest : « la boucle tient 40 tours, après c'est bof ». Selon le bot, une fois le kit L1 maîtrisé, plus aucune décision ne compte. L'atelier de soudure rapporte environ 130 000 sur 240 jours, et le délai moteur (10 jours, un seul fournisseur) reste le facteur limitant.

Cette spec transforme « acheter ou fabriquer » en **progression étalée sur la partie** : quatre nouveaux ateliers, des investissements croissants, et un atelier qui en débloque un autre. Le goulot se déplace au fil de la partie : d'abord le moteur acheté (délai), puis la cadence de l'atelier moteurs, puis le hall et le pas de tir, enfin les techniciens et la trésorerie.

Dilemmes :
1. **Dans quel ordre investir.** Chaque atelier a son profil. Le réservoir est rentable vite. La coiffe coûte peu, mais rapporte peu. L'avionique est rentable à moyen terme. Le moteur rapporte le plus, mais il coûte le plus cher et il exige d'abord un atelier d'usinage. Il est impossible de tout acheter au départ (305 000 pour les quatre ateliers, contre 200 000 de trésorerie initiale).
2. **Quand investir : la montée en cadence.** Un atelier neuf produit beaucoup de rebuts, et son taux de rebut baisse à chaque pièce tentée. Investir tôt, c'est payer la courbe d'apprentissage pendant que la trésorerie est fragile. Investir tard, c'est la payer au moment où l'on a besoin des pièces.
3. **Fabriquer tout ou une partie.** Un atelier moteurs à plein régime sort environ 4 moteurs en 12 jours, juste ce qu'il faut pour un lanceur, et moins pendant la montée en cadence. Le mix naturel est « je fabrique 2 ou 3 moteurs, j'achète le reste », pas « tout ou rien ».
4. **Où mettre les techniciens** (spec 001). Chaque atelier ajoute des postes. Un technicien affecté à l'usinage n'assemble pas, et à pleine intégration l'arbitrage se fait entre ateliers.

Contreparties qui empêchent « tout fabriquer » d'être strictement dominant :
- **Capital immobilisé** : coût de construction, matières achetées d'avance, encours.
- **Coûts fixes** : un atelier coûte son entretien chaque jour, qu'il produise ou non. S'il tourne au ralenti (peu de contrats, échec de tir), il coûte plus cher que l'achat.
- **Rebuts** : une pièce rebutée fait perdre ses matières et sa main-d'œuvre. C'est surtout vrai en début de vie de l'atelier.
- **Cadence plafonnée** : `max_count` 1 par atelier, donc au-delà d'environ 1 lanceur par 12 jours, il faut de toute façon acheter.
- **Horizon** : l'atelier moteurs se rentabilise en environ 11 lanceurs. Construit trop tard, il ne se rembourse pas.

## Règles

### R1. Nouvelles matières premières et pièce intermédiaire
Liste courte : trois matières et une pièce intermédiaire.

| id | Nom | Rôle | Achetable | Fabricable |
|---|---|---|---|---|
| `alloy_billet` | Lingots de superalliage | entrée des turbopompes et des moteurs | oui | non |
| `electronic_kit` | Lot de composants électroniques | entrée de l'avionique | oui | non |
| `composite_roll` | Rouleau de fibre composite préimprégnée | entrée de la coiffe | oui | non |
| `turbopump` | Turbopompe | pièce intermédiaire du moteur | **non** | oui (atelier d'usinage) |

La turbopompe n'est pas achetable : c'est ce qui donne son sens au prérequis R3 (voir Questions).

### R2. Recettes
Le format est celui de la spec 001 (R3), avec trois champs optionnels pour le rebut (R4).

| id | Installation | Entrées | Sortie | `work_points` |
|---|---|---|---|---|
| `machine_turbopump` | `machine_shop` | `alloy_billet ×2` | `turbopump ×1` | 60 |
| `build_engine` | `engine_shop` | `turbopump ×1, alloy_billet ×2` | `engine ×1` | 100 |
| `wire_avionics` | `electronics_lab` | `electronic_kit ×3` | `avionics ×1` | 50 |
| `layup_fairing` | `composite_shop` | `composite_roll ×3` | `fairing ×1` | 60 |

Les règles de jobs de la spec 001 (R5) s'appliquent sans changement : file d'attente, entrées consommées au démarrage, au plus un job terminé par instance et par jour, sortie bloquée si l'entrepôt est plein.

### R3. Prérequis de construction
- Nouveau champ optionnel d'un type d'installation : `requires_facilities` (liste de types). La commande `build(facility_type)` est rejetée avec `missing_prerequisite` s'il n'existe pas, pour **chacun** des types listés, au moins une instance `ready`. Une instance `building` ne compte pas.
- Le contrôle se fait **avant** le contrôle des fonds. Ordre des rejets : `not_buildable`, `max_count_reached`, `missing_prerequisite`, `insufficient_funds`.
- Valeur initiale : `engine_shop.requires_facilities = ["machine_shop"]`. Les autres ateliers n'ont pas de prérequis.
- Pas de démolition (spec 001). Un prérequis satisfait le reste donc pour toujours.

### R4. Rebut et montée en cadence
- Une recette peut avoir trois paramètres : `scrap_rate_start`, `scrap_rate_floor` et `scrap_rate_drop_per_attempt` (probabilités, valeurs par défaut 0 : pas de rebut).
- L'état stocke `recipe_attempts: {recipe_id: int}`, le nombre de jobs de cette recette arrivés au contrôle qualité depuis le début de la partie, **rebutés compris** : on apprend aussi de ses rebuts.
- Taux courant : `scrap_rate(r) = max(scrap_rate_floor, scrap_rate_start − scrap_rate_drop_per_attempt × recipe_attempts[r])`.
- **Contrôle qualité**, étape 4. Quand un job atteint `progress >= work_points` pour la première fois, la sim tire `rng < scrap_rate(r)` dans le flux dédié `&"production"` (ADR 0005 : nouveau sous-système, nouveau flux), puis incrémente `recipe_attempts[r]`.
  - Rebut : la sortie est perdue (les entrées l'étaient déjà, consommées au démarrage), le job quitte la file et l'événement `job_scrapped` est émis. Le rebut compte comme le job terminé du jour pour cette instance.
  - Sinon, la sortie est livrée comme dans la spec 001. Si elle est bloquée (`output_blocked`), le job garde son résultat de contrôle (`qc_passed = true`) et **ne refait pas de tirage** aux tentatives suivantes.
- Ordre des tirages dans le flux `production` : instances par `id` croissant, au plus un tirage par instance et par jour.
- Une recette sans rebut (taux 0) ne fait **aucun tirage**, ce qui garde intacts les tirages des autres recettes.
- Un job rebuté n'est pas remis en file automatiquement : le joueur relance (voir Questions).

### R5. Ateliers
Les nouveaux types suivent le modèle de `tank_shop` (spec 001, R2 et R4). Leurs valeurs sont dans Données. Rien ne change pour `tank_shop` ni pour `weld_tank` (rebut 0 par défaut, voir Questions).

### R6. Requête « acheter ou fabriquer » généralisée
La requête du comparateur (spec 001, UI) est étendue à tout composant fabricable, y compris le moteur avec sa chaîne à deux niveaux. Pour un composant, elle renvoie :
- **achat** : prix au comptant le moins cher et son délai, avec la spec 007 si elle est implémentée, sinon `unit_price` ;
- **fabrication** : coût matière estimé (somme des entrées au prix d'achat le moins cher, en remontant les pièces intermédiaires), durée par pièce à l'affectation courante, taux de rebut courant de chaque recette de la chaîne et **coût effectif** = coût matière / produit des taux de réussite ;
- la liste des installations manquantes, avec leurs prérequis.

La requête vit dans `sim/queries.gd` et l'UI ne fait aucun calcul.

## Données

### Paramètres et valeurs initiales proposées

`components.json` (ajouts)

| id | mass_kg | storage_units |
|---|---|---|
| `alloy_billet` | 250 | 1 |
| `electronic_kit` | 20 | 1 |
| `composite_roll` | 100 | 2 |
| `turbopump` | 300 | 2 |

`suppliers.json` (ajouts, noms fictifs)

| id | composant | unit_price | lead_time_days | delay_chance | delay_days |
|---|---|---|---|---|---|
| `valmorin_fonderies` | `alloy_billet` | 550 | 3 | 0.05 | 1 |
| `kessring_metals` | `alloy_billet` | 430 | 7 | 0.25 | 3 |
| `maelis_composants` | `electronic_kit` | 500 | 4 | 0.1 | 2 |
| `tessaline_fibres` | `composite_roll` | 350 | 5 | 0.1 | 2 |

Les lingots ont deux fournisseurs, sur le même modèle que les tôles : rapide et cher, ou lent et peu fiable.

`facilities.json` (ajouts ; nouveau champ optionnel `requires_facilities`)

| id | Nom | upkeep_per_day | build_cost | build_days | max_count | slots | productivity_per_slot | requires_facilities |
|---|---|---|---|---|---|---|---|---|
| `composite_shop` | Atelier composites | 100 | 20 000 | 8 | 1 | 2 | 10 | – |
| `electronics_lab` | Laboratoire avionique | 250 | 45 000 | 12 | 1 | 2 | 10 | – |
| `machine_shop` | Atelier d'usinage | 300 | 60 000 | 14 | 1 | 3 | 10 | – |
| `engine_shop` | Atelier moteurs | 700 | 140 000 | 20 | 1 | 4 | 10 | `machine_shop` |

`recipes.json` (ajouts ; nouveaux champs optionnels de rebut)

| id | scrap_rate_start | scrap_rate_floor | scrap_rate_drop_per_attempt | Plancher atteint après |
|---|---|---|---|---|
| `machine_turbopump` | 0.20 | 0.04 | 0.02 | 8 pièces |
| `build_engine` | 0.30 | 0.05 | 0.025 | 10 pièces |
| `wire_avionics` | 0.35 | 0.08 | 0.03 | 9 pièces |
| `layup_fairing` | 0.25 | 0.05 | 0.04 | 5 pièces |
| `weld_tank` (existant) | 0 | 0 | 0 | – |

`staff.json` : inchangé. Total des postes à pleine intégration avec un hall : 3 + 2 + 2 + 3 + 4 + 4 = 18, sous `max_technicians` 20. La contrainte vient donc des salaires, pas du plafond (voir Questions).

`state` (ajouts) : `recipe_attempts`. Par job : `qc_passed` (bool, false par défaut).

### Ordres de grandeur visés (pour `make balance`, pas des tests)
Conventions de calcul, celles de la spec 001 : main-d'œuvre = 15 crédits par point de travail (150 par jour / 10 points), entretien ramené à une cadence de **1 lanceur par 12 jours** (cadence actuelle du bot « tout acheter »), taux de rebut au plancher.

| Atelier | Coût matière + main-d'œuvre par pièce | Prix d'achat | Économie par L1 brute | Entretien par 12 j | Économie nette par L1 | Construction | Retour sur investissement |
|---|---|---|---|---|---|---|---|
| `tank_shop` (existant) | ~1 800 | 9 000 | 14 400 | 3 600 | ~10 800 | 40 000 | ~4 lanceurs |
| `composite_shop` | 1 050 + 900 = 1 950 | 5 000 | 3 050 | 1 200 | ~1 850 | 20 000 | ~11 lanceurs |
| `electronics_lab` | 1 500 + 750 = 2 250 | 6 000 ×2 | 7 500 | 3 000 | ~4 500 | 45 000 | ~10 lanceurs |
| `machine_shop` + `engine_shop` | 2 000 + 2 400 = 4 400 | 12 000 ×4 | 30 400 | 12 000 | ~18 400 | 200 000 | ~11 lanceurs |

- Cadence de l'atelier moteurs à plein régime : 4 postes → 40 points par jour → 3 jours par moteur, soit 4 moteurs en 12 jours. Usinage : 3 postes → 2 jours par turbopompe. La chaîne suit tout juste 1 lanceur par 12 jours, elle ne le suit pas pendant la montée en cadence, et elle ne suit pas une cadence plus élevée.
- Montée en cadence du moteur : rendement de la chaîne au départ 0,8 × 0,7 = 0,56, soit un coût effectif d'environ 7 900 par moteur réussi pour les premières pièces. Au plancher : 0,96 × 0,95 ≈ 0,91, soit environ 4 800.
- Intégration complète : environ 305 000 de construction et 1 350 d'entretien par jour en plus.
- Point clé : l'atelier moteurs construit vers le jour 80 se rembourse **à peine** sur 240 jours (environ 13 lanceurs restants). Son intérêt vient aussi de la suppression du délai moteur de 10 jours, qui peut augmenter la cadence, et de la protection contre le marché (spec 007). C'est voulu, et c'est à vérifier au bot (voir Questions, horizon).

### Schémas
- `facilities.schema.json` : `requires_facilities`, tableau de chaînes, optionnel. Le validateur vérifie que chaque type référencé existe et qu'il n'y a pas de cycle.
- `recipes.schema.json` : les trois champs de rebut sont optionnels, des nombres dans [0, 1], avec la contrainte `scrap_rate_floor <= scrap_rate_start` vérifiée par le validateur.
- Le validateur vérifie que tout composant non achetable (aucune entrée de catalogue) qui figure comme entrée d'une recette est la sortie d'au moins une recette (sinon, la chaîne est morte).

## Commandes et événements

Aucune nouvelle commande : `build`, `hire`, `assign_staff` et `queue_job` suffisent.

| Commande | Nouveau rejet |
|---|---|
| `build` | `missing_prerequisite` (champ `missing` : liste des types manquants) |

| Événement | Étape | Champs |
|---|---|---|
| `job_scrapped` | 4 | `job_id`, `facility_id`, `recipe_id`, `scrap_rate` |
| `job_completed` (étendu) | 4 | + `scrap_rate` (taux au moment du contrôle) |

Le flux RNG `&"production"` est ajouté à `sim/rng.gd`. La ligne « Implémenté » de `sim/CLAUDE.md` sera mise à jour par l'issue concernée (étape 4 : contrôle qualité).

## UI minimale pour le squelette
Rectangles et listes, aucune règle côté UI.
- **Panneau Construire** : les types dont le prérequis manque restent visibles, grisés, avec « Requiert : Atelier d'usinage (prêt) ». C'est le seul affichage de la progression, il doit être lisible.
- **Panneau Installations** : pour chaque atelier, sous la barre de progression du job, afficher « Rebut : 22 % (plancher 5 %, atteint dans 7 pièces) ».
- **Comparateur acheter / fabriquer** : une ligne par composant fabricable (réservoir, moteur, avionique, coiffe), alimentée par la requête R6. Colonnes : prix d'achat et délai, coût effectif de fabrication, durée par pièce, ateliers manquants.
- **Nomenclature L1** : inchangée. La turbopompe n'y figure pas (pièce intermédiaire), mais elle apparaît dans le stock.
- **Rapport du jour** : ligne « Rebuts : 1 moteur (atelier moteurs, taux 27 %) ».

## Critères d'acceptation
Fixtures (dans `tests/sim/fixtures.gd`) : composants `ore` (1 unité), `part` (1 unité, non achetable), `engine` (1 unité) ; entrepôt de capacité 50 ; type `mill` (2 postes, productivité 10, `build_cost` 1 000, `build_days` 2, `max_count` 1) ; type `forge` (2 postes, productivité 10, `build_cost` 2 000, `build_days` 2, `max_count` 1, `requires_facilities` `["mill"]`) ; recette `make_part` (`mill`, `ore ×1` → `part ×1`, 20 points, sans rebut) ; recette `make_engine` (`forge`, `part ×1 + ore ×1` → `engine ×1`, 20 points, rebut paramétré selon le test) ; salaires à 0, entretiens à 0.

1. **Prérequis manquant** : 10 000 crédits, aucun `mill`. `build("forge")` → `command_rejected` `missing_prerequisite`, `missing = ["mill"]`, argent inchangé.
2. **Prérequis en construction** : `build("mill")` au jour 0, puis `build("forge")` au jour 1 → rejet `missing_prerequisite`. Au jour 2, le `mill` est `ready` : `build("forge")` est accepté, argent = 10 000 − 1 000 − 2 000.
3. **Ordre des rejets** : `mill` prêt, 500 crédits, `build("forge")` → `insufficient_funds`. Aucun `mill`, 500 crédits → `missing_prerequisite` (le prérequis est contrôlé avant les fonds).
4. **Chaîne à deux niveaux** : `mill` et `forge` prêts, 2 techniciens chacun (débit 20, un job dure 1 jour), `ore` 2, rebut 0. `queue_job(mill, make_part, 1)` et `queue_job(forge, make_engine, 1)` au jour 0. Deux variantes, selon l'ordre des `id` (spec 001 R5 : instances traitées par `id` croissant, et ce qui est produit est utilisable par la suite de la même étape) :
   - a. `mill` d'`id` plus petit que `forge` → après 1 jour : `part` = 0, `engine` = 1, `ore` = 0 (la pièce sortie du `mill` est consommée dans la même résolution).
   - b. `forge` d'`id` plus petit que `mill` → après 1 jour : `job_blocked` `missing_inputs` sur la `forge`, `part` = 1, `engine` = 0 ; après 2 jours : `engine` = 1, `part` = 0, `ore` = 0.
5. **Rebut certain** : `make_engine` avec `scrap_rate_start` 1.0, plancher 1.0. `part` 1, `ore` 1, job lancé. → après 1 jour : `job_scrapped` émis, `engine` = 0, `part` = 0, `ore` = 0, file vide, `recipe_attempts[make_engine]` = 1.
6. **Pas de rebut, pas de tirage** : `mill` (recette sans rebut) d'`id` 1 et `forge` (taux 0.5) d'`id` 2 terminent un job le même jour. Le résultat du contrôle de la `forge` est identique, pour 20 seeds, à celui d'une partie jumelle où le `mill` ne produit rien ce jour-là : la recette sans rebut n'a consommé aucun tirage du flux `production`.
7. **Courbe d'apprentissage** : `scrap_rate_start` 0.5, `drop` 0.1, `floor` 0.1. Avec `recipe_attempts` à 0, 3, 4 et 10, la requête du taux renvoie respectivement 0.5, 0.2, 0.1 et 0.1.
8. **Les rebuts font progresser la courbe** : `scrap_rate_start` 1.0, `drop` 1.0, plancher 0. Deux jobs en file, entrées pour deux. → jour 1 : le premier job est rebuté (taux 1.0) ; jour 2 : le second passe (taux 0.0), `engine` = 1, `recipe_attempts` = 2.
9. **Pas de second tirage après une sortie bloquée** : entrepôt plein au moment de la fin du job, taux 0.5, seed telle que le premier tirage passe. → `output_blocked`, `qc_passed = true`. On libère de la place à la main → livraison au jour suivant, sans `job_scrapped`, et `recipe_attempts` reste à 1.
10. **Statistique seedée** : taux fixe de 0.3, 1 000 jobs sur les seeds 1..1000 → entre 250 et 350 rebuts.
11. **Isolation des flux** : même seed, même plan de commandes, avec et sans un atelier qui produit des rebuts → mêmes retards de livraison et mêmes résultats de tir (flux `deliveries`, `weather` et `launch` inchangés).
12. **Non-régression** : les tests de la spec 001 (`weld`, sans champs de rebut) passent sans modification.

## Ce que `make balance` doit montrer
Nouvelles stratégies de bot (toutes fabriquent ce qu'elles peuvent et achètent le reste au moins cher, puis embauchent pour remplir les postes de chaque atelier construit) :

| Stratégie | Comportement |
|---|---|
| `buy_all` (existante) | référence |
| `workshop` (existante) | `tank_shop` au jour 0 |
| `integrate_staged` | construit l'atelier suivant de la liste `tank_shop → machine_shop → engine_shop → electronics_lab → composite_shop` dès que `money >= build_cost + reserve`, avec `reserve` = coût de 2 kits L1 achetés (paramètre du bot, pas de `data/`) |
| `integrate_greedy` | même ordre, construit dès que `money >= build_cost` |
| `engines_only` | `tank_shop`, puis `machine_shop` et `engine_shop`, rien d'autre |

Métriques à ajouter au rapport : jour de mise en service de chaque atelier, lanceur à partir duquel chaque atelier est rentabilisé (économie cumulée ≥ construction + entretien cumulé), nombre de rebuts par recette, part des moteurs fabriqués, et le **goulot** du lanceur (le composant dont l'attente a été la plus longue avant le début de l'assemblage).

Comportement attendu (à 240 jours, 40 seeds, et en plus à 360 jours si la question 5 est retenue) :
- `integrate_staged` bat `workshop` en médiane de 5 à 15 %, mais **pas** sur toutes les seeds : on veut au moins 20 % de seeds où `workshop` fait mieux.
- `integrate_greedy` fait moins bien que `integrate_staged` en médiane et a **au moins autant** de faillites que `workshop`. Si `greedy` domine, les contreparties sont trop faibles.
- L'atelier moteurs construit avant le jour 100 se rembourse avant le jour 240. Construit après le jour 150, il ne se rembourse pas.
- `composite_shop` reste marginal (économie inférieure à 30 000 sur la partie). C'est acceptable, à réévaluer avec la spec 007 (pénuries de coiffes).
- Le goulot dominant change au cours de la partie : moteur acheté au début, puis hall ou pas de tir pour `integrate_staged` en fin de partie. Si le moteur reste le goulot en fin de partie pour `integrate_staged`, la cadence de l'atelier moteurs est trop basse.
- Aucune stratégie n'atteint le plancher de rebut sur le moteur avant le jour 120 environ (sinon la montée en cadence est trop courte pour être une décision).

## Hors périmètre
- Défauts cachés qui influencent la fiabilité du tir, banc d'essai (voir Questions).
- Métiers spécialisés (machiniste, électronicien), compétence (étape 6).
- Second exemplaire des nouveaux ateliers, amélioration d'atelier, recherche qui fait baisser le taux de rebut.
- Revente d'installations ou de stock.
- Recyclage des rebuts.

## Décisions (validées par Flavien le 2026-11-14)
Toutes les recommandations ci-dessous sont retenues.
1. **Rebut visible en sortie d'atelier, ou défaut caché qui dégrade la fiabilité du tir ?** Le défaut caché est plus réaliste et plus dramatique, mais il est invisible pour le joueur sans banc d'essai, et il touche la spec 003. *Recommandation : rebut visible maintenant. Le défaut caché viendra avec le banc d'essai (une spec dédiée) : on transformera alors une partie du rebut en « défaut non détecté sans test ».*
2. **Prérequis : atelier seulement, ou aussi un nombre de succès de tir (« certification ») ?** Exemple : l'atelier moteurs exige 2 lancements réussis. Cela étale encore la progression, mais c'est un verrou arbitraire. *Recommandation : atelier seulement. Prévoir un champ `requires_successful_launches` (défaut 0) seulement si le bot montre que `integrate_greedy` construit l'atelier moteurs trop tôt.*
3. **`max_count` des nouveaux ateliers.** Un seul atelier moteurs plafonne la cadence à environ 1 lanceur par 12 jours. *Recommandation : 1 pour l'instant. Un second atelier moteurs, ou une amélioration, est le prochain palier de progression naturel (spec suivante).*
4. **Turbopompe achetable ?** Si oui, l'usinage devient optionnel et le prérequis perd son sens. *Recommandation : non.*
5. **Horizon de référence du bot.** Avec 240 jours, l'atelier moteurs est tout juste rentable. Combien de jours dure une partie (ou un niveau de campagne) ? *Recommandation : ajouter un rapport à 360 jours à `make balance` et viser la rentabilité de l'intégration complète sur cet horizon.*
6. **Prix d'achat de la coiffe.** À 5 000, l'atelier composites est marginal. Il peut le rester (c'est l'atelier « résilience », bon marché, qui apprend la mécanique de rebut), ou on peut monter le prix à 7 000, ce qui fait passer le kit acheté de 83 000 à 85 000. *Recommandation : ne rien changer avant d'avoir le rapport du bot avec la spec 007.*
7. **Rebut sur `weld_tank`.** L'activer rendrait le système cohérent, mais rééquilibrerait la phase 2. *Recommandation : 0 pour l'instant.*
8. **Rebut : remise en file automatique ?** *Recommandation : non. Le joueur relance, et le rapport du jour le signale. Une option « relancer en cas de rebut » pourra venir avec le polish de l'UI.*
9. **Plafond de techniciens.** À 20, il ne contraint pas l'intégration complète (18 postes). *Recommandation : ne pas y toucher. La masse salariale suffit comme contrainte. On verra avec les métiers spécialisés.*

## Découpage en issues
Dépendances : l'issue 1 (données) peut avancer seule. Les issues 2 et 3 sont indépendantes l'une de l'autre. L'issue 4 dépend de 2 et 3, et l'issue 5 de 1, 2 et 3.

1. **Données et schémas de l'intégration verticale** : ajouts dans `components.json`, `suppliers.json`, `facilities.json` et `recipes.json` (toutes les valeurs des tableaux de la section Données ci-dessus), champs `requires_facilities` et `scrap_rate_*` dans les schémas, contrôles du validateur (types référencés, absence de cycle, plancher ≤ départ, composant non achetable produit par une recette). `make validate` vert. Valeurs externes : aucune. Modèle : **haiku**.
2. **Prérequis de construction** : `requires_facilities` dans `GameData`, rejet `missing_prerequisite` dans `build`, à sa place dans l'ordre des rejets. Critères 1 à 3. Valeurs externes : ordre des rejets de `build` de la spec 001, R2 (`not_buildable`, `max_count_reached`, puis `insufficient_funds`). Modèle : **haiku**.
3. **Rebut et montée en cadence (étape 4)** : `recipe_attempts`, `qc_passed`, flux `&"production"` dans `sim/rng.gd`, tirage au contrôle qualité, événement `job_scrapped`, champ `scrap_rate` dans `job_completed`, requête du taux courant, mise à jour de `sim/CLAUDE.md`. Critères 4 à 12. Valeurs externes : règles de jobs de la spec 001, R5 (un job terminé par instance et par jour, `output_blocked`). Modèle : **sonnet**.
4. **Requête et UI acheter / fabriquer généralisée** : requête R6 dans `sim/queries.gd` (coût effectif avec la chaîne de recettes et le rebut), panneau Construire avec les prérequis, taux de rebut dans le panneau Installations, ligne de rebuts dans le rapport du jour. Valeurs externes : si la spec 007 est implémentée, le prix d'achat est le prix au comptant (requête `spot_price` de la spec 007), sinon `unit_price`. Modèle : **sonnet**.
5. **Stratégies de bot** : `integrate_staged`, `integrate_greedy`, `engines_only` dans `tests/balance_bot.gd`, métriques du rapport (mise en service, rentabilisation, rebuts, goulot), option d'horizon à 360 jours. Valeurs externes : `reserve` = coût de 2 kits L1 achetés (83 000 × 2 aux prix actuels, à calculer depuis `data/`, pas en dur). Modèle : **sonnet**.

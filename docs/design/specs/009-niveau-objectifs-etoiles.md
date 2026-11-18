# 009 — Premier niveau : objectifs en étoiles
Statut : validée (2026-11-18)

## Intention joueur
Aujourd'hui, la partie n'a ni but ni fin. Selon le bot, une fois la boucle maîtrisée, l'argent monte tout seul (1,38 M à 240 jours en achetant tout, 2,21 M à 360 jours) et rien ne résiste au joueur. Cette spec donne un but : un **niveau** de 240 jours sur la Pointe des Sternes, noté de 1 à 3 étoiles, façon Two Point.

- **Étoile 1** : la base tourne. On l'obtient en achetant tout.
- **Étoile 2** : on a utilisé **un** des deux systèmes profonds, au choix : un atelier (spec 006) ou un contrat d'approvisionnement (spec 007).
- **Étoile 3** : on a utilisé **les deux**, tôt, avec une base bien rangée (spec 008), et on a fini riche.

Dilemmes :
1. **Par où passer pour l'étoile 2.** L'atelier de soudure coûte 30 000 et doit être construit tôt (la part fabriquée est cumulée depuis le jour 0). Le contrat d'approvisionnement ne coûte rien à signer, mais ses factures tombent à dates fixes.
2. **Sécuriser une étoile ou investir.** Les étoiles 1 et 2 demandent de la trésorerie, et chaque atelier la fait chuter. Une étoile acquise est définitive : faut-il passer le seuil avant d'acheter l'atelier d'usinage, ou investir tout de suite et prendre l'étoile plus tard ?
3. **D'où viennent les moteurs, pour l'étoile 3.** Il faut à la fois 200 000 d'achats sous contrat et 45 % de pièces maison. Chaque moteur acheté sous contrat est un moteur non fabriqué. Le chemin attendu est un enchaînement : contrat au début, comptant au milieu, atelier moteurs ensuite. L'atelier doit donc être commandé vers le jour 90, quand la trésorerie est encore fragile (« tout construire tôt » fait faillite 39 fois sur 40).
4. **Le dernier mois.** À l'approche du jour 240, chaque kit commandé baisse la trésorerie et ne rapporte que si le tir a lieu avant la fin. Lancer un tir de plus, ou s'arrêter pour tenir le seuil ?
5. **Assurer ses tirs.** Un échec coûte environ 200 000 (kit, remise en état, solde perdu). Avec un seuil de trésorerie à tenir, la prime d'assurance (spec 003) devient une vraie décision.

Honnêteté :
- **L'étoile 1 ne crée pas de dilemme.** C'est voulu : elle valide la boucle de base. Seul le dilemme 2 la touche.
- **`contracts_completed` est presque redondant avec la trésorerie.** L'argent ne vient que des contrats de lancement : qui a 750 000 a déjà une dizaine de contrats. Cet objectif sert de compteur lisible et croissant à côté de jauges qui montent et descendent. Aux étoiles 2 et 3, il ne sera sans doute jamais l'objectif limitant. Le rapport du bot le dira (section balance) et on le retirera si c'est confirmé.
- **L'objectif « contrat d'approvisionnement » est une recette une fois connue** : signer un contrat de moteurs au jour 0. Il garde un risque réel (48 000 de facture tous les 14 jours avec 200 000 au départ) et il entre en tension avec la part maison, mais ce n'est pas un choix renouvelé.
- **« Base aux normes » ne mord que si l'on construit.** Un joueur sans atelier la remplit sans y penser. De plus, la spec 008 annonce que l'atelier moteurs ne tient pas en zone sûre et desservie sur la parcelle de départ ; avec la rotation, il y tient (voir le retour sur la spec 008). Tant que ce point n'est pas corrigé, l'objectif se résout par un bon rangement, sans achat de parcelle.
- **La chance pèse sur l'étoile 3.** Avec la fiabilité actuelle (85 % puis +2 % par succès), 39 % des parties de 16 tirs n'ont aucun échec. Le joueur n'a aucun levier sur la fiabilité (pas de banc d'essai), seulement sur les conséquences : l'assurance et le placement.
- **Effet de fin de niveau.** Une trésorerie mesurée à date fixe pousse à « liquider » : ne plus commander, licencier, démolir pour toucher le remboursement de la spec 008 (environ 106 000 pour une base entièrement intégrée, installations de départ comprises). La mesure retenue neutralise les avances clients, pas la démolition (question 5).
- **Objectifs écartés** :
  - *Tirs sans échec* : pure loterie aujourd'hui (voir ci-dessus). À reprendre quand un banc d'essai donnera un levier.
  - *Réputation* : plafonnée à 100, +6 par succès, −15 par échec. C'est un compteur de succès récents, atteint sans y penser (60 après 2 succès). La métrique existe dans le format, le niveau 1 ne l'utilise pas.
  - *Nombre d'ateliers construits* : imposerait un chemin. La part maison en valeur laisse le choix des ateliers.

## Règles

### R1. Un niveau, source unique des conditions de départ
- Nouveau fichier `data/levels.json` : une liste de niveaux. Un niveau = un site (`site`, id de `sites.json`), des conditions de départ (`start`), une durée (`duration_days`), trois étoiles (`stars`).
- **`data/start.json` et son schéma sont supprimés.** Leur contenu, tel que modifié par la spec 008 (`owned_lots`, installations avec position), devient le bloc `start` du niveau. Le champ `site` remonte à la racine du niveau. Le validateur échoue si `data/start.json` existe encore.
- Répartition :

| Donnée | Fichier |
|---|---|
| Géographie, météo, carte, parcelles et leurs prix | `sites.json` (inchangé) |
| Argent, techniciens et affectations de départ ; parcelles possédées ; installations de départ et leurs positions ; site joué | `levels.json` → `start` et `site` |
| Objectifs, durée, alertes de temps | `levels.json` |
| Réputation de départ, faillite, règles spatiales | `contracts.json`, `rules.json`, `layout.json` (inchangés, globaux) |

- Un niveau ne surcharge **aucune** règle globale dans cette spec (pas de prix ni de modèles de contrat propres à un niveau).
- Côté sim, `GameData` est construit **pour un niveau** : `data.level` est l'enregistrement du niveau choisi, `data.start` est son bloc `start` et `data.active_site_id` son `site`. `new_game(data, seed)` ne change pas de signature. Un `GameData` construit sans `levels` (toutes les fixtures des specs 001 à 008, qui fournissent un `start` en ligne) donne une partie **sans niveau** : pas d'objectifs, pas de fin, comportement actuel. Le mécanisme exact de sélection (paramètre du chargeur) est laissé à l'architecte (question 10).

### R2. État de niveau
`GameState.level` : `{id, status, stars, star_days, end_day, end_reason}`.
- `status` ∈ `running` | `ended` | `free_play`. `new_game` avec un niveau : `running`. Sans niveau : `id` = `""` et `status` = `free_play`.
- `stars` : nombre d'étoiles acquises (0 à 3). `star_days` : 3 entiers, le jour d'obtention de chaque étoile, −1 sinon.
- `end_day` (−1 tant que le niveau court) et `end_reason` ∈ `""` | `all_stars` | `time_up` | `bankruptcy`.

### R3. Compteurs
Trois compteurs, tenus à jour dans toutes les parties (avec ou sans niveau), sans événement ni tirage :
- `stats.kit_consumed[component_id]` : à l'étape 4, quand un job dont la recette produit un lanceur démarre (`job_started`), on ajoute les quantités consommées.
- `stats.components_made[component_id]` : à l'étape 4, quand la sortie d'un job entre réellement en stock (après le contrôle qualité et après le contrôle de place), on ajoute la quantité. Un job rebuté ou bloqué en sortie n'ajoute rien.
- `invoiced_total` sur chaque contrat d'approvisionnement : à l'étape 2, on ajoute la facture de chaque expédition (spec 007, R5.3). Les paiements de take-or-pay (R7) et les frais de résiliation (R8) ne sont pas ajoutés.

### R4. Métriques
Une métrique est une **requête pure** `metric_value(state, data, metric)` qui renvoie un entier.

| `metric` | Mesure | Évolution |
|---|---|---|
| `contracts_completed` | nombre de contrats de `state.contracts` au statut `completed` | croissante |
| `net_cash` | `money − Σ advance` des contrats de lancement au statut `active` | monte et descend |
| `reputation` | `state.reputation` | monte et descend |
| `in_house_share_pct` | R4a | monte et descend |
| `supply_completed_value` | `Σ invoiced_total` des contrats d'approvisionnement au statut `completed` (un contrat `terminated` compte pour 0) | croissante |
| `site_violations` | R4b | monte et descend |

`net_cash` retire les avances parce qu'elles ne sont pas encore gagnées : sans cela, signer trois contrats le même jour ferait franchir un seuil (environ +120 000).

**R4a. Part fabriquée maison** (en valeur de catalogue des pièces montées sur les lanceurs) :
- Pièces du kit : les composants en entrée des recettes qui produisent un lanceur (pour le L1 : `engine`, `tank`, `avionics`, `fairing`). La turbopompe, pièce intermédiaire, n'en fait pas partie.
- `ref_price[c]` : le plus petit `unit_price` de catalogue du composant, tous fournisseurs confondus, sans indice de marché.
- `credited[c] = min(components_made[c], kit_consumed[c])` : une pièce fabriquée ne compte que si une pièce de ce type a été montée. Fabriquer des réservoirs en trop ne gonfle pas la part.
- `in_house_share_pct = (100 × Σ ref_price[c] × credited[c]) div (Σ ref_price[c] × kit_consumed[c])`, et 0 si rien n'a encore été monté.
- Le stock est fongible : on ne suit pas l'origine de chaque pièce, on crédite la fabrication d'abord.

**R4b. Infractions du site** : nombre d'instances (hors pas de tir), `ready` ou `building`, situées dans la zone de sécurité d'au moins un pas (spec 008, R5), plus nombre d'instances `ready` dont le type a des `slots` et qui ne sont pas desservies (spec 008, R6). Une instance en zone et non desservie compte deux fois. Un site sans carte renvoie 0. La requête s'appuie sur `facility_spatial` de la spec 008 : aucune règle de distance n'est redéfinie ici.

### R5. Objectifs et étoiles
- Un **objectif** : `{id, metric, op, target}`, avec `op` ∈ `gte` | `lte`. Il est rempli si `metric_value >= target` (`gte`) ou `<= target` (`lte`).
- Une **étoile** : une liste `objectives` (tous requis) et, en option, un bloc `any_of` `{min_met, objectives}` : au moins `min_met` de ces objectifs doivent être remplis.
- Une étoile est **remplie** un jour donné si tous ses objectifs requis et son bloc `any_of` le sont **le même jour**.
- Les étoiles s'obtiennent **dans l'ordre** : l'étoile `n` exige l'étoile `n − 1`. Plusieurs étoiles peuvent tomber le même jour.
- Une étoile acquise est **définitive** : `stars` ne baisse jamais, même si une métrique redescend, même en cas de faillite ensuite.

### R6. Évaluation quotidienne
Dernière sous-étape de l'**étape 8**, après les finances et après la faillite (spec 004). Rien n'est évalué à la création de la partie. Si `level.status != running`, la sous-étape ne fait rien.
1. Si `game_over` vient de passer à vrai ce jour-là : fin de niveau (R7, `bankruptcy`), **sans** évaluer les étoiles.
2. Sinon, pour `n` de `stars + 1` à 3 : si l'étoile `n` est remplie, `stars = n`, `star_days[n − 1] = day`, événement `star_earned` ; sinon, arrêt.
3. Si `stars == 3` : fin de niveau (`all_stars`).
4. Sinon, avec `days_left = duration_days − (day + 1)` : si `duration_days > 0` et `days_left <= 0`, fin de niveau (`time_up`) ; sinon, si `days_left` figure dans `time_warnings_days`, événement `level_time_warning`.

Un niveau de 240 jours se joue donc sur 240 résolutions (jours 0 à 239). Une étoile remplie à la résolution du dernier jour compte. `duration_days = 0` signifie « sans limite » (prévu par le format, non utilisé par le niveau 1).

### R7. Fin de niveau
- Effet : `level.status = ended`, `level.end_day = day`, `level.end_reason`, événement `level_ended`.
- Tant que `status == ended`, la partie est gelée, comme en `game_over` (spec 004, R4) : `end_day` ne fait rien et ne fait pas avancer le jour, et toute commande autre que `continue_free_play` est rejetée avec `level_over`.
- Un niveau terminé avec 0 étoile est **échoué**, avec 1 à 3 étoiles il est **réussi**. Cette distinction est un affichage : elle ne change aucune règle.
- La faillite (spec 004) reste la seule condition d'échec en cours de partie. Elle termine le niveau et les étoiles déjà acquises sont conservées.

### R8. Mode libre
`continue_free_play()` à l'étape 1. Rejets, dans cet ordre : `game_over` (rejet général de la spec 004), `level_not_ended` (`status != ended`). Effet : `status = free_play`, événement `free_play_started`. La partie reprend sur le même état, sans limite de temps. Les étoiles sont **gelées** : plus aucune évaluation. Après une faillite, pas de mode libre.

### R9. Requêtes (aucun calcul dans l'UI)
- `metric_value(metric)` : R4.
- `level_progress()` : `{level_id, status, end_reason, duration_days, days_left, stars, star_days, star_list}`. `days_left = duration_days − day` (nombre de fins de journée restantes). Chaque entrée de `star_list` : `{star, name, earned, earned_day, objectives: [{id, metric, op, target, value, met}], any_of: {min_met, met_count, objectives: [...]}}`.
- `level_summary()` pour l'écran de fin : contrats réussis et échoués, `money`, `net_cash`, réputation, part maison, achats sous contrat menés à terme, jours joués, `star_days`.
- `level_list(best_stars_by_level)` : les niveaux triés par `order`, avec `unlocked` calculé depuis `unlock` (voir « Ce que le format prévoit pour la campagne »).

### R10. Sauvegardes
`level` et `stats` sont des champs de `GameState`, donc sauvegardés. Valeurs par défaut pour une sauvegarde antérieure : `level = {id: "", status: "free_play", stars: 0, star_days: [-1, -1, -1], end_day: -1, end_reason: ""}`, `stats = {kit_consumed: {}, components_made: {}}`, `invoiced_total = 0` sur chaque contrat d'approvisionnement. Une ancienne sauvegarde se charge donc **en mode libre, sans objectifs**. `level` et `stats` sont ajoutés à `SaveGame.OPTIONAL_STATE_KEYS`, et `SAVE_VERSION` ne change pas.

## Données

### `levels.json` (nouveau) : le niveau `pointe_sternes_1`
```json
{
  "levels": [
    {
      "id": "pointe_sternes_1",
      "name": "Pointe des Sternes",
      "briefing": "Première base, premiers clients. Tu as 240 jours.",
      "site": "pointe_sternes",
      "order": 1,
      "unlock": { "requires_level": null, "min_stars": 0 },
      "duration_days": 240,
      "time_warnings_days": [30, 7],
      "start": {
        "money": 200000,
        "technicians": 4,
        "owned_lots": ["lot_start"],
        "facilities": [
          { "facility_type": "warehouse", "x": 10, "y": 14, "rotation": 0 },
          { "facility_type": "integration_hall", "x": 10, "y": 8, "rotation": 0 },
          { "facility_type": "launch_pad", "x": 22, "y": 10, "rotation": 0 }
        ],
        "assignments": { "integration_hall": 4 }
      },
      "stars": [
        {
          "name": "Mise en service",
          "objectives": [
            { "id": "s1_contracts", "metric": "contracts_completed", "op": "gte", "target": 5 },
            { "id": "s1_cash", "metric": "net_cash", "op": "gte", "target": 300000 }
          ]
        },
        {
          "name": "Montée en cadence",
          "objectives": [
            { "id": "s2_contracts", "metric": "contracts_completed", "op": "gte", "target": 10 },
            { "id": "s2_cash", "metric": "net_cash", "op": "gte", "target": 750000 }
          ],
          "any_of": {
            "min_met": 1,
            "objectives": [
              { "id": "s2_in_house", "metric": "in_house_share_pct", "op": "gte", "target": 15 },
              { "id": "s2_supply", "metric": "supply_completed_value", "op": "gte", "target": 60000 }
            ]
          }
        },
        {
          "name": "Maîtrise industrielle",
          "objectives": [
            { "id": "s3_contracts", "metric": "contracts_completed", "op": "gte", "target": 14 },
            { "id": "s3_cash", "metric": "net_cash", "op": "gte", "target": 1600000 },
            { "id": "s3_in_house", "metric": "in_house_share_pct", "op": "gte", "target": 45 },
            { "id": "s3_supply", "metric": "supply_completed_value", "op": "gte", "target": 200000 },
            { "id": "s3_site", "metric": "site_violations", "op": "lte", "target": 0 }
          ]
        }
      ]
    }
  ]
}
```
Les positions, `owned_lots` et la carte viennent de la spec 008. L'ordre des installations de départ est celui du `start.json` actuel (entrepôt, hall, pas) : il fixe leurs `id` (1, 2, 3), qu'il ne faut pas changer.

### Lecture des paliers

| Métrique | Étoile 1 | Étoile 2 | Étoile 3 |
|---|---|---|---|
| Contrats de lancement réussis | 5 | 10 | 14 |
| Trésorerie hors avances | 300 000 | 750 000 | 1 600 000 |
| Part fabriquée maison | – | 15 % *(au choix)* | 45 % |
| Achats sous contrat mené à terme | – | 60 000 *(au choix)* | 200 000 |
| Infractions du site | – | – | 0 |

À l'étoile 2, un seul des deux objectifs « au choix » suffit. « Tout acheter au comptant » plafonne donc à 1 étoile **par construction**. « Tout acheter, dont une partie sous contrat » peut atteindre 2 étoiles.

### Calibrage (estimations tirées du bot, à recaler après la spec 008)
Repères, à 240 jours et 40 seeds : `buy_all` réussit 16,1 contrats (un tous les 14 jours après le premier tir du jour 16) et gagne en moyenne 73 000 par contrat, moins au début. La spec 008 retire environ 51 000 de roll-out à tout le monde. `net_cash` est inférieur à l'argent affiché de 40 000 à 120 000 (1 à 3 avances en cours).

- **Étoile 1** (5 contrats, 300 000). `buy_all` y arrive vers le jour 75 à 90, avec environ 370 000. La marge de 70 000 est pour le joueur qui découvre. Un joueur qui investit avant le seuil la retarde (dilemme 2).
- **Étoile 2** (10 contrats, 750 000). La trésorerie est l'objectif limitant : environ 11 contrats, vers le jour 165. Il reste 75 jours de marge.
  - Part maison 15 % : les réservoirs pèsent 21,7 % du kit. L'atelier de soudure suffit s'il fabrique avant le 3e lanceur environ. Construit après le 5e lanceur, il ne suffit plus en 240 jours : il faut y ajouter le laboratoire avionique (14,5 %).
  - Achats sous contrat 60 000 : le plus petit contrat de moteurs (4 moteurs × 3 livraisons, environ 150 000) suffit, comme un contrat de 4 livraisons de réservoirs.
- **Étoile 3**.
  - Part maison 45 % : le maximum **sans** moteurs est 42 % (réservoirs 21,7 + avionique 14,5 + coiffe 6,0). La chaîne moteur est donc nécessaire, par conception. Exemple sur 16 lanceurs : réservoirs maison à partir du 2e (20 %) et moteurs maison pour les 8 derniers (29 %) donnent 49 %. L'atelier moteurs doit produire vers le jour 110, donc être commandé vers le jour 90 et l'usinage vers le jour 70. Avec deux lanceurs de retard, on tombe à 42 % : il faut alors le laboratoire avionique.
  - Achats sous contrat 200 000 : par exemple 4 livraisons de 4 moteurs (environ 201 000 au prix fixe avec priorité, moins si l'indice est bas : le joueur doit lire le devis), terminées vers le jour 52. Ou un contrat de moteurs plus court complété par un contrat de lingots, ce qui épargne la part maison.
  - Trésorerie 1 600 000 : `integrate_staged` finit à 1,70 M aujourd'hui, soit environ 1,56 M en `net_cash` après la spec 008 (roll-out, parcelle, avances). Une stratégie qui ajoute un contrat de moteurs au départ devrait finir entre 1,55 et 1,75 M. Le seuil se situe donc autour de sa médiane. **C'est la valeur la moins sûre de la spec.**
  - Contrats 14 : simple plancher de cadence (16,5 en moyenne pour `integrate_staged`), qui tolère deux échecs de tir.
- **Rythme visé** pour un bon joueur : étoile 1 au premier tiers, étoile 2 au deuxième, étoile 3 dans les 25 derniers jours.
- **Durée de session** : 240 jours en 30 à 60 minutes, soit 7 à 15 secondes par jour en moyenne avec l'avance rapide. À mesurer au premier playtest (question 1).

Poids de la part maison (informatif, calculé depuis `data/`) : moteurs 4 × 12 000 = 48 000 (57,8 %), réservoirs 2 × 9 000 = 18 000 (21,7 %), avionique 2 × 6 000 = 12 000 (14,5 %), coiffe 5 000 (6,0 %), kit 83 000.

### Schéma et validateur
- `levels.schema.json`. Par niveau : `id` (motif des ids), `name`, `briefing`, `site`, `order` (entier ≥ 1), `unlock` (`requires_level` : id ou `null` ; `min_stars` : 0 à 3), `duration_days` (entier ≥ 0), `time_warnings_days` (entiers ≥ 1, uniques), `start` (le schéma du `start.json` de la spec 008, sans `site`), `stars` (exactement 3 entrées). Par étoile : `name`, `objectives`, `any_of` optionnel (`min_met` ≥ 1). Par objectif : `id`, `metric` (énumération de R4), `op` (`gte` | `lte`), `target` (entier).
- Contrôles du validateur :
  - `site` existe ; `start.owned_lots` existent dans ce site ; les contrôles de la spec 008 sur les installations de départ (dans les parcelles possédées, sans chevauchement) s'appliquent à chaque niveau ; `assignments` ne cite que des types présents dans `start.facilities`.
  - `order` unique ; `unlock.requires_level` existe et n'est pas le niveau lui-même.
  - Chaque étoile a au moins un objectif ; `any_of.min_met` ≤ nombre d'objectifs du bloc ; `id` d'objectif unique dans le niveau ; chaque valeur de `time_warnings_days` < `duration_days`.
  - Paliers gradués : pour une même métrique en objectif requis, les cibles `gte` ne décroissent pas de l'étoile 1 à l'étoile 3.
  - Si un niveau utilise `in_house_share_pct`, chaque composant en entrée d'une recette de lanceur a au moins une entrée de catalogue. S'il utilise `site_violations`, son site a une carte.
  - `data/start.json` ne doit plus exister.

### État (ajouts)
`level` (R2), `stats` (R3), `invoiced_total` par contrat d'approvisionnement. Valeurs par défaut : R10.

### Ce que le format prévoit pour la campagne (non implémenté ici)
- `id` stable : c'est la clé des sauvegardes (`level.id`) et du profil.
- `order` et `unlock` `{requires_level, min_stars}` : le déblocage est une fonction pure (`level_list`), jamais l'ordre du fichier.
- **Meilleur score** : il vit hors de `GameState`, dans un profil écrit par l'UI (`user://profile.json`) : `{profile_version, levels: {level_id: {best_stars, best_star_days, runs}}}`. Mis à jour à chaque `star_earned` et à `level_ended`, il ne baisse jamais.
- Non prévu : surcharge de règles par niveau, plusieurs sites dans une même partie.

## Commandes et événements

| Commande | Args | Rejets |
|---|---|---|
| `continue_free_play` | – | `level_not_ended` |
| *(toutes les autres)* | | + `level_over` si `level.status == ended` (après le contrôle `game_over`) |

| Événement | Étape | Champs |
|---|---|---|
| `free_play_started` | 1 | `level_id` |
| `star_earned` | 8 | `level_id`, `star`, `day` |
| `level_time_warning` | 8 | `days_left` |
| `level_ended` | 8 | `level_id`, `reason` (`all_stars` \| `time_up` \| `bankruptcy`), `stars`, `star_days` |

Ordre à l'étape 8 : finances et échéances de contrats, faillite (`bankruptcy_warning`, `game_over`), puis niveau (`star_earned`, `level_ended` ou `level_time_warning`). Les compteurs de R3 sont des sous-étapes silencieuses des étapes 2 et 4. **L'ordre de résolution ne change pas**, et aucun tirage n'est ajouté. La ligne « Implémenté » de `sim/CLAUDE.md` sera mise à jour par l'issue 3.

## UI
La carte reste l'écran principal (spec 008). Les objectifs vivent à trois endroits.

- **Widget de la barre du haut** (l'emplacement réservé par la spec 008), toujours visible : trois étoiles pleines ou vides, « Reste 153 j », et l'avancement de la prochaine étoile (« 2/3 », le bloc « au choix » comptant pour un). En mode libre : « Mode libre » et les étoiles acquises. Un clic ouvre le panneau.
- **Panneau global « Objectifs »**, nouvelle icône en tête de la colonne de gauche. Il se superpose à la carte comme les autres panneaux. Il affiche les trois étoiles **dès le jour 0**, y compris la troisième : la part maison est cumulée, il faut connaître la cible tôt. Par étoile : nom, état (acquise au jour X, en cours, à venir), puis une ligne par objectif avec libellé, valeur et cible, jauge et coche. Le bloc « au choix » porte le titre « Au choix : 1 sur 2 ». Une infobulle par métrique dit comment elle se mesure (« en valeur de catalogue des pièces montées sur tes lanceurs », « hors avances clients », « contrats résiliés exclus »). Pour `site_violations`, un bouton « Voir » centre la carte sur les installations en infraction.
- **Notifications** :
  - `star_earned` : bandeau « Étoile 2 obtenue, jour 171 », animation de l'étoile dans la barre, son, ligne au Journal.
  - `level_time_warning` : bandeau « Il reste 30 jours ».
  - `star_earned`, `level_time_warning` et `level_ended` sont ajoutés à la liste d'arrêt de l'avance rapide (spec 005).
- **Écran de briefing** au jour 0 : nom du niveau, `briefing`, durée, les trois étoiles et leurs objectifs, bouton « Commencer ».
- **Écran de fin** à `level_ended`, par-dessus la carte. Il remplace l'écran de fin de partie de la spec 004 :
  - titre selon `reason` : « Trois étoiles » / « Temps écoulé » / « Faillite » ;
  - étoiles acquises avec leur jour, tableau des objectifs (valeur finale et cible), résumé (`level_summary`), meilleur score ;
  - boutons « Continuer en mode libre » (absent après une faillite), « Recommencer » (même niveau, nouvelle seed), « Menu ».
  - Recharger une sauvegarde dont le niveau est `ended` rouvre cet écran.
- Libellés des métriques par `tr()` à partir de `metric` : « Contrats de lancement réussis », « Trésorerie (hors avances clients) », « Réputation », « Part fabriquée maison », « Achats sous contrat mené à terme », « Installations en zone de sécurité ou non desservies ».

Assets pour `svg-artist` (icônes carrées, `viewBox` 0 0 64 64, aucune règle de lint à changer) : `icon_objectives.svg`, `icon_star_full.svg`, `icon_star_empty.svg`. Couleur de l'étoile acquise : `Attention` (`#FFB547`), seule teinte chaude de la palette (même réserve que la question 6 de la spec 008). Son : `sfx_star_earned` (paramètres sfxr).

## Critères d'acceptation
Fixtures, construites dans le fichier de test à partir de celles de la phase 2 :
- Contrat `t_leo` (paiement 100 000, avance 20 000). Lanceur `t_l`, fiabilité 1, météo 0, recette `assemble_t` (hall, `engine ×2 + tank ×1`, 20 points).
- Fournisseurs : `sup_a` vend `engine` à 1 000, `tank` à 500 et `ore` ; `sup_b` vend `engine` à 1 200. Donc `ref_price` : `engine` 1 000, `tank` 500, kit 2 500.
- Atelier `forge`, recette `make_engine` (`ore ×1` → `engine ×1`, 20 points, sans rebut sauf mention).
- Contrat d'approvisionnement du critère 9 de la spec 007 (10 unités, prix fixe 101, 3 livraisons, période 7).
- Entretiens et salaires à 0. `bankruptcy_grace_days` 3.
- Niveau `t_level` : site sans carte, `duration_days` 20, `time_warnings_days` [5], `start.money` 10 000.
  - Étoile 1 : `contracts_completed gte 1`.
  - Étoile 2 : `net_cash gte 50 000` ; `any_of` (`min_met` 1) : `in_house_share_pct gte 40`, `supply_completed_value gte 3 000`.
  - Étoile 3 : `contracts_completed gte 3`, `site_violations lte 0`.

1. **Chargement du niveau** : `GameData` construit pour `t_level`, `new_game` → `money` 10 000, installations de `start.facilities` créées `ready` avec des `id` dans l'ordre de la liste, `level` = `{id: "t_level", status: "running", stars: 0, star_days: [-1, -1, -1], end_day: -1, end_reason: ""}`, et `active_site()` renvoie le site du niveau.
2. **Sans niveau, rien ne change** : fixtures de la phase 2 (un `start`, pas de `levels`) → `level.id` = `""`, `level.status` = `free_play` ; 30 jours sans aucun événement `star_earned`, `level_time_warning` ni `level_ended`. Les tests des specs 001 à 008 passent sans modification.
3. **Étoile 1 en fin de journée** : un contrat `t_leo` actif, tir planifié au jour 3. → Jours 0 à 2 : pas de `star_earned`. Résolution du jour 3 : `contract_completed`, `daily_costs`, puis `star_earned {star: 1, day: 3}` ; `level.stars` = 1, `level.star_days` = [3, −1, −1].
4. **Une étoile est définitive** : variante où l'étoile 1 est `net_cash gte 5 000`, argent 10 000. → Résolution du jour 0 : `star_earned` 1. On met l'argent à 0 à la main, 5 jours : `level.stars` reste 1, un seul `star_earned` sur toute la partie.
5. **Ordre des étoiles** : argent 60 000, un contrat d'approvisionnement `completed` avec `invoiced_total` 3 030 posé à la main, aucun contrat de lancement réussi. → 1 jour : aucune étoile. On pose un contrat `completed` à la main → 1 jour : `star_earned` 1 puis `star_earned` 2, le même jour, dans cet ordre.
6. **Trésorerie hors avances** : argent 45 000, `accept_contract` → `money` 65 000 et `metric_value("net_cash")` = 45 000. Après le succès du tir (solde 80 000) : `net_cash` = `money` = 145 000.
7. **Part fabriquée maison** :
   - a. rien d'assemblé → 0 ;
   - b. la `forge` fabrique 1 `engine`, on achète 1 `engine` et 1 `tank`, le hall assemble un `t_l` → `kit_consumed` = {engine: 2, tank: 1}, `components_made` = {engine: 1}, part = 100 × 1 000 div 2 500 = 40 ;
   - c. 5 `engine` fabriqués, un seul lanceur assemblé → 100 × 2 000 div 2 500 = 80 ;
   - d. un job `make_engine` rebuté (taux 1.0) n'incrémente pas `components_made`.
8. **Contrat d'approvisionnement mené à terme** :
   - a. mené à terme → `invoiced_total` 3 030 ; `supply_completed_value` vaut 3 030 à partir de la résolution du jour 15, 0 avant ;
   - b. `skip_supply_delivery` sur la 2e livraison → à terme, 2 020 ;
   - c. `terminate_supply_contract` après 2 livraisons → `supply_completed_value` 0.
9. **Objectifs au choix** : étoile 1 acquise, argent 60 000, ni atelier ni contrat d'approvisionnement → pas d'étoile 2. Avec l'état du 7b (part 40) → `star_earned` 2. Avec l'état du 8a → `star_earned` 2. Avec `min_met` 2 et l'état du 7b seul → pas d'étoile.
10. **Infractions du site** (fixtures de la spec 008 : `t_site`, `pad` en (6, 0), `wh` en (0, 0)) :
    - `shop` prêt en (2, 0) → 1 (en zone) ; en (0, 3) → 0 ; en (0, 5) → 1 (non desservi) ;
    - `shop` en construction en (0, 5) → 0 ; en construction en (2, 0) → 1 ;
    - site sans carte → 0.
11. **Fin par le temps et alerte** : `t_level`, aucune commande. → `level_time_warning {days_left: 5}` une seule fois, à la résolution du jour 14. Résolution du jour 19 : `level_ended {reason: "time_up", stars: 0}`, `level.status` = `ended`, `level.end_day` = 19, `day` = 20.
12. **Le dernier jour compte** : comme le 3, tir au jour 19. → Résolution du jour 19 : `star_earned` 1, puis `level_ended {reason: "time_up", stars: 1}`.
13. **Niveau terminé, partie gelée** : après le 11, `order(...)` → `command_rejected` `level_over`, argent inchangé ; `end_day` renvoie `[]` et `day` reste à 20.
14. **Mode libre** : après le 11, `continue_free_play` → `free_play_started`, `level.status` = `free_play`, `end_day` avance de nouveau. On remplit ensuite l'étoile 1 : aucun `star_earned`, `level.stars` reste 0. Pendant un niveau `running` : `continue_free_play` → `level_not_ended`.
15. **Trois étoiles, fin immédiate** : état du 5 avec 3 contrats `completed` posés à la main. → Le même jour : `star_earned` 1, 2 et 3, puis `level_ended {reason: "all_stars", stars: 3}`.
16. **Faillite** : argent −1 000 000, tir réussi le 3e jour d'endettement (le solde ne ramène pas l'argent au-dessus de 0). → Ce jour-là : `contract_completed`, `game_over`, puis `level_ended {reason: "bankruptcy", stars: 0}`, **sans** `star_earned`. Même scénario avec `level.stars` = 1 au départ : `level_ended` porte `stars` 1. Ensuite, `continue_free_play` → `game_over`.
17. **Requête de progression** : dans l'état du 6 après la signature, `level_progress` renvoie, pour l'étoile 2, l'objectif `net_cash` avec `value` 45 000, `target` 50 000, `met` faux, et `any_of.met_count` 0 ; `days_left` = 20 − `day`.
18. **Sauvegarde** : `from_dict(to_dict())` conserve `level`, `stats` et `invoiced_total`, en entiers. La sauvegarde de référence antérieure (sans ces champs) se charge avec les valeurs de R10, `end_day` fonctionne et n'émet aucun événement de niveau.
19. **Déterminisme** : même seed et mêmes commandes, avec `t_level` et avec le même `start` sans niveau → mêmes événements, hors `star_earned`, `level_time_warning` et `level_ended`, jusqu'à la fin du niveau.
20. **Validateur** : il rejette un site inconnu, une parcelle inconnue dans `owned_lots`, 2 étoiles au lieu de 3, une `metric` inconnue, `any_of.min_met` supérieur au nombre d'objectifs, deux objectifs de même `id`, des cibles `gte` décroissantes, et la présence de `data/start.json`.

## Ce que `make balance` doit montrer
Le bot joue **le niveau** : chaque stratégie, 40 seeds, jusqu'à `level_ended`. Pour l'horizon de 360 jours, il envoie `continue_free_play` et poursuit, étoiles gelées.

Nouvelle stratégie `star_chaser` (paramètres du bot, pas de `data/`), pour mesurer l'étoile 3 :
- base `integrate_staged` avec le placement `careful` de la spec 008 ;
- au jour 0, un contrat de moteurs à prix fixe avec priorité, 4 moteurs tous les 14 jours, avec le plus petit nombre de livraisons dont le devis (`supply_contract_quote`) atteint la cible `supply_completed_value` de l'étoile 3 ; pas de renouvellement ;
- ordre de construction : `tank_shop`, `machine_shop`, `engine_shop`, `electronics_lab` ; jamais `composite_shop` ;
- plus aucune construction quand `days_left < 60` ; plus aucun kit commandé si le tir ne peut pas avoir lieu avant la fin ;
- aucune liquidation (ni démolition, ni licenciement, ni signature de dernière minute) : le bot mesure un jeu honnête.

Métriques à ajouter au rapport :
- par stratégie : part des seeds à au moins 1, au moins 2 et 3 étoiles, et jour médian d'obtention de chaque étoile (sur les seeds qui l'ont) ;
- par objectif : part des seeds où il est **limitant** (rempli le jour même de l'étoile, ou non rempli à la fin si l'étoile manque) ;
- P10, médiane et P90 de chaque métrique à la fin du niveau ;
- taux de 3 étoiles selon que la seed a connu 0 ou au moins 1 échec de tir ;
- sonde d'exploit : `star_chaser` avec démolition de tout ce qui est libre au dernier jour, et l'écart de taux de 3 étoiles.

| Stratégie | 1 étoile | 2 étoiles | 3 étoiles |
|---|---|---|---|
| `buy_all` | ≥ 80 % | 0 % (par construction) | 0 % |
| `workshop` | ≥ 75 % | 50 à 80 % | 0 % |
| `contract_engines` | ≥ 80 % | 50 à 80 % | 0 % |
| `integrate_staged`, `engines_only` (`careful`) | ≥ 70 % | 40 à 70 % | 0 % (aucun contrat d'approvisionnement) |
| `star_chaser` | ≥ 80 % | ≥ 60 % | **10 à 30 %** |
| `integrate_greedy`, `contract_overcommit`, `contract_full_kit`, `opportunist` | pour information | | |

Autres attentes :
- Jour médian : étoile 1 entre 60 et 100 pour `buy_all` (avant le jour 45, elle est donnée) ; étoile 2 entre 140 et 200 ; étoile 3 après le jour 200.
- `star_chaser` : pas plus de 8 faillites sur 40. Au-delà, viser 3 étoiles est un piège.
- Au moins un quart des seeds à 3 étoiles ont connu un échec de tir. Sinon, l'étoile 3 est une loterie.
- Un objectif limitant sur moins de 5 % des seeds, toutes stratégies confondues, est **décoratif** : le retirer ou le durcir (attendu pour `s2_contracts` et `s3_contracts`).
- Sonde d'exploit : si la démolition finale ajoute plus de 10 points au taux de 3 étoiles, traiter la question 5.

Procédure de recalage, à lancer après la fusion de la spec 008 (elle change l'argent de toutes les stratégies) :
1. Étoile 1 : si `buy_all` est sous 80 %, baisser `s1_cash` par pas de 50 000 (plancher 250 000), puis `s1_contracts` à 4.
2. Étoile 2 : régler `s2_cash` par pas de 50 000 pour amener `workshop` et `contract_engines` entre 50 et 80 %.
3. Étoile 3 : régler `s3_cash` par pas de 100 000 pour amener `star_chaser` entre 10 et 30 %. `s3_in_house` reste entre 43 et 50 : sous 43, on l'atteint sans moteurs.

## Hors périmètre
- La campagne : plusieurs niveaux, écran de sélection, déblocage effectif, second site.
- Règles propres à un niveau (prix, modèles de contrat, réputation de départ), événements scénarisés, niveaux de difficulté.
- Objectifs secondaires ou bonus, succès, score au-delà des étoiles, classement.
- Tutoriel et guidage pas à pas.
- Un vrai mode bac à sable (GDD §9) : le mode libre n'est que la suite de la partie, sans réglage.
- Objectifs liés à la fiabilité (« tirs sans échec ») tant qu'il n'existe pas de banc d'essai.
- Indication « étoile hors d'atteinte » : la sim ne prédit pas si un objectif cumulé peut encore être rempli.

## Décisions (validées par Flavien le 2026-11-18)
Toutes les recommandations ci-dessous sont retenues.
1. **Limite de temps, ou niveau sans limite comme dans Two Point ?** Sans limite, tout seuil s'atteint en attendant : à 360 jours, `buy_all` a 2,21 M, plus que la cible de l'étoile 3. Les étoiles ne mesureraient plus que la patience. *Recommandation : limite de 240 jours (l'horizon du bot, et 30 à 60 minutes de jeu). Le format accepte `duration_days = 0` si tu préfères tester sans limite. Une durée de 300 jours favoriserait l'intégration, qui se rembourse tard (chaîne moteur au 17e lanceur).*
2. **Étoile 2 « au choix » (atelier ou contrat) ?** C'est ce qui permet de pousser les systèmes sans tous les imposer, au prix d'un format un peu plus riche (`any_of`). *Recommandation : oui.*
3. **Deux étoiles impossibles en achetant tout au comptant ?** Avec la question 2, `buy_all` plafonne à 1 étoile. *Recommandation : oui. Un seul contrat d'approvisionnement suffit pour lever le blocage, ce qui reste « tout acheter ».*
4. **Une étoile reste-t-elle acquise après une faillite ?** *Recommandation : oui (définitive, enregistrée au profil). Sinon, viser l'étoile suivante devient trop risqué et le joueur s'arrête à la première.*
5. **Trésorerie : brute, hors avances, ou « valeur de l'entreprise » ?** La trésorerie brute se gonfle en signant des contrats. Hors avances, il reste la démolition de fin de niveau (environ 106 000 à pleine intégration). Une valeur d'entreprise (trésorerie − avances + valeur de revente des installations) rend la démolition neutre, mais elle est moins lisible et elle récompense le fait de construire. *Recommandation : hors avances maintenant, et décider sur la sonde d'exploit du bot.*
6. **Fin immédiate à 3 étoiles ?** *Recommandation : oui, écran de fin puis mode libre. Il n'y a plus rien à gagner.*
7. **Montrer l'étoile 3 dès le jour 0 ?** Two Point ne dévoile que l'étoile suivante. Ici la part maison est cumulée : la découvrir au jour 170 serait injuste. *Recommandation : tout montrer dès le briefing.*
8. **« Base aux normes » à l'étoile 3 ?** Pour qui vise 3 étoiles, l'objectif transforme le pari de la zone de sécurité (spec 008, question 1) en contrainte. Le pari reste entier pour les autres. *Recommandation : oui, mais corriger d'abord la spec 008 (l'atelier moteurs tourné tient en zone sûre et desservie), sinon l'objectif ne coûte presque rien.*
9. **Écarter « tirs sans échec » et la réputation ?** *Recommandation : oui pour ce niveau, pour les raisons données dans « Honnêteté ».*
10. **Supprimer `start.json` au profit du niveau.** C'est une décision d'organisation des données : le niveau devient l'unité de chargement des conditions de départ. *Recommandation : oui, avec un ADR court de l'architecte s'il la juge structurante.*
11. **Mode libre : étoiles gelées ?** Continuer à en gagner après la limite viderait la limite de son sens. *Recommandation : gelées.*
12. **Meilleur score conservé dès le MVP ?** Un seul niveau, mais « j'ai eu 2 étoiles, je retente » est la rejouabilité du MVP. *Recommandation : oui, c'est petit (dans l'issue 5).*

## Découpage en issues
Dépendances internes : 1 et 2 sont indépendantes. 3 dépend de 1 et 2. 4 dépend de 2. 5 et 6 dépendent de 3. Les issues de la spec 008 sont notées 008-1 à 008-7.

1. **Données et chargement du niveau** : `levels.json` (JSON de la section Données), `levels.schema.json`, contrôles du validateur, suppression de `start.json` et de son schéma, `levels` dans `GameData`, sélection du niveau (`data.level`, `data.start`, `active_site_id`), `level_list`. Critères 1 (chargement), 2 et 20.
   - Dépend de 008-1 et 008-2 (format de `start` avec positions et `owned_lots`). Si elles ne sont pas faites, déplacer le `start.json` actuel tel quel : 008-1 éditera alors `levels.json`.
   - Valeurs externes : `start.json` actuel (200 000, 4 techniciens, `integration_hall` : 4, ordre entrepôt, hall, pas) ; spec 008 (`owned_lots` `["lot_start"]`, positions du tableau « `start.json` (modifié) », contrôles des installations de départ) ; règle de `GameData` : pas de site implicite, pas d'ordre de fichier.
   - Modèle : **sonnet**.
2. **Compteurs et métriques (hors spatial)** : `stats`, `invoiced_total`, `metric_value` pour `contracts_completed`, `net_cash`, `reputation`, `in_house_share_pct`, `supply_completed_value`, valeurs par défaut de sauvegarde. Critères 6, 7, 8 et 18 (partie compteurs).
   - Aucune dépendance.
   - Valeurs externes : statuts `active` et `completed` et champ `advance` (spec 002, R1) ; les entrées sont consommées au `job_started`, le contrôle qualité précède la sortie, `output_blocked` retarde l'entrée en stock (specs 001 et 006, R4) ; facture = quantité expédiée × prix unitaire à l'étape 2, statuts `completed` et `terminated` (spec 007, R5 à R8) ; règle « Sauvegardes » de `sim/CLAUDE.md`.
   - Modèle : **sonnet**.
3. **Étoiles, fin de niveau et mode libre** : `GameState.level`, évaluation à l'étape 8 (R5 à R7), `continue_free_play`, rejet `level_over`, gel de `end_day`, `level_progress`, `level_summary`, mise à jour de `sim/CLAUDE.md`. Critères 1 (état), 3 à 5, 9, 11 à 17, 18 (partie `level`) et 19.
   - Valeurs externes : ordre finances puis faillite, `game_over` rejette toute commande et gèle `end_day` (spec 004, R1 à R4) ; un contrat réussi est `completed` le jour du tir (spec 002, R4).
   - Modèle : **sonnet**, revue par **fable** (interactions avec la faillite et le dernier jour).
4. **Métrique `site_violations`** : R4b et critère 10.
   - Dépend de 2 et de 008-3 (zone et desserte).
   - Valeurs externes : en zone si `gap < safety_radius_cells` (spec 008, R5) ; desservie si un entrepôt `ready` non endommagé est à `gap <= service_radius_cells`, uniquement pour les types à `slots` (R6) ; requête `facility_spatial`.
   - Modèle : **haiku**.
5. **UI : objectifs, notifications, briefing, écran de fin, profil** : widget de la barre du haut, panneau « Objectifs », bandeaux, événements ajoutés à `FAST_FORWARD_STOP_EVENTS`, écrans de briefing et de fin (qui remplace celui de la spec 004), `continue_free_play`, profil `user://profile.json`, les trois icônes (rectangles provisoires acceptés, puis `svg-artist`). Aucune règle côté UI : tout vient de `level_progress`, `level_summary` et `level_list`.
   - Dépend de 3 et de 008-5 (barre du haut, colonne d'icônes, panneaux superposés).
   - Valeurs externes : liste d'arrêt de l'avance rapide dans `ui/game_session.gd` (spec 005) ; `GameSession.end_day` et `submit` ne testent aujourd'hui que `game_over`.
   - Modèle : **sonnet**.
6. **Bot, rapport et recalage** : le bot joue le niveau, stratégie `star_chaser`, métriques et tableau de la section balance, sonde d'exploit, puis recalage des cibles dans `data/levels.json` selon la procédure (résumé du rapport joint à la PR).
   - Dépend de 3, 4 et 008-7 (placement `careful`). À relancer une fois toute la spec 008 fusionnée.
   - Valeurs externes : `integrate_staged` et sa `reserve` de 2 kits (spec 006) ; fournisseur de moteurs `brannoc_propulsion`, quantité minimale 4, périodes 14 ou 28 jours, 3 à 12 livraisons, requête `supply_contract_quote` (spec 007).
   - Modèle : **sonnet** pour le bot, **haiku** pour le recalage des valeurs.

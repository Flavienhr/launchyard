# 007 — Marché et contrats d'approvisionnement
Statut : validée (2026-11-14)

## Intention joueur
Aujourd'hui, un fournisseur est un prix fixe, un délai et une probabilité de retard. Une fois qu'on sait quoi commander, il n'y a plus rien à décider. Cette spec ajoute deux couches :

1. Un **marché** minimal et déterministe : les prix au comptant bougent chaque semaine, des **pénuries** temporaires font monter les prix, allongent les délais et réduisent la **capacité** des fournisseurs.
2. Des **contrats-cadres** (« tous les 28 jours, je reçois 8 moteurs ») assortis de garanties réalistes : prix fixe ou indexé, remise sur volume, pénalités de retard payées par le fournisseur, engagement d'achat (take-or-pay), frais de résiliation et clause de priorité en cas de pénurie.

Un contrat à prix fixe n'a de valeur que parce que le prix au comptant varie, et une clause de priorité n'en a que parce que les pénuries existent. Le marché est calibré pour que le comptant reste viable en moyenne : le contrat est une **assurance**, pas un passage obligé.

Dilemmes :
1. **Comptant, fixe ou indexé.** Le prix fixe protège des hausses, mais il coûte une prime de risque et se signe au cours du jour : signer pendant une pénurie, c'est figer un prix haut. L'indexé suit le marché, avec la remise et la sécurité d'approvisionnement mais sans la protection du prix. Le comptant est flexible, mais exposé aux hausses, aux pénuries et à la capacité limitée.
2. **Combien s'engager.** Plus de volume, c'est plus de remise. Mais les livraisons arrivent **qu'on en ait besoin ou non** : elles remplissent l'entrepôt, chaque facture tombe à date fixe, et si la cadence chute (échec de tir, pas de contrat de lancement), il faut payer la livraison dont on ne veut pas (take-or-pay) ou résilier.
3. **Payer la priorité ?** C'est une prime permanente contre un risque rare mais violent : une pénurie de moteurs bloque toute la production.
4. **Avec la spec 006 : contrat sur le produit fini ou sur la matière ?** Un contrat sur les lingots engage à faire tourner l'atelier moteurs. Un contrat sur les moteurs rend l'atelier moins utile.

## Règles

### R1. Indice de prix par composant
- L'état contient `market.index[component_id]`, un entier en pour mille (1 000 = prix de catalogue). Valeur initiale : `index_base` pour tout composant.
- **Prix au comptant** d'une entrée de catalogue : `spot_price = (unit_price × index_effectif + 500) div 1000` (arrondi à l'entier le plus proche, demi vers le haut, en entiers). `index_effectif = index + (pénurie active ? shortage_price_bonus_permille : 0)`.
- L'indice est **par composant** : deux fournisseurs du même composant suivent le même indice, chacun sur son propre `unit_price`.
- Un composant absent de `market.json` a un indice fixe de 1 000, jamais de pénurie et une capacité illimitée. C'est le cas des fixtures de la phase 2, qui restent donc vertes.

### R2. Mise à jour du marché (étape 7, flux `&"market"`)
- Le marché se met à jour **une fois par période** : à l'étape 7 du jour J, si `(J + 1) % market_period_days == 0`. Les nouveaux prix sont visibles au début du jour J+1.
- Pour chaque composant de `market.json`, par `id` trié (ordre lexicographique), tirages dans cet ordre :
  1. `shock` : entier uniforme dans `[−volatility_permille, +volatility_permille]` ;
  2. `index = clamp(index + shock + ((index_base − index) × reversion_pct) div 100, index_min, index_max)`, la division `div` étant tronquée vers zéro ;
  3. pénurie : si une pénurie est active et que `J + 1 >= ends_day`, elle se termine (`shortage_ended`), **sans tirage**. Sinon, si aucune pénurie n'est active, la sim tire `rng < shortage_chance` ; en cas de succès, elle tire une durée en périodes, entière uniforme dans `[shortage_min_periods, shortage_max_periods]`, puis fixe `ends_day = J + 1 + durée × market_period_days` (événement `shortage_started`). Une pénurie qui vient de se terminer ne peut pas recommencer à la même mise à jour.
- Le marché est **exogène** : aucune action du joueur ne modifie l'indice ni les pénuries. Les tirages du flux `market` ne dépendent que de la seed et du jour.

### R3. Effets sur la commande au comptant (`order`, étape 1)
- Coût = `quantity × spot_price` au moment de la commande, débité immédiatement (comme aujourd'hui).
- Délai = `lead_time_days + (pénurie active ? shortage_extra_lead_days : 0)`.
- **Capacité** : chaque entrée de catalogue a `spot_capacity_per_period` (optionnel ; absent = illimité). L'état compte `market.spot_used["supplier_id|component_id"]`, remis à 0 à chaque mise à jour du marché (R2). En pénurie, la capacité effective vaut `(spot_capacity_per_period × shortage_capacity_pct) div 100`. La commande est rejetée avec `supplier_capacity` si `spot_used + quantity > capacité effective` (champ `remaining` dans le rejet).
- Les livraisons sous contrat ne consomment **pas** la capacité au comptant : le fournisseur réserve sa production pour ses contrats.
- Retards (flux `deliveries`) et `warehouse_full` : inchangés.

### R4. Signature d'un contrat d'approvisionnement
`sign_supply_contract(supplier_id, component_id, quantity, period_days, deliveries, pricing, priority)`, à l'étape 1.
- `quantity` : unités par livraison, dans `[min_quantity, max_quantity]` de l'entrée de catalogue (`contract_terms`).
- `period_days` : une valeur de `period_options_days`.
- `deliveries` : nombre de livraisons, dans `[min_deliveries, max_deliveries]`.
- `pricing` : `fixed` ou `indexed`. `priority` : booléen.

Rejets, dans cet ordre : `not_in_catalog`, `contracts_not_offered` (l'entrée n'a pas de `contract_terms`), `invalid_quantity`, `invalid_period`, `invalid_duration`, `invalid_pricing`, `duplicate_contract` (il existe déjà un contrat `active` pour ce couple fournisseur-composant), `too_many_supply_contracts` (`max_supply_contracts` contrats `active` atteints).

Prix :
- `monthly_value = quantity × unit_price × 28 div period_days` (valeur de catalogue ramenée à 28 jours, sert uniquement au palier de remise).
- `discount_pct` : le plus grand palier de `volume_discount_tiers` tel que `monthly_value >= min_value` (0 si aucun).
- `pct = 100 − discount_pct + (priority ? priority_premium_pct : 0) + (pricing == fixed ? fixed_premium_pct : 0)`.
- Prix fixe : `contract_unit_price = (spot_price_à_la_signature × pct + 50) div 100`, figé pour toute la durée du contrat.
- Prix indexé : recalculé à chaque expédition, `(spot_price_du_jour × pct + 50) div 100`. Le spot du jour inclut le bonus de pénurie : l'indexé ne protège pas le prix.

Aucun débit à la signature. Le contrat est créé `active` avec `next_delivery_day = day + lead_time_days`, `deliveries_done = 0` et `skip_next = false`.

### R5. Livraisons sous contrat (étape 2)
Au début de l'étape 2, **avant** le traitement des commandes en transit, pour chaque contrat `active` par `id` croissant, si `next_delivery_day == day + 1` :
1. Si `skip_next` est vrai : rien n'est expédié ni facturé (le take-or-pay a été payé en R7), `skip_next = false`, et l'on passe directement au point 4.
2. Quantité expédiée : `quantity`, ou `(quantity × shortage_fill_pct) div 100` si une pénurie est active sur le composant et que `priority` est faux. Dans ce second cas, l'événement `supply_delivery_reduced` est émis. La part non livrée n'est ni facturée ni pénalisée (force majeure).
3. Facture : `quantité expédiée × prix unitaire` (R4), débitée **immédiatement**, même si la trésorerie devient négative (la faillite suit la spec 004). La sim crée ensuite une commande en transit `{supplier_id, component_id, quantity, arrival_day = day + 1, contract_id, scheduled_day = day + 1, invoice}`. Elle passe par le traitement normal de l'étape 2 dans la même résolution : tirage de retard (flux `deliveries`), `warehouse_full`, `delivery_received`.
4. `deliveries_done += 1`. Si `deliveries_done == deliveries`, le contrat passe en `completed` (`supply_contract_completed`). Sinon, `next_delivery_day += period_days`.

Précision : la facture tombe à la date **prévue**, qu'il y ait un retard ou un entrepôt plein (voir Questions).

### R6. Garanties
- **Pénalité de retard** (à la charge du fournisseur) : à la réception d'une livraison sous contrat, `days_late = jours de retard tirés` (pas l'attente due à l'entrepôt plein). `penalty = (invoice × min(late_penalty_cap_pct, late_penalty_pct_per_day × days_late)) div 100`, créditée à l'étape 8 du jour de la réception (événement `supply_penalty_earned` à l'étape 2, montant dans `daily_costs.supply_penalties`).
- **Frais de garde** : une livraison sous contrat qui attend faute de place (`warehouse_full`) coûte `holding_fee_per_unit_per_day × quantity × storage_units` par jour d'attente, débités à l'étape 8 (`daily_costs.holding_fees`). Les commandes au comptant ne paient pas de frais de garde (comportement actuel, voir Questions).
- **Priorité** : un contrat avec `priority` n'est pas réduit en pénurie (R5.2). Il subit quand même les retards normaux du fournisseur.

### R7. Sauter une livraison (take-or-pay)
`skip_supply_delivery(contract_id)` à l'étape 1. La livraison concernée est la **prochaine** (`next_delivery_day`).
- Rejets : `unknown_contract` (inexistant ou non `active`), `already_skipped` (`skip_next` déjà vrai), `notice_too_short` (`next_delivery_day − day < skip_notice_days`), `insufficient_funds`.
- Coût : `(quantity × prix_unitaire_courant × take_or_pay_pct) div 100`, débité immédiatement. Pour un contrat indexé, le prix courant est celui du jour de la commande. La livraison compte comme effectuée (R5.1).

### R8. Résilier
`terminate_supply_contract(contract_id)` à l'étape 1.
- Rejets : `unknown_contract`, `insufficient_funds`.
- Frais : `(livraisons_restantes × quantity × prix_unitaire_courant × termination_fee_pct) div 100`, avec `livraisons_restantes = deliveries − deliveries_done` (une livraison déjà sautée mais pas encore échue compte comme faite). Débit immédiat, le contrat passe en `terminated`, aucune livraison future. Les marchandises déjà expédiées (en transit) arrivent normalement.

### R9. Requêtes (aucun calcul dans l'UI)
- `spot_price(supplier_id, component_id)`, `spot_capacity_remaining(supplier_id, component_id)`, `market_snapshot()` (indice, variation depuis la période précédente, pénurie et son `ends_day`, par composant).
- `supply_contract_quote(args)` : rejet éventuel et sa raison (même ordre que R4), `discount_pct`, prix unitaire (indexé : au cours du jour), facture par livraison, unités d'entrepôt par livraison, engagement total estimé et frais de résiliation immédiats.
- `supply_schedule(days)` : liste datée des livraisons et factures prévues sur les `days` prochains jours (contrats et commandes en transit). C'est l'outil de trésorerie du joueur.

## Données

### `market.json` (nouveau)
Paramètres globaux :

| Paramètre | Valeur |
|---|---|
| `market_period_days` | 7 |
| `index_base` | 1 000 |
| `index_min` / `index_max` | 700 / 1 800 |
| `reversion_pct` | 20 |
| `shortage_price_bonus_permille` | 350 |
| `shortage_extra_lead_days` | 5 |
| `shortage_capacity_pct` | 30 |
| `shortage_min_periods` / `shortage_max_periods` | 2 / 5 |

Par composant (`components`) :

| component_id | volatility_permille | shortage_chance (par période) |
|---|---|---|
| `steel_sheet` | 60 | 0.03 |
| `alloy_billet` (spec 006) | 80 | 0.04 |
| `electronic_kit` (spec 006) | 100 | 0.04 |
| `composite_roll` (spec 006) | 50 | 0.03 |
| `engine` | 30 | 0.05 |
| `tank` | 30 | 0.03 |
| `avionics` | 40 | 0.04 |
| `fairing` | 30 | 0.04 |

Si la spec 006 n'est pas encore implémentée, les trois matières sont simplement absentes : le validateur vérifie que chaque `component_id` de `market.json` existe dans `components.json`.

### `supply_contracts.json` (nouveau)

| Paramètre | Valeur |
|---|---|
| `period_options_days` | [14, 28] |
| `min_deliveries` / `max_deliveries` | 3 / 12 |
| `volume_discount_tiers` | `[{min_value: 20000, pct: 2}, {min_value: 60000, pct: 5}, {min_value: 120000, pct: 8}]` |
| `fixed_premium_pct` | 6 |
| `priority_premium_pct` | 4 |
| `late_penalty_pct_per_day` | 2 |
| `late_penalty_cap_pct` | 20 |
| `holding_fee_per_unit_per_day` | 50 |
| `shortage_fill_pct` | 50 |
| `take_or_pay_pct` | 70 |
| `skip_notice_days` | 3 |
| `termination_fee_pct` | 40 |
| `max_supply_contracts` | 4 |

### `suppliers.json` (champs ajoutés par entrée de catalogue)

| Fournisseur | Composant | `spot_capacity_per_period` | `contract_terms` (`min_quantity`..`max_quantity`) |
|---|---|---|---|
| `gulf_steelworks` | `steel_sheet` | 40 | 8..40 |
| `northern_alloys` | `steel_sheet` | 20 | – (pas de contrat : le fournisseur « premium au comptant ») |
| `brannoc_propulsion` | `engine` | 8 | 4..16 |
| `halvard_tanks` | `tank` | 4 | 2..8 |
| `vey_avionique` | `avionics` | 6 | 2..8 |
| `corrandi_composites` | `fairing` | 3 | 1..4 |
| `valmorin_fonderies` (006) | `alloy_billet` | 30 | 8..40 |
| `kessring_metals` (006) | `alloy_billet` | 20 | 8..40 |
| `maelis_composants` (006) | `electronic_kit` | 30 | 6..30 |
| `tessaline_fibres` (006) | `composite_roll` | 20 | 3..15 |

### État (ajouts)
- `market` : `{index: {component_id: int}, prev_index: {…}, shortages: {component_id: ends_day}, spot_used: {"supplier|component": int}}`.
- `supply_contracts` : liste de `{id, supplier_id, component_id, quantity, period_days, deliveries, deliveries_done, next_delivery_day, pricing, priority, contract_unit_price (fixe uniquement), skip_next, status: active|completed|terminated}` ; `next_supply_contract_id`.
- Commandes en transit : champs optionnels `contract_id`, `scheduled_day`, `invoice`, `delay_days`, `waiting_for_space` (bool, mis à vrai par `warehouse_full`, pour les frais de garde).

### Ordres de grandeur visés (pour `make balance`, pas des tests)
- Indice hors pénurie : avec un retour à la moyenne de 20 % et un choc de ±80 ‰, l'écart typique est d'environ 8 %, avec des pointes à ±20 %.
- Fraction du temps en pénurie pour un composant : environ 0,04 × 3,5 / (1 + 0,14) ≈ **12 %**. Le comptant moyen ressort donc à environ 1 000 + 12 % × 350 ≈ **1 040 ‰**.
- Contrat fixe moteurs de 8 unités par 28 jours (valeur mensuelle 96 000, palier à 5 %) : 100 − 5 + 6 = 101 % du spot à la signature. Signé au cours moyen, il gagne environ 3 % sur le comptant moyen : **gain faible en moyenne, fort en pénurie**. Signé à 1 200 ‰, il perd. Avec la priorité (105 %), il devient à peu près neutre en prix et sert uniquement d'assurance d'approvisionnement.
- Pénurie de moteurs : capacité au comptant 8 → 2 par semaine, délai 10 → 15 jours, prix +35 %. Un joueur « tout comptant » lancé à 1 L1 par 12 jours (4 moteurs) passe à environ 1 L1 par 14 jours, à prix fort, pendant 2 à 5 semaines.
- Entrepôt : 8 moteurs livrés en une fois = 48 unités sur 100. Deux contrats mal calés (moteurs et réservoirs le même jour) saturent l'entrepôt de départ, et les frais de garde valent alors 50 × 48 = 2 400 par jour.
- Trésorerie : la facture d'une livraison de 8 moteurs vaut environ 97 000, soit la moitié de la trésorerie de départ.

### Schémas
- `market.schema.json`, `supply_contracts.schema.json` (nouveaux), plus les champs optionnels de `suppliers.schema.json`. Le validateur vérifie : `index_min <= index_base <= index_max`, `min_quantity <= max_quantity`, `min_deliveries <= max_deliveries`, paliers triés par `min_value` croissant, références de composants existantes.

## Commandes et événements

| Commande | Args | Rejets |
|---|---|---|
| `order` (modifiée) | inchangés | + `supplier_capacity` (champ `remaining`) |
| `sign_supply_contract` | `supplier_id`, `component_id`, `quantity`, `period_days`, `deliveries`, `pricing`, `priority` | `not_in_catalog`, `contracts_not_offered`, `invalid_quantity`, `invalid_period`, `invalid_duration`, `invalid_pricing`, `duplicate_contract`, `too_many_supply_contracts` |
| `skip_supply_delivery` | `contract_id` | `unknown_contract`, `already_skipped`, `notice_too_short`, `insufficient_funds` |
| `terminate_supply_contract` | `contract_id` | `unknown_contract`, `insufficient_funds` |

| Événement | Étape | Champs |
|---|---|---|
| `supply_contract_signed` | 1 | `contract_id`, `supplier_id`, `component_id`, `unit_price` (fixe) ou `null`, `discount_pct` |
| `supply_delivery_skipped` | 1 | `contract_id`, `delivery_day`, `cost` |
| `supply_contract_terminated` | 1 | `contract_id`, `fee` |
| `supply_delivery_dispatched` | 2 | `contract_id`, `order_id`, `quantity`, `unit_price`, `invoice` |
| `supply_delivery_reduced` | 2 | `contract_id`, `quantity_contracted`, `quantity_shipped` |
| `supply_penalty_earned` | 2 | `contract_id`, `order_id`, `days_late`, `amount` |
| `supply_contract_completed` | 2 | `contract_id` |
| `delivery_received`, `delivery_delayed`, `warehouse_full` (étendus) | 2 | + `contract_id` (ou `null`) |
| `market_updated` | 7 | `index` (par composant) |
| `shortage_started` / `shortage_ended` | 7 | `component_id`, `ends_day` |
| `daily_costs` (étendu) | 8 | + `holding_fees`, `supply_penalties` (crédit) |

Liste d'arrêt de l'avance rapide (spec 005) : ajouter `shortage_started`, `supply_delivery_reduced` et `supply_delivery_dispatched`. Le nouveau flux `&"market"` va dans `sim/rng.gd`, et `sim/CLAUDE.md` sera mis à jour (étapes 2 et 7).

## UI minimale pour le squelette
Rectangles et listes, aucune règle côté UI : tous les chiffres viennent des requêtes R9.
- **Panneau Marché** : une ligne par composant avec l'indice en % (« 112 % »), une flèche de variation depuis la période précédente, un badge « PÉNURIE jusqu'au jour 84 » et, par fournisseur, le prix au comptant et la capacité restante cette semaine. Afficher le jour de la prochaine mise à jour.
- **Formulaire de commande** (existant) : afficher le prix au comptant, le délai effectif et la capacité restante. Le bouton est désactivé avec la raison si la capacité est dépassée.
- **Panneau Contrats d'approvisionnement** :
  - liste des contrats actifs (fournisseur, composant, quantité par période, prochaine livraison, prix unitaire ou « indexé », livraisons restantes, priorité), avec les boutons « Sauter la prochaine livraison (coût X) » et « Résilier (frais Y) », coûts affichés avant le clic ;
  - formulaire « Nouveau contrat » : fournisseur et composant, quantité, période (14 ou 28 jours), nombre de livraisons, fixe ou indexé, case « Priorité en pénurie ». Le devis se met à jour à chaque modification : remise, prix unitaire, facture par livraison, place d'entrepôt par livraison comparée à la place libre, engagement total.
- **Échéancier** (requête `supply_schedule(30)`) : liste chronologique des 30 prochains jours, « J+3 : livraison 8 moteurs, facture 97 000 », avec la trésorerie projetée en regard des seuls coûts fixes connus. C'est l'outil qui rend la tension de trésorerie lisible.
- **Rapport du jour** : livraisons sous contrat, réductions pour pénurie, pénalités perçues, frais de garde payés.

## Critères d'acceptation
Fixtures (dans `tests/sim/fixtures.gd`) : composant `steel` (1 unité) ; fournisseur `s1` qui vend `steel` à `unit_price` 100, délai 2, `delay_chance` 0, `spot_capacity_per_period` 10, `contract_terms` 1..50 ; entrepôt de capacité 20 ; entretien et salaires à 0. `market` : période 7, `index_base` 1 000, bornes 500..2 000, `volatility_permille` 0 et `shortage_chance` 0 sauf mention contraire, `reversion_pct` 0, bonus de pénurie 500, délai supplémentaire 3, capacité en pénurie 30 %. Contrats : périodes [7, 14], livraisons 2..6, palier unique `{min_value: 3000, pct: 5}`, prime fixe 6, prime de priorité 4, pénalité 2 %/jour plafonnée à 20 %, frais de garde 10, `shortage_fill_pct` 50, take-or-pay 70, préavis 3, résiliation 40, au plus 2 contrats.

1. **Prix au comptant** : `market.index.steel` fixé à 1 200 dans l'état. `order(s1, steel, 3)` → coût 360.
2. **Arrondi** : `unit_price` 333, indice 1 001 → prix au comptant 333 ; indice 1 002 → 334 (333,666 arrondi).
3. **Mise à jour périodique** : `reversion_pct` 50, indice 1 400 au jour 0. → indice inchangé au début des jours 1 à 6 ; au début du jour 7, il vaut 1 200 ; `market_updated` n'est émis qu'à la résolution du jour 6.
4. **Bornes** : `volatility_permille` 1 000, 50 seeds × 70 jours → l'indice reste toujours dans [500, 2 000].
5. **Pénurie** : `shortage_chance` 1.0, durée 2..2. → au début du jour 7, pénurie active, `ends_day` = 21, prix au comptant 150, délai d'une commande = 5, capacité 3 : `order(s1, steel, 4)` → `supplier_capacity` (`remaining` 3). Au début du jour 21, la pénurie est terminée (`shortage_ended` émis à la résolution du jour 20). Une nouvelle pénurie ne commence pas avant la mise à jour suivante (jour 28).
6. **Capacité au comptant** : jour 0, `order(s1, steel, 6)` accepté, `order(s1, steel, 5)` → `supplier_capacity` (`remaining` 4). Au jour 7, `order(s1, steel, 5)` est accepté.
7. **Contrat à prix fixe** : indice 1 100, `sign_supply_contract(s1, steel, 10, 7, 3, fixed, false)`. Valeur mensuelle 10 × 100 × 28 / 7 = 4 000 ≥ 3 000, donc remise de 5 % ; pct = 101 ; prix = (110 × 101 + 50) div 100 = 111. L'indice passe ensuite à 1 500 → chaque facture vaut 1 110.
8. **Contrat indexé** : même contrat en `indexed`, l'indice vaut 1 500 le jour de l'expédition → prix = (150 × 95 + 50) div 100 = 143, facture 1 430.
9. **Calendrier et factures** : 100 000 crédits, signature au jour 0 (fixe, indice 1 000, prix 101), 3 livraisons, période 7. → réceptions au début des jours 2, 9 et 16 ; chaque facture de 1 010 est débitée à la résolution des jours 1, 8 et 15 ; `supply_contract_completed` à la résolution du jour 15 ; argent au jour 16 = 100 000 − 3 030 ; la capacité au comptant n'a pas été consommée.
10. **Entrepôt plein, frais de garde** : entrepôt 20/20, livraison de 10 prévue au jour 2. → facture débitée à la résolution du jour 1, `warehouse_full`, puis 10 × 1 × 10 = 100 de frais de garde par jour d'attente. On libère 10 unités à la main au jour 4 → réception à la résolution du jour 4, total des frais de garde = 300 (jours 1, 2 et 3).
11. **Pénalité de retard** : `delay_chance` 1, `delay_days` 3, facture 1 010. → réception 3 jours après la date prévue, `supply_penalty_earned` de (1 010 × 6) div 100 = 60, crédité à l'étape 8 du jour de réception.
12. **Plafond de pénalité** : `delay_days` 15 → pénalité de (1 010 × 20) div 100 = 202.
13. **Pénurie sans priorité** : pénurie active, contrat de 10 sans priorité → 5 expédiées et facturées, `supply_delivery_reduced` émis. Avec priorité → 10 expédiées.
14. **Take-or-pay** : contrat fixe à 101, prochaine livraison au jour 7. Au jour 3, `skip_supply_delivery` → débit de (10 × 101 × 70) div 100 = 707 ; au jour 7, rien n'arrive, rien n'est facturé et `deliveries_done` a augmenté de 1. Au jour 5 (préavis de 2 jours), le même appel → `notice_too_short`. Un second saut de la même livraison → `already_skipped`.
15. **Résiliation** : contrat de 3 livraisons, 1 effectuée, prix 101. `terminate_supply_contract` → frais (2 × 10 × 101 × 40) div 100 = 808, statut `terminated`, aucune livraison ensuite ; une livraison déjà en transit arrive quand même.
16. **Rejets de signature** : quantité 0 → `invalid_quantity` ; période 10 → `invalid_period` ; 7 livraisons → `invalid_duration` ; second contrat `s1`/`steel` → `duplicate_contract` ; troisième contrat sur un troisième couple fournisseur-composant (fixture : `s2` et `s3` identiques à `s1`), alors que deux sont actifs, → `too_many_supply_contracts`.
17. **Trésorerie négative** : 500 crédits, facture de 1 010 → débitée, argent −510 ; l'alerte de faillite de la spec 004 se déclenche.
18. **Marché exogène** : même seed, une partie sans commande et une autre avec commandes, contrats et sauts → mêmes `market.index` et mêmes pénuries pendant 90 jours (volatilité 80, `shortage_chance` 0.1).
19. **Non-régression** : fixtures de la phase 2 sans `market` ni `contract_terms` → tous les tests existants passent, les prix d'`order` sont inchangés.

## Ce que `make balance` doit montrer
Nouvelles stratégies de bot :

| Stratégie | Comportement |
|---|---|
| `buy_all` (existante) | comptant uniquement, désormais exposée au marché et aux pénuries |
| `contract_engines` | contrat fixe et prioritaire de 4 moteurs tous les 14 jours, renouvelé à l'échéance ; le reste au comptant |
| `contract_full_kit` | contrats fixes sans priorité sur tous les composants du kit, quantités calées sur 1 L1 tous les 14 jours |
| `contract_overcommit` | contrat de 16 moteurs tous les 14 jours (trop gros pour la cadence réelle), saute une livraison quand l'entrepôt dépasse 80 % |
| `opportunist` | comptant, mais signe un contrat fixe de 6 livraisons quand l'indice d'un composant du kit passe sous 950, sans priorité |

Métriques à ajouter : P10, médiane et P90 de l'argent final ; jours de production bloqués faute de pièce pendant une pénurie ; frais de garde, coûts de take-or-pay et de résiliation payés ; pénalités perçues ; indice moyen observé par composant.

Comportement attendu (240 jours, 40 seeds) :
- **Le marché est neutre** : l'indice moyen observé par composant est dans [980, 1 080].
- **Le comptant reste viable** : la médiane de `buy_all` est à moins de 10 % de la meilleure stratégie à contrats. Si l'écart est plus grand, les contrats sont obligatoires, et il faut baisser les pénuries ou monter les primes.
- **Les contrats réduisent la variance** : l'écart P90 − P10 de `contract_engines` est nettement inférieur à celui de `buy_all` (cible : au moins 25 % de moins), et son P10 est supérieur.
- **Le surengagement se paie** : `contract_overcommit` a la médiane la plus basse des stratégies à contrats, avec des frais de garde et de take-or-pay visibles dans le rapport. Faillites acceptées, mais pas plus de 5 sur 40.
- `opportunist` fait au moins aussi bien que `buy_all` en médiane : savoir lire le marché doit rapporter un peu.
- Avec la spec 006, `integrate_staged` est moins sensible aux pénuries de moteurs que `buy_all` (moins de jours bloqués).

## Hors périmètre
- Négociation (contre-offre, marchandage), réputation auprès des fournisseurs, prix dépendant de la réputation.
- Faillite ou disparition d'un fournisseur, nouveaux fournisseurs en cours de partie.
- Revente de stock sur le marché, spéculation.
- Influence du joueur sur le marché (ses achats ne font pas monter les prix).
- Annonces ou rumeurs de pénurie à l'avance.
- Indexation des paiements des contrats de lancement.
- Le navigateur web dans le jeu (GDD, Idées en attente) : une autre présentation des mêmes commandes.

## Décisions (validées par Flavien le 2026-11-14)
Toutes les recommandations ci-dessous sont retenues.
1. **Termes des contrats choisis par le joueur (formulaire), ou offres générées par les fournisseurs, comme le tableau des contrats de lancement ?** Le formulaire donne plus de prise et ne demande aucun tirage. Les offres sont plus « vivantes », mais ajoutent un flux RNG et du contenu. *Recommandation : formulaire maintenant. Des offres spéciales ponctuelles (« Brannoc propose −10 % sur 6 mois ») pourront venir plus tard comme événement.*
2. **Facturation à la date prévue ou à la réception ?** À la date prévue, c'est du take-or-pay pur : plus dur, plus lisible dans l'échéancier. À la réception, un retard du fournisseur soulage la trésorerie, ce qui brouille la pénalité. *Recommandation : à la date prévue.*
3. **Frais de garde aussi pour les commandes au comptant bloquées par l'entrepôt plein ?** C'est plus cohérent, mais cela modifie l'équilibrage de la phase 2. *Recommandation : contrats seulement pour l'instant, puis étendre au comptant si le bot montre que les joueurs « stockent chez le fournisseur » gratuitement.*
4. **Pénuries par composant ou par fournisseur ?** Par fournisseur, diversifier aurait un intérêt (deux fournisseurs de tôles), mais le moteur n'a qu'un fournisseur. *Recommandation : par composant (lisible : « pénurie mondiale d'électronique »). La question revient si l'on ajoute des fournisseurs.*
5. **Un second fournisseur de moteurs ?** C'est le remède évident au goulot du playtest, mais il réduirait la valeur des contrats prioritaires et de l'atelier moteurs (spec 006). *Recommandation : non. Le goulot moteur est le moteur des deux specs.*
6. **Pas du marché : hebdomadaire ou quotidien ?** *Recommandation : hebdomadaire. C'est lisible, il y a moins d'événements, et l'on peut planifier « la semaine prochaine ».*
7. **Montrer à l'avance une probabilité de pénurie (« tensions sur l'électronique ») ?** Cela crée de l'anticipation et récompense le contrat signé à temps, mais demande une règle de plus (état « tension » avant la pénurie). *Recommandation : pas dans cette spec. C'est la meilleure extension si le bot montre que `opportunist` n'a pas d'avantage.*
8. **Le prix indexé inclut-il le bonus de pénurie ?** Si oui, l'indexé ne protège que la quantité, et seulement avec la priorité. Si non, il devient presque aussi protecteur que le fixe. *Recommandation : oui, il l'inclut, pour garder trois options bien distinctes.*
9. **Valeurs des garanties** (pénalité de 2 %/jour plafonnée à 20 %, take-or-pay à 70 %, résiliation à 40 %) : dans la réalité, on voit plutôt 0,5 à 1 %/jour plafonné à 10 %. *Recommandation : garder des valeurs plus fortes que le réel pour que les garanties se voient dans la partie, et les ajuster au bot.*

## Découpage en issues
Dépendances : l'issue 1 est un prérequis de toutes les autres. L'issue 2 précède 3 et 4. Les issues 5 et 6 viennent en dernier. La spec 006 n'est pas un prérequis : sans elle, les trois matières sont absentes de `market.json`.

1. **Données et schémas** : `market.json`, `supply_contracts.json`, champs `spot_capacity_per_period` et `contract_terms` dans `suppliers.json` (toutes les valeurs des tableaux de la section Données), schémas et contrôles du validateur, chargement dans `GameData`. Valeurs externes : les ids `alloy_billet`, `electronic_kit`, `composite_roll` et les fournisseurs `valmorin_fonderies`, `kessring_metals`, `maelis_composants`, `tessaline_fibres` viennent de la spec 006 ; ne les inclure que s'ils existent déjà dans `components.json` et `suppliers.json`. Modèle : **haiku**.
2. **Marché : indice, mise à jour et pénuries (étape 7)** : état `market`, flux `&"market"` dans `sim/rng.gd`, R1 et R2, requêtes `spot_price` et `market_snapshot`, valeurs neutres quand le composant est absent, mise à jour de `sim/CLAUDE.md`. Critères 1 à 5, 18 et 19. Valeurs externes : convention de temps de la spec 001 (un fait du jour X est traité à la résolution du jour X−1). Modèle : **sonnet**.
3. **Comptant soumis au marché** : `order` au prix au comptant, délai de pénurie, capacité et rejet `supplier_capacity`, requêtes `order_quote` (existante, étendue) et `spot_capacity_remaining`. Critère 6. Modèle : **haiku**.
4. **Contrats : signature, livraisons et garanties** : `sign_supply_contract`, `skip_supply_delivery`, `terminate_supply_contract`, expédition à l'étape 2 avant les commandes en transit, réduction en pénurie, pénalités, frais de garde, extension de `daily_costs`, requêtes `supply_contract_quote` et `supply_schedule`. Critères 7 à 17. Valeurs externes : traitement actuel des commandes en transit à l'étape 2 (tirage de retard une seule fois par commande, `warehouse_full` avec nouvelle tentative chaque jour) ; la faillite suit la spec 004 (rien à changer, l'argent négatif suffit). Modèle : **sonnet** (opus en revue : beaucoup d'interactions temporelles).
5. **UI** : panneau Marché, prix et capacité dans le formulaire de commande, panneau Contrats avec formulaire et devis, échéancier, lignes du rapport du jour, événements ajoutés à la liste d'arrêt de l'avance rapide (`ui/game_session.gd`, spec 005). Modèle : **sonnet**.
6. **Stratégies de bot et métriques** : `contract_engines`, `contract_full_kit`, `contract_overcommit`, `opportunist` et les métriques de la section précédente dans `tests/balance_bot.gd` et `tests/balance.gd`. Valeurs externes : seuil d'`opportunist` à 950 ‰, saut d'`contract_overcommit` à 80 % d'entrepôt (paramètres du bot, pas de `data/`). Modèle : **sonnet**.

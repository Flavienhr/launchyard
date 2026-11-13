# 002 — Tableau de contrats
Statut : validée (2026-11-13)

## Intention joueur
Les contrats sont la seule source de revenus et le métronome de la partie. Ils transforment la production en pari daté.

Dilemmes :
1. **S'engager ou attendre.** Signer rapporte une avance immédiate (trésorerie pour commander le lanceur), mais engage une date limite et une pénalité. Refuser, c'est espérer une meilleure offre, alors que l'offre visible expire et que les coûts fixes tournent.
2. **Combien de contrats en parallèle.** Deux contrats signés = deux avances, mais il faut deux lanceurs, deux kits en entrepôt et un pas de tir libre aux bons moments. Chaque contrat raté coûte argent et réputation.
3. **Réputation comme porte d'entrée.** Les contrats les plus rentables (géostationnaire) exigent une réputation que seuls des succès apportent : un premier vol réussi vaut plus que son paiement.

## Règles

### R1. Modèle d'un contrat
`{id, template_id, client, orbit, payload_kg, payment, advance, penalty, deadline_day, status, offer_expires_day}` avec `status` ∈ `offer` | `active` | `completed` | `failed` | `expired`.
- `payment` : montant total. `advance = floor(payment × advance_pct / 100)`, versée à la signature. Le **solde** `payment − advance` est versé au succès du lancement.
- `penalty = floor(payment × penalty_pct / 100)`, payée si la date limite est manquée.
- `deadline_day` : dernier jour où un lancement réussi compte (inclus).

### R2. Génération des offres (seedée, étape 7)
- Le tableau a `offer_slots` emplacements. Chaque jour à l'étape 7, si le nombre d'offres visibles est < `offer_slots`, tirer `rng < offer_spawn_chance` ; si oui, générer **une** offre.
- Choix du modèle de contrat : tirage pondéré par `weight` parmi les modèles éligibles : `min_reputation <= reputation` **et** orbite atteignable depuis le site (spec 003, R1) si `generate_unreachable` est `false`.
- Tirages, dans cet ordre : modèle, client (uniforme dans `clients` du modèle), `payload_kg` (uniforme dans `[mass_min_kg, mass_max_kg]`, arrondi au multiple de `mass_step_kg`), délai (uniforme dans `[deadline_min_days, deadline_max_days]`).
- `payment = round_to(base_payment + per_kg_payment × payload_kg, payment_rounding)` ; `deadline_day = day + délai` ; `offer_expires_day = day + offer_validity_days`.
- Partie neuve : `initial_offers` offres générées par `new_game` (avec un RNG dérivé de la seed et dédié à l'initialisation), parmi les modèles éligibles à la réputation de départ.
- Une offre non signée dont `offer_expires_day <= day` passe en `expired` à l'étape 7 (avant la génération du jour, ce qui libère l'emplacement).

### R3. Signature
`accept_contract(contract_id)` à l'étape 1. Rejetée si :
- le contrat n'est pas une offre visible (`not_an_offer`) ;
- le nombre de contrats `active` atteint `max_active_contracts` (`too_many_contracts`) ;
- l'orbite n'est pas atteignable depuis le site (`orbit_unreachable`) ;
- `payload_kg` dépasse la capacité du meilleur modèle de lanceur disponible vers cette orbite (`payload_too_heavy`, spec 003, R1).

Sinon : `status = active`, `advance` créditée **immédiatement** (pas à l'étape 8 : le joueur doit pouvoir commander avec dans la même journée).

### R4. Fin d'un contrat
- **Succès** (spec 003) : lancement réussi avec ce contrat, au plus tard le `deadline_day`. À l'étape 8 du même jour : solde crédité, `status = completed`, réputation `+ rep_on_success`.
- **Échec du lanceur** (spec 003) : `status = failed` (`reason = launch_failed`), l'avance reste acquise (le client est assuré), pas de solde, pas de pénalité, réputation `+ rep_on_launch_failure` (négatif).
- **Date limite manquée** : à l'étape 8 du jour `deadline_day`, un contrat encore `active` passe en `failed` (`reason = deadline_missed`) : débit de `advance + penalty` (l'avance est remboursée en plus de la pénalité), réputation `+ rep_on_deadline_missed` (négatif). Un tir planifié pour ce contrat est annulé, le lanceur reste sur son pas de tir sans contrat (spec 003).
- Pas d'annulation volontaire d'un contrat signé en phase 2 (voir Questions).

### R5. Réputation
- Entier `reputation` dans `[reputation_min, reputation_max]`, valeur initiale `reputation_start`, borné après chaque variation.
- Effet en phase 2 : **uniquement** l'éligibilité des modèles de contrat (`min_reputation`). Pas d'effet sur les prix.

## Données

`contracts.json` (nouveau)

Paramètres globaux :

| Paramètre | Valeur |
|---|---|
| `offer_slots` | 4 |
| `initial_offers` | 3 |
| `offer_spawn_chance` | 0.3 |
| `offer_validity_days` | 8 |
| `advance_pct` | 20 |
| `penalty_pct` | 30 |
| `max_active_contracts` | 3 |
| `payment_rounding` | 1 000 |
| `mass_step_kg` | 50 |
| `generate_unreachable` | false |
| `reputation_start` / `min` / `max` | 50 / 0 / 100 |
| `rep_on_success` | +6 |
| `rep_on_launch_failure` | −15 |
| `rep_on_deadline_missed` | −10 |

Modèles (`templates`) :

| id | orbit | mass_min..max_kg | base_payment | per_kg_payment | deadline_min..max_days | weight | min_reputation | paiement résultant |
|---|---|---|---|---|---|---|---|---|
| `leo_small` | `leo` | 300..1 200 | 110 000 | 50 | 30..60 | 5 | 0 | 125 000..170 000 |
| `leo_heavy` | `leo` | 1 200..2 000 | 140 000 | 50 | 35..65 | 2 | 40 | 200 000..240 000 |
| `sso_observation` | `sso` | 300..1 000 | 150 000 | 60 | 30..60 | 3 | 0 | 168 000..210 000 |
| `gto_telecom` | `gto` | 200..500 | 220 000 | 120 | 45..75 | 2 | 60 | 244 000..280 000 |

Clients fictifs (champ `clients` par modèle) : « Archipel Télécom », « Coopérative Agrisonde », « Institut Héliade », « Cartoterra », « Réseau Boréal », « Observatoire de Kerlann ».

Repères d'équilibrage : un L1 entièrement acheté coûte 83 000 et le cycle le plus court (commande → tir) dure ~17 jours, soit ~41 000 de coûts fixes au départ. Un `leo_small` moyen (~150 000) laisse donc une marge de l'ordre de 25 000 à l'achat, nettement plus avec l'atelier. `deadline_min_days` = 30 garantit qu'une offre initiale est toujours faisable en achetant tout. Avec `reputation_start` 50 et +6 par succès, le géostationnaire s'ouvre après **2 succès**.

`state` (ajouts) : `contracts` (offres + signés + terminés), `next_contract_id`, `reputation`.

Schéma : `contracts.schema.json` ; le validateur vérifie que chaque `orbit` existe dans `orbits.json` (spec 003) et que `mass_min_kg <= mass_max_kg`, `deadline_min_days <= deadline_max_days`.

## Commandes et événements

| Commande | Args | Rejets |
|---|---|---|
| `accept_contract` | `contract_id` | `not_an_offer`, `too_many_contracts`, `orbit_unreachable`, `payload_too_heavy` |

| Événement | Étape | Champs |
|---|---|---|
| `contract_accepted` | 1 | `contract_id`, `advance` |
| `offer_expired` | 7 | `contract_id` |
| `offer_generated` | 7 | `contract_id`, `orbit`, `payload_kg`, `payment`, `deadline_day` |
| `contract_completed` | 8 | `contract_id`, `balance_paid` |
| `contract_failed` | 8 | `contract_id`, `reason` (`launch_failed` \| `deadline_missed`), `amount_debited` |
| `reputation_changed` | 8 | `delta`, `reputation` |

La génération et l'expiration sont rattachées à l'étape 7 (« événements aléatoires », ici le marché), les mouvements d'argent de fin de contrat à l'étape 8. **Aucun changement de l'ordre de résolution.**

## UI
- **Tableau des offres** : une carte par offre (client, orbite, masse, paiement, avance, pénalité, date limite en jours restants, expiration de l'offre). Marqueur si la masse est proche de la capacité. Bouton Signer (désactivé avec la raison si la sim refuserait).
- **Contrats signés** : liste triée par date limite, jours restants, lanceur et tir associés le cas échéant, alerte quand la date limite approche sans tir planifié.
- **Réputation** : jauge, avec le seuil du prochain modèle débloqué.
- Rapport du jour : nouvelles offres, offres expirées, contrats réussis ou échoués avec montants.

## Critères d'acceptation
Fixtures : un modèle `t_leo` (orbite `leo`, masse 1 000..1 000, `base_payment` 100 000, `per_kg_payment` 0, délai 20..20, poids 1, `min_reputation` 0), un modèle `t_gto` (`min_reputation` 60), `advance_pct` 20, `penalty_pct` 30, `offer_validity_days` 5, `offer_slots` 2, `initial_offers` 1, `max_active_contracts` 1, réputation de départ 50, site fixture atteignant `leo` et `gto`, lanceur fixture de capacité `leo` 2 000.

1. **Offres initiales** : `new_game` → exactement 1 offre, modèle `t_leo` (`t_gto` non éligible à 50), `payment` 100 000, `deadline_day` 20.
2. **Déterminisme** : même seed + mêmes commandes sur 60 jours avec `offer_spawn_chance` 0.5 → listes de contrats identiques ; seed différente → listes différentes.
3. **Génération forcée** : `offer_spawn_chance` 1.0, 1 offre visible, `offer_slots` 2 → après 1 jour, 2 offres ; après 2 jours, toujours 2 (tableau plein).
4. **Expiration** : `offer_spawn_chance` 0 ; après 5 jours, l'offre initiale est `expired`, `offer_expired` émis, 0 offre visible.
5. **Signature** : `accept_contract(1)` au jour 0 → argent + 20 000 immédiatement, `status = active`, `contract_accepted` émis.
6. **Limite de contrats actifs** : 1 contrat actif, une autre offre ; `accept_contract` → `too_many_contracts`, argent inchangé.
7. **Charge trop lourde** : offre de 2 500 kg vers `leo` (capacité 2 000) → `payload_too_heavy`.
8. **Orbite inaccessible** : site fixture sans `sso`, offre `sso` injectée dans l'état → `orbit_unreachable`.
9. **Date limite manquée** : contrat signé au jour 0 (`deadline_day` 20), aucun tir. → après 20 jours : toujours `active` ; après 21 jours : `failed` (`deadline_missed`), argent = initial + 20 000 − 20 000 − 30 000 − coûts fixes, réputation 40.
10. **Succès** (avec la spec 003) : contrat actif, tir réussi au jour 10 → à l'issue du jour 10, `completed`, solde 80 000 crédité, réputation 56.
11. **Échec du lanceur** (avec la spec 003) : fiabilité fixture 0 → `failed` (`launch_failed`), aucun débit de pénalité, avance conservée, réputation 35.
12. **Déblocage par réputation** : réputation forcée à 60, `offer_spawn_chance` 1.0, poids de `t_gto` élevé → une offre `t_gto` apparaît dans les jours suivants ; à 59, jamais (100 jours).
13. **Bornes** : réputation 5, échec de date limite (−10) → réputation 0, pas −5.

## Hors périmètre
- Négociation (prix, date), annulation volontaire, prolongation de date limite.
- Plusieurs charges utiles par tir (covoiturage).
- Effet de la réputation sur les prix ou le nombre d'offres.
- Objectifs de niveau et étoiles (phase 3).
- Faillite / fin de partie (voir Questions).

## Décisions (validées par Flavien le 2026-11-13)
Toutes les recommandations ci-dessous sont retenues.
1. **Avance à la signature** (20 %) ? Elle crée le dilemme de trésorerie « signer pour pouvoir acheter », mais rend la signature tentante même sans capacité de livrer. Recommandation : **oui**, compensée par le remboursement de l'avance + pénalité en cas de date limite manquée.
2. **Échec du lanceur : qui paie ?** Option A (proposée) : le contrat est perdu, l'avance est conservée, pas de pénalité, seule la réputation baisse. Option B : pénalité comme une date manquée. Option C : le contrat reste ouvert et on peut retenter avant la date limite. Recommandation : **A**. B rend l'échec doublement punitif (le lanceur est déjà perdu) ; C n'a pas de sens physique (la charge est détruite).
3. **Report météo le jour de la date limite** = contrat perdu ? C'est dur mais c'est ce qui donne un sens à la marge de planification. Alternative : une tolérance `weather_grace_days`. Recommandation : **pas de tolérance** en phase 2, l'UI doit montrer le risque de report du jour planifié ; on réévalue au playtest.
4. **Offres d'orbite inaccessible** : les afficher grisées (le joueur apprend qu'un autre site les ouvrirait) ou ne pas les générer ? Recommandation : **ne pas les générer** en phase 2 (`generate_unreachable` = false) : un seul site, aucun moyen d'y répondre, c'est du bruit.
5. **Faillite** : aujourd'hui l'argent peut devenir négatif sans conséquence. Pour savoir si la boucle est amusante, il faut pouvoir perdre. Recommandation : une règle minimale dans une petite spec à part, par exemple fin de partie après `bankruptcy_grace_days` = 10 jours consécutifs sous 0.
6. **Refuser explicitement une offre** pour libérer un emplacement ? Recommandation : **non** en phase 2 (l'expiration à 8 jours suffit) ; à ajouter si le tableau paraît bouché au playtest.
7. **Flux RNG** : la génération d'offres consomme le même RNG journalier que les livraisons. Ajouter une feature (ou un tirage) décale tous les tirages suivants du jour, ce qui rend les tests et les seeds d'équilibrage fragiles. Recommandation : un RNG **par sous-système** (`hash([seed, day, "contracts"])`, `"deliveries"`, `"launch"`…). Décision d'architecture : à porter en ADR par l'architecte avant l'implémentation de cette spec.

## Découpage en issues
1. **Générateur d'offres** : fonction pure `(rng, data, reputation, site, day) -> contract`, offres initiales dans `new_game`, génération et expiration à l'étape 7. Critères 1-4, 12. Modèle : **sonnet**.
2. **Signature et fin de contrat** : commande `accept_contract`, avance, échec par date limite à l'étape 8, réputation bornée, points d'entrée `complete_contract` / `fail_contract` appelés par la spec 003. Critères 5-9, 13 (10-11 viendront avec la 003). Modèle : **sonnet**.
3. **Données et schéma** : `contracts.json`, `contracts.schema.json`, validation croisée des orbites. Modèle : **haiku**.
4. **UI tableau de contrats** : offres, contrats signés, jauge de réputation. Modèle : **sonnet**.

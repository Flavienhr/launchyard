# 003 — Lancement
Statut : validée (2026-11-13)

## Intention joueur
Le tir est le moment de vérité où tout le travail logistique est payé (ou perdu). Il doit rester un moment de tension, pas un simple bouton.

Dilemmes :
1. **Quand tirer.** Tirer tôt libère le pas de tir et encaisse plus vite, mais en saison orageuse les reports s'enchaînent et grignotent la marge avant la date limite. Garder de la marge, c'est payer des jours de coûts fixes.
2. **Quel contrat d'abord.** Avec un lanceur prêt et deux contrats signés, le joueur choisit lequel servir et lequel risque la date limite.
3. **Le pas de tir comme goulot.** Un seul tir par pas et par jour, puis une remise en état. Un lanceur posé sur le pas sans contrat le bloque. Construire un second pas est l'un des gros réinvestissements possibles.

Honnêteté : le tirage de fiabilité lui-même n'offre **aucun choix** en phase 2 (pas de banc d'essai, pas de qualité des pièces). La seule prise du joueur sur le risque d'échec est d'attendre que la fiabilité du modèle monte, ce qui n'est pas un levier. Voir la question 1 (assurance) pour un dilemme supplémentaire peu coûteux.

## Règles

### R1. Orbites, site et capacité (sans physique)
- Chaque orbite a un azimut abstrait `azimuth_deg`. Le site a une liste `azimuth_ranges` (intervalles fermés `[min, max]`). Une orbite est **atteignable** si son azimut tombe dans au moins un intervalle.
- Capacité d'un modèle de lanceur vers une orbite depuis le site : `floor(payload_kg[orbit] × (100 + site.payload_bonus_pct[orbit]) / 100)`, bonus absent = 0. C'est la traduction en pourcentage de la règle « près de l'équateur, plus de charge vers le géostationnaire » du GDD.
- Les pas de tir héritent des contraintes de leur site (pas d'azimut propre en phase 2).

### R2. Planifier un tir
`schedule_launch(launcher_id, pad_id, contract_id, launch_day)` à l'étape 1. Rejetée si :
- le lanceur n'existe pas ou a déjà un tir planifié (`launcher_unavailable`) ;
- le pas n'est pas `ready`, est en remise en état, ou est occupé par un **autre** lanceur (`pad_unavailable`) ;
- le contrat n'est pas `active` ou a déjà un tir planifié (`contract_unavailable`) ;
- l'orbite n'est pas atteignable ou la charge dépasse la capacité du modèle (`orbit_unreachable`, `payload_too_heavy`) ;
- `launch_day < day + rollout_days` si le lanceur est encore dans le hall, ou `launch_day < day + 1` s'il est déjà sur ce pas (`too_early`) ;
- `launch_day > contract.deadline_day` (`after_deadline`).

Effet : le lanceur quitte le hall **immédiatement** (le hall est libéré pour l'assemblage suivant dès la résolution du jour), il est posé sur le pas, qui passe en `occupied`. Un objet `launch` `{id, launcher_id, pad_id, contract_id, launch_day, scrubs}` est créé.

`reschedule_launch(launch_id, launch_day)` : mêmes contraintes de date (`too_early` avec `day + 1`, `after_deadline`).
`cancel_launch(launch_id)` : le contrat redevient libre, le lanceur **reste sur le pas** (pas de retour au hall en phase 2).

### R3. Résolution du jour de tir (étape 5)
Pour chaque `launch` avec `launch_day == day`, par `id` croissant :
1. **Météo** : saison `s = ((day + site.start_day_offset) / season_length_days) % 4` (division entière). Tirer `rng < scrub_chance_by_season[s]` → **report** : `launch_day += scrub_recycle_days`, `scrubs += 1`, coût `scrub_cost` (étape 8), événement `launch_scrubbed`. Aucun tirage de fiabilité.
2. Sinon **fiabilité** : `p = min(reliability_max, reliability_base + reliability_gain_per_success × successes[model])`. Tirer `rng < p` → succès, sinon échec.
3. Le lanceur est consommé dans les deux cas (non réutilisable). Le pas passe en remise en état.
4. Les tirages se font dans cet ordre exact (météo puis fiabilité, lancement par lancement) pour la reproductibilité.

Un report qui pousse le tir au-delà de `deadline_day` n'est pas bloqué : le contrat échouera à l'étape 8 du jour limite (spec 002, R4), le tir est alors annulé et le lanceur reste sur le pas.

### R4. Conséquences
- **Succès** : `successes[model] += 1`, contrat `completed` et solde versé (spec 002), réputation `+ rep_on_success`, événement `launch_succeeded`.
- **Échec** : contrat `failed` (`launch_failed`), réputation `+ rep_on_launch_failure`, lanceur perdu, événement `launch_failed`. Le pas subit une remise en état longue. `successes` inchangé.
- La fiabilité affichée au joueur est celle du **modèle** (pas du lanceur individuel).

### R5. Remise en état du pas
- Après un tir (succès ou échec, pas après un report), le pas est indisponible jusqu'au jour `launch_day + refurb_days` (succès) ou `launch_day + refurb_days_after_failure` (échec), disponible au début de ce jour. Coût `refurb_cost` ou `refurb_cost_after_failure`, débité à l'étape 8 du jour du tir.
- Un seul tir par pas et par jour est garanti par l'unicité du lanceur sur le pas.
- Événement `pad_ready` quand le pas redevient disponible (étape 5, avant les tirs du jour).

### R6. Construction de pas supplémentaires
Le type `launch_pad` est `buildable` (spec 001, R2), avec `max_count` 2.

## Données

`orbits.json` (nouveau)

| id | nom | azimuth_deg |
|---|---|---|
| `leo` | Orbite basse | 90 |
| `sso` | Orbite polaire héliosynchrone | 195 |
| `gto` | Transfert géostationnaire | 95 |

`sites.json` (nouveau, un seul site en phase 2, fictif)

| Paramètre | Valeur |
|---|---|
| `id` | `pointe_sternes` |
| `latitude_deg` | 28 (informatif) |
| `azimuth_ranges` | `[[45, 110]]` → `leo`, `gto` oui ; `sso` non |
| `payload_bonus_pct` | `{}` (aucun bonus en phase 2) |
| `season_length_days` | 90 |
| `start_day_offset` | 0 |
| `season_names` | hiver, printemps, été, automne |
| `scrub_chance_by_season` | `[0.10, 0.15, 0.35, 0.25]` |

`launchers.json` (nouveau)

| Paramètre | `l1` |
|---|---|
| `recipe_id` | `assemble_l1` |
| `payload_kg` | `leo` 2 000, `sso` 1 400, `gto` 500 |
| `reliability_base` | 0.85 |
| `reliability_gain_per_success` | 0.02 |
| `reliability_max` | 0.97 |

`facilities.json` : type `launch_pad` → `upkeep_per_day` 600, `buildable` true, `build_cost` 120 000, `build_days` 20, `max_count` 2, `rollout_days` 2, `scrub_recycle_days` 1, `scrub_cost` 2 000, `refurb_days` 4, `refurb_cost` 5 000, `refurb_days_after_failure` 12, `refurb_cost_after_failure` 20 000.

`state` (ajouts) : `launches`, `next_launch_id`, `model_stats` (`{model: {successes}}`), par instance de pas `refurb_until_day` et `launcher_id`.

Repères : avec 15 % d'échec au premier vol et un kit à 83 000, l'espérance d'un premier `leo_small` reste positive (~+20 000) mais un échec précoce met la trésorerie en danger : c'est voulu. En été (35 %), la probabilité de 3 reports consécutifs est ~4 % : une marge de 3 à 5 jours suffit presque toujours.

## Commandes et événements

| Commande | Args | Rejets |
|---|---|---|
| `schedule_launch` | `launcher_id`, `pad_id`, `contract_id`, `launch_day` | `launcher_unavailable`, `pad_unavailable`, `contract_unavailable`, `orbit_unreachable`, `payload_too_heavy`, `too_early`, `after_deadline` |
| `reschedule_launch` | `launch_id`, `launch_day` | `unknown_launch`, `too_early`, `after_deadline` |
| `cancel_launch` | `launch_id` | `unknown_launch` |

| Événement | Étape | Champs |
|---|---|---|
| `launch_scheduled` / `launch_rescheduled` / `launch_cancelled` | 1 | `launch_id`, `launch_day` |
| `pad_ready` | 5 | `pad_id` |
| `launch_scrubbed` | 5 | `launch_id`, `season`, `new_launch_day`, `scrubs` |
| `launch_succeeded` | 5 | `launch_id`, `contract_id`, `reliability` |
| `launch_failed` | 5 | `launch_id`, `contract_id`, `reliability` |
| `contract_completed` / `contract_failed` | 8 | voir spec 002 |
| `daily_costs` (étendu) | 8 | `scrub_costs`, `refurb_costs` |

Le contrat est mis à jour par l'étape 8 à partir des résultats de l'étape 5 (les mouvements d'argent restent groupés à l'étape 8). **Aucun changement de l'ordre de résolution.**

## UI
- **Pas de tir** : statut (libre, occupé par tel lanceur, remise en état jusqu'au jour X), tir planifié.
- **Planifier un tir** : depuis un lanceur prêt, choisir pas, contrat (seuls les compatibles sont actifs, les autres grisés avec la raison), jour. Afficher pour le jour choisi la saison et la probabilité de report, la fiabilité du modèle, et la marge restante avant la date limite.
- **Calendrier** simple sur 30 jours : saisons colorées, dates limites des contrats, tirs planifiés, fins de remise en état.
- **Jour de tir** : un écran de résultat dédié (report / succès / échec) dans le rapport du jour, c'est le temps fort de la boucle.

## Critères d'acceptation
Fixtures : site atteignant `[[45, 110]]` ; orbites `leo` (90) et `sso` (195) ; saisons de 10 jours, `scrub_chance_by_season` paramétrable ; modèle `l1` (capacité `leo` 2 000, fiabilité paramétrable, gain 0.1, max 1.0) ; pas `pad` (`rollout_days` 2, `scrub_recycle_days` 1, `scrub_cost` 10, `refurb_days` 3, `refurb_cost` 100, `refurb_days_after_failure` 6, `refurb_cost_after_failure` 300) ; un lanceur `l1` dans le hall ; un contrat actif `leo` 1 000 kg, `payment` 100 000, avance 20 000 déjà versée, `deadline_day` 20.

1. **Atteignabilité** : `leo` atteignable, `sso` non. Capacité `leo` avec `payload_bonus_pct` `{leo: 10}` = 2 200.
2. **Tir trop tôt** : jour 0, `schedule_launch(..., launch_day = 1)` → `too_early` ; `launch_day = 2` → accepté, le lanceur est sur le pas, le hall est libre (un assemblage en attente de `hall_occupied` démarre à cette résolution).
3. **Après la date limite** : `launch_day = 21` → `after_deadline`.
4. **Succès** : scrub 0, fiabilité 1.0, tir planifié au jour 2. → après 3 jours : `launch_succeeded`, contrat `completed`, argent = initial + 80 000 − 100 − coûts fixes, `successes[l1]` = 1, plus aucun lanceur, pas en remise en état jusqu'au jour 5.
5. **Échec** : scrub 0, fiabilité 0.0. → après 3 jours : `launch_failed`, contrat `failed` (`launch_failed`), aucune pénalité, argent = initial − 300 − coûts fixes, `successes` = 0, pas indisponible jusqu'au jour 8.
6. **Report météo** : scrub 1.0 sur la saison du jour 2, 0 sur la saison suivante, saison qui change au jour 10. → `launch_scrubbed` chaque jour du jour 2 au jour 9 (8 reports, coût 8 × 10), succès au jour 10.
7. **Report jusqu'à l'échec du contrat** : `deadline_day` 3, tir au jour 3, scrub 1.0. → après 4 jours : `launch_scrubbed` puis `contract_failed` (`deadline_missed`) le même jour, tir annulé, le lanceur reste sur le pas, le pas est `occupied`.
8. **Fiabilité croissante** : `reliability_base` 0.5, gain 0.1 ; après 2 succès forcés, la fiabilité calculée vaut 0.7 ; plafonnée à `reliability_max`.
9. **Un tir par pas** : un lanceur sur le pas, un second lanceur dans le hall ; `schedule_launch` du second sur ce pas → `pad_unavailable`. Pendant la remise en état → `pad_unavailable` ; au jour de fin, accepté.
10. **Statistique seedée** : fiabilité 0.8, scrub 0, 1 000 tirs simulés sur des seeds 1..1000 → entre 760 et 840 succès (déterministe, donc stable en CI).
11. **Reproductibilité** : même seed, même plan de tirs → mêmes reports et mêmes résultats ; l'ordre des tirages est météo puis fiabilité, par `id` de tir.
12. **Annulation** : `cancel_launch` → contrat sans tir, lanceur toujours sur le pas ; `schedule_launch` du même lanceur sur le même pas avec `launch_day = day + 1` est accepté.

## Hors périmètre
- Fenêtres de tir horaires, plafond réglementaire de lancements, multi-sites.
- Retour d'un lanceur du pas vers le hall.
- Tests au banc d'essai, mises à feu statiques, qualité des pièces influençant la fiabilité.
- Échec partiel (mauvaise orbite), débris, enquête post-échec.
- Réutilisation du lanceur.
- Prévision météo bruitée (la probabilité saisonnière est connue exactement).

## Décisions (validées par Flavien le 2026-11-13)
Toutes les recommandations ci-dessous sont retenues.
1. **Assurance de lancement** pour donner un choix face au tirage de fiabilité : option `insured` à la planification, prime `insurance_premium_pct` (ex. 8 % du paiement) ; en cas d'échec, remboursement de `insurance_payout_pct` (ex. 60 %) du coût d'achat d'un kit L1. Recommandation : **oui, en issue séparée et optionnelle**, car c'est le seul vrai dilemme possible sur le risque d'échec en phase 2, pour 2 paramètres et un booléen. À retirer si le playtest montre que c'est une taxe automatique.
2. **Effet de la météo** : report d'un jour automatique (proposé) ou le joueur doit replanifier lui-même ? Recommandation : **automatique**, moins de clics, la tension vient de la marge qui fond.
3. **Fiabilité après un échec** : inchangée (proposé) ou petit gain « on apprend de l'échec » ? Recommandation : **inchangée** en phase 2, on gardera le levier « itérer vite ou rester prudent » pour l'arrivée du banc d'essai.
4. **Le lanceur quitte le hall dès la planification** (proposé) : simple et libère le hall tôt, mais un tir planifié à 30 jours immobilise le pas. Alternative : roll-out automatique à `launch_day − rollout_days`. Recommandation : **dès la planification** en phase 2, c'est un arbitrage lisible pas de tir vs hall.
5. **SSO inaccessible depuis le site de phase 2** : volontaire pour que la règle d'azimut existe, mais elle n'a aucun effet de jeu tant qu'il n'y a qu'un site. Faut-il plutôt rendre `sso` atteignable mais avec un bonus/malus de capacité ? Recommandation : **garder `sso` inaccessible** et ne pas générer ces offres (spec 002, question 4) ; la règle sert au multi-sites.
6. **Avance rapide « jusqu'au prochain événement »** (GDD §2) : sans elle, attendre 10 jours de livraison moteur = 10 clics, ce qui biaise le test « est-ce fun ». Recommandation : **l'inclure en phase 2** comme petite spec UI séparée (s'arrêter sur livraison, fin de job, offre, tir, date limite proche).
7. **Bot d'équilibrage** : `make balance` a besoin d'une stratégie scriptée qui joue la boucle complète (signer, commander, assembler, tirer). Recommandation : une issue `tools/` à part, après les trois specs, avec deux stratégies (tout acheter / atelier au jour 0) pour vérifier la cible « atelier rentabilisé au 3e-5e lanceur ».

## Découpage en issues
1. **Orbites, site et requêtes** : chargement de `orbits.json`, `sites.json`, `launchers.json` dans `GameData`, requêtes `is_orbit_reachable`, `payload_capacity`, `season_of(day)`, `model_reliability`, schémas. Critères 1 et 8. Modèle : **sonnet** (code), données : **haiku**.
2. **Planification et pas de tir** : `schedule_launch`, `reschedule_launch`, `cancel_launch`, états du pas, libération du hall, remise en état et `pad_ready`. Critères 2, 3, 9, 12. Modèle : **sonnet**.
3. **Résolution du tir à l'étape 5** : météo, fiabilité, conséquences, branchement sur les fins de contrat de la spec 002, coûts à l'étape 8. Critères 4-7, 10, 11. Modèle : **sonnet**.
4. **UI lancement** : pas de tir, dialogue de planification, calendrier, écran de résultat. Modèle : **sonnet**.
5. **(Optionnelle, si question 1 validée) Assurance de lancement**. Modèle : **haiku**.

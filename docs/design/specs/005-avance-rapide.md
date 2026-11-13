# 005 — Avance rapide « jusqu'au prochain événement »
Statut : validée (2026-11-13), issue de la décision 003-6

## Intention joueur
Attendre une livraison de 10 jours ne doit pas coûter 10 clics. Le joueur décide quand quelque chose se passe, pas quand rien ne se passe.

## Règles
C'est de la présentation pure : aucune règle de jeu, aucun changement dans `sim/`.
- R1. Le bouton « Avancer ▸▸ » appelle `end_day()` en boucle.
- R2. La boucle s'arrête **après** le premier jour qui produit au moins un événement d'une liste d'arrêt : `delivery_received`, `delivery_delayed`, `warehouse_full`, `job_completed`, `contract_offered`, `launch_result`, `bankruptcy_warning`, `game_over`, ou qui fait passer la trésorerie sous zéro. Les noms exacts suivront les événements définis par les specs 001 à 004.
- R3. Garde-fou : la boucle s'arrête dans tous les cas après `fast_forward_max_days` jours (30). Ce paramètre d'UI vit dans `ui/`, pas dans `data/`.
- R4. Tous les événements des jours sautés vont quand même dans le journal.

## Critères d'acceptation
1. Aucune commande en cours : l'avance s'arrête après 30 jours.
2. Une commande arrive dans 3 jours : l'avance s'arrête au jour de la livraison.
3. Le journal contient l'entretien de chaque jour sauté.

## Découpage en issues
1. Bouton et boucle dans `ui/game_session.gd` (`fast_forward()`) : critères 1-3, testés en appelant `GameSession` en headless. Modèle : **haiku**.

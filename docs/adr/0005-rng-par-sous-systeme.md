# 0005 — Un générateur aléatoire par sous-système
Date : 2026-11-13 · Statut : acceptée (décision 002-7)

## Contexte
Aujourd'hui, `end_day` crée **un** RNG par jour (`hash([seed, day])`), partagé par tous les systèmes. Les tirages sont donc consommés dans l'ordre de résolution. Si on ajoute un tirage quelque part (par exemple la génération d'offres de contrats), **tous les tirages suivants de la journée changent**, y compris les retards de livraison qui n'ont rien à voir.

Conséquences :
- une seed d'équilibrage ou de rapport de bug ne reproduit plus la même partie après l'ajout d'une feature ;
- un test qui s'appuie sur un tirage précis casse sans raison valable ;
- impossible de raisonner sur un système isolément.

## Décision
- Chaque sous-système tire dans **son propre flux** : `rng_for(state, stream)`, avec une seed `hash([game_seed, day, stream])`.
- Les flux sont nommés par des constantes : `&"deliveries"`, `&"contracts"`, `&"weather"`, `&"launch"`, `&"events"`. Un nouveau sous-système = un nouveau flux.
- Dans un même flux, l'ordre des tirages reste celui de l'itération (déterministe).
- La fonction vit dans `sim/rng.gd` (`class_name SimRng`). `end_day` ne crée plus de RNG lui-même.

## Alternatives écartées
- **Garder un RNG global et figer l'ordre des tirages** : fragile, chaque feature casse les seeds.
- **Un seul RNG pour toute la partie, stocké dans l'état** : pire, un tirage en plus décale toute la suite de la partie.

## Conséquences
- Ajouter le tirage des contrats ne change pas les livraisons d'une seed donnée.
- La migration change les tirages de livraison actuels. Les tests de phase 1 n'en dépendent pas : ils utilisent des probabilités 0, 1, ou comparent deux parties de même seed.
- À implémenter **avant** la spec 002 (issue dédiée).

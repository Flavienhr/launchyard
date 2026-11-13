# 0004 — Orchestration des agents via git, issues et PR
Date : 2026-11-12 · Statut : acceptée

## Contexte
On veut des agents spécialisés, une hiérarchie de modèles pour maîtriser les coûts, et à terme des agents autonomes sur l'infra perso (k3s).

## Décision
- Les agents ne communiquent **pas** entre eux directement. Le bus de messages, c'est **GitHub** : issues (tâches), PR (livrables), commentaires (review).
- Les rôles sont définis dans `.claude/agents/*.md`, avec un modèle et des outils restreints par rôle.
- Le déclenchement automatique viendra en phase B : un label `agent:<rôle>` sur une issue lance un workflow GitHub Actions qui exécute Claude Code en headless. Ensuite, en phase C, ce workflow tournera sur un runner self-hosted dans le k3s.
- Seul Flavien merge dans `main`.

## Alternatives écartées
- Orchestrateur multi-agents maison (file de messages, agents qui se parlent) : complexe, opaque, coûteux en tokens et difficile à auditer.

## Conséquences
- Chaque action d'agent est tracée, versionnée et réversible.
- Le goulot d'étranglement est la review humaine, et c'est voulu.

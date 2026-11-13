# Plan du projet

## 1. Roadmap

| Phase | Objectif | Critère de sortie |
|---|---|---|
| **0. Fondations** ✅ | Repo, CLAUDE.md, ADR, CI minimale | `make test` tourne en CI sur une sim vide |
| **1. Spike technique** 🚧 | Valider la chaîne complète sur un cas jouet | 1 ressource, 1 fournisseur, 1 bâtiment, « Fin de journée » qui fait évoluer l'argent ; test headless + export Mac/Linux/Windows |
| **2. Boucle de jeu (moche)** | La boucle complète jouable avec des rectangles | Commander → recevoir → assembler → lancer → être payé. **Est-ce que c'est fun ?** |
| **3. MVP** | Un niveau complet (1 site) avec objectifs en étoiles | Partie de 30-60 min jouable par un tiers, build itch.io |
| **4. Contenu et polish** | Style visuel final, sons, recherche, événements | – |
| **5. Multi-sites** | Campagne de plusieurs sites, réseau de flux | – |
| **DLC** | Orbite, Lune, Mars (nouveaux `Site` + systèmes) | – |

**Règle** : on ne passe à la phase suivante que si le critère de sortie est atteint. La phase 2 est le vrai test : si la boucle n'est pas amusante avec des rectangles, on itère sur le design, pas sur les graphismes.

## 2. Organisation : le studio d'agents

Flavien = **directeur créatif + producteur** : il fixe la vision, arbitre et merge. Tout passe par sa review.

| Rôle | Agent (`.claude/agents/`) | Modèle | Entrée | Sortie | Vérification |
|---|---|---|---|---|---|
| Game designer | `game-designer` | Opus | idée, GDD | spec dans `docs/design/specs/` | review Flavien |
| Architecte | (session principale) | Opus | spec | ADR, découpage en issues | review Flavien |
| Dev sim | `sim-dev` | Sonnet | issue + spec | code `sim/` + tests | `make test` |
| Dev UI | `ui-dev` | Sonnet | issue + maquette | scènes `ui/` | revue visuelle |
| Équilibrage | `data-balancer` | Haiku | spec + rapport `make balance` | `data/*.json` | `make validate` + `make balance` |
| Artiste SVG | `svg-artist` | Sonnet | guide de style + liste d'assets | `assets/src/*.svg` | `make assets` + revue visuelle |
| Relecteur | `reviewer` | Sonnet | diff d'une PR | commentaires | – |
| Release | **pas un agent** : pipeline CI | – | tag `vX.Y.Z` | builds 3 OS | CI |

### Flux de travail
```
Idée ──► game-designer ──► spec (docs/design/specs/NNN-*.md) ──► review Flavien
     ──► architecte ──► ADR si besoin + issues GitHub (1 issue = 1 tâche testable)
     ──► sim-dev / ui-dev / data-balancer / svg-artist ──► branche + PR
     ──► CI (test, validate, build) ──► reviewer ──► review Flavien ──► merge
```

### Une bonne issue pour un agent
- **Contexte** : lien vers la spec (pas de copie).
- **Périmètre** : fichiers ou dossiers autorisés.
- **Critère d'acceptation** : un test qui doit passer, ou une commande qui doit réussir.
- **Modèle suggéré** : label `model:haiku|sonnet|opus`.

## 3. Économie de tokens

Hiérarchie, dans l'ordre de préférence :
1. **Script (0 token)** : tests, validation, rendu d'assets, simulations d'équilibrage, export, release.
2. **Haiku** : tâches mécaniques sur une spec claire (remplir des données, traductions, triage, résumés de logs).
3. **Sonnet** : implémenter une issue bien spécifiée, relire une PR.
4. **Opus** : design, architecture, découpage, bugs transverses.

Détails et mécanismes : `docs/context-management.md`.

## 4. Infrastructure (progressive)

| Étape | Où tournent les agents | Déclencheur |
|---|---|---|
| A (maintenant) | Mac, Claude Code interactif | Flavien |
| B | GitHub Actions + Claude Code headless | label `agent:*` sur une issue |
| C | Runner GitHub self-hosted sur le k3s (VPS Hostinger) | idem, avec un coût CI maîtrisé |

**Communication entre agents = git + issues + PR.** Aucun orchestrateur maison tant que ça suffit : c'est asynchrone, tracé, versionné et rejouable.

**Sécurité** : `main` protégée, merge uniquement par Flavien, token GitHub à permissions minimales, secrets de release inaccessibles aux workflows d'agents, plafond de dépense API.

## 5. Pipeline de release
- PR : `make validate` + `make test` + build Linux.
- Tag `vX.Y.Z` (semver) : export Linux / macOS (universel) / Windows, puis publication itch.io via `butler`.
- Changelog généré depuis les Conventional Commits.
- macOS : signature et notarisation (compte Apple Developer) à partir de la phase 3.
- Binaires générés par la CI, jamais commités. Git LFS seulement pour les rares binaires sources.

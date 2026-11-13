# Gestion du contexte et des tokens

## Pourquoi c'est important
- **Coût** : à chaque tour, le modèle relit *tout* le contexte. Une session à 150k tokens paie ces 150k à chaque message. Le *prompt caching* rend un préfixe identique beaucoup moins cher, mais seulement s'il reste **stable** (même début de contexte : system prompt, puis CLAUDE.md, puis fichiers).
- **Qualité** : plus le contexte est grand, plus l'attention se dilue. Le modèle suit moins bien les consignes et mélange les détails. Un contexte court et pertinent bat un contexte long et exhaustif.

## Les mécanismes, du plus au moins persistant

### 1. CLAUDE.md hiérarchiques
- Le `CLAUDE.md` racine est chargé **à chaque session**. Il doit donc être court (moins de 80 lignes) et ne contenir que ce qui est vrai partout.
- Les `CLAUDE.md` de sous-dossiers (`sim/`, `ui/`, `data/`, `assets/`, `tools/`) sont chargés **quand l'agent travaille dans ce dossier**. On y met les règles locales.
- **Ce qui n'y va pas** : l'historique (c'est le rôle de git), le détail du design (dans `docs/design/`), les décisions argumentées (dans `docs/adr/`). Le CLAUDE.md **pointe** vers ces documents, il ne les recopie pas.

### 2. La mémoire est dans le repo, pas dans la conversation
- Specs, ADR et issues sont la source de vérité.
- Une tâche se lance dans une **session neuve** : « implémente l'issue #42 ». L'agent lit l'issue, la spec liée et le CLAUDE.md local. Rien d'autre.
- Session trop longue ? On écrit l'état dans l'issue ou la spec, puis on repart à zéro (`/clear`) plutôt que de traîner le contexte.

### 3. Subagents (`.claude/agents/*.md`)
- Chaque subagent a **son propre contexte** et ne renvoie qu'un résultat condensé. L'exploration bruyante ne pollue donc pas la session principale.
- Le champ `model:` du frontmatter fixe le modèle. C'est là qu'on applique la hiérarchie Haiku/Sonnet/Opus.
- Le champ `tools:` restreint les outils : moindre privilège, et moins de tentations hors périmètre.

### 4. Skills (`.claude/skills/`, plus tard)
Pour une procédure récurrente (« ajouter un composant à la nomenclature », « créer une installation »). Elle est écrite une fois et chargée **seulement quand elle sert**. On en crée une dès qu'une procédure a été expliquée deux fois.

### 5. Hooks (`.claude/settings.json`, phase 1)
Des automatismes exécutés par le harnais, pas par le modèle. Exemple : lancer `make validate` après toute édition dans `data/`. Ça ne coûte aucun token de raisonnement, et l'agent n'a pas à y penser.

## Règles pratiques
1. Répétable → script. Si on demande deux fois la même chose à un LLM, on écrit un script (le LLM peut l'écrire une fois).
2. Les tests ne consomment pas de tokens : `make test`, puis on ne lit que la sortie d'échec.
3. Petits fichiers, une responsabilité chacun. Lire 3000 lignes pour en modifier 10 gaspille des tokens.
4. `grep` avant `Read`. Lire des extraits, pas des fichiers entiers.
5. Ne jamais coller de logs ou de JSON complets : extraire la partie utile par script.
6. Design et architecture en Opus, **une fois**, puis exécution en Sonnet ou Haiku à partir des documents produits.

## Pourquoi les docs agents sont en Markdown et pas en Typst
Les modèles lisent le Markdown nativement, il n'y a pas d'étape de compilation, et GitHub l'affiche directement. Les **livrables humains** (pitch, rapport, présentation) restent en Typst et pourront être générés depuis ces Markdown.

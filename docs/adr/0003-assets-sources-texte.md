# 0003 — Assets : sources texte, binaires générés
Date : 2026-11-12 · Statut : acceptée

## Contexte
Les assets doivent être générés par IA tout en restant modifiables à la main et versionnables. Une image ou un audio générés sont des résultats finaux, sans source éditable.

## Décision
| Type | Source versionnée (`assets/src/`) | Rendu (`tools/`, non versionné) |
|---|---|---|
| Graphismes | SVG | **import SVG natif de Godot** (rastérisé à l'import, rien à rendre) |
| Effets sonores | paramètres sfxr en JSON | WAV |
| Musique | MIDI | OGG via soundfont (FluidSynth) |
| Textes / i18n | CSV | import Godot natif |

- Style unique : vectoriel épuré vue de dessus, esthétique « mission control » (`assets/src/STYLE.md`).
- Audio : les binaires rendus iront dans `assets/build/` (ignoré par git), générés par script.
- `make assets` vérifie les SVG (viewBox, palette, balises interdites) via `tools/lint_assets.py`.

## Alternatives écartées
- Génération d'images par diffusion : style incohérent, rien de retouchable, statut juridique flou, et Steam impose de déclarer le contenu généré par IA.
- Musique générée en audio (Suno, etc.) : aucune source éditable.

## Conséquences
- Toute la chaîne d'assets est reproductible et revue en diff.
- Dépendances outils : Python (`tools/requirements.txt`), plus tard `fluidsynth` pour l'audio.

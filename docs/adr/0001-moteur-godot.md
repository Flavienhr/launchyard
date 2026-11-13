# 0001 — Moteur : Godot 4 + GDScript
Date : 2026-11-12 · Statut : acceptée

## Contexte
C'est un jeu de gestion : beaucoup d'interface, une 2D vectorielle, et une cible Mac (prioritaire), Linux et Windows. Le code et les assets doivent être produits en grande partie par des agents IA, puis rester lisibles et versionnables par un humain.

## Décision
- **Godot 4**, scripts en **GDScript**.
- Version épinglée : **4.7.2-stable** (variable `GODOT_VERSION` dans `.github/workflows/`). Changer de version = mettre à jour cet ADR + la CI dans la même PR.
- Renderer **Compatibility** (OpenGL/ANGLE) : suffisant pour de la 2D et le plus portable.

## Alternatives écartées
- **Bevy (Rust)** : excellent pour un code entièrement textuel, mais son UI est encore trop immature pour un jeu de gestion.
- **Unity** : fichiers de scène peu lisibles, beaucoup de binaires, licence propriétaire.
- **GDScript ou C#** : C# alourdit l'export et la CI pour un gain faible ici.

## Conséquences
- Scènes `.tscn` et ressources `.tres` en texte : diffables et éditables par les agents.
- Export des 3 OS depuis la CI Linux. La signature et la notarisation macOS seront à prévoir.
- Si la sim devient trop lente, on pourra porter `sim/` en Rust via GDExtension sans toucher à `ui/`, grâce à la séparation imposée par l'ADR 0002.

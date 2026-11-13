# Game Design Document (vivant)

> Statut : brouillon v0. Les sections marquées **[À DÉCIDER]** attendent un arbitrage de Flavien.

## 1. Pitch
Tu diriges une jeune entreprise de lancement spatial. Tu construis ta base sur une parcelle côtière : entrepôts, usines, banc d'essai, pas de tir. Tu négocies avec tes fournisseurs, tu embauches et tu remplis des contrats de lancement avant leur date limite. Le réalisme est **industriel et logistique**, pas physique.

**Inspirations** : Two Point Hospital/Campus (structure, construction, staff, objectifs), Surviving Mars (réseaux, événements, recherche), Prison Architect (lisibilité vue de dessus), l'actualité des nouveaux sites de lancement. Toutes les marques, entreprises et sites sont **fictifs**.

**Ton** : [À DÉCIDER] humour décalé ou sérieux passionné.

## 2. Boucle de jeu : le tour journalier
```
┌─ Phase de planification (temps arrêté) ───────────────────┐
│  construire / agrandir · commander des pièces · embaucher │
│  affecter le staff · accepter des contrats · lancer       │
│  la recherche · planifier un tir                          │
└───────────────────────── [ Fin de journée ] ──────────────┘
                                 │
┌─ Résolution (sim) ─────────────▼──────────────────────────┐
│  livraisons · production · tests · fatigue/moral          │
│  météo · événements · lancements · finances               │
└─────────────────────────────────┬─────────────────────────┘
                                  ▼
            Rapport du jour (recettes, dépenses, alertes)
```
- **Avance rapide** : « passer jusqu'au prochain événement » (livraison, fin de construction, fenêtre de tir), qui enchaîne les jours sans interruption tant que rien ne demande d'action.
- Plus tard, possible : un « replay » animé de la journée (le staff qui bouge) en pur cosmétique, sans effet sur la sim.

## 3. Entités principales
| Entité | Attributs clés |
|---|---|
| **Site** | latitude, azimuts autorisés, météo saisonnière, accès (port/rail/route), plafond réglementaire de lancements, vivier de recrutement, taille de parcelle |
| **Installation** | type, emprise sur la grille, capacité, staff requis, coût de construction et d'entretien, durée de construction |
| **Composant** | id, masse, temps de fabrication, recette (sous-composants), stockage requis |
| **Fournisseur** | catalogue, prix, délai, fiabilité (retards), qualité (taux de défaut) |
| **Staff** | métier, compétence (1-5), traits, salaire, fatigue, moral, formation |
| **Contrat** | client, orbite cible, masse de charge utile, date limite, paiement, pénalité |
| **Lanceur** | modèle, nomenclature, fiabilité cumulée, réutilisable (oui/non) |

## 4. Nomenclature du lanceur (MVP)
```
Lanceur L1
├── Étage 1 : moteur ×N + réservoir + avionique
├── Étage 2 : moteur ×1 + réservoir + avionique
├── Coiffe
└── Ergols (LOX + carburant) : livrés par camion, stockage limité, évaporation journalière
```
**Dilemme central : acheter ou fabriquer.** L'achat est rapide, mais cher et dépendant d'un fournisseur. La fabrication demande un gros investissement, puis devient moins chère et donne la maîtrise de la qualité.

## 5. Sites et fenêtres de tir (sans physique)
- Une orbite exige un azimut autorisé par le site. Exemple : une orbite polaire n'est possible que depuis certains sites.
- Plus le site est près de l'équateur, plus la charge utile vers une orbite géostationnaire est grande (bonus en %).
- Chaque jour de tir planifié a une probabilité de report liée à la météo saisonnière du site.
- Un seul tir par pas de tir et par jour. Le pas de tir doit être remis en état entre deux tirs (durée en jours).

## 6. Progression
- **Campagne** : un site par niveau, avec des objectifs notés de 1 à 3 étoiles.
- **Recherche** : réutilisabilité, nouveaux moteurs, automatisation, etc.
- **Fiabilité** : chaque test ou vol réussi augmente la fiabilité ; un échec fait perdre de la réputation. Itérer vite ou rester prudent est un choix du joueur.

## 7. Style visuel
- **Vectoriel épuré, vue de dessus**, esthétique d'interface de mission control : fond sombre, lignes fines, palette restreinte avec des couleurs d'accent par catégorie (logistique, production, lancement).
- Tous les assets en **SVG source** générés ou retouchés, puis rendus par script.
- Guide de style détaillé : `assets/src/STYLE.md` (à écrire en phase 1).

## 8. MVP (phase 3)
1 site côtier · 1 lanceur non réutilisable · 3-4 fournisseurs · ~6 installations (entrepôt, atelier réservoirs, hall d'intégration, banc d'essai, pas de tir, bureaux/cantine) · 5 métiers · tableau de contrats · météo saisonnière · objectifs en étoiles.

## 9. Hors périmètre MVP
Réutilisabilité, multi-sites, Lune/Mars, mode bac à sable, staff animé.

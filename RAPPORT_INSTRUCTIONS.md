# Instructions de Génération du Rapport

Ce document contient les directives pour la rédaction du rapport de projet Master BDD comparant Cypher 5, Cypher 25, SQL et Neo4j GDS.

## Structure Générale du Rapport

### 1. Introduction
- Contexte : Projet Master niveau bases de données
- Objectif : Comparaison Cypher 5 vs Cypher 25 sur données de vols US 2015
- Dataset : Kaggle Flight Delays 2015 (107,230 vols, 313 aéroports, 14 compagnies)
- Période : 1-7 janvier 2015
- Technologies : Neo4j (Cypher 5 & 25), PostgreSQL, Neo4j GDS

### 2. Choix du Dataset
**Important** : Expliquer pourquoi le dataset IDFM a été abandonné

#### IDFM GTFS (abandonné)
- Structure complexe : 9 fichiers CSV interconnectés
- agency.csv → routes.csv → trips.csv → stop_times.csv → stops.csv
- Problème : Trop orienté relationnel, peu adapté aux graphes
- Redondance excessive pour modélisation en graphe

#### Kaggle Flight Delays 2015 (choisi)
- Structure naturelle de graphe : Aéroports = nœuds, Vols = relations
- Propriétés riches : distance, delay, timestamps
- Cas d'usage pertinents : chemins pondérés, algorithmes de graphe
- Volume gérable : 107k vols sur 1 semaine

### 3. Modélisation des Données

#### Modèle Neo4j (Graphe)
```
(:Airport {iata_code, name, city, state, country, latitude, longitude})
-[:FLIGHT {airline, departure_ts, arrival_ts, distance, delay}]->
(:Airport)

(:Airline {iata_code, name})
```

**Points clés** :
- Aéroports = nœuds (313 entités)
- Vols = relations (107,230 arêtes)
- Timestamps en ISO 8601 : "2015-01-01T23:54:00"
- Propriétés sur relations : distance (miles), delay (minutes)

#### Modèle PostgreSQL (Relationnel)
```sql
airlines (iata_code PK, name)
airports (iata_code PK, name, city, state, country, latitude, longitude)
flights (id PK, source FK, target FK, airline FK, departure_ts, arrival_ts, distance, delay)
```

**Contraintes** :
- Foreign keys : source, target, airline
- CHECK : source != target, distance > 0
- Indexes : source, target, departure_ts, distance, delay
- Index composé : (source, target)

### 4. Import et Nettoyage des Données

#### Scripts de Préparation
**normalize_data.py** :
- Filtrage : Première semaine de janvier 2015 uniquement
- Gestion timestamps : Minuit (2400 → 0000), vols overnight
- Suppression : Lignes avec timestamps manquants
- Filtrage aéroports : Seulement ceux utilisés dans les vols

#### Import Neo4j (import_neo4j.cypher)
- LOAD CSV avec headers
- Contraintes d'unicité : airport_iata_unique, airline_iata_unique
- Index : city, state, departure_ts, arrival_ts, delay, distance

#### Import PostgreSQL (import_postgresql.sql)
- \COPY avec format CSV
- Création tables + contraintes + indexes
- Vérification : COUNT(*) par table

### 5. Requêtes Comparatives (4 obligatoires)

#### Requête 01 : Increasing Property Paths
**Fichiers** : `queries/01_increasing_property_paths.cypher/.sql`

**Problème SIGMOD** :
- Cypher 5 : `reduce()` dans WHERE = NP-complet
- Exemple : Chemins avec distances croissantes
- Timeout à partir de 10 nœuds (Hamiltonian path)
- 93% des programmeurs sous-estiment la complexité

**Solution Cypher 25** :
- `allReduce()` évite le NP-complet
- Syntaxe déclarative optimisée
- Performance acceptable

**À inclure** :
- Exemple concret avec LAX → JFK (distances croissantes)
- Comparaison timings Cypher 5 vs Cypher 25
- Référence à l'article SIGMOD

#### Requête 02 : Quantified Graph Patterns
**Fichiers** : `queries/02_quantified_graph_patterns.cypher/.sql`

**Cypher 5 (verbeux)** :
```cypher
MATCH path = (start)-[:FLIGHT]->(hub1)-[:FLIGHT]->(hub2)-[:FLIGHT]->(end)
WHERE start <> hub1 AND start <> hub2 AND start <> end
  AND hub1 <> hub2 AND hub1 <> end
  AND hub2 <> end
```
7 lignes, 6 comparaisons WHERE

**Cypher 25 (concis)** :
```cypher
MATCH path = (start)(()-->(:Airport)){3}(end)
WHERE allReduce(...)  // Détection cycles simplifiée
```
1 ligne, syntaxe déclarative

**Réduction du code** :
| Cas d'usage       | Cypher 5   | Cypher 25 | Réduction |
|-------------------|------------|-----------|-----------|
| Exactement N hops | 7 lignes   | 1 ligne   | 86%       |
| Range (2-3 hops)  | 2 requêtes | 1 requête | 50%       |

**REPEATABLE ELEMENTS - NE PAS UTILISER** :
- Fonctionnalité Cypher 25 : `MATCH REPEATABLE ELEMENTS path = ...`
- Permet de revisiter les mêmes nœuds (cycles)
- **Pourquoi non pertinent** :
  - Chaque vol a un timestamp unique → relations déjà différentes
  - Pas de cycles réalistes dans les itinéraires commerciaux
  - Modèle avec timestamps > modèle simplifié

**À mentionner dans le rapport** :
```
REPEATABLE ELEMENTS est une fonctionnalité Cypher 25 permettant
de revisiter les mêmes nœuds dans un chemin. Cependant, elle n'est
pas applicable à notre modèle car chaque vol (relation FLIGHT) est
unique grâce à son timestamp departure_ts. Le comportement par défaut
de Cypher suffit.
```

#### Requête 03 : Shortest Path Algorithms
**Fichiers** : `queries/03_shortest_path_algorithms.cypher/.sql`

**Exemple** : JFK → DAY (Dayton), optimal = 590 miles via BWI

**Cypher 5 shortestPath()** :
- Compte uniquement les sauts (BFS)
- Ne prend PAS en compte les poids (distance)
- Résultat : [JFK, ATL, DAY] = 1192 miles (non optimal, +102%)
- Temps : ~15ms

**Cypher 25 exploration exhaustive** :
- `[:FLIGHT*1..2]` avec `reduce()` pour calculer distance totale
- Résultat : [JFK, BWI, DAY] = 590 miles (optimal)
- Temps : 293ms pour *1..2
- **EXPLOSION COMBINATOIRE** : 137 secondes pour *1..3 (facteur 467x)
- Inutilisable au-delà de 2-3 sauts

**GDS Dijkstra (SEULE SOLUTION)** :
- Projection du graphe avec propriété distance
- Algorithme optimisé en C++
- Résultat : [JFK, BWI, DAY] = 590 miles (optimal garanti)
- Temps : 37ms (8x plus rapide que Cypher exhaustif)
- Scale à N sauts sans problème

**Tableau performances** :
| Approche              | Temps  | Distance | Optimal? | Complexité        |
|-----------------------|--------|----------|----------|-------------------|
| Cypher shortestPath() | 15ms   | 1192 mi  | ✗        | BFS (min sauts)   |
| Cypher exhaustif *1..2| 293ms  | 590 mi   | ✓        | O(branches^depth) |
| Cypher exhaustif *1..3| 137s   | 590 mi   | ✓        | 467x plus lent!   |
| GDS Dijkstra          | 37ms   | 590 mi   | ✓        | O(E log V)        |

**Limitations techniques** :
- Cypher pur : Pas de priority queue → Dijkstra impossible
- SQL WITH RECURSIVE : Même problème, scan séquentiel
- GDS : Implémentation C++, priority queue native

**Conclusion** :
- Chemins pondérés → GDS Dijkstra OBLIGATOIRE
- Chemins non pondérés → shortestPath() suffit

#### Requête 04 : GDS vs Pure Cypher 25
**Fichiers** : `queries/04_gds_algorithms_in_cypher25.cypher`

**Algorithmes GDS** :
- Degree centrality : Identifier les hubs (ATL, ORD, DFW)
- Triangle count : Patterns de connexions entre aéroports
- Performances : 10-1000x plus rapide que Cypher pur

**Comparaison** :
- Pure Cypher : Possible mais très lent
- GDS : Algorithmes optimisés, production-ready

### 6. Contraintes et Indexes

#### Neo4j
**Contraintes** :
- `airport_iata_unique` : Unicité des codes IATA aéroports
- `airline_iata_unique` : Unicité des codes IATA compagnies

**Index** :
- Sur nœuds : city, state
- Sur relations : departure_ts, arrival_ts, delay, distance

#### PostgreSQL
**Contraintes** :
- PRIMARY KEY : iata_code (airports, airlines), id (flights)
- FOREIGN KEY : source, target, airline
- CHECK : source != target, distance > 0

**Index** :
- Simples : source, target, airline, departure_ts, arrival_ts, delay, distance
- Composés : (source, target), DATE(departure_ts)
- Géospatial : (latitude, longitude)

### 7. Plans d'Exécution et Analyse

**À inclure** :
- PROFILE pour requêtes Cypher (Neo4j Browser)
- EXPLAIN ANALYZE pour SQL (PostgreSQL)
- Comparaison db hits, temps d'exécution
- Screenshots des plans d'exécution

**Métriques importantes** :
- Temps d'exécution
- Nombre de nœuds/relations scannés
- Utilisation des index
- Mémoire consommée

### 8. Synthèse et Conclusions

#### Bénéfices Cypher 25
1. **Syntaxe** : Quantified patterns {n,m} → réduction 50-86% du code
2. **Évite NP-complet** : allReduce() vs reduce() dans WHERE
3. **Maintenabilité** : Code plus lisible, moins d'erreurs
4. **Standards** : Alignement sur spécification GQL

#### Limites Cypher Pur (5 et 25)
1. **Chemins pondérés** : Pas de Dijkstra efficace
2. **Complexité** : Explosion combinatoire pour profondeur > 3
3. **Production** : GDS obligatoire pour algorithmes avancés

#### Quand Utiliser Chaque Outil
**Cypher 5** :
- Codebases existantes
- Pattern matching simple
- Chemins non pondérés (min sauts)

**Cypher 25** :
- Nouveaux projets
- Quantified patterns (profondeur variable)
- allReduce pour éviter NP-complet

**GDS** :
- Chemins pondérés (OBLIGATOIRE)
- Algorithmes de graphe (centrality, community detection)
- Performance critique

**SQL WITH RECURSIVE** :
- Contraintes métier complexes (temps de correspondance)
- Pédagogie (voir algorithme explicitement)
- Pas de Neo4j disponible

### 9. Références

**Articles** :
- SIGMOD : "Reducing Cypher Query Complexity with allReduce"
- "Solving Hard Graph Problems with Cypher 25"
- "Query, Chomp, Repeat: Quantified Path Patterns"

**Documentation** :
- Neo4j Cypher Manual (Cypher 5 et GQL/Cypher 25)
- Neo4j GDS Documentation
- PostgreSQL Recursive Queries

**Dataset** :
- Kaggle: "2015 Flight Delays and Cancellations"
- Source: US Department of Transportation

## Format du Rapport

### Style
- Langue : Français
- Niveau : Master universitaire
- Ton : Académique mais accessible
- Code : Bien formaté avec syntax highlighting
- IA : On ne doit pas comprendre que le rapport a été fait par une IA

### Structure Markdown
- Titres : # ## ### pour hiérarchie
- Code blocks : ```cypher, ```sql avec langage spécifié
- Tableaux : Format markdown pour comparaisons
- Listes : - pour énumérations, avec un saut de ligne avant pour la génération pandoc

### Éléments Visuels
- Schémas de modèle de données (optionnel)
- Screenshots plans d'exécution
- Tableaux de comparaison performances
- Exemples de code annotés

## Points d'Attention Spécifiques

### À Mettre en Avant
1. **Problème SIGMOD** : reduce() dans WHERE = NP-complet
2. **Explosion combinatoire** : 293ms → 137s (facteur 467x) pour +1 saut
3. **GDS indispensable** : Seule solution pour chemins pondérés
4. **Quantified patterns** : Réduction 50-86% du code

### À Justifier
1. **Choix dataset** : Flight Delays vs IDFM
2. **Pas de REPEATABLE ELEMENTS** : Timestamps rendent relations uniques
3. **GDS pour shortest path** : Cypher pur timeout au-delà de 2-3 sauts
4. **Profondeur limitée** : Dataset n'a pas de vols >1 escale

## Génération PDF (Optionnel)

Si conversion en PDF nécessaire :

```bash
pandoc RAPPORT.md -o RAPPORT.pdf \
  --pdf-engine=xelatex \
  --variable mainfont="DejaVu Sans" \
  --variable monofont="DejaVu Sans Mono" \
  --highlight-style=tango \
  --toc \
  --number-sections
```

## Notes pour la Rédaction

- **Expliquer AVANT de montrer** : Contexte → Code → Résultats
- **Comparer systématiquement** : Cypher 5 vs 25 vs SQL vs GDS
- **Quantifier les gains** : Pourcentages, facteurs, timings
- **Référencer les sources** : SIGMOD, documentation Neo4j
- **Rester critique** : Montrer limites ET avantages

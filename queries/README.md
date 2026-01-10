# Queries - Cypher 5 vs Cypher 25 vs SQL

Ce dossier contient toutes les requêtes développées pour la Part 2 du projet : comparaison des langages de requêtes sur données de transport IDFM.

## Vue d'ensemble

| Fichier | Description | Technologies |
|---------|-------------|--------------|
| `01_increasing_paths.*` | Chemins avec propriétés croissantes (horaires) | Cypher 5, Cypher 25, SQL |
| `02_quantified_patterns.*` | Patterns quantifiés (comptage, agrégations) | Cypher 5, Cypher 25, SQL |
| `03_shortest_path.*` | Plus courts chemins (pondérés/non pondérés) | Cypher 5, Cypher 25, SQL |
| `04_shortest_path_gds.cypher` | Algorithmes GDS (Dijkstra, A*, Yen's) | Neo4j GDS |
| `05_additional_patterns.cypher` | Patterns problématiques (subset sum, trails) | Cypher 5, Cypher 25 |

## Patterns implémentés

### 1. Increasing Property Paths ✅ MANDATORY
**Objectif** : Chemins où les horaires de départ augmentent strictement

**Problème Cypher 5** :
- `reduce` dans `WHERE` → complexité exponentielle
- Timeout attendu : >10 stops (selon SIGMOD)

**Solutions** :
- Cypher 25 : `allReduce` (syntaxe future, non disponible Neo4j 5.x)
- Cypher 5 alternative : déplacer `reduce` dans `WITH`
- SQL : CTE récursive avec contrainte dans le `WHERE`

**Fichiers** :
- `01_increasing_paths.cypher` : versions Cypher avec tests de performance
- `01_increasing_paths.sql` : version SQL avec EXPLAIN ANALYZE

### 2. Quantified Graph Patterns ✅ MANDATORY
**Objectif** : Démontrer l'expressivité des quantified patterns

**Cas d'usage** :
- Arrêts avec ≥3 lignes accessibles PMR
- Hubs avec ≥2 correspondances rapides
- Stations multi-modales

**Comparaison** :
- Cypher 25 : `EXISTS {} >= N` (syntaxe future)
- Cypher 5 : `WITH count() ... HAVING`
- SQL : `GROUP BY ... HAVING COUNT()`

**Fichiers** :
- `02_quantified_patterns.cypher` : versions Cypher avec/sans quantified patterns
- `02_quantified_patterns.sql` : versions SQL avec CTEs

### 3. Shortest Path Algorithms ✅ MANDATORY
**Objectif** : Comparer toutes les variantes de plus courts chemins

**Algorithmes testés** :
- **Cypher 5** : `shortestPath`, `allShortestPaths` (BFS non pondéré)
- **Cypher 25** : `SHORTEST N PATHS` avec pondération (syntaxe future)
- **GDS** : Dijkstra, A*, Yen's K-Shortest, Delta-Stepping, All Pairs
- **SQL** : CTE récursive (approximation BFS/Dijkstra)

**Analyses attendues** :
- BFS unidirectionnel vs bidirectionnel
- Impact de la pondération
- Performance selon la profondeur max
- Mémoire utilisée

**Fichiers** :
- `03_shortest_path.cypher` : versions Cypher natives
- `03_shortest_path.sql` : versions SQL récursives
- `04_shortest_path_gds.cypher` : tous les algorithmes GDS

### 4. GDS Implementation in Cypher 25 ✅ MANDATORY
**Objectif** : Implémenter des algorithmes GDS directement en Cypher

**Inclus dans** : `04_shortest_path_gds.cypher`
- Configuration des projections de graphe
- Comparaison Dijkstra GDS vs Cypher natif
- Utilisation de A* avec coordonnées géographiques
- Yen's K-Shortest Paths
- All Pairs Shortest Path (attention à la mémoire)

### 5. Additional Problematic Patterns
**Objectif** : Démontrer les patterns NP-complets identifiés dans SIGMOD

**Patterns inclus** :
- **Subset Sum** : chemins totalisant exactement N secondes (timeout ≥27 nœuds)
- **Trail Semantics** : chemins sans répétition d'arêtes
- **RPQ (Regular Path Queries)** : séquences de patterns répétitifs
- **Hamiltonian-style** : visite complète d'un ensemble de nœuds (timeout ≥10 nœuds)
- **Counting patterns** : comptages le long des chemins

**Fichier** : `05_additional_patterns.cypher`

## Comment utiliser ces requêtes

### Prérequis
1. ✅ Données chargées dans Neo4j et PostgreSQL (voir Part 1)
2. ✅ Neo4j Desktop 5.x ou supérieur
3. ✅ PostgreSQL 14+ avec support des CTEs récursives
4. ⚠️ Neo4j GDS plugin installé (pour `04_shortest_path_gds.cypher`)

### Exécution Neo4j

```bash
# Ouvrir Neo4j Browser
# Charger un fichier .cypher
# Ou copier-coller les requêtes dans le Browser
```

**Important** :
- Utiliser `PROFILE` pour obtenir les plans d'exécution
- Noter les `db hits` pour comparer les performances
- Tester avec différentes profondeurs pour identifier les timeouts

### Exécution PostgreSQL

```bash
# Depuis psql
\i queries/01_increasing_paths.sql

# Ou avec timing
\timing on
\i queries/03_shortest_path.sql
```

**Important** :
- Utiliser `EXPLAIN ANALYZE` pour les plans d'exécution
- Les CTEs récursives peuvent consommer beaucoup de mémoire
- Ajuster les limites de profondeur selon les performances

### Exécution GDS

```bash
# Dans Neo4j Browser
# 1. Créer la projection
CALL gds.graph.project('transport-network', 'Stop', 'TRANSFER');

# 2. Exécuter les algorithmes
# (voir 04_shortest_path_gds.cypher)

# 3. Nettoyer
CALL gds.graph.drop('transport-network');
```

## Métriques à collecter

Pour chaque requête, documenter :

### Performance
- ✅ Temps d'exécution (ms)
- ✅ Mémoire utilisée
- ✅ Nombre de résultats
- ✅ Timeout threshold (taille max du graphe)

### Plans d'exécution

**Neo4j (PROFILE)** :
- Algorithme utilisé (Expand, ShortestPath, etc.)
- BFS unidirectionnel vs bidirectionnel
- Db hits
- Estimated rows

**PostgreSQL (EXPLAIN ANALYZE)** :
- Type de join (Hash, Nested Loop, Merge)
- Index scans vs Sequential scans
- Rows scanned
- Actual time

### Comparaisons

| Pattern | Cypher 5 | Cypher 25 | SQL | GDS | Gagnant |
|---------|----------|-----------|-----|-----|---------|
| Increasing paths | ? | N/A | ? | - | ? |
| Quantified patterns | ? | N/A | ? | - | ? |
| Shortest path (hops) | ? | N/A | ? | - | ? |
| Shortest path (weighted) | ? | N/A | ? | ✓ | ? |
| Subset sum | ? | N/A | - | - | ? |

## Résultats attendus (selon SIGMOD)

### Timeouts Cypher 5
- **Hamiltonian path** : ≥10 nœuds (p=0.2 density)
- **Subset sum** : ≥27 nœuds
- **Data-aware paths** : Variable selon les propriétés

### Améliorations Cypher 25
- `allReduce` : résout les data-aware paths
- `TRAIL` : native trail semantics (3× larger graphs, <1ms)
- Quantified patterns : syntaxe plus claire
- `SHORTEST N PATHS` : pondération native

### SQL vs Cypher
- **Trails** : SQL pire que Neo4j
- **Listes** : SQL légèrement meilleur mais timeout aussi
- **Avantage SQL** : plus difficile d'écrire des requêtes problématiques par accident

## Notes importantes

### Cypher 25 non disponible
⚠️ **La syntaxe Cypher 25 est documentée mais NON implémentée dans Neo4j Desktop 5.x**

Les requêtes Cypher 25 sont :
- Commentées avec `/* ... */`
- Documentées pour le rapport
- À tester quand Neo4j 6.x sera disponible

### APOC Functions
Certaines requêtes utilisent APOC (ex: `apoc.coll.toSet`).

Si APOC n'est pas installé :
- Installer via Neo4j Desktop (Plugins)
- Ou utiliser des alternatives natives Cypher

### Limites de profondeur
Les requêtes incluent des limites (ex: `*..10`) pour éviter les timeouts lors des tests initiaux.

**Pour le rapport** :
- Augmenter progressivement
- Documenter le seuil de timeout
- Comparer avec les benchmarks SIGMOD

## Structure des tests

### Phase 1 : Tests fonctionnels
- ✅ Vérifier que chaque requête s'exécute
- ✅ Comparer les résultats Cypher vs SQL
- ✅ Valider la cohérence des données

### Phase 2 : Tests de performance
- Mesurer les temps d'exécution
- Identifier les timeouts
- Collecter les plans d'exécution
- Comparer avec SIGMOD

### Phase 3 : Analyse
- Expliquer les différences de performance
- Référencer les enseignements SIGMOD
- Proposer des optimisations
- Documenter dans le rapport

## Questions pour le rapport

### Générales
1. Quels patterns sont les plus problématiques en Cypher 5 ?
2. Cypher 25 résout-il effectivement ces problèmes ?
3. Dans quels cas SQL est-il plus performant que Cypher ?
4. GDS apporte-t-il un gain significatif ?

### Techniques
5. Différence entre BFS unidirectionnel et bidirectionnel ?
6. Impact de `reduce` dans `WHERE` vs `WITH` ?
7. Quel algorithme Neo4j utilise pour `shortestPath` ?
8. Pourquoi les CTEs récursives SQL sont-elles parfois plus rapides ?

### Architecture
9. Quand utiliser GDS vs Cypher natif ?
10. Comment optimiser les projections GDS ?
11. Index utilisés par PostgreSQL vs Neo4j ?
12. Mémoire requise pour All Pairs Shortest Path ?

## Références

- **SIGMOD Article** : `../article/SIGMOD.MD`
- **Cypher 25 Guide** : `../article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`
- **Documentation Part 2** : `../docs/PART2.MD`
- **Neo4j GDS Docs** : https://neo4j.com/docs/graph-data-science/
- **PostgreSQL Recursive CTEs** : https://www.postgresql.org/docs/current/queries-with.html
